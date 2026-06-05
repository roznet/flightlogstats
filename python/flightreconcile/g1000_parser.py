"""Parse a Garmin G1000 / Perspective CSV flight log.

The file has a leading ``#airframe_info`` comment line, then a units row, then a
header row, then 1 Hz data. We load it with pandas, normalise the columns we
care about, build a UTC timestamp, and extract the *active waypoint sequencing*
events (each time ``AtvWpt`` changes, the previous waypoint was sequenced).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional

import pandas as pd

from . import geo

# G1000 column name -> our normalised name. Names are matched after stripping.
_COLMAP = {
    "Lcl Date": "date",
    "Lcl Time": "time",
    "UTCOfst": "utc_ofst",
    "AtvWpt": "atvwpt",
    "Latitude": "lat",
    "Longitude": "lon",
    "AltMSL": "alt_msl",
    "OAT": "oat",
    "IAS": "ias",
    "GndSpd": "gs",
    "TAS": "tas",
    "FQtyL": "fuel_l",
    "FQtyR": "fuel_r",
    "E1 FFlow": "ff1",
    "E2 FFlow": "ff2",
    "WndSpd": "wind_spd",
    "WndDr": "wind_dir",
    "WptDst": "wpt_dst",
    "WptBrg": "wpt_brg",
    "MagVar": "mag_var",
    "HDG": "hdg",
    "TRK": "trk",
}


@dataclass
class WptEvent:
    """The moment the FMS sequenced (left) a waypoint."""
    ident: str
    idx: int                 # row index at sequencing
    time_utc: pd.Timestamp
    elapsed_s: float         # seconds since first data sample
    lat: float
    lon: float
    alt_msl: Optional[float]
    fuel_total: Optional[float]
    gs: Optional[float]
    tas: Optional[float]
    wind_dir: Optional[float]
    wind_spd: Optional[float]
    closest_dist_nm: Optional[float] = None  # min WptDst while this wpt active


@dataclass
class PhaseMetrics:
    label: str
    duration_s: Optional[float] = None
    fuel_gal: Optional[float] = None
    dist_nm: Optional[float] = None
    alt_start: Optional[float] = None
    alt_end: Optional[float] = None
    rate_fpm: Optional[float] = None      # +climb / -descent
    avg_ias: Optional[float] = None
    avg_tas: Optional[float] = None
    avg_gs: Optional[float] = None


class FlightLog:
    def __init__(self, df: pd.DataFrame):
        self.df = df
        self.start = df["time_utc"].iloc[0]
        self.end = df["time_utc"].iloc[-1]

    @property
    def duration_s(self) -> float:
        return (self.end - self.start).total_seconds()

    def fuel_total(self) -> pd.Series:
        return self.df["fuel_l"].fillna(0) + self.df["fuel_r"].fillna(0)

    def fuel_at_start(self) -> Optional[float]:
        """First credible total fuel reading (skips pre-power-up zeros)."""
        ft = self.fuel_total()
        valid = ft[ft > 1.0]
        return float(valid.iloc[0]) if len(valid) else None

    def fuel_at_end(self) -> Optional[float]:
        ft = self.fuel_total()
        valid = ft[ft > 1.0]
        return float(valid.iloc[-1]) if len(valid) else None

    def track(self) -> pd.DataFrame:
        """Valid-position rows only (lat/lon present)."""
        return self.df.dropna(subset=["lat", "lon"])

    def flown_distance_nm(self) -> float:
        t = self.track()
        lat = t["lat"].to_numpy()
        lon = t["lon"].to_numpy()
        total = 0.0
        for i in range(1, len(lat)):
            total += geo.haversine_nm(lat[i - 1], lon[i - 1], lat[i], lon[i])
        return total

    def waypoint_events(self) -> List[WptEvent]:
        """One event per active-waypoint segment, at the moment it sequences.

        We record the *last* sample before AtvWpt changes (the sequencing point)
        and the closest distance achieved to that waypoint while it was active.
        """
        df = self.df
        wpt = df["atvwpt"].fillna("")
        events: List[WptEvent] = []
        n = len(df)
        seg_start = 0
        cur = wpt.iloc[0]
        for i in range(1, n + 1):
            val = wpt.iloc[i] if i < n else None
            if i == n or val != cur:
                if cur:  # non-empty waypoint segment just ended at i-1
                    seg = df.iloc[seg_start:i]
                    last = df.iloc[i - 1]
                    closest = seg["wpt_dst"].min() if "wpt_dst" in seg else None
                    events.append(WptEvent(
                        ident=cur,
                        idx=i - 1,
                        time_utc=last["time_utc"],
                        elapsed_s=(last["time_utc"] - self.start).total_seconds(),
                        lat=last["lat"],
                        lon=last["lon"],
                        alt_msl=_get(last, "alt_msl"),
                        fuel_total=_fuel(last),
                        gs=_get(last, "gs"),
                        tas=_get(last, "tas"),
                        wind_dir=_get(last, "wind_dir"),
                        wind_spd=_get(last, "wind_spd"),
                        closest_dist_nm=float(closest) if pd.notna(closest) else None,
                    ))
                if i < n:
                    cur = val
                    seg_start = i
        return events

    def segment_metrics(self, i0: int, i1: int, label: str) -> PhaseMetrics:
        """Summarise the flight between two positional indices."""
        seg = self.df.iloc[i0:i1 + 1]
        m = PhaseMetrics(label=label)
        if len(seg) < 2:
            return m
        m.duration_s = (seg["time_utc"].iloc[-1] - seg["time_utc"].iloc[0]).total_seconds()
        if "fuel_burn" in seg:
            m.fuel_gal = float(seg["fuel_burn"].iloc[-1] - seg["fuel_burn"].iloc[0])
        pts = seg.dropna(subset=["lat", "lon"])
        if len(pts) > 1:
            lat, lon = pts["lat"].to_numpy(), pts["lon"].to_numpy()
            m.dist_nm = float(sum(
                geo.haversine_nm(lat[i - 1], lon[i - 1], lat[i], lon[i])
                for i in range(1, len(lat))))
        if "alt_msl" in seg:
            m.alt_start = float(seg["alt_msl"].iloc[0])
            m.alt_end = float(seg["alt_msl"].iloc[-1])
            if m.duration_s and m.duration_s > 0:
                m.rate_fpm = (m.alt_end - m.alt_start) / (m.duration_s / 60.0)
        for col, attr in (("ias", "avg_ias"), ("tas", "avg_tas"), ("gs", "avg_gs")):
            if col in seg:
                v = seg[col].mean()
                setattr(m, attr, float(v) if pd.notna(v) else None)
        return m

    def phases(self) -> Optional[dict]:
        """Detect takeoff / TOC / TOD / landing and summarise each phase.

        cruise_alt is the 95th-pct airborne altitude. TOC = first time within
        500 ft of it; TOD = last time within 1500 ft of it (so a late step-down
        still counts as cruise).
        """
        df = self.df
        if "gs" not in df or "alt_msl" not in df:
            return None
        air = df[df["gs"] > 40]
        if not len(air):
            return None
        cruise_alt = float(air["alt_msl"].quantile(0.95))
        to_i = int(air.index[0])
        land_i = int(air.index[-1])
        climb = air[air["alt_msl"] >= cruise_alt - 500]
        toc_i = int(climb.index[0]) if len(climb) else to_i
        desc = air[air["alt_msl"] >= cruise_alt - 1500]
        tod_i = int(desc.index[-1]) if len(desc) else land_i
        return {
            "cruise_alt": cruise_alt,
            "takeoff_i": to_i, "toc_i": toc_i, "tod_i": tod_i, "land_i": land_i,
            "climb": self.segment_metrics(to_i, toc_i, "Climb"),
            "cruise": self.segment_metrics(toc_i, tod_i, "Cruise"),
            "descent": self.segment_metrics(tod_i, land_i, "Descent"),
        }

    def sample_at_elapsed(self, elapsed_s: float) -> pd.Series:
        """Nearest data row to a given elapsed time (seconds since start)."""
        target = self.start + pd.Timedelta(seconds=elapsed_s)
        idx = (self.df["time_utc"] - target).abs().idxmin()
        return self.df.loc[idx]


def _get(row, col):
    v = row.get(col)
    return float(v) if pd.notna(v) else None


def _fuel(row):
    l = row.get("fuel_l")
    r = row.get("fuel_r")
    tot = (l if pd.notna(l) else 0) + (r if pd.notna(r) else 0)
    return float(tot)


def parse_g1000(path: str) -> FlightLog:
    # Row 0 is the #airframe_info comment, row 1 is units, row 2 is the header.
    df = pd.read_csv(path, skiprows=[0, 1], skipinitialspace=True,
                     low_memory=False)
    df.columns = [c.strip() for c in df.columns]
    rename = {k: v for k, v in _COLMAP.items() if k in df.columns}
    df = df.rename(columns=rename)

    # numeric coercion
    for c in ("lat", "lon", "alt_msl", "oat", "ias", "gs", "tas",
              "fuel_l", "fuel_r", "ff1", "ff2", "wind_spd", "wind_dir",
              "wpt_dst", "wpt_brg", "mag_var", "hdg", "trk"):
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce")

    if "atvwpt" in df.columns:
        df["atvwpt"] = df["atvwpt"].astype(str).str.strip().replace("nan", "")

    # G1000 stores WndDr as a value that can be negative; normalise to 0-360.
    if "wind_dir" in df.columns:
        df["wind_dir"] = df["wind_dir"] % 360.0

    # build a UTC timestamp from date + time + offset
    ts = pd.to_datetime(
        df["date"].astype(str).str.strip() + " " + df["time"].astype(str).str.strip(),
        format="%Y-%m-%d %H:%M:%S", errors="coerce",
    )
    df["time_utc"] = ts  # offset is +00:00 for this log; UTC already
    df = df.dropna(subset=["time_utc"]).reset_index(drop=True)

    # integrate fuel flow (gph) over time -> cumulative gallons burned.
    # Smoother and more accurate than coarse tank-quantity deltas, and is the
    # apples-to-apples comparison against the planned flow-based fuel model.
    ff = df["ff1"].fillna(0) if "ff1" in df.columns else 0.0
    if "ff2" in df.columns:
        ff = ff + df["ff2"].fillna(0)
    dt = df["time_utc"].diff().dt.total_seconds().fillna(0).clip(lower=0, upper=10)
    df["fuel_burn"] = (ff * dt / 3600.0).cumsum()

    return FlightLog(df)


if __name__ == "__main__":
    import sys
    log = parse_g1000(sys.argv[1])
    print(f"rows={len(log.df)} start={log.start} end={log.end} "
          f"dur={log.duration_s/3600:.2f}h")
    fs, fe = log.fuel_at_start(), log.fuel_at_end()
    print(f"fuel start={fs:.1f} end={fe:.1f} burned={fs-fe:.1f} gal")
    print(f"flown distance = {log.flown_distance_nm():.1f} nm")
    print("waypoint events:")
    for e in log.waypoint_events():
        print(f"  {e.ident:8s} t+{e.elapsed_s/60:6.1f}min  "
              f"fuel={e.fuel_total:5.1f}  gs={e.gs}  closest={e.closest_dist_nm}")
