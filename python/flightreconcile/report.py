"""Render a reconciliation as a markdown report and a route map PNG."""
from __future__ import annotations

import os
from typing import Optional

from .reconcile import Reconciliation


def _hms(s: Optional[float]) -> str:
    if s is None:
        return "-"
    s = int(round(s))
    sign = "-" if s < 0 else ""
    s = abs(s)
    return f"{sign}{s // 3600}:{(s % 3600) // 60:02d}:{s % 60:02d}"

def _hm(s: Optional[float]) -> str:
    if s is None:
        return "-"
    s = int(round(s))
    sign = "-" if s < 0 else ""
    s = abs(s)
    return f"{sign}{s // 3600}:{(s % 3600) // 60:02d}"


def _ms(s: Optional[float]) -> str:
    if s is None:
        return "-"
    s = int(round(s))
    return f"{s // 60}:{s % 60:02d}"


def _f(v, fmt="{:.1f}"):
    return "-" if v is None else fmt.format(v)


def _signed(v, fmt="{:+.1f}"):
    return "-" if v is None else fmt.format(v)


def _phase_table(L, title, plan, actual):
    """Append a planned-vs-actual table for one flight phase (PhaseMetrics)."""
    p = plan
    a = actual
    def row(name, pv, av, fmt="{:.1f}", signed=False, delta=True):
        d = "-"
        if delta and pv is not None and av is not None:
            d = (_signed(av - pv, "{:+.1f}") if not signed
                 else _signed(av - pv, "{:+.0f}"))
        return f"| {name} | {_f(pv, fmt)} | {_f(av, fmt)} | {d} |"
    L.append(f"**{title}**")
    L.append("")
    L.append("| Metric | Plan | Actual | Δ |")
    L.append("|---|--:|--:|--:|")
    L.append(f"| Time | {_hm(p.duration_s) if p else '-'} | {_hm(a.duration_s) if a else '-'} | "
             f"{_hm((a.duration_s - p.duration_s) if (p and a and p.duration_s and a.duration_s) else None)} |")
    L.append(row("Fuel (gal)", p.fuel_gal if p else None, a.fuel_gal if a else None))
    L.append(row("Distance (NM)", p.dist_nm if p else None, a.dist_nm if a else None))
    L.append(row("Avg rate (fpm)", p.rate_fpm if p else None, a.rate_fpm if a else None, "{:.0f}"))
    L.append(row("Avg TAS (kt)", p.avg_tas if p else None, a.avg_tas if a else None, "{:.0f}"))
    L.append(row("Avg GS (kt)", p.avg_gs if p else None, a.avg_gs if a else None, "{:.0f}"))
    aalt = f"{_f(a.alt_start,'{:.0f}')}→{_f(a.alt_end,'{:.0f}')}" if a else "-"
    palt = f"{_f(p.alt_start,'{:.0f}')}→{_f(p.alt_end,'{:.0f}')}" if p else "-"
    L.append(f"| Altitude (ft) | {palt} | {aalt} | |")
    L.append("")


def markdown(rec: Reconciliation) -> str:
    nav, t = rec.nav, rec.totals
    L = []
    L.append(f"# Flight reconciliation — {nav.departure} → {nav.destination}")
    L.append("")
    L.append(f"*Aircraft {nav.aircraft}. Planned route:* `{nav.route}`")
    L.append("")

    # ---- summary ----
    L.append("## Summary: planned vs flown")
    L.append("")
    L.append("| Metric | Planned | Actual | Δ |")
    L.append("|---|--:|--:|--:|")
    pd_ = t.get("planned_dist_nm")
    fd = t.get("flown_dist_nm")
    L.append(f"| Distance (NM) | {_f(pd_)} | {_f(fd)} | {_signed(t.get('dist_saved_nm') and -t['dist_saved_nm'])} (saved {_f(t.get('dist_saved_nm'))}) |")
    L.append(f"| Time | {_hm(t.get('planned_ete_s'))} | {_hm(t.get('actual_airborne_s'))} (airborne) | {_hm((t.get('actual_airborne_s') or 0) - (t.get('planned_ete_s') or 0))} |")
    burn = t.get('fuel_burned_totaliser_gal')
    L.append(f"| Fuel to dest (gal) | {_f(t.get('planned_fuel_dest_gal'))} | {_f(burn)} (totaliser) | {_signed((burn or 0) - (t.get('planned_fuel_dest_gal') or 0))} |")
    L.append(f"| Fuel burn — totaliser vs tank (gal) | | {_f(t.get('fuel_burned_totaliser_gal'))} totaliser / {_f(t.get('fuel_burned_tank_gal'))} tank | |")
    L.append(f"| Fuel on board (gal) | {_f(nav.fuel_plan.get('Total',{}).get('gal'))} start / {_f(nav.fuel_plan.get('Landing',{}).get('gal'))} land | {_f(t.get('fuel_start_gal'))} start / {_f(t.get('fuel_remaining_totaliser_gal'))} land (totaliser) | |")
    cw = f"{t.get('cruise_wind_dir')}/{t.get('cruise_wind_spd')}" if t.get('cruise_wind_dir') is not None else "-"
    L.append(f"| Cruise wind (avg) | {nav.avg_wind} | {cw} | |")
    L.append("")
    L.append(f"- Planned waypoints overflown: **{t.get('n_overflown')}**, skipped/cut: **{t.get('n_skipped')}**")
    L.append("")

    # ---- model accuracy on fairly-comparable (overflown) legs ----
    acc = t.get("accuracy", {})
    L.append("## ForeFlight model accuracy (overflown legs only)")
    L.append("")
    L.append("Computed over the {} legs where both endpoints were overflown, so "
             "routing differences don't contaminate the comparison — this is how "
             "good the *plan's estimates* were.".format(acc.get("n_reliable_legs")))
    L.append("")
    L.append("| Quantity | Value |")
    L.append("|---|--:|")
    L.append(f"| Mean ground-speed error (actual−plan) | {_signed(acc.get('mean_gs_err_kt'))} kt |")
    L.append(f"| Mean leg-time error | {_hms(acc.get('mean_leg_time_err_s'))} |")
    L.append(f"| Mean leg-fuel error (totaliser−plan) | {_signed(acc.get('mean_leg_fuel_err_gal'),'{:+.2f}')} gal |")
    L.append(f"| Mean headwind error (actual−plan) | {_signed(acc.get('mean_headwind_err_kt'))} kt |")
    L.append(f"| Fuel over these legs: plan / totaliser / tank | {_f(acc.get('reliable_fuel_plan_gal'))} / {_f(acc.get('reliable_fuel_totaliser_gal'))} / {_f(acc.get('reliable_fuel_tank_gal'))} gal |")
    L.append("")

    # ---- climb / descent ----
    phases = t.get("phases") or {}
    actual = phases.get("actual") or {}
    L.append("## Climb & descent vs plan")
    L.append("")
    L.append("Planned climb = departure → `-TOC-`; planned descent = `-TOD-` → "
             "destination. Actual phases are detected from the altitude profile "
             "(climb = takeoff→within 500 ft of cruise; descent = leaving cruise→"
             "landing). Fuel is totaliser. Rate is +climb/−descent.")
    L.append("")
    _phase_table(L, "Climb (gross, incl. level-offs)", phases.get("climb_plan"), actual.get("climb"))

    # climb broken into climbing / level-off sub-segments
    subs = phases.get("climb_subsegments") or []
    if subs:
        lvl = phases.get("climb_level_s") or 0
        L.append(f"**Climb sub-segments** — level-off time during climb: "
                 f"**{_ms(lvl)}** (likely ATC step-climbs). Each contiguous "
                 "climbing / level run from takeoff to top-of-climb:")
        L.append("")
        L.append("| # | Mode | Alt band (ft) | Time (m:s) | Dist | Fuel | Rate (fpm) | IAS |")
        L.append("|--:|---|--:|--:|--:|--:|--:|--:|")
        for i, (lab, m) in enumerate(subs, 1):
            band = f"{_f(m.alt_start,'{:.0f}')}→{_f(m.alt_end,'{:.0f}')}"
            L.append(
                f"| {i} | {lab} | {band} | {_ms(m.duration_s)} | "
                f"{_f(m.dist_nm)} | {_f(m.fuel_gal)} | {_f(m.rate_fpm,'{:.0f}')} | "
                f"{_f(m.avg_ias,'{:.0f}')} |"
            )
        L.append("")
        active = phases.get("climb_active")
        if active:
            _phase_table(L, "Climbing only (level-offs removed) vs plan",
                         phases.get("climb_plan"), active)

    _phase_table(L, "Descent", phases.get("descent_plan"), actual.get("descent"))

    # ---- per-waypoint ----
    L.append("## Waypoints: planned vs actual (abeam)")
    L.append("")
    L.append("Offset = how far the actual track passed from the planned point "
             "(large ⇒ shortcut/vectors). ETA/fuel 'actual' are taken when the "
             "aircraft was abeam (closest to) the planned point. Fuel 'act' is "
             "integrated fuel flow. HW = head(+)/tail(−)wind component (kt). "
             "Rows marked `·fms` were active FMS waypoints. The fairest "
             "plan-vs-actual comparison is on `✈ over` (overflown) rows; large-"
             "offset rows reflect the shortcut, not model error.")
    L.append("")
    L.append("| Wpt | Status | Off (NM) | ETA plan | ETA act | ΔETA | Fuel plan | act | Δ | GS plan | act | Wind plan | act | HW plan | act |")
    L.append("|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|")
    for w in rec.waypoints:
        p = w.planned
        status = "✈ over" if w.overflown else ("— skip" if w.lateral_offset_nm is not None else "?")
        if w.fms_event is not None:
            status += " ·fms"
        wind_p = f"{int(p.wind_dir)}/{int(p.wind_speed)}" if p.wind_dir is not None and p.wind_speed is not None else "-"
        wind_a = f"{int(w.abeam_wind_dir)}/{int(w.abeam_wind_spd)}" if w.abeam_wind_dir is not None and w.abeam_wind_spd is not None else "-"
        L.append(
            f"| {w.name} | {status} | {_f(w.lateral_offset_nm)} | "
            f"{_hm(p.eta_elapsed_s)} | {_hm(w.abeam_elapsed_s)} | {_hm(w.eta_delta_s)} | "
            f"{_f(p.fuel_used)} | {_f(w.fuel_used_actual)} | {_signed(w.fuel_used_delta)} | "
            f"{_f(p.gs,'{:.0f}')} | {_f(w.abeam_gs,'{:.0f}')} | {wind_p} | {wind_a} | "
            f"{_signed(w.headwind_planned,'{:+.0f}')} | {_signed(w.headwind_actual,'{:+.0f}')} |"
        )
    L.append("")

    # ---- legs ----
    L.append("## Legs: planned vs actual")
    L.append("")
    L.append("`✓` = reliable leg (both endpoints overflown). On non-reliable "
             "legs the abeam timing is distorted by the shortcut, so dist/time/GS "
             "are indicative only. Fuel columns: **plan** vs **tot** (totaliser, "
             "integrated FFlow) vs **tank** (fuel-quantity sensor delta).")
    L.append("")
    L.append("| Leg | | Dist plan | act | Time plan | act | Fuel plan | tot | tank | GS plan | act |")
    L.append("|---|:-:|--:|--:|--:|--:|--:|--:|--:|--:|--:|")
    for lg in rec.legs:
        flag = "✓" if lg.reliable else ""
        L.append(
            f"| {lg.frm}→{lg.to} | {flag} | {_f(lg.planned_dist_nm)} | {_f(lg.actual_dist_nm)} | "
            f"{_hm(lg.planned_time_s)} | {_hm(lg.actual_time_s)} | "
            f"{_f(lg.planned_fuel)} | {_f(lg.actual_fuel)} | {_f(lg.actual_fuel_tank)} | "
            f"{_f(lg.planned_gs,'{:.0f}')} | {_f(lg.actual_gs,'{:.0f}')} |"
        )
    L.append("")

    # ---- off-plan waypoints actually flown ----
    if rec.off_plan:
        L.append("## Off-plan waypoints flown (not in the navlog)")
        L.append("")
        L.append("Fixes the FMS sequenced that were not on the filed route — "
                 "vectors and the arrival/approach into the destination.")
        L.append("")
        L.append("| Wpt | t+ | Fuel rem (tank) | GS | Lat | Lon |")
        L.append("|---|--:|--:|--:|--:|--:|")
        for e in rec.off_plan:
            L.append(
                f"| {e.ident} | {_hm(e.elapsed_s)} | {_f(e.fuel_total)} | "
                f"{_f(e.gs,'{:.0f}')} | {e.lat:.3f} | {e.lon:.3f} |"
            )
        L.append("")
    return "\n".join(L)


import re as _re


def _inline(s: str) -> str:
    s = (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
    s = _re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = _re.sub(r"\*(.+?)\*", r"<em>\1</em>", s)
    s = _re.sub(r"`(.+?)`", r"<code>\1</code>", s)
    return s


_SEP = _re.compile(r"^\|[\s:\-|]+\|$")


def _md_to_html(md: str) -> str:
    out, table, in_list = [], [], False
    def flush_table():
        nonlocal table
        if not table:
            return
        head, *rows = table
        out.append("<table><thead><tr>"
                   + "".join(f"<th>{_inline(c)}</th>" for c in head)
                   + "</tr></thead><tbody>")
        for r in rows:
            out.append("<tr>" + "".join(f"<td>{_inline(c)}</td>" for c in r) + "</tr>")
        out.append("</tbody></table>")
        table = []
    for line in md.splitlines():
        if line.startswith("|"):
            if _SEP.match(line):
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            table.append(cells)
            continue
        flush_table()
        if in_list and not line.startswith("- "):
            out.append("</ul>"); in_list = False
        if line.startswith("# "):
            out.append(f"<h1>{_inline(line[2:])}</h1>")
        elif line.startswith("## "):
            out.append(f"<h2>{_inline(line[3:])}</h2>")
        elif line.startswith("- "):
            if not in_list:
                out.append("<ul>"); in_list = True
            out.append(f"<li>{_inline(line[2:])}</li>")
        elif line.strip():
            out.append(f"<p>{_inline(line)}</p>")
    flush_table()
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


_CSS = """
body{font:14px/1.5 -apple-system,Helvetica,Arial,sans-serif;max-width:1100px;
margin:2rem auto;padding:0 1rem;color:#222}
h1{font-size:1.6rem} h2{font-size:1.2rem;margin-top:1.8rem;border-bottom:1px solid #eee;padding-bottom:.2rem}
table{border-collapse:collapse;width:100%;margin:.5rem 0;font-size:13px}
th,td{border:1px solid #ddd;padding:3px 7px;text-align:right}
th:first-child,td:first-child{text-align:left}
thead th{background:#f5f5f5}
tr:nth-child(even) td{background:#fafafa}
code{background:#f0f0f0;padding:1px 4px;border-radius:3px}
img{margin:1rem 0;border:1px solid #eee}
"""


def html(rec: Reconciliation, map_rel: Optional[str] = None) -> str:
    body = _md_to_html(markdown(rec))
    if map_rel:
        # insert the map right after the first </p> (after the route line)
        img = f'<img src="{map_rel}" alt="route map">'
        idx = body.find("</p>")
        if idx != -1:
            body = body[:idx + 4] + "\n" + img + body[idx + 4:]
        else:
            body += img
    title = f"Reconciliation {rec.nav.departure}-{rec.nav.destination}"
    return (f"<!doctype html><html><head><meta charset='utf-8'><title>{title}</title>"
            f"<style>{_CSS}</style></head><body>{body}</body></html>")


def save_map(rec: Reconciliation, path: str) -> Optional[str]:
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as e:  # pragma: no cover
        return None

    nav = rec.nav
    track = rec.log.track()
    fig, ax = plt.subplots(figsize=(11, 9))

    # actual track
    ax.plot(track["lon"], track["lat"], "-", color="#1f77b4", lw=1.2,
            label="Flown track", zorder=2)

    # planned route
    plat = [w.lat for w in nav.waypoints if w.lat is not None]
    plon = [w.lon for w in nav.waypoints if w.lon is not None]
    ax.plot(plon, plat, "--", color="#d62728", lw=1.0, alpha=0.8,
            label="Planned route", zorder=3)

    # planned waypoints colored by overflown/skipped
    for w in rec.waypoints:
        p = w.planned
        if p.lat is None:
            continue
        if w.overflown:
            ax.plot(p.lon, p.lat, "o", color="#2ca02c", ms=5, zorder=4)
        else:
            ax.plot(p.lon, p.lat, "x", color="#d62728", ms=6, zorder=4)
        ax.annotate(w.name, (p.lon, p.lat), fontsize=6,
                    xytext=(3, 3), textcoords="offset points")

    ax.set_title(f"{nav.departure} → {nav.destination}: planned vs flown")
    ax.set_xlabel("Longitude"); ax.set_ylabel("Latitude")
    ax.legend(loc="best"); ax.grid(True, alpha=0.3)
    ax.set_aspect(1.0 / max(0.1, abs(__import__("math").cos(
        __import__("math").radians(sum(plat) / len(plat))))))
    fig.tight_layout()
    fig.savefig(path, dpi=130)
    plt.close(fig)
    return path
