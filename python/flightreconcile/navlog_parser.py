"""Parse a ForeFlight International Navlog PDF into structured planned data.

The navlog has a very regular layout. Each waypoint occupies up to three
stacked text sub-rows, and every field lives in a fixed column (by x position):

  sub-row 0 (name row): NAME  AWY  windComp  magHDG  TAS  distLEG  fuelREM  fuelUSED  FLOW  legTIME  etaELAPSED
  sub-row 1 (coord row): COORD ALT  windDIR/SPD crs  GS   distREM           (blank)         eteREMAIN
  sub-row 2 (msa row):         MSA  OAT/ISA                                  (+ optional navaid name/freq)

We anchor on the coordinate row (unambiguous regex), take the row above as the
name/data row and the row(s) below as the MSA/OAT row.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field, asdict
from typing import Optional, List, Dict, Any

import pdfplumber

from . import geo


# ---- column x-bins (by word x0). Tuned to the ForeFlight navlog layout. ----
def _col_of(x: float) -> str:
    if x < 130:
        return "name"
    if x < 165:
        return "awy"      # awy / alt / msa by sub-row
    if x < 212:
        return "wind"     # comp / dir-spd / oat-isa by sub-row
    if x < 242:
        return "hdg"      # mag hdg / crs
    if x < 268:
        return "tas"      # tas / gs
    if x < 296:
        return "dist"     # leg / rem
    if x < 326:
        return "fuelrem"
    if x < 362:
        return "fuelused"
    if x < 392:
        return "flow"
    if x < 416:
        return "time1"    # leg time / ete
    if x < 452:
        return "time2"    # eta-elapsed
    return "time3"


_HEADER_TOKENS = {
    "AWY", "WIND", "MAG", "KT", "DIST", "FUEL", "G", "TIMES", "REMARKS",
    "WAYPOINT", "ALT", "DIR/SPD", "HDG", "TAS", "LEG", "REM", "USED",
    "FLOW", "ETE", "ETA", "COORDINATES", "MSA", "OAT/ISA", "CRS", "GS",
    "ACTL", "ATE", "ATA",
}


@dataclass
class PlannedWaypoint:
    name: str
    lat: Optional[float] = None
    lon: Optional[float] = None
    coord_raw: Optional[str] = None
    airway: Optional[str] = None
    altitude_ft: Optional[int] = None
    msa: Optional[int] = None
    wind_dir: Optional[float] = None       # degrees TRUE wind blows from
    wind_speed: Optional[float] = None     # kt
    wind_comp_raw: Optional[str] = None    # e.g. "H12" / "T9"
    oat: Optional[float] = None            # deg C
    isa_dev: Optional[float] = None        # deg C vs ISA
    mag_hdg: Optional[float] = None
    crs: Optional[float] = None            # magnetic course
    tas: Optional[float] = None
    gs: Optional[float] = None
    dist_leg: Optional[float] = None       # nm this leg
    dist_rem: Optional[float] = None       # nm remaining to destination
    fuel_rem: Optional[float] = None       # gal remaining
    fuel_used: Optional[float] = None      # gal used cumulative
    flow: Optional[float] = None           # gph
    leg_time_s: Optional[int] = None       # seconds for this leg
    ete_remaining_s: Optional[int] = None  # seconds remaining to dest
    eta_elapsed_s: Optional[int] = None    # seconds elapsed since departure
    is_pseudo: bool = False                # -TOC- / -TOD-
    navaid: Optional[str] = None

    def as_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class Navlog:
    departure: Optional[str] = None
    destination: Optional[str] = None
    aircraft: Optional[str] = None
    route: Optional[str] = None
    ete_total_s: Optional[int] = None
    dist_total_nm: Optional[float] = None
    avg_tas: Optional[float] = None
    cruise_alt_ft: Optional[int] = None
    avg_wind: Optional[str] = None
    fuel_plan: Dict[str, Any] = field(default_factory=dict)
    waypoints: List[PlannedWaypoint] = field(default_factory=list)


def _num(s: Optional[str]) -> Optional[float]:
    if s is None:
        return None
    s = s.strip()
    if s in ("", "-", "--"):
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _hhmm_to_s(s: Optional[str]) -> Optional[int]:
    if not s or s.strip() in ("-", "", "--"):
        return None
    parts = s.strip().split(":")
    try:
        if len(parts) == 2:
            return int(parts[0]) * 3600 + int(parts[1]) * 60
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
    except ValueError:
        return None
    return None


def _split_pair(s: Optional[str]):
    """'264/018' -> (264.0, 18.0); '+13/-2' -> (13.0, -2.0)."""
    if not s or "/" not in s:
        return None, None
    a, b = s.split("/", 1)
    return _num(a), _num(b)


def _rows_from_pages(pdf, page_indices):
    """Return ordered list of rows; each row is dict[col] -> list[(x0,text)].

    Header rows and the page footer URL are dropped. Rows are globally ordered
    across pages so a waypoint split across a page boundary stays contiguous.
    """
    rows = []
    for pi in page_indices:
        page = pdf.pages[pi]
        words = page.extract_words()
        # cluster words into rows by 'top'
        buckets: Dict[int, list] = {}
        for w in words:
            key = round(w["top"] / 3)
            buckets.setdefault(key, []).append(w)
        for key in sorted(buckets):
            ws = buckets[key]
            texts = {w["text"] for w in ws}
            # skip repeated header rows and footer
            if texts & _HEADER_TOKENS and not any(geo.is_coord(w["text"]) for w in ws):
                # header-ish row (but never drop a row that holds a coordinate)
                if len(texts & _HEADER_TOKENS) >= 2:
                    continue
            if any(w["text"].startswith("https://") for w in ws):
                continue
            # page title / footer (repeats on every page, breaks cross-page joins)
            if {"ForeFlight", "Navlog"} <= texts or "Page" in texts:
                continue
            cols: Dict[str, list] = {}
            for w in ws:
                cols.setdefault(_col_of(w["x0"]), []).append((w["x0"], w["text"]))
            for c in cols:
                cols[c].sort()
            rows.append({"order": pi * 100000 + key, "cols": cols})
    rows.sort(key=lambda r: r["order"])
    return rows


def _first(cols, col):
    vals = cols.get(col)
    return vals[0][1] if vals else None


def parse_navlog(path: str) -> Navlog:
    nav = Navlog()
    with pdfplumber.open(path) as pdf:
        _parse_summary(pdf.pages[0], nav)
        # table pages: any page that holds at least a few coordinate tokens
        # (the column header only appears on the first table page).
        table_pages = []
        for i, page in enumerate(pdf.pages):
            txt = page.extract_text() or ""
            if sum(1 for t in txt.split() if geo.is_coord(t)) >= 3:
                table_pages.append(i)
        rows = _rows_from_pages(pdf, table_pages)
        nav.waypoints = _parse_waypoints(rows)
    return nav


def _parse_waypoints(rows) -> List[PlannedWaypoint]:
    # indices of coordinate rows
    coord_idx = []
    for i, r in enumerate(rows):
        nm = _first(r["cols"], "name")
        if nm and geo.is_coord(nm):
            coord_idx.append(i)

    wpts: List[PlannedWaypoint] = []
    for k, ci in enumerate(coord_idx):
        data = rows[ci - 1]["cols"] if ci > 0 else {}
        coord = rows[ci]["cols"]
        # extra rows: between this coord and the *next* data row
        next_ci = coord_idx[k + 1] if k + 1 < len(coord_idx) else len(rows)
        extra_rows = rows[ci + 1: max(ci + 1, next_ci - 1)]

        name = _first(data, "name")
        if not name:
            continue
        wp = PlannedWaypoint(name=name)
        wp.is_pseudo = name.startswith("-") and name.endswith("-")

        # coordinate row
        wp.coord_raw = _first(coord, "name")
        ll = geo.parse_ff_coord(wp.coord_raw) if wp.coord_raw else None
        if ll:
            wp.lat, wp.lon = ll

        # data (name) row fields
        wp.airway = _first(data, "awy")
        wp.wind_comp_raw = _first(data, "wind")
        wp.mag_hdg = _num(_first(data, "hdg"))
        wp.tas = _num(_first(data, "tas"))
        wp.dist_leg = _num(_first(data, "dist"))
        wp.fuel_rem = _num(_first(data, "fuelrem"))
        wp.fuel_used = _num(_first(data, "fuelused"))
        wp.flow = _num(_first(data, "flow"))
        wp.leg_time_s = _hhmm_to_s(_first(data, "time1"))
        wp.eta_elapsed_s = _hhmm_to_s(_first(data, "time2"))

        # coord row fields
        wp.altitude_ft = int(_num(_first(coord, "awy"))) if _num(_first(coord, "awy")) else None
        wdir, wspd = _split_pair(_first(coord, "wind"))
        wp.wind_dir, wp.wind_speed = wdir, wspd
        wp.crs = _num(_first(coord, "hdg"))
        wp.gs = _num(_first(coord, "tas"))
        wp.dist_rem = _num(_first(coord, "dist"))
        wp.ete_remaining_s = _hhmm_to_s(_first(coord, "time1"))

        # extra (msa / oat-isa / navaid) rows
        for er in extra_rows:
            ec = er["cols"]
            msa = _num(_first(ec, "awy"))
            if msa is not None and wp.msa is None:
                wp.msa = int(msa)
            oat, isa = _split_pair(_first(ec, "wind"))
            if oat is not None:
                wp.oat, wp.isa_dev = oat, isa
            nm = _first(ec, "name")
            if nm and not geo.is_coord(nm) and wp.navaid is None and nm.isupper():
                wp.navaid = nm

        wpts.append(wp)
    return wpts


_RE_HDR = re.compile(
    r"([A-Z]{4})\s+[—-]\s+([A-Z]{4}).*?in\s+(\S+)", re.S
)


def _parse_summary(page, nav: Navlog) -> None:
    txt = page.extract_text() or ""
    lines = [l.strip() for l in txt.splitlines()]

    m = _RE_HDR.search(txt)
    if m:
        nav.departure, nav.destination, nav.aircraft = m.group(1), m.group(2), m.group(3)

    # Top metrics: a label line "ETE Distance Avg Wind ..." followed by a
    # value line "2h58m 538NM 7kt tail (261°/015) ... 174kt 11000'".
    for i, l in enumerate(lines):
        if l.startswith("ETE") and "Distance" in l and i + 1 < len(lines):
            v = lines[i + 1]
            mm = re.search(r"(\d+)h(\d+)m", v)
            if mm:
                nav.ete_total_s = int(mm.group(1)) * 3600 + int(mm.group(2)) * 60
            d = re.search(r"([\d.]+)NM", v)
            if d:
                nav.dist_total_nm = float(d.group(1))
            # avg TAS is the last "<n>kt" on the line (the first is the wind)
            kts = re.findall(r"(\d+)kt", v)
            if kts:
                nav.avg_tas = float(kts[-1])
            a = re.search(r"(\d+)'", v)
            if a:
                nav.cruise_alt_ft = int(a.group(1))
            w = re.search(r"([\d.]+kt\s+\w+\s+\([^)]*\))", v)
            if w:
                nav.avg_wind = w.group(1)
            break

    # Route block
    for i, l in enumerate(lines):
        if l == "Route":
            route_lines = []
            j = i + 1
            while j < len(lines) and lines[j] and not lines[j].startswith("FUEL"):
                route_lines.append(lines[j])
                j += 1
            nav.route = " ".join(route_lines)
            break

    # Fuel plan rows like "Destination 51.8 2:58"
    for l in lines:
        m = re.match(r"(Taxi|Destination|Final Reserve|Min required|Extra|Total|Landing)\s+([\d.]+)(?:\s+([\d:]+))?", l)
        if m:
            nav.fuel_plan[m.group(1)] = {
                "gal": float(m.group(2)),
                "time_s": _hhmm_to_s(m.group(3)) if m.group(3) else None,
            }


if __name__ == "__main__":
    import sys, json
    nav = parse_navlog(sys.argv[1])
    print(f"{nav.departure} -> {nav.destination}  {nav.aircraft}")
    print(f"dist={nav.dist_total_nm} ete={nav.ete_total_s}s tas={nav.avg_tas} alt={nav.cruise_alt_ft}")
    print(f"route: {nav.route}")
    print(f"fuel: {json.dumps(nav.fuel_plan)}")
    print(f"{len(nav.waypoints)} waypoints:")
    for w in nav.waypoints:
        print(f"  {w.name:8s} {w.coord_raw or '':17s} alt={w.altitude_ft} "
              f"wind={w.wind_dir}/{w.wind_speed} crs={w.crs} tas={w.tas} gs={w.gs} "
              f"legnm={w.dist_leg} rem={w.dist_rem} fuelrem={w.fuel_rem} "
              f"used={w.fuel_used} flow={w.flow} eta={w.eta_elapsed_s}")
