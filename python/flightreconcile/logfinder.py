"""Find the G1000 CSV log that matches a planned navlog.

Each log is named ``log_YYMMDD_HHMMSS_<airport>.csv`` (airport sometimes blank).
We match a navlog to a log by:
  1. date from the filename == the navlog date (cheap prefilter), then
  2. the log's *start* position ≈ navlog origin and *end* position ≈ destination.

Peeking only reads the first valid fix and tail of each file, so scanning a big
directory stays fast.
"""
from __future__ import annotations

import glob
import os
import re
from dataclasses import dataclass
from typing import List, Optional, Tuple

from . import geo
from .navlog_parser import Navlog

_FNAME = re.compile(r"log_(\d{6})_(\d{6})_", re.IGNORECASE)


def _flt(s: str) -> Optional[float]:
    s = s.strip()
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _first_fix(path: str, max_scan: int = 5000):
    """First data row with a valid lat/lon -> (date, time, lat, lon)."""
    with open(path, "r", errors="replace") as f:
        for _ in range(3):            # skip airframe / units / header lines
            f.readline()
        for _ in range(max_scan):
            line = f.readline()
            if not line:
                break
            p = line.split(",")
            if len(p) > 6:
                lat, lon = _flt(p[4]), _flt(p[5])
                if lat is not None and lon is not None:
                    return p[0].strip(), p[1].strip(), lat, lon
    return None


def _last_fix(path: str, nbytes: int = 32768):
    """Last data row with a valid lat/lon -> (date, time, lat, lon)."""
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        f.seek(max(0, size - nbytes))
        data = f.read().decode("utf-8", "replace")
    for line in reversed(data.splitlines()):
        p = line.split(",")
        if len(p) > 6:
            lat, lon = _flt(p[4]), _flt(p[5])
            if lat is not None and lon is not None:
                return p[0].strip(), p[1].strip(), lat, lon
    return None


@dataclass
class LogMatch:
    path: str
    start_dist_nm: float        # log start -> navlog origin
    end_dist_nm: float          # log end   -> navlog destination
    start_time: Optional[str] = None

    @property
    def score(self) -> float:
        return self.start_dist_nm + self.end_dist_nm


def find_logs(nav: Navlog, directory: str,
              match_nm: float = 12.0) -> Tuple[List[LogMatch], List[LogMatch]]:
    """Return (matches, all_ranked).

    `matches` are candidates whose start≈origin AND end≈destination within
    `match_nm`, best first. `all_ranked` is every scored candidate (for
    diagnostics when nothing matches cleanly).
    """
    wps = [w for w in nav.waypoints if w.lat is not None]
    if not wps:
        return [], []
    o_lat, o_lon = wps[0].lat, wps[0].lon
    d_lat, d_lon = wps[-1].lat, wps[-1].lon
    datestr = nav.date.strftime("%y%m%d") if nav.date else None

    files = sorted(glob.glob(os.path.join(directory, "log_*.csv")))
    # prefilter by date in the filename; fall back to all if that yields nothing
    dated = []
    for fp in files:
        m = _FNAME.search(os.path.basename(fp))
        if m and (datestr is None or m.group(1) == datestr):
            dated.append(fp)
    candidates = dated if dated else files

    ranked: List[LogMatch] = []
    for fp in candidates:
        try:
            start = _first_fix(fp)
            end = _last_fix(fp)
        except OSError:
            continue
        if not start or not end:
            continue
        sd = geo.haversine_nm(start[2], start[3], o_lat, o_lon)
        ed = geo.haversine_nm(end[2], end[3], d_lat, d_lon)
        ranked.append(LogMatch(fp, sd, ed, start_time=f"{start[0]} {start[1]}"))

    ranked.sort(key=lambda m: m.score)
    matches = [m for m in ranked
               if m.start_dist_nm <= match_nm and m.end_dist_nm <= match_nm]
    return matches, ranked
