"""Predict the ATC frequency you are likely to get, from your own past logs.

Every G1000 log records the *active* COM1/COM2 frequency once a second, so a
corpus of logs is a record of where, at what altitude and in which direction
each frequency was actually used. This module turns that into two things:

  1. **A point index** - a thinned (one sample every ``STEP`` seconds) cloud of
     positions, each tagged with the frequency in use, the frequency that came
     next, and the track miles remaining until that change.
  2. **A transition table** - how often frequency A was followed by frequency B.

Prediction blends the two. Nearby past points vote for a frequency (a k-nearest
neighbour vote), and the transition table sharpens the guess when the current
frequency is known. Blending beats either alone: on the author's corpus the
current frequency is right ~63% of the time (top-1) and the next frequency ~56%,
against ~5% for guessing the most common frequency. See ``evaluate()``.

Why position *and* altitude *and* direction: the point where a handoff happens
is diffuse (a median ~20 nm spread around its centroid) because it depends on
which way you are going and how high you are. The region a frequency covers is
far better defined than the point where you were given it, so the model asks
"which sector am I in" rather than "which handoff point is nearest".
"""
from __future__ import annotations

import glob
import hashlib
import math
import os
import pickle
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np

from . import geo

CACHE_DIR = os.path.expanduser("~/.cache/flightreconcile")
CACHE_VERSION = 3      # bump when the scan or segment logic changes

DEFAULT_LOG_DIR = os.path.expanduser(
    "~/Library/Mobile Documents/iCloud~net~ro-z~flightlogstats/Documents")
DEFAULT_DB = os.path.expanduser(
    "~/Developer/public/flyfun-apps/main/data/nav.db")

STEP = 15              # seconds between indexed points (logs are 1 Hz)
MIN_DWELL_S = 60.0     # shorter frequency runs are radio flicker, not a handoff
MIN_GS_KT = 15.0       # below this we are parked, not taxiing or flying

# --- kNN distance weights, tuned by leave-one-flight-out on the real corpus ---
ALT_NM_PER_1000FT = 6.0   # 1000 ft of altitude difference costs 6 nm
DIR_PENALTY_NM = 25.0     # flying the exact opposite way costs 25 nm
K_NEIGHBOURS = 60
SOFTEN_NM = 2.0           # neighbour weight is 1/(distance + SOFTEN_NM)
BLEND_TRANSITION = 0.4    # weight of the transition table vs the spatial vote

# Route climb/descent gradient, in track miles per 1000 ft. Measured off the
# author's own climbs (an SR22T is ~6500-8000 ft twelve miles out), and it
# matters: handoffs early in the climb are decided by altitude, so assuming too
# shallow a climb predicts the departure frequency for too long.
CLIMB_NM_PER_1000FT = 2.0


# --------------------------------------------------------------------------
# scanning
# --------------------------------------------------------------------------

@dataclass
class FreqSegment:
    """One continuous period on a single COM1 frequency."""
    freq: str
    file: str
    date: str
    t_start: str
    t_end: str
    dur_s: float
    nm: float                     # track miles flown while on this frequency
    lat_in: float                 # where it became active
    lon_in: float
    alt_in: float
    trk_in: float
    lat_out: float                # where it was left
    lon_out: float
    alt_out: float
    prev_freq: Optional[str] = None
    next_freq: Optional[str] = None
    wpt_in: str = ""


@dataclass
class FreqCorpus:
    """Thinned point index plus the frequency segments behind it."""
    lat: np.ndarray
    lon: np.ndarray
    alt: np.ndarray
    trk: np.ndarray
    gs: np.ndarray
    freq_i: np.ndarray            # index into .freqs
    next_i: np.ndarray            # index of the frequency that came next, -1 if none
    nm_to_next: np.ndarray        # track miles until that change, nan if none
    flight: np.ndarray            # index into .files
    freqs: List[str]
    files: List[str]
    segments: List[FreqSegment] = field(default_factory=list)

    # local flat-earth projection, in nautical miles, set by _project()
    x: np.ndarray = None
    y: np.ndarray = None
    tx: np.ndarray = None         # unit track vector, east component
    ty: np.ndarray = None
    lat0: float = 0.0
    lon0: float = 0.0

    def __len__(self) -> int:
        return len(self.lat)

    def freq_name(self, i: int) -> Optional[str]:
        return self.freqs[i] if 0 <= i < len(self.freqs) else None


_COLS = ["Lcl Date", "Lcl Time", "COM1", "COM2", "Latitude", "Longitude",
         "AltMSL", "TRK", "GndSpd", "AtvWpt"]


def _norm_date(d: str) -> str:
    """Normalise a log date to YYYY-MM-DD.

    Most logs use ISO, but some write DD/MM/YYYY, and comparing the two as
    strings silently gets the ordering wrong, which the --since filter relies on.
    """
    d = (d or "").strip()
    if len(d) == 10 and d[4] == "-" and d[7] == "-":
        return d
    if len(d) == 10 and d[2] == "/" and d[5] == "/":
        return f"{d[6:]}-{d[3:5]}-{d[:2]}"
    return d


def _secs(hhmmss: str) -> Optional[float]:
    try:
        h, m, s = hhmmss.split(":")
        return int(h) * 3600 + int(m) * 60 + float(s)
    except (ValueError, AttributeError):
        return None


def _read_rows(path: str) -> Optional[dict]:
    """Read the columns we need from one G1000 CSV, line by line.

    Deliberately not pandas: we scan a thousand files and only need ten of the
    seventy-odd columns, so a plain split is several times faster.
    """
    with open(path, "r", errors="replace") as f:
        f.readline()                                   # #airframe_info
        f.readline()                                   # units
        header = [h.strip() for h in f.readline().split(",")]
        idx = {h: i for i, h in enumerate(header)}
        if any(c not in idx for c in ("COM1", "Latitude", "Longitude", "AltMSL")):
            return None                                # older log without radios
        want = [idx.get(c) for c in _COLS]
        date, time_s, com1, com2 = [], [], [], []
        lat, lon, alt, trk, gs, wpt = [], [], [], [], [], []
        last = None
        for line in f:
            p = line.split(",")
            if len(p) < len(header) - 3:
                continue
            try:
                v = [p[i].strip() if i is not None and i < len(p) else "" for i in want]
            except IndexError:
                continue
            t = _secs(v[1])
            if t is None or not v[2] or not v[4] or not v[5]:
                continue
            try:
                la, lo = float(v[4]), float(v[5])
                al = float(v[6]) if v[6] else 0.0
                tk = float(v[7]) if v[7] else 0.0
                sp = float(v[8]) if v[8] else 0.0
            except ValueError:
                continue
            # as the app's FlightData: a repeated timestamp is dropped and a clock
            # going backwards restarts the log, so both readers see the same rows
            # (a new date is taken as moving forward: date formats vary and do not sort)
            if last is not None and v[0] == last[0] and t <= last[1]:
                if t == last[1]:
                    continue
                for col in (date, time_s, com1, com2, lat, lon, alt, trk, gs, wpt):
                    col.clear()
            last = (v[0], t)
            date.append(v[0]); time_s.append(t); com1.append(v[2]); com2.append(v[3])
            lat.append(la); lon.append(lo); alt.append(al); trk.append(tk)
            gs.append(sp); wpt.append(v[9])
    if len(lat) < 60:
        return None
    return dict(date=_norm_date(date[0]) if date else "", t=np.array(time_s), com1=com1,
                com2=com2, lat=np.array(lat), lon=np.array(lon),
                alt=np.array(alt), trk=np.array(trk), gs=np.array(gs), wpt=wpt)


def _cum_nm(lat: np.ndarray, lon: np.ndarray) -> np.ndarray:
    """Cumulative great-circle track distance in nm (vectorised haversine)."""
    p1 = np.radians(lat[:-1]); p2 = np.radians(lat[1:])
    dphi = p2 - p1
    dl = np.radians(lon[1:] - lon[:-1])
    a = np.sin(dphi / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dl / 2) ** 2
    leg = 2 * geo.EARTH_R_NM * np.arcsin(np.clip(np.sqrt(a), 0, 1))
    return np.concatenate([[0.0], np.cumsum(leg)])


def _runs(values: Sequence[str]) -> List[Tuple[str, int, int]]:
    """Run-length encode a sequence -> [(value, first_idx, last_idx), ...]."""
    out: List[Tuple[str, int, int]] = []
    start = 0
    for i in range(1, len(values) + 1):
        if i == len(values) or values[i] != values[start]:
            out.append((values[start], start, i - 1))
            start = i
    return out


def _debounce(runs: List[Tuple[str, int, int]], t: np.ndarray,
              min_dwell_s: float) -> List[Tuple[str, int, int]]:
    """Drop runs shorter than ``min_dwell_s`` and merge equal neighbours.

    A standby swap made and undone shows up as a one-second run; roughly a tenth
    of all raw runs are this kind of flicker and they would otherwise look like
    handoffs. The first and last run are kept regardless: they are the ground
    frequencies, which are short only because the log starts or stops there.
    """
    keep = [r for i, r in enumerate(runs)
            if i in (0, len(runs) - 1) or (t[r[2]] - t[r[1]]) >= min_dwell_s]
    merged: List[Tuple[str, int, int]] = []
    for r in keep:
        if merged and merged[-1][0] == r[0]:
            merged[-1] = (r[0], merged[-1][1], r[2])
        else:
            merged.append(r)
    return merged


def scan_logs(directory: str = DEFAULT_LOG_DIR, step: int = STEP,
              min_dwell_s: float = MIN_DWELL_S, min_gs_kt: float = MIN_GS_KT,
              cache: bool = True, progress=None) -> FreqCorpus:
    """Build the point index and segments from every log in ``directory``.

    The result is cached on disk keyed by the file listing, so the first run
    costs a few minutes and later ones are instant.
    """
    if cache:
        hit = _cache_load(directory, step, min_dwell_s, min_gs_kt)
        if hit is not None:
            return _project(hit)

    files = sorted(glob.glob(os.path.join(directory, "log_*.csv")))
    freqs: List[str] = []
    fidx: Dict[str, int] = {}
    kept_files: List[str] = []
    segments: List[FreqSegment] = []
    P: List[Tuple[float, float, float, float, float, int, int, float, int]] = []

    def freq_id(f: str) -> int:
        if f not in fidx:
            fidx[f] = len(freqs)
            freqs.append(f)
        return fidx[f]

    for n, path in enumerate(files):
        if progress and n % 100 == 0:
            progress(n, len(files))
        try:
            r = _read_rows(path)
        except OSError:
            continue
        if r is None:
            continue
        runs = _debounce(_runs(r["com1"]), r["t"], min_dwell_s)
        if len(runs) < 2:
            continue                                   # radio never changed: no signal
        cum = _cum_nm(r["lat"], r["lon"])
        flight = len(kept_files)
        kept_files.append(os.path.basename(path))

        for j, (freq, i0, i1) in enumerate(runs):
            nxt = runs[j + 1][0] if j + 1 < len(runs) else None
            segments.append(FreqSegment(
                freq=freq, file=os.path.basename(path), date=r["date"],
                t_start=_hhmm(r["t"][i0]), t_end=_hhmm(r["t"][i1]),
                dur_s=float(r["t"][i1] - r["t"][i0]), nm=float(cum[i1] - cum[i0]),
                lat_in=float(r["lat"][i0]), lon_in=float(r["lon"][i0]),
                alt_in=float(r["alt"][i0]), trk_in=float(r["trk"][i0]),
                lat_out=float(r["lat"][i1]), lon_out=float(r["lon"][i1]),
                alt_out=float(r["alt"][i1]),
                prev_freq=runs[j - 1][0] if j else None, next_freq=nxt,
                wpt_in=r["wpt"][i0]))
            # index every step-th sample of the run, annotated with what comes next
            fi = freq_id(freq)
            ni = freq_id(nxt) if nxt else -1
            change_nm = cum[i1] if nxt else None
            for i in range(i0, i1 + 1, step):
                if r["gs"][i] < min_gs_kt:
                    continue
                P.append((float(r["lat"][i]), float(r["lon"][i]), float(r["alt"][i]),
                          float(r["trk"][i]), float(r["gs"][i]), fi, ni,
                          float(change_nm - cum[i]) if change_nm is not None else math.nan,
                          flight))

    if not P:
        raise RuntimeError(f"no usable logs with COM1 data in {directory}")
    arr = np.array(P, dtype=float)
    corpus = FreqCorpus(
        lat=arr[:, 0], lon=arr[:, 1], alt=arr[:, 2], trk=arr[:, 3], gs=arr[:, 4],
        freq_i=arr[:, 5].astype(int), next_i=arr[:, 6].astype(int),
        nm_to_next=arr[:, 7], flight=arr[:, 8].astype(int),
        freqs=freqs, files=kept_files, segments=segments)
    if cache:
        _cache_save(directory, step, min_dwell_s, min_gs_kt, corpus)
    return _project(corpus)


def _hhmm(t: float) -> str:
    t = int(t)
    return f"{t // 3600:02d}:{(t % 3600) // 60:02d}:{t % 60:02d}"


def _project(c: FreqCorpus) -> FreqCorpus:
    """Add a local equirectangular projection in nm, and track unit vectors.

    The corpus spans a few hundred miles, so a flat projection about its centre
    is accurate to well under the resolution the model cares about, and it makes
    the neighbour search a plain squared distance.
    """
    c.lat0 = float(c.lat.mean())
    c.lon0 = float(c.lon.mean())
    c.x, c.y = project(c.lat, c.lon, c.lat0, c.lon0)
    r = np.radians(c.trk)
    c.tx, c.ty = np.sin(r), np.cos(r)
    return c


def project(lat, lon, lat0: float, lon0: float):
    """Latitude/longitude -> (east, north) nautical miles about (lat0, lon0)."""
    return ((np.asarray(lon) - lon0) * 60.0 * math.cos(math.radians(lat0)),
            (np.asarray(lat) - lat0) * 60.0)


# --------------------------------------------------------------------------
# the model
# --------------------------------------------------------------------------

@dataclass
class Guess:
    freq: str
    prob: float
    support: int = 0          # how many past flights back this
    nm_to_change: float = math.nan


class FreqModel:
    """Blend of a spatial neighbour vote and a frequency transition table."""

    def __init__(self, corpus: FreqCorpus, k: int = K_NEIGHBOURS,
                 alt_nm_per_1000ft: float = ALT_NM_PER_1000FT,
                 dir_penalty_nm: float = DIR_PENALTY_NM,
                 blend: float = BLEND_TRANSITION,
                 since_date: Optional[str] = None):
        self.c = corpus
        self.k = k
        self.alt_w = alt_nm_per_1000ft
        self.dir_w = dir_penalty_nm
        self.blend = blend
        self.mask = self._recency_mask(since_date)
        self.trans = self._transitions()

    def _recency_mask(self, since_date: Optional[str]) -> Optional[np.ndarray]:
        """Keep only flights on/after ``since_date`` (YYYY-MM-DD).

        Airspace is reorganised and frequencies renumber for 8.33 kHz, so old
        flights can be confidently wrong. Restricting by date is the bluntest
        but clearest way to deal with that.
        """
        if not since_date:
            return None
        dates = {}
        for s in self.c.segments:
            dates.setdefault(s.file, s.date)
        ok = np.zeros(len(self.c.files), dtype=bool)
        for i, name in enumerate(self.c.files):
            d = dates.get(name, "")
            ok[i] = bool(d) and d >= since_date
        if not ok.any():
            return None
        return ok[self.c.flight]

    def _transitions(self):
        """Counts of current-frequency -> next-frequency over the segments.

        Kept both in total and per flight, so a flight can be subtracted again.
        Evaluation depends on that: scoring a flight with its own transitions
        still in the table overstates the next-frequency accuracy badly.
        """
        fidx = {f: i for i, f in enumerate(self.c.freqs)}
        by_file = {self.c.files[i]: i for i in range(len(self.c.files))}
        keep = None
        if self.mask is not None:
            keep = {self.c.files[i] for i in np.unique(self.c.flight[self.mask])}
        total: Dict[int, Dict[int, float]] = {}
        per_flight: Dict[Tuple[int, int], Dict[int, float]] = {}
        for s in self.c.segments:
            if s.next_freq is None:
                continue
            if keep is not None and s.file not in keep:
                continue
            a, b = fidx.get(s.freq), fidx.get(s.next_freq)
            if a is None or b is None:
                continue
            total.setdefault(a, {})
            total[a][b] = total[a].get(b, 0.0) + 1.0
            fl = by_file.get(s.file)
            if fl is not None:
                d = per_flight.setdefault((fl, a), {})
                d[b] = d.get(b, 0.0) + 1.0
        self.trans_flight = per_flight
        return total

    def _transition_probs(self, ci: int,
                          exclude_flight: Optional[int] = None) -> Dict[int, float]:
        """P(next | current), optionally with one flight's own counts removed."""
        counts = dict(self.trans.get(ci, {}))
        if exclude_flight is not None:
            for b, n in self.trans_flight.get((exclude_flight, ci), {}).items():
                left = counts.get(b, 0.0) - n
                if left > 0:
                    counts[b] = left
                else:
                    counts.pop(b, None)
        total = sum(counts.values())
        return {k: v / total for k, v in counts.items()} if total else {}

    # -- neighbour search -------------------------------------------------
    def _neighbours(self, lat: float, lon: float, alt: float,
                    trk: Optional[float], exclude_flight: Optional[int] = None):
        c = self.c
        x, y = project(lat, lon, c.lat0, c.lon0)
        d = np.hypot(c.x - x, c.y - y) + np.abs(c.alt - alt) / 1000.0 * self.alt_w
        if trk is not None:
            r = math.radians(trk)
            cosang = c.tx * math.sin(r) + c.ty * math.cos(r)
            d = d + (1.0 - cosang) / 2.0 * self.dir_w
        keep = self.mask
        if exclude_flight is not None:
            own = c.flight == exclude_flight
            keep = ~own if keep is None else (keep & ~own)
        if keep is not None:
            d = np.where(keep, d, np.inf)
        k = min(self.k, int(np.isfinite(d).sum()))
        if k <= 0:
            return np.array([], dtype=int), np.array([])
        sel = np.argpartition(d, k - 1)[:k]
        sel = sel[np.isfinite(d[sel])]
        return sel, d[sel]

    @staticmethod
    def _vote(keys: Sequence[int], weights: Sequence[float]) -> Dict[int, float]:
        out: Dict[int, float] = {}
        for k, w in zip(keys, weights):
            if k >= 0:
                out[k] = out.get(k, 0.0) + w
        total = sum(out.values()) or 1.0
        return {k: v / total for k, v in out.items()}

    # -- public API -------------------------------------------------------
    def current(self, lat: float, lon: float, alt: float,
                trk: Optional[float] = None, top: int = 3,
                exclude_flight: Optional[int] = None) -> List[Guess]:
        """Which frequency are you most likely on, here, at this altitude?"""
        sel, d = self._neighbours(lat, lon, alt, trk, exclude_flight)
        if len(sel) == 0:
            return []
        w = 1.0 / (d + SOFTEN_NM)
        dist = self._vote(self.c.freq_i[sel], w)
        nflights = {}
        for i in sel:
            nflights.setdefault(int(self.c.freq_i[i]), set()).add(int(self.c.flight[i]))
        # mean remaining distance to the handoff, over the neighbours that agree
        rv = []
        for fi, p in sorted(dist.items(), key=lambda kv: -kv[1])[:top]:
            same = sel[self.c.freq_i[sel] == fi]
            nm = self.c.nm_to_next[same]
            nm = nm[np.isfinite(nm)]
            rv.append(Guess(self.c.freqs[fi], p, len(nflights.get(fi, ())),
                            float(nm.mean()) if len(nm) else math.nan))
        return rv

    def next(self, lat: float, lon: float, alt: float,
             trk: Optional[float] = None, current: Optional[str] = None,
             top: int = 3, exclude_flight: Optional[int] = None) -> List[Guess]:
        """Which frequency comes next, given where you are and what you are on?

        The spatial vote answers "what do flights around here change to"; the
        transition table answers "what usually follows this frequency". Neither
        is enough alone, so the two log-probabilities are blended.
        """
        sel, d = self._neighbours(lat, lon, alt, trk, exclude_flight)
        if len(sel) == 0:
            return []
        w = 1.0 / (d + SOFTEN_NM)
        spatial = self._vote(self.c.next_i[sel], w)

        trans: Dict[int, float] = {}
        if current is not None and current in self.c.freqs:
            trans = self._transition_probs(self.c.freqs.index(current),
                                           exclude_flight)

        a = self.blend if trans else 0.0
        eps = 1e-4
        keys = set(spatial) | set(trans)
        score = {k: a * math.log(trans.get(k, eps)) +
                    (1 - a) * math.log(spatial.get(k, eps)) for k in keys}
        # back to a comparable 0-1 scale for display
        mx = max(score.values()) if score else 0.0
        exp = {k: math.exp(v - mx) for k, v in score.items()}
        tot = sum(exp.values()) or 1.0

        nflights = {}
        for i in sel:
            nflights.setdefault(int(self.c.next_i[i]), set()).add(int(self.c.flight[i]))
        rv = []
        for fi, v in sorted(exp.items(), key=lambda kv: -kv[1])[:top]:
            rv.append(Guess(self.c.freqs[fi], v / tot, len(nflights.get(fi, ()))))
        return rv

    def when(self, lat: float, lon: float, alt: float,
             trk: Optional[float] = None,
             exclude_flight: Optional[int] = None) -> float:
        """Estimated track miles until the next frequency change (nan if unknown)."""
        sel, d = self._neighbours(lat, lon, alt, trk, exclude_flight)
        if len(sel) == 0:
            return math.nan
        nm = self.c.nm_to_next[sel]
        ok = np.isfinite(nm)
        if not ok.any():
            return math.nan
        w = 1.0 / (d[ok] + SOFTEN_NM)
        return float((nm[ok] * w).sum() / w.sum())


# --------------------------------------------------------------------------
# route prediction: the "frequency ladder"
# --------------------------------------------------------------------------

@dataclass
class Rung:
    """One predicted frequency along a route."""
    freq: str
    from_nm: float
    to_nm: float
    confidence: float
    support: int
    alt: float
    alternates: List[str] = field(default_factory=list)
    unsettled: bool = False       # no clear winner over this stretch


def sample_route(points: Sequence[Tuple[float, float]], step_nm: float = 4.0
                 ) -> List[Tuple[float, float, float, float]]:
    """Densify a route into (lat, lon, track, along-track nm) samples."""
    out: List[Tuple[float, float, float, float]] = []
    total = 0.0
    for (la1, lo1), (la2, lo2) in zip(points, points[1:]):
        leg = geo.haversine_nm(la1, lo1, la2, lo2)
        brg = geo.initial_bearing(la1, lo1, la2, lo2)
        n = max(1, int(leg / step_nm))
        for i in range(n):
            f = i / n
            out.append((la1 + (la2 - la1) * f, lo1 + (lo2 - lo1) * f,
                        brg, total + leg * f))
        total += leg
    if points:
        la, lo = points[-1]
        brg = out[-1][2] if out else 0.0
        out.append((la, lo, brg, total))
    return out


def altitude_profile(along_nm: float, total_nm: float, cruise_alt: float,
                     field_alt: float = 1000.0,
                     nm_per_1000ft: float = CLIMB_NM_PER_1000FT,
                     end_alt: Optional[float] = None) -> float:
    """A crude climb/cruise/descent profile.

    Altitude matters near the ends, where tower and approach frequencies live at
    low level and area control lives above, so a flat cruise altitude would
    predict the wrong frequencies for the first and last few minutes.

    ``field_alt`` is where the climb starts and ``end_alt`` where the descent
    finishes. They differ in live mode: the start is the altitude you are at
    right now (already level, so no climb), while the far end is still airfield
    elevation. Tying them together would hold the profile at cruise all the way
    to the threshold and lose every arrival frequency.
    """
    end_alt = field_alt if end_alt is None else end_alt
    climb = max(0.0, (cruise_alt - field_alt) / 1000.0 * nm_per_1000ft)
    descent = max(0.0, (cruise_alt - end_alt) / 1000.0 * nm_per_1000ft)
    if along_nm < climb and climb > 0:
        return field_alt + (cruise_alt - field_alt) * (along_nm / climb)
    if along_nm > total_nm - descent and descent > 0:
        left = max(0.0, total_nm - along_nm)
        return end_alt + (cruise_alt - end_alt) * (left / descent)
    return cruise_alt


def route_progress(points: Sequence[Tuple[float, float]], lat: float, lon: float
                   ) -> Tuple[int, float]:
    """Where we are along the route: (index of the next waypoint, offset nm).

    Projects the position onto each leg and keeps the closest. The offset is how
    far off the planned line we are, which is what distinguishes "on the route"
    from "being vectored".
    """
    if len(points) < 2:
        return 0, 0.0
    lat0 = sum(p[0] for p in points) / len(points)
    lon0 = sum(p[1] for p in points) / len(points)
    px, py = project(lat, lon, lat0, lon0)
    best_i, best_d = 1, float("inf")
    for i in range(len(points) - 1):
        ax, ay = project(points[i][0], points[i][1], lat0, lon0)
        bx, by = project(points[i + 1][0], points[i + 1][1], lat0, lon0)
        vx, vy = bx - ax, by - ay
        seg2 = vx * vx + vy * vy
        t = 0.0 if seg2 == 0 else max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / seg2))
        d = math.hypot(px - (ax + t * vx), py - (ay + t * vy))
        if d < best_d:
            best_d, best_i = d, i + 1
    return best_i, best_d


def rejoin_index(points: Sequence[Tuple[float, float]], lat: float, lon: float,
                 trk: Optional[float], cone_deg: float = 100.0,
                 from_index: int = 0) -> Optional[int]:
    """Index of the route waypoint we would next be sent direct to.

    Off the planned route - vectors, a shortcut, a deviation - the realistic
    assumption is the IFR one: you rejoin at the next fix you are actually
    flying towards, not at the nearest point on the line, which may be behind
    you. Candidates start at the next waypoint along the route, so a bearing
    alone can never nominate a fix already passed (flying south of mid-route,
    the departure airport is "ahead" by bearing but is not a rejoin). Among
    those, take the earliest lying within ``cone_deg`` of the current track;
    if nothing is (a hold, a 180 for weather), take the next one along, since
    that is where the vectors will eventually put you.

    ``from_index`` is the furthest waypoint already passed, so progress never
    runs backwards.
    """
    if not points:
        return None
    nxt, _ = route_progress(points, lat, lon)
    start = max(from_index, min(nxt, len(points) - 1))
    remaining = list(range(start, len(points)))
    if not remaining:
        return None
    if trk is not None:
        for i in remaining:
            brg = geo.initial_bearing(lat, lon, points[i][0], points[i][1])
            if abs(geo.angle_diff(brg, trk)) <= cone_deg / 2.0:
                return i
    return remaining[0]


def remaining_route(points: Sequence[Tuple[float, float]], lat: float, lon: float,
                    trk: Optional[float], from_index: int = 0
                    ) -> Tuple[List[Tuple[float, float]], Optional[int]]:
    """Current position, then the route from the rejoin waypoint onward."""
    i = rejoin_index(points, lat, lon, trk, from_index=from_index)
    if i is None:
        return [(lat, lon)], None
    return [(lat, lon)] + [tuple(p) for p in points[i:]], i


def live_ladder(model: FreqModel, points: Sequence[Tuple[float, float]],
                lat: float, lon: float, alt: float, trk: Optional[float],
                cruise_alt: Optional[float] = None, from_index: int = 0,
                step_nm: float = 4.0, min_rung_nm: float = 8.0,
                destination_alt: float = 1000.0
                ) -> Tuple[List[Rung], Optional[int]]:
    """The ladder ahead of you from where you actually are.

    Distances are from the current position, not from departure. The altitude
    profile starts at the current altitude rather than field elevation, so a
    level aircraft gets no phantom climb - only the descent at the far end.
    """
    route, idx = remaining_route(points, lat, lon, trk, from_index)
    if len(route) < 2:
        return [], idx
    rungs = route_ladder(model, route, cruise_alt or alt, step_nm=step_nm,
                         min_rung_nm=min_rung_nm, field_alt=alt,
                         end_alt=destination_alt)
    return rungs, idx


def route_ladder(model: FreqModel, points: Sequence[Tuple[float, float]],
                 cruise_alt: float, step_nm: float = 4.0,
                 min_rung_nm: float = 8.0, field_alt: float = 1000.0,
                 climb_nm_per_1000ft: float = CLIMB_NM_PER_1000FT,
                 end_alt: Optional[float] = None) -> List[Rung]:
    """Predict the frequency sequence along a route, in order.

    Walks the route, asks "which frequency here" at every sample, then collapses
    runs of the same answer. Runs shorter than ``min_rung_nm`` are dropped as
    prediction noise rather than real handoffs.
    """
    samples = sample_route(points, step_nm)
    if not samples:
        return []
    total = samples[-1][3]
    preds = []
    for la, lo, brg, nm in samples:
        alt = altitude_profile(nm, total, cruise_alt, field_alt,
                               climb_nm_per_1000ft, end_alt)
        g = model.current(la, lo, alt, brg, top=3)
        preds.append((nm, alt, g))

    rungs: List[Rung] = []
    for nm, alt, g in preds:
        if not g:
            continue
        top = g[0]
        if rungs and rungs[-1].freq == top.freq:
            r = rungs[-1]
            r.to_nm = nm
            r.confidence = max(r.confidence, top.prob)
            r.support = max(r.support, top.support)
        else:
            rungs.append(Rung(top.freq, nm, nm, top.prob, top.support, alt,
                              [x.freq for x in g[1:]]))
    def solid(r: Rung) -> bool:
        # Approach and tower sectors near an airport are only a few miles of
        # route, and they are the ones worth knowing, so a short rung survives
        # when the vote is clear and several flights back it.
        return r.confidence >= 0.6 and r.support >= 5

    merged: List[Rung] = []
    i = 0
    while i < len(rungs):
        r = rungs[i]
        # The first rung is the departure frequency: always kept, however brief.
        if i == 0 or (r.to_nm - r.from_nm) >= min_rung_nm or solid(r):
            if merged and merged[-1].freq == r.freq:
                merged[-1].to_nm = r.to_nm
            else:
                merged.append(r)
            i += 1
            continue

        # A run of short, unconvincing rungs means the model has no settled
        # answer over this stretch. Collapsing them into the PREVIOUS rung would
        # quietly extend a confident frequency across ground it was never
        # predicted for - claiming "123.430, 87%" for 19 nm when the real answer
        # is a three-way tie around 40%. So they become one band of their own,
        # carrying the candidates and the low confidence that goes with them.
        group: List[Rung] = []
        while i < len(rungs):
            rj = rungs[i]
            if (rj.to_nm - rj.from_nm) >= min_rung_nm or solid(rj):
                break
            group.append(rj)
            i += 1
        if not group:
            continue
        span: Dict[str, float] = {}
        weighted: Dict[str, float] = {}
        for g in group:
            w = max(g.to_nm - g.from_nm, step_nm)
            span[g.freq] = span.get(g.freq, 0.0) + w
            weighted[g.freq] = weighted.get(g.freq, 0.0) + w * g.confidence
        band_span = sum(span.values()) or 1.0      # not `total`: that is the route length
        order = sorted(span, key=lambda f: -span[f])
        best = order[0]
        band = Rung(best, group[0].from_nm, group[-1].to_nm,
                    weighted[best] / band_span,
                    max(g.support for g in group if g.freq == best),
                    group[0].alt, order[1:3], unsettled=len(order) > 1)
        if merged and merged[-1].freq == band.freq and not band.unsettled:
            merged[-1].to_nm = band.to_nm
        else:
            merged.append(band)

    # Each rung runs to where the prediction flips, so the ladder has no gaps:
    # its own last sample is only the last point that voted for it.
    for a, b in zip(merged, merged[1:]):
        a.to_nm = b.from_nm
    if merged:
        merged[-1].to_nm = total
    return merged


# --------------------------------------------------------------------------
# evaluation
# --------------------------------------------------------------------------

def evaluate(model: FreqModel, per_flight: int = 10, min_alt: float = 800.0,
             min_gs: float = 40.0, seed: int = 1, top: int = 3) -> dict:
    """Leave-one-flight-out accuracy for the current and next frequency.

    Each query point is predicted from every flight *except its own*, which
    matters: leaving a flight's own transitions in the table inflates the next
    frequency score by more than ten points.
    """
    import random
    rng = random.Random(seed)
    c = model.c
    airborne = np.nonzero((c.alt >= min_alt) & (c.gs >= min_gs))[0]
    by_flight: Dict[int, List[int]] = {}
    for i in airborne:
        by_flight.setdefault(int(c.flight[i]), []).append(int(i))
    queries: List[int] = []
    for fl, ix in by_flight.items():
        if len(set(c.freq_i[ix].tolist())) < 3:
            continue                     # a flight on one frequency teaches nothing
        queries += rng.sample(ix, min(per_flight, len(ix)))

    stat = {k: [0, 0, 0] for k in ("current", "next", "next_no_current")}
    err = []
    prior = np.bincount(c.freq_i, minlength=len(c.freqs))
    prior_top = list(np.argsort(-prior)[:top])
    stat["prior"] = [0, 0, 0]

    for qi in queries:
        fl = int(c.flight[qi])
        la, lo, al, tk = c.lat[qi], c.lon[qi], c.alt[qi], c.trk[qi]
        cur = c.freqs[int(c.freq_i[qi])]

        g = model.current(la, lo, al, tk, top=top, exclude_flight=fl)
        _tally(stat["current"], cur, [x.freq for x in g])

        _tally(stat["prior"], cur, [c.freqs[i] for i in prior_top])

        ni = int(c.next_i[qi])
        if ni >= 0:
            truth = c.freqs[ni]
            g = model.next(la, lo, al, tk, current=cur, top=top, exclude_flight=fl)
            _tally(stat["next"], truth, [x.freq for x in g])
            g = model.next(la, lo, al, tk, current=None, top=top, exclude_flight=fl)
            _tally(stat["next_no_current"], truth, [x.freq for x in g])
            est = model.when(la, lo, al, tk, exclude_flight=fl)
            if math.isfinite(est) and math.isfinite(c.nm_to_next[qi]):
                err.append(abs(est - c.nm_to_next[qi]))

    out = {"queries": len(queries), "flights": len(by_flight),
           "freqs": len(c.freqs), "points": len(c)}
    for k, (a, b, n) in stat.items():
        if n:
            out[k] = {"top1": a / n, f"top{top}": b / n, "n": n}
    if err:
        err.sort()
        out["nm_error_median"] = err[len(err) // 2]
        out["nm_error_p90"] = err[int(len(err) * 0.9)]
    return out


def _tally(slot: List[int], truth: str, guesses: List[str]) -> None:
    slot[2] += 1
    if guesses and guesses[0] == truth:
        slot[0] += 1
    if truth in guesses:
        slot[1] += 1


# --------------------------------------------------------------------------
# naming frequencies by where they are used
# --------------------------------------------------------------------------

def frequency_places(corpus: FreqCorpus, model_nav=None, min_uses: int = 3
                     ) -> Dict[str, dict]:
    """Summarise each frequency: how often used, where, and at what altitude.

    Without an AIP frequency database we cannot print "London Information", so
    the next best label is the nearest known fix or airport to the middle of the
    area where the frequency is used, plus its altitude band.
    """
    out: Dict[str, dict] = {}
    for fi, freq in enumerate(corpus.freqs):
        sel = corpus.freq_i == fi
        n = int(sel.sum())
        if n == 0:
            continue
        uses = len({s.file for s in corpus.segments if s.freq == freq})
        if uses < min_uses:
            continue
        lat = float(corpus.lat[sel].mean())
        lon = float(corpus.lon[sel].mean())
        alt = corpus.alt[sel]
        out[freq] = dict(
            uses=uses, points=n, lat=lat, lon=lon,
            alt_p10=float(np.percentile(alt, 10)),
            alt_p90=float(np.percentile(alt, 90)),
            near=nearest_ident(model_nav, lat, lon) if model_nav else "")
    return out


_NAV_CACHE: Dict[int, Tuple[np.ndarray, np.ndarray, List[str]]] = {}


def _nav_arrays(model_nav):
    """Flatten the nav model's airports and waypoints into numpy arrays once.

    Called per frequency otherwise, and the model holds tens of thousands of
    waypoints, so a Python loop each time is far too slow.
    """
    key = id(model_nav)
    if key not in _NAV_CACHE:
        lat, lon, name = [], [], []
        for ap in model_nav.airports:
            if ap.latitude_deg is not None:
                lat.append(ap.latitude_deg); lon.append(ap.longitude_deg)
                name.append(ap.ident)
        for w in model_nav.waypoints:
            if w.latitude_deg is not None:
                lat.append(w.latitude_deg); lon.append(w.longitude_deg)
                name.append(w.name)
        _NAV_CACHE[key] = (np.array(lat), np.array(lon), name)
    return _NAV_CACHE[key]


def nearest_ident(model_nav, lat: float, lon: float) -> str:
    """Nearest airport or waypoint ident to a position, as a place label."""
    alat, alon, names = _nav_arrays(model_nav)
    if not len(alat):
        return ""
    p1 = np.radians(alat); p2 = math.radians(lat)
    a = (np.sin((lat - alat) * math.pi / 360.0) ** 2
         + np.cos(p1) * math.cos(p2) * np.sin(np.radians(lon - alon) / 2) ** 2)
    d = 2 * geo.EARTH_R_NM * np.arcsin(np.clip(np.sqrt(a), 0, 1))
    i = int(np.argmin(d))
    return f"{names[i]} {d[i]:.0f}nm"


# --------------------------------------------------------------------------
# disk cache
# --------------------------------------------------------------------------

def _cache_key(directory: str, step: int, dwell: float, gs: float) -> str:
    files = sorted(glob.glob(os.path.join(directory, "log_*.csv")))
    sig = "".join(f"{os.path.basename(f)}:{os.path.getsize(f)};" for f in files)
    key = f"v{CACHE_VERSION}|{directory}|{step}|{dwell}|{gs}|{sig}"
    return hashlib.md5(key.encode()).hexdigest()


def _cache_path(directory: str, step: int, dwell: float, gs: float) -> str:
    return os.path.join(CACHE_DIR, f"freq_{_cache_key(directory, step, dwell, gs)}.pkl")


def _cache_load(directory: str, step: int, dwell: float, gs: float):
    p = _cache_path(directory, step, dwell, gs)
    if os.path.exists(p):
        try:
            with open(p, "rb") as f:
                return pickle.load(f)
        except Exception:
            return None
    return None


def _cache_save(directory: str, step: int, dwell: float, gs: float,
                corpus: FreqCorpus) -> None:
    os.makedirs(CACHE_DIR, exist_ok=True)
    try:
        with open(_cache_path(directory, step, dwell, gs), "wb") as f:
            pickle.dump(corpus, f)
    except OSError:
        pass
