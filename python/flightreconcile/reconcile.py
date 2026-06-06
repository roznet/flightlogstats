"""Reconcile a planned navlog against a flown G1000 log.

Three complementary layers:

  A. Waypoint sequencing  - match planned idents to the FMS AtvWpt events.
  B. Geometric abeam      - for every planned waypoint, the closest point on the
                            actual track gives lateral offset + abeam time/fuel.
  C. Route totals         - planned vs flown distance/time/fuel + shortcut saving.

Layer B is the workhorse: it is defined for every planned waypoint (flown or
skipped) and yields a uniform planned-vs-actual comparison. Layer A adds the
"this was an active FMS waypoint" confirmation and the closest in-FMS distance.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import List, Optional, Dict

import numpy as np

from . import geo
from .navlog_parser import Navlog, PlannedWaypoint
from .g1000_parser import FlightLog, WptEvent, PhaseMetrics

OVERFLOWN_NM = 5.0   # lateral offset below which we treat the wpt as overflown


@dataclass
class WaypointRecon:
    name: str
    planned: PlannedWaypoint
    lateral_offset_nm: Optional[float] = None   # min track distance to planned pt
    abeam_elapsed_s: Optional[float] = None      # actual time when abeam
    abeam_fuel: Optional[float] = None           # actual fuel remaining when abeam
    abeam_gs: Optional[float] = None
    abeam_tas: Optional[float] = None
    abeam_wind_dir: Optional[float] = None
    abeam_wind_spd: Optional[float] = None
    abeam_alt: Optional[float] = None
    fms_event: Optional[WptEvent] = None         # matched FMS sequencing event
    overflown: bool = False

    # deltas (actual - planned), populated when both sides available
    eta_delta_s: Optional[float] = None
    fuel_used_actual: Optional[float] = None
    fuel_used_delta: Optional[float] = None
    gs_delta: Optional[float] = None
    headwind_planned: Optional[float] = None
    headwind_actual: Optional[float] = None


@dataclass
class LegRecon:
    frm: str
    to: str
    planned_dist_nm: Optional[float] = None
    actual_dist_nm: Optional[float] = None
    planned_time_s: Optional[float] = None
    actual_time_s: Optional[float] = None
    planned_fuel: Optional[float] = None
    actual_fuel: Optional[float] = None        # totaliser (integrated FFlow)
    actual_fuel_tank: Optional[float] = None   # tank-sensor delta over the leg
    planned_gs: Optional[float] = None
    actual_gs: Optional[float] = None
    reliable: bool = False                     # both endpoints overflown


@dataclass
class Reconciliation:
    nav: Navlog
    log: FlightLog
    waypoints: List[WaypointRecon] = field(default_factory=list)
    legs: List[LegRecon] = field(default_factory=list)
    off_plan: List = field(default_factory=list)   # flown WptEvents not in plan
    totals: Dict = field(default_factory=dict)


def _track_arrays(log: FlightLog):
    t = log.track()
    return {
        "idx": t.index.to_numpy(),
        "lat": t["lat"].to_numpy(),
        "lon": t["lon"].to_numpy(),
        "elapsed": (t["time_utc"] - log.start).dt.total_seconds().to_numpy(),
        "fuel": (t["fuel_l"].fillna(0) + t["fuel_r"].fillna(0)).to_numpy(),
        "burn": t["fuel_burn"].to_numpy() if "fuel_burn" in t else np.full(len(t), np.nan),
        "gs": t["gs"].to_numpy() if "gs" in t else np.full(len(t), np.nan),
        "tas": t["tas"].to_numpy() if "tas" in t else np.full(len(t), np.nan),
        "alt": t["alt_msl"].to_numpy() if "alt_msl" in t else np.full(len(t), np.nan),
        "wdir": t["wind_dir"].to_numpy() if "wind_dir" in t else np.full(len(t), np.nan),
        "wspd": t["wind_spd"].to_numpy() if "wind_spd" in t else np.full(len(t), np.nan),
        "trk": t["trk"].to_numpy() if "trk" in t else np.full(len(t), np.nan),
    }


def _vec_haversine_nm(lat, lon, lat0, lon0):
    """Vectorised great-circle distance (NM) from array of points to one point."""
    p1 = np.radians(lat)
    p2 = math.radians(lat0)
    dphi = np.radians(lat0 - lat)
    dlmb = np.radians(lon0 - lon)
    a = np.sin(dphi / 2) ** 2 + np.cos(p1) * math.cos(p2) * np.sin(dlmb / 2) ** 2
    return 2 * geo.EARTH_R_NM * np.arcsin(np.clip(np.sqrt(a), 0, 1))


def _nan_to_none(v):
    return None if v is None or (isinstance(v, float) and math.isnan(v)) else float(v)


def reconcile(nav: Navlog, log: FlightLog) -> Reconciliation:
    rec = Reconciliation(nav=nav, log=log)
    ta = _track_arrays(log)
    events = {e.ident: e for e in log.waypoint_events()}
    fuel_start = log.fuel_at_start()

    # ---- Layer A + B per planned waypoint ----
    for wp in nav.waypoints:
        wr = WaypointRecon(name=wp.name, planned=wp)
        wr.fms_event = events.get(wp.name)
        if wp.lat is not None and wp.lon is not None and len(ta["lat"]):
            d = _vec_haversine_nm(ta["lat"], ta["lon"], wp.lat, wp.lon)
            j = int(np.argmin(d))
            wr.lateral_offset_nm = float(d[j])
            wr.abeam_elapsed_s = float(ta["elapsed"][j])
            wr.abeam_fuel = float(ta["fuel"][j]) if ta["fuel"][j] > 1 else None
            wr.abeam_gs = _nan_to_none(ta["gs"][j])
            wr.abeam_tas = _nan_to_none(ta["tas"][j])
            wr.abeam_alt = _nan_to_none(ta["alt"][j])
            wr.abeam_wind_dir = _nan_to_none(ta["wdir"][j])
            wr.abeam_wind_spd = _nan_to_none(ta["wspd"][j])
            wr.overflown = wr.lateral_offset_nm <= OVERFLOWN_NM
            trk = _nan_to_none(ta["trk"][j])

            # deltas
            if wp.eta_elapsed_s is not None:
                wr.eta_delta_s = wr.abeam_elapsed_s - wp.eta_elapsed_s
            # actual fuel used = integrated fuel-flow burn up to the abeam point
            burn = ta["burn"][j]
            if not math.isnan(burn):
                wr.fuel_used_actual = float(burn)
                if wp.fuel_used is not None:
                    wr.fuel_used_delta = wr.fuel_used_actual - wp.fuel_used
            if wp.gs is not None and wr.abeam_gs is not None:
                wr.gs_delta = wr.abeam_gs - wp.gs
            # headwind components (planned vs actual) along respective course
            if wp.wind_dir is not None and wp.wind_speed is not None and wp.crs is not None:
                wr.headwind_planned, _ = geo.wind_components(wp.wind_dir, wp.wind_speed, wp.crs)
            if wr.abeam_wind_dir is not None and wr.abeam_wind_spd is not None and trk is not None:
                wr.headwind_actual, _ = geo.wind_components(wr.abeam_wind_dir, wr.abeam_wind_spd, trk)
        rec.waypoints.append(wr)

    # ---- per-leg (between consecutive planned waypoints, using abeam) ----
    for a, b in zip(rec.waypoints, rec.waypoints[1:]):
        leg = LegRecon(frm=a.name, to=b.name)
        leg.planned_dist_nm = b.planned.dist_leg
        leg.planned_time_s = b.planned.leg_time_s
        leg.planned_gs = b.planned.gs
        leg.reliable = a.overflown and b.overflown
        if a.planned.fuel_used is not None and b.planned.fuel_used is not None:
            leg.planned_fuel = b.planned.fuel_used - a.planned.fuel_used
        if a.abeam_elapsed_s is not None and b.abeam_elapsed_s is not None:
            leg.actual_time_s = b.abeam_elapsed_s - a.abeam_elapsed_s
            if a.fuel_used_actual is not None and b.fuel_used_actual is not None:
                leg.actual_fuel = b.fuel_used_actual - a.fuel_used_actual
            if a.abeam_fuel is not None and b.abeam_fuel is not None:
                leg.actual_fuel_tank = a.abeam_fuel - b.abeam_fuel
            # distance flown along track between the two abeam samples
            ia = int(np.argmin(np.abs(ta["elapsed"] - a.abeam_elapsed_s)))
            ib = int(np.argmin(np.abs(ta["elapsed"] - b.abeam_elapsed_s)))
            if ib > ia:
                seg_lat, seg_lon = ta["lat"][ia:ib + 1], ta["lon"][ia:ib + 1]
                leg.actual_dist_nm = float(np.sum(
                    _consecutive_nm(seg_lat, seg_lon)))
                if leg.actual_time_s and leg.actual_time_s > 0:
                    leg.actual_gs = leg.actual_dist_nm / (leg.actual_time_s / 3600.0)
        rec.legs.append(leg)

    # waypoints actually flown (FMS) that were not in the plan (vectors/arrival)
    planned_names = {w.name for w in nav.waypoints}
    rec.off_plan = [e for e in log.waypoint_events() if e.ident not in planned_names]

    rec.totals = _totals(nav, log, rec)
    return rec


def _consecutive_nm(lat, lon):
    out = np.zeros(max(0, len(lat) - 1))
    for i in range(1, len(lat)):
        out[i - 1] = geo.haversine_nm(lat[i - 1], lon[i - 1], lat[i], lon[i])
    return out


def _planned_route_distance(nav: Navlog) -> float:
    pts = [(w.lat, w.lon) for w in nav.waypoints if w.lat is not None]
    return sum(geo.haversine_nm(*pts[i - 1], *pts[i]) for i in range(1, len(pts)))


def _mean(vals):
    vals = [v for v in vals if v is not None]
    return sum(vals) / len(vals) if vals else None


def _cruise_wind(log: FlightLog):
    """Vector-average wind over the cruise (alt > 5000 ft, GS > 100 kt)."""
    df = log.df
    mask = (df.get("alt_msl", 0) > 5000) & (df.get("gs", 0) > 100)
    sub = df[mask]
    if not len(sub):
        return None, None
    import numpy as _np
    d = sub["wind_dir"].dropna()
    s = sub.loc[d.index, "wind_spd"]
    if not len(d):
        return None, None
    rad = _np.radians(d.to_numpy())
    u = _np.nanmean(s.to_numpy() * _np.sin(rad))
    v = _np.nanmean(s.to_numpy() * _np.cos(rad))
    direction = (math.degrees(math.atan2(u, v)) + 360) % 360
    speed = math.hypot(u, v)
    return round(direction), round(speed, 1)


def _planned_climb_descent(nav: Navlog):
    """Build planned Climb (dep->TOC) and Descent (TOD->dest) PhaseMetrics."""
    by_name = {w.name: w for w in nav.waypoints}
    wpts = nav.waypoints
    dep = wpts[0] if wpts else None
    dest = wpts[-1] if wpts else None
    toc = by_name.get("-TOC-")
    tod = by_name.get("-TOD-")

    climb = PhaseMetrics(label="Climb")
    if dep and toc:
        climb.duration_s = toc.eta_elapsed_s
        if toc.fuel_used is not None and dep.fuel_used is not None:
            climb.fuel_gal = toc.fuel_used - dep.fuel_used
        climb.dist_nm = toc.dist_leg
        climb.alt_start = dep.altitude_ft
        climb.alt_end = toc.altitude_ft
        if climb.duration_s and climb.alt_start is not None and climb.alt_end is not None:
            climb.rate_fpm = (climb.alt_end - climb.alt_start) / (climb.duration_s / 60.0)
        climb.avg_tas = toc.tas
        climb.avg_gs = toc.gs

    descent = PhaseMetrics(label="Descent")
    if tod and dest:
        if dest.eta_elapsed_s is not None and tod.eta_elapsed_s is not None:
            descent.duration_s = dest.eta_elapsed_s - tod.eta_elapsed_s
        if dest.fuel_used is not None and tod.fuel_used is not None:
            descent.fuel_gal = dest.fuel_used - tod.fuel_used
        descent.dist_nm = tod.dist_rem
        descent.alt_start = tod.altitude_ft
        descent.alt_end = dest.altitude_ft
        if descent.duration_s and descent.alt_start is not None and descent.alt_end is not None:
            descent.rate_fpm = (descent.alt_end - descent.alt_start) / (descent.duration_s / 60.0)
        # average planned speeds across the descent waypoints
        seg = [w for w in wpts if w.eta_elapsed_s is not None
               and tod.eta_elapsed_s is not None
               and w.eta_elapsed_s >= tod.eta_elapsed_s]
        descent.avg_tas = _mean([w.tas for w in seg])
        descent.avg_gs = _mean([w.gs for w in seg])
    return climb, descent


def _aggregate_subsegs(subs, want):
    """Combine same-label sub-segments into one PhaseMetrics (e.g. climbing
    portions only, with level-offs removed)."""
    items = [m for lab, m in subs if lab == want and m.duration_s]
    if not items:
        return None
    agg = PhaseMetrics(label=f"{want.capitalize()} only")
    agg.duration_s = sum(m.duration_s for m in items)
    agg.fuel_gal = sum(m.fuel_gal for m in items if m.fuel_gal is not None)
    agg.dist_nm = sum(m.dist_nm for m in items if m.dist_nm is not None)
    agg.alt_start = items[0].alt_start
    agg.alt_end = items[-1].alt_end
    alt_gain = sum((m.alt_end - m.alt_start) for m in items
                   if m.alt_end is not None and m.alt_start is not None)
    agg.rate_fpm = alt_gain / (agg.duration_s / 60.0) if agg.duration_s else None

    def wavg(attr):
        num = sum(getattr(m, attr) * m.duration_s for m in items
                  if getattr(m, attr) is not None)
        den = sum(m.duration_s for m in items if getattr(m, attr) is not None)
        return num / den if den else None
    agg.avg_ias = wavg("avg_ias")
    agg.avg_tas = wavg("avg_tas")
    agg.avg_gs = wavg("avg_gs")
    return agg


def _accuracy(rec: "Reconciliation") -> Dict:
    """Model accuracy over reliable (overflown->overflown) legs only."""
    rl = [lg for lg in rec.legs if lg.reliable]
    gs_err = _mean([(lg.actual_gs - lg.planned_gs)
                    for lg in rl if lg.actual_gs and lg.planned_gs])
    time_err = _mean([(lg.actual_time_s - lg.planned_time_s)
                      for lg in rl if lg.actual_time_s and lg.planned_time_s])
    fuel_err_tot = _mean([(lg.actual_fuel - lg.planned_fuel)
                          for lg in rl if lg.actual_fuel is not None and lg.planned_fuel is not None])
    # headwind error on overflown waypoints
    hw_err = _mean([(w.headwind_actual - w.headwind_planned)
                    for w in rec.waypoints
                    if w.overflown and w.headwind_actual is not None
                    and w.headwind_planned is not None])
    # totaliser vs tank consumption over reliable legs
    sum_tot = sum(lg.actual_fuel for lg in rl if lg.actual_fuel is not None)
    sum_tank = sum(lg.actual_fuel_tank for lg in rl if lg.actual_fuel_tank is not None)
    sum_plan = sum(lg.planned_fuel for lg in rl if lg.planned_fuel is not None)
    return {
        "n_reliable_legs": len(rl),
        "mean_gs_err_kt": round(gs_err, 1) if gs_err is not None else None,
        "mean_leg_time_err_s": round(time_err) if time_err is not None else None,
        "mean_leg_fuel_err_gal": round(fuel_err_tot, 2) if fuel_err_tot is not None else None,
        "mean_headwind_err_kt": round(hw_err, 1) if hw_err is not None else None,
        "reliable_fuel_plan_gal": round(sum_plan, 1),
        "reliable_fuel_totaliser_gal": round(sum_tot, 1),
        "reliable_fuel_tank_gal": round(sum_tank, 1),
    }


def _totals(nav: Navlog, log: FlightLog, rec: Reconciliation) -> Dict:
    fuel_start, fuel_end = log.fuel_at_start(), log.fuel_at_end()
    flown = log.flown_distance_nm()
    planned_gc = _planned_route_distance(nav)

    # airborne window: first/last GS > 40kt
    gs = log.df["gs"]
    airborne = log.df[gs > 40]
    if len(airborne):
        t0 = airborne["time_utc"].iloc[0]
        t1 = airborne["time_utc"].iloc[-1]
        airborne_s = (t1 - t0).total_seconds()
    else:
        airborne_s = log.duration_s

    burn_tot = (round(float(log.df["fuel_burn"].iloc[-1]), 1)
                if "fuel_burn" in log.df else None)
    burn_tank = round(fuel_start - fuel_end, 1) if fuel_start and fuel_end else None
    wind_dir, wind_spd = _cruise_wind(log)

    actual_phases = log.phases()
    climb_plan, descent_plan = _planned_climb_descent(nav)
    phases = {
        "actual": actual_phases,
        "climb_plan": climb_plan,
        "descent_plan": descent_plan,
    }
    if actual_phases:
        subs = log.vertical_subsegments(actual_phases["takeoff_i"],
                                        actual_phases["toc_i"])
        phases["climb_subsegments"] = subs
        phases["climb_active"] = _aggregate_subsegs(subs, "climb")
        phases["climb_level_s"] = sum(
            m.duration_s for lab, m in subs if lab == "level" and m.duration_s)

    return {
        "planned_dist_nm": nav.dist_total_nm,
        "planned_route_gc_nm": round(planned_gc, 1),
        "flown_dist_nm": round(flown, 1),
        "dist_saved_nm": round((nav.dist_total_nm or planned_gc) - flown, 1),
        "planned_ete_s": nav.ete_total_s,
        "actual_airborne_s": round(airborne_s),
        "planned_fuel_dest_gal": (nav.fuel_plan.get("Destination") or {}).get("gal"),
        "fuel_start_gal": fuel_start,
        "fuel_end_gal": fuel_end,
        # totaliser (integrated fuel flow) is the primary consumption figure
        "fuel_burned_totaliser_gal": burn_tot,
        "fuel_burned_tank_gal": burn_tank,
        "fuel_remaining_totaliser_gal": round(fuel_start - burn_tot, 1)
            if fuel_start and burn_tot is not None else None,
        "cruise_wind_dir": wind_dir,
        "cruise_wind_spd": wind_spd,
        "phases": phases,
        "n_overflown": sum(1 for w in rec.waypoints if w.overflown),
        "n_skipped": sum(1 for w in rec.waypoints
                         if w.lateral_offset_nm is not None and not w.overflown),
        "accuracy": _accuracy(rec),
    }
