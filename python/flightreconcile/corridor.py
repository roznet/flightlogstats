"""Compare routing options along a corridor across many flights.

A *corridor* is an anchor (airport or fix) and a common via-point that several
filed routings pass through (e.g. EGTF <-> BILGO). This scans a directory of
G1000 logs, keeps the flights that fly the corridor, isolates the common
anchor<->via segment, auto-clusters the segments into routing options, labels
each option by the nav fix that best distinguishes it, and compares them with
**wind-adjusted** metrics so flights on different days are comparable.

Wind adjustment: each second logs both ground speed and TAS, so

  track_nm     = sum of GPS leg distances           (geometry, wind-independent)
  still_air_s  = sum(leg_nm / TAS)  == integral GS/TAS dt   (time in zero wind)
  avg_tas                                            (speed = altitude/power)

Still-air time strips the day's wind, leaving geometry x speed -> directly
comparable across days.
"""
from __future__ import annotations

import glob
import hashlib
import math
import os
import pickle
import re
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

import numpy as np

from . import geo
from .g1000_parser import parse_g1000
from .logfinder import _first_fix, _last_fix, _flt

CACHE_DIR = os.path.expanduser("~/.cache/flightreconcile")
CACHE_VERSION = 3  # bump when scan/metric logic changes to invalidate caches

# Rule-based route labels by the fixes actually flown (the AtvWpt sequence).
# Ordered; first match wins. all_of: every fix present; any_of: at least one;
# none_of: none present. These describe how a pilot files/flies the corridor.
# Route labels by the fixes actually flown (FMS AtvWpt sequence). "OCAS" = filed
# low outside controlled airspace via the pilot's own departure fixes (M25* are
# custom names; OCK/LYD) — even if ATC climbs you high later. "Airways" = filed
# through controlled airspace via GWC, split by whether the CMB shortcut was
# flown. M25* is a definitive OCAS marker, checked before the airways rules.
DEFAULT_RULES = [
    {"label": "OCAS (low, OCK/LYD)", "any_prefix": ["M25"]},
    {"label": "Airways + CMB shortcut", "any_of": ["GWC"], "all_of": ["CMB"]},
    {"label": "Airways (no shortcut)", "any_of": ["GWC"]},
    {"label": "OCAS (low, OCK/LYD)", "any_of": ["OCK", "LYD", "LZD", "RINTI", "DVR"]},
    {"label": "Direct / other"},
]


def _vec_haversine_nm(lat, lon, lat0, lon0):
    p1 = np.radians(lat)
    p2 = math.radians(lat0)
    dphi = np.radians(lat0 - lat)
    dl = np.radians(lon0 - lon)
    a = np.sin(dphi / 2) ** 2 + np.cos(p1) * math.cos(p2) * np.sin(dl / 2) ** 2
    return 2 * geo.EARTH_R_NM * np.arcsin(np.clip(np.sqrt(a), 0, 1))


def _cheap_latlon(path: str, step: int = 8):
    """Fast downsampled read of lat/lon (every `step`-th fix) for prefiltering.

    Returns (lat_array, lon_array). Avoids a full pandas parse.
    """
    lats, lons = [], []
    with open(path, "r", errors="replace") as f:
        for _ in range(3):
            f.readline()
        i = 0
        for line in f:
            i += 1
            if i % step:
                continue
            p = line.split(",", 6)
            if len(p) > 5:
                la, lo = _flt(p[4]), _flt(p[5])
                if la is not None and lo is not None:
                    lats.append(la)
                    lons.append(lo)
    return np.array(lats), np.array(lons)

DEFAULT_DB = os.path.expanduser(
    "~/Developer/public/flyfun-apps/main/data/nav.db")
DEFAULT_LOG_DIR = os.path.expanduser(
    "~/Library/Mobile Documents/iCloud~net~ro-z~flightlogstats/Documents")

_MODEL = None


def navmodel(db_path: str = DEFAULT_DB):
    global _MODEL
    if _MODEL is None:
        from euro_aip.storage import DatabaseStorage
        _MODEL = DatabaseStorage(db_path).load_model()
    return _MODEL


def resolve(model, ident: str, ref: Optional[Tuple[float, float]] = None):
    """Resolve an airport or waypoint ident to (lat, lon).

    For ambiguous waypoint idents the candidate nearest ``ref`` is chosen.
    """
    ident = ident.upper()
    ap = model.airports.where(ident=ident).first()
    if ap and ap.latitude_deg is not None:
        return (ap.latitude_deg, ap.longitude_deg)
    cands = [w for w in model.waypoints
             if w.name == ident and w.latitude_deg is not None]
    if not cands:
        return None
    if ref and len(cands) > 1:
        cands.sort(key=lambda w: geo.haversine_nm(
            ref[0], ref[1], w.latitude_deg, w.longitude_deg))
    return (cands[0].latitude_deg, cands[0].longitude_deg)


@dataclass
class CorridorFlight:
    path: str
    date: str
    direction: str               # 'out' = anchor->via, 'in' = via->anchor
    track_nm: float
    time_s: float
    still_air_s: float
    avg_tas: float
    avg_gs: float
    avg_alt: float
    max_alt: float
    fuel_gal: float
    near_via_nm: float
    start_hhmm: str = ""
    fms_seq: List[str] = field(default_factory=list)
    far_ident: Optional[str] = None
    lat: np.ndarray = None        # segment track (anchor->via order)
    lon: np.ndarray = None
    offsets: List[float] = field(default_factory=list)  # cross-track profile
    cluster: int = -1
    label: str = ""

    @property
    def name(self) -> str:
        return os.path.basename(self.path)


def _seg_metrics(seg) -> dict:
    lat = seg["lat"].to_numpy()
    lon = seg["lon"].to_numpy()
    legs = np.array([geo.haversine_nm(lat[i - 1], lon[i - 1], lat[i], lon[i])
                     for i in range(1, len(lat))])
    track_nm = float(legs.sum())
    # order-independent duration (segment may be reversed for inbound flights)
    time_s = abs(float((seg["time_utc"].iloc[-1] - seg["time_utc"].iloc[0]).total_seconds()))
    tas = seg["tas"].to_numpy() if "tas" in seg else np.full(len(lat), np.nan)
    # still-air time: each ground leg flown at that leg's TAS, zero wind
    tas_leg = tas[1:]
    valid = np.isfinite(tas_leg) & (tas_leg > 40)
    still_air_s = float(np.sum(legs[valid] / tas_leg[valid]) * 3600.0) if valid.any() else float("nan")
    gs = seg["gs"].to_numpy() if "gs" in seg else np.full(len(lat), np.nan)
    alt = seg["alt_msl"].to_numpy() if "alt_msl" in seg else np.full(len(lat), np.nan)
    fuel = (abs(float(seg["fuel_burn"].iloc[-1] - seg["fuel_burn"].iloc[0]))
            if "fuel_burn" in seg else float("nan"))
    return {
        "track_nm": track_nm,
        "time_s": time_s,
        "still_air_s": still_air_s,
        "avg_tas": float(np.nanmean(tas[np.isfinite(tas) & (tas > 40)])) if np.isfinite(tas).any() else float("nan"),
        "avg_gs": track_nm / (time_s / 3600.0) if time_s > 0 else float("nan"),
        "avg_alt": float(np.nanmean(alt)),
        "max_alt": float(np.nanmax(alt)) if np.isfinite(alt).any() else float("nan"),
        "fuel_gal": fuel,
        "lat": lat, "lon": lon,
    }


def _offset_profile(lat, lon, a_ll, v_ll, n=9) -> List[float]:
    """Signed cross-track offset (nm) from the direct anchor->via line, sampled
    at n fractions of along-track ground distance."""
    legs = np.array([0.0] + [geo.haversine_nm(lat[i - 1], lon[i - 1], lat[i], lon[i])
                             for i in range(1, len(lat))])
    cum = np.cumsum(legs)
    total = cum[-1] if cum[-1] > 0 else 1.0
    out = []
    for f in np.linspace(1.0 / (n + 1), n / (n + 1), n):
        target = f * total
        j = int(np.searchsorted(cum, target))
        j = min(max(j, 0), len(lat) - 1)
        out.append(geo.cross_track_nm(lat[j], lon[j], a_ll[0], a_ll[1], v_ll[0], v_ll[1]))
    return out


def scan_corridor(directory: str, anchor_ll, via_ll, model=None,
                  anchor_radius_nm: float = 8.0, via_radius_nm: float = 14.0,
                  cache: bool = True) -> List[CorridorFlight]:
    """Find flights that fly anchor<->via and measure their common segment.

    Three passes for speed: cheap head/tail peek (reject non-anchor flights),
    cheap downsampled lat/lon read (reject flights that miss the via point),
    then a full parse only for the survivors. Results are cached on disk.
    """
    if cache:
        cached = _cache_load(directory, anchor_ll, via_ll, anchor_radius_nm, via_radius_nm)
        if cached is not None:
            return cached

    apt_arr = _airport_arrays(model) if model is not None else None
    files = sorted(glob.glob(os.path.join(directory, "log_*.csv")))
    flights: List[CorridorFlight] = []
    for fp in files:
        try:
            s = _first_fix(fp)
            e = _last_fix(fp)
        except OSError:
            continue
        if not s or not e:
            continue
        d_start = geo.haversine_nm(s[2], s[3], anchor_ll[0], anchor_ll[1])
        d_end = geo.haversine_nm(e[2], e[3], anchor_ll[0], anchor_ll[1])
        if min(d_start, d_end) > anchor_radius_nm:
            continue  # not an anchor flight (peek-only reject)

        # cheap via prefilter on a downsampled track before the full parse
        cl, co = _cheap_latlon(fp)
        if len(cl) < 5:
            continue
        if _vec_haversine_nm(cl, co, via_ll[0], via_ll[1]).min() > via_radius_nm + 3:
            continue

        try:
            log = parse_g1000(fp)
        except Exception:
            continue
        track = log.track()
        if len(track) < 30:
            continue
        lat = track["lat"].to_numpy()
        lon = track["lon"].to_numpy()
        dv = _vec_haversine_nm(lat, lon, via_ll[0], via_ll[1])
        vi = int(np.argmin(dv))
        if dv[vi] > via_radius_nm:
            continue  # doesn't pass the via point

        direction = "out" if d_start <= d_end else "in"
        if direction == "out":
            seg = track.iloc[:vi + 1]
            far_ll = (e[2], e[3])
        else:
            seg = track.iloc[vi:]
            # for inbound, flip so the segment runs anchor->via for consistency
            seg = seg.iloc[::-1]
            far_ll = (s[2], s[3])
        if len(seg) < 10:
            continue

        m = _seg_metrics(seg)
        far = _nearest_airport(apt_arr, far_ll) if apt_arr is not None else None

        # fixes actually flown on the segment (FMS active-waypoint sequence,
        # split at the via point by direction)
        evs = log.waypoint_events()
        fms_seq: List[str] = []
        if evs:
            de = [geo.haversine_nm(e.lat, e.lon, via_ll[0], via_ll[1]) for e in evs]
            kv = int(np.argmin(de))
            chosen = evs[:kv + 1] if direction == "out" else evs[kv:]
            fms_seq = [e.ident for e in chosen]

        cf = CorridorFlight(
            path=fp, date=s[0], direction=direction,
            track_nm=m["track_nm"], time_s=m["time_s"], still_air_s=m["still_air_s"],
            avg_tas=m["avg_tas"], avg_gs=m["avg_gs"], avg_alt=m["avg_alt"],
            max_alt=m["max_alt"], fuel_gal=m["fuel_gal"], near_via_nm=float(dv[vi]),
            start_hhmm=str(s[1])[:5], fms_seq=fms_seq, far_ident=far,
            lat=m["lat"], lon=m["lon"],
        )
        cf.offsets = _offset_profile(m["lat"], m["lon"], anchor_ll, via_ll)
        flights.append(cf)
    if cache:
        _cache_save(directory, anchor_ll, via_ll, anchor_radius_nm, via_radius_nm, flights)
    return flights


def _matches(rule, f) -> bool:
    s = set(f.fms_seq or [])
    if any(x not in s for x in rule.get("all_of", [])):
        return False
    if rule.get("any_of") and not any(x in s for x in rule["any_of"]):
        return False
    if rule.get("any_prefix") and not any(
            tok.startswith(p) for tok in s for p in rule["any_prefix"]):
        return False
    if any(x in s for x in rule.get("none_of", [])):
        return False
    if "alt_above" in rule and not (f.max_alt and f.max_alt > rule["alt_above"]):
        return False
    if "alt_below" in rule and not (f.max_alt and f.max_alt < rule["alt_below"]):
        return False
    return True


def classify(flights: List[CorridorFlight], rules=DEFAULT_RULES
             ) -> List[List[CorridorFlight]]:
    """Group flights by the first matching route rule (flown fixes + altitude).

    Sets each flight's .label; returns groups ordered by rule order. Flights
    matching no rule fall into 'Direct / other'.
    """
    groups = {}
    for f in flights:
        label = next((r["label"] for r in rules if _matches(r, f)), "Direct / other")
        f.label = label
        groups.setdefault(label, []).append(f)
    order = list(dict.fromkeys([r["label"] for r in rules] + ["Direct / other"]))
    clusters = [groups[l] for l in order if l in groups]
    for cid, cl in enumerate(clusters):
        for f in cl:
            f.cluster = cid
    return clusters


def cluster(flights: List[CorridorFlight], rms_thresh_nm: float = 12.0
            ) -> List[List[CorridorFlight]]:
    """Agglomerative (complete-linkage) clustering of cross-track offset profiles.

    Mutates each flight's .cluster id. Returns clusters (lists of flights),
    ordered largest first.
    """
    if not flights:
        return []
    X = np.array([f.offsets for f in flights])
    groups = [[i] for i in range(len(flights))]

    def gdist(a, b):
        return max(float(np.sqrt(np.mean((X[i] - X[j]) ** 2)))
                   for i in a for j in b)

    while len(groups) > 1:
        best = None
        for x in range(len(groups)):
            for y in range(x + 1, len(groups)):
                d = gdist(groups[x], groups[y])
                if best is None or d < best[0]:
                    best = (d, x, y)
        if best[0] > rms_thresh_nm:
            break
        _, x, y = best
        groups[x] += groups[y]
        del groups[y]

    groups.sort(key=len, reverse=True)
    out = []
    for cid, g in enumerate(groups):
        members = [flights[i] for i in g]
        for f in members:
            f.cluster = cid
        out.append(members)
    return out


def corridor_fixes(model, anchor_ll, via_ll, margin_nm: float = 35.0):
    """Named nav fixes within a bounding box around the anchor->via corridor."""
    mid_lat = (anchor_ll[0] + via_ll[0]) / 2
    dlat = margin_nm / 60.0
    dlon = margin_nm / (60.0 * max(0.2, math.cos(math.radians(mid_lat))))
    lo_lat, hi_lat = min(anchor_ll[0], via_ll[0]) - dlat, max(anchor_ll[0], via_ll[0]) + dlat
    lo_lon, hi_lon = min(anchor_ll[1], via_ll[1]) - dlon, max(anchor_ll[1], via_ll[1]) + dlon
    names, lats, lons, navaid = [], [], [], []
    for w in model.waypoints:
        if w.latitude_deg is None:
            continue
        if lo_lat <= w.latitude_deg <= hi_lat and lo_lon <= w.longitude_deg <= hi_lon:
            names.append(w.name)
            lats.append(w.latitude_deg)
            lons.append(w.longitude_deg)
            navaid.append(bool(getattr(w, "is_navaid", False)))
    return names, np.array(lats), np.array(lons), np.array(navaid)


def label_clusters(clusters: List[List[CorridorFlight]], fixes,
                   anchor_ll, via_ll, near_nm: float = 8.0, sep_nm: float = 6.0):
    """Label each cluster by the fix that best distinguishes it: close for this
    cluster, far for the others. Sets each flight's .label."""
    names, flats, flons, navaid = fixes
    if len(names) == 0:
        for cid, cl in enumerate(clusters):
            for f in cl:
                f.label = f"Group {cid + 1}"
        return

    # mean nearest-approach of each cluster to each fix
    # min distance from a fix to a flight's track, averaged over the cluster
    n_fix = len(names)
    cluster_meandist = []
    for cl in clusters:
        per_fix = np.zeros(n_fix)
        for k in range(n_fix):
            ds = [float(_vec_haversine_nm(f.lat, f.lon, flats[k], flons[k]).min())
                  for f in cl]
            per_fix[k] = np.mean(ds)
        cluster_meandist.append(per_fix)

    used = set()
    for cid, cl in enumerate(clusters):
        mine = cluster_meandist[cid]
        others = (np.min([cluster_meandist[o] for o in range(len(clusters)) if o != cid], axis=0)
                  if len(clusters) > 1 else np.full(n_fix, 1e9))
        # distinctiveness: close to me, far from others
        score = others - mine
        # prefer navaids (recognisable reporting points) over obscure intersections:
        # try navaids first, then any fix, then closest fix.
        label = None
        for pool in (np.where(navaid)[0], np.arange(n_fix)):
            order = sorted(pool, key=lambda k: -score[k])
            for k in order:
                if names[k] in used:
                    continue
                if mine[k] <= near_nm and (len(clusters) == 1 or score[k] >= sep_nm):
                    label = names[k]
                    used.add(names[k])
                    break
            if label:
                break
        if label is None:
            k = int(np.argmin(mine))
            label = names[k] if mine[k] <= near_nm else f"Group {cid + 1}"
        for f in cl:
            f.label = label


def _airport_arrays(model):
    idents, lats, lons = [], [], []
    for ap in model.airports:
        if ap.latitude_deg is not None:
            idents.append(ap.ident)
            lats.append(ap.latitude_deg)
            lons.append(ap.longitude_deg)
    return idents, np.array(lats), np.array(lons)


def _nearest_airport(apt_arr, ll, max_nm: float = 6.0) -> Optional[str]:
    idents, lats, lons = apt_arr
    d = _vec_haversine_nm(lats, lons, ll[0], ll[1])
    j = int(np.argmin(d))
    return idents[j] if d[j] <= max_nm else None


def _cache_key(directory, anchor_ll, via_ll, ar, vr) -> str:
    files = sorted(glob.glob(os.path.join(directory, "log_*.csv")))
    sig = "".join(f"{os.path.basename(f)}:{os.path.getsize(f)};" for f in files)
    key = f"v{CACHE_VERSION}|{directory}|{anchor_ll}|{via_ll}|{ar}|{vr}|{sig}"
    return hashlib.md5(key.encode()).hexdigest()


def _cache_path(directory, anchor_ll, via_ll, ar, vr) -> str:
    return os.path.join(CACHE_DIR, f"corridor_{_cache_key(directory, anchor_ll, via_ll, ar, vr)}.pkl")


def _cache_load(directory, anchor_ll, via_ll, ar, vr):
    p = _cache_path(directory, anchor_ll, via_ll, ar, vr)
    if os.path.exists(p):
        try:
            with open(p, "rb") as f:
                return pickle.load(f)
        except Exception:
            return None
    return None


def _cache_save(directory, anchor_ll, via_ll, ar, vr, flights):
    os.makedirs(CACHE_DIR, exist_ok=True)
    try:
        with open(_cache_path(directory, anchor_ll, via_ll, ar, vr), "wb") as f:
            pickle.dump(flights, f)
    except Exception:
        pass
