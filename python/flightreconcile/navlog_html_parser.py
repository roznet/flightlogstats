"""Parse a ForeFlight navlog exported as **HTML**.

ForeFlight can save a navlog as HTML, which carries the same data as the PDF but
in real <table> elements - far more robust to parse than the PDF's positional
text. Produces the same ``Navlog`` / ``PlannedWaypoint`` structures as
``navlog_parser`` so the rest of the pipeline is unchanged.
"""
from __future__ import annotations

import html as _html
import re
from typing import List, Optional

import pandas as pd

from . import geo
from .navlog_parser import (
    Navlog, PlannedWaypoint, _num, _hhmm_to_s, _split_pair, parse_header_date,
)

_HDR_RE = re.compile(r"([A-Z]{4})\s*[—–-]\s*([A-Z]{4})\s*\([^)]*\)\s*in\s+(\S+)")


def _toks(cell) -> List[str]:
    """Whitespace-split a table cell, dropping NaN/blank tokens."""
    if cell is None:
        return []
    s = str(cell).strip()
    if s in ("", "nan", "NaN"):
        return []
    return [t for t in s.split() if t]


def _val(tok: Optional[str]):
    return None if tok in (None, "-", "--", "") else tok


def parse_navlog_html(path: str) -> Navlog:
    raw = open(path, encoding="utf-8").read()
    nav = Navlog()
    _parse_text(raw, nav)
    # header=None: never promote a row to column names, so single-row tables
    # (the summary metrics) keep their data and indexing stays uniform.
    tables = pd.read_html(path, header=None)
    _parse_summary(tables, nav)
    _parse_fuel(tables, nav)
    nav.waypoints = _parse_waypoints(tables)
    if not nav.dist_total_nm and nav.waypoints:
        nav.dist_total_nm = nav.waypoints[0].dist_rem
    return nav


def _parse_text(raw: str, nav: Navlog) -> None:
    text = _html.unescape(re.sub(r"<[^>]+>", "\n", raw))
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    for i, l in enumerate(lines):
        m = _HDR_RE.search(l)
        if m:
            nav.departure, nav.destination, nav.aircraft = m.groups()
            nav.date = parse_header_date(l)
        if l == "Route" and i + 1 < len(lines):
            nav.route = lines[i + 1]


def _find_table(tables, predicate):
    for t in tables:
        try:
            if predicate(t):
                return t
        except Exception:
            continue
    return None


def _parse_summary(tables, nav: Navlog) -> None:
    t = _find_table(tables, lambda t: str(t.iloc[0, 0]).startswith("ETE"))
    if t is None:
        return
    # each cell packs "Label  value" (label and value split by 2+ spaces)
    d = {}
    for cell in t.iloc[0].tolist():
        parts = re.split(r"\s{2,}", str(cell).strip(), maxsplit=1)
        if len(parts) == 2:
            d[parts[0].strip()] = parts[1].strip()
    ete = d.get("ETE", "")
    mm = re.search(r"(\d+)h(\d+)m", ete)
    if mm:
        nav.ete_total_s = int(mm.group(1)) * 3600 + int(mm.group(2)) * 60
    dist = re.search(r"([\d.]+)\s*NM", d.get("Distance", ""))
    if dist:
        nav.dist_total_nm = float(dist.group(1))
    tas = re.search(r"(\d+)\s*kt", d.get("Avg TAS", ""))
    if tas:
        nav.avg_tas = float(tas.group(1))
    alt = re.search(r"(\d+)", d.get("Altitude", "").replace(",", ""))
    if alt:
        nav.cruise_alt_ft = int(alt.group(1))
    nav.avg_wind = d.get("Avg Wind")


_FUEL_LABELS = {"Taxi", "Destination", "Alternate Fuel", "Final Reserve",
                "Additional", "Min required", "Extra", "Total", "Landing"}


def _parse_fuel(tables, nav: Navlog) -> None:
    t = _find_table(tables, lambda t: "Taxi" in t.iloc[:, 0].astype(str).values)
    if t is None:
        return
    for _, row in t.iterrows():
        label = str(row.iloc[0]).split("  ")[0].strip()
        label = next((k for k in _FUEL_LABELS if label.startswith(k)), None)
        if not label:
            continue
        gal = _num(str(row.iloc[1]))
        time_s = _hhmm_to_s(str(row.iloc[2])) if len(row) > 2 else None
        if gal is not None:
            nav.fuel_plan[label] = {"gal": gal, "time_s": time_s}


def _is_waypoint_table(t) -> bool:
    if t.shape[0] < 3:
        return False
    col0 = t.iloc[:, 0].astype(str)
    return sum(1 for v in col0 if any(geo.is_coord(tok) for tok in v.split())) >= 3


def _parse_waypoints(tables) -> List[PlannedWaypoint]:
    t = _find_table(tables, _is_waypoint_table)
    if t is None:
        return []
    wpts: List[PlannedWaypoint] = []
    for _, row in t.iterrows():
        c = [row.iloc[i] if i < len(row) else None for i in range(13)]
        name_toks = _toks(c[0])
        if not name_toks:
            continue
        # name / coordinate / optional navaid
        coord = next((tk for tk in name_toks if geo.is_coord(tk)), None)
        if coord is None:
            continue
        name = name_toks[0]
        wp = PlannedWaypoint(name=name, coord_raw=coord)
        ll = geo.parse_ff_coord(coord)
        if ll:
            wp.lat, wp.lon = ll
        wp.is_pseudo = name.startswith("-") and name.endswith("-")
        rest = [tk for tk in name_toks[1:] if tk != coord and tk.isupper()]
        if rest:
            wp.navaid = rest[0]

        # AWY / ALT / MSA
        awy = _toks(c[2])
        if awy:
            if re.search(r"[A-Za-z]", awy[0]):           # airway present
                wp.airway = _val(awy[0])
                nums = awy[1:]
            else:
                nums = awy
            if len(nums) >= 1:
                wp.altitude_ft = int(_num(nums[0])) if _num(nums[0]) is not None else None
            if len(nums) >= 2:
                wp.msa = int(_num(nums[1])) if _num(nums[1]) is not None else None

        # WIND: comp / dir-spd / oat-isa
        wind = _toks(c[3])
        if len(wind) >= 1:
            wp.wind_comp_raw = _val(wind[0])
        if len(wind) >= 2:
            wp.wind_dir, wp.wind_speed = _split_pair(_val(wind[1]))
        if len(wind) >= 3:
            wp.oat, wp.isa_dev = _split_pair(_val(wind[2]))

        # MAG: hdg / crs
        mag = _toks(c[4])
        if len(mag) >= 1:
            wp.mag_hdg = _num(_val(mag[0]))
        if len(mag) >= 2:
            wp.crs = _num(_val(mag[1]))

        # KT: tas / gs
        kt = _toks(c[5])
        if len(kt) >= 1:
            wp.tas = _num(_val(kt[0]))
        if len(kt) >= 2:
            wp.gs = _num(_val(kt[1]))

        # DIST: leg / rem
        dist = _toks(c[6])
        if len(dist) >= 1:
            wp.dist_leg = _num(_val(dist[0]))
        if len(dist) >= 2:
            wp.dist_rem = _num(_val(dist[1]))

        wp.fuel_rem = _num(_val((_toks(c[7]) or [None])[0]))
        wp.fuel_used = _num(_val((_toks(c[8]) or [None])[0]))
        wp.flow = _num(_val((_toks(c[9]) or [None])[0]))

        # TIMES: leg / ete-remaining (col10), eta-elapsed (col11)
        times = _toks(c[10])
        if len(times) >= 1:
            wp.leg_time_s = _hhmm_to_s(_val(times[0]))
        if len(times) >= 2:
            wp.ete_remaining_s = _hhmm_to_s(_val(times[1]))
        wp.eta_elapsed_s = _hhmm_to_s(_val((_toks(c[11]) or [None])[0]))

        wpts.append(wp)
    return wpts


if __name__ == "__main__":
    import sys
    nav = parse_navlog_html(sys.argv[1])
    print(f"{nav.departure} -> {nav.destination}  {nav.aircraft}")
    print(f"dist={nav.dist_total_nm} ete={nav.ete_total_s}s tas={nav.avg_tas} alt={nav.cruise_alt_ft}")
    print(f"route: {nav.route}")
    print(f"fuel: {nav.fuel_plan}")
    print(f"{len(nav.waypoints)} waypoints:")
    for w in nav.waypoints:
        print(f"  {w.name:11s} {w.coord_raw or '':17s} alt={w.altitude_ft} "
              f"wind={w.wind_dir}/{w.wind_speed} crs={w.crs} tas={w.tas} gs={w.gs} "
              f"leg={w.dist_leg} rem={w.dist_rem} frem={w.fuel_rem} used={w.fuel_used} "
              f"eta={w.eta_elapsed_s}")
