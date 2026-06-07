"""Render a corridor routing-option comparison (markdown + map)."""
from __future__ import annotations

import os
from typing import List, Optional

import numpy as np

from .report import _hm, _ms, _f, _signed
from .corridor import CorridorFlight


def _mean(vals):
    vals = [v for v in vals if v is not None and not (isinstance(v, float) and np.isnan(v))]
    return float(np.mean(vals)) if vals else None


def _option_rows(clusters: List[List[CorridorFlight]]):
    rows = []
    for cl in clusters:
        label = cl[0].label if cl else "?"
        rows.append({
            "label": label,
            "n": len(cl),
            "track_nm": _mean([f.track_nm for f in cl]),
            "still_air_s": _mean([f.still_air_s for f in cl]),
            "time_s": _mean([f.time_s for f in cl]),
            "avg_tas": _mean([f.avg_tas for f in cl]),
            "avg_alt": _mean([f.avg_alt for f in cl]),
            "fuel": _mean([f.fuel_gal for f in cl]),
        })
    return rows


def _direction_section(L, title, clusters):
    flights = [f for cl in clusters for f in cl]
    L.append(f"## {title}  ({len(flights)} flights, {len(clusters)} option"
             f"{'s' if len(clusters) != 1 else ''})")
    L.append("")
    if not flights:
        L.append("_No flights._")
        L.append("")
        return

    rows = _option_rows(clusters)
    # plain-language profile tag (short/long, low/high) relative to the others
    trks = [r["track_nm"] for r in rows if r["track_nm"]]
    alts = [r["avg_alt"] for r in rows if r["avg_alt"]]
    t_mid = (max(trks) + min(trks)) / 2 if trks else 0
    a_mid = (max(alts) + min(alts)) / 2 if alts else 0
    for r in rows:
        spread_t = (max(trks) - min(trks)) if trks else 0
        spread_a = (max(alts) - min(alts)) if alts else 0
        t = ("short" if r["track_nm"] < t_mid else "long") if spread_t > 6 else "med"
        a = ("low" if r["avg_alt"] < a_mid else "high") if spread_a > 1500 else "med"
        r["profile"] = f"{t}/{a}"

    # option comparison (means). still-air time is the wind-neutral comparator.
    L.append("**Routing options (means over the segment; still-air time removes "
             "the day's wind):**")
    L.append("")
    L.append("| Option (via) | Profile | Flights | Track NM | Still-air | Avg TAS | Avg alt | Fuel | Actual time |")
    L.append("|---|---|--:|--:|--:|--:|--:|--:|--:|")
    best_air = min((r["still_air_s"] for r in rows if r["still_air_s"]), default=None)
    best_trk = min((r["track_nm"] for r in rows if r["track_nm"]), default=None)
    for r in rows:
        air = _ms(r["still_air_s"])
        trk = _f(r["track_nm"])
        if r["still_air_s"] == best_air:
            air = f"**{air}**"
        if r["track_nm"] == best_trk:
            trk = f"**{trk}**"
        L.append(
            f"| {r['label']} | {r['profile']} | {r['n']} | {trk} | {air} | "
            f"{_f(r['avg_tas'],'{:.0f}')} | {_f(r['avg_alt'],'{:.0f}')} | "
            f"{_f(r['fuel'])} | {_ms(r['time_s'])} |"
        )
    L.append("")

    # head-to-head if exactly-ish two main options
    if len(rows) >= 2 and rows[0]["still_air_s"] and rows[1]["still_air_s"]:
        a, b = rows[0], rows[1]
        d_air = (b["still_air_s"] - a["still_air_s"]) / 60.0
        d_trk = (b["track_nm"] - a["track_nm"])
        faster = a["label"] if d_air > 0 else b["label"]
        L.append(f"- **{a['label']}** vs **{b['label']}**: "
                 f"{abs(d_air):.1f} min still-air difference (faster: **{faster}**), "
                 f"{abs(d_trk):.0f} NM track difference, "
                 f"{abs(a['avg_alt'] - b['avg_alt']):.0f} ft mean-altitude difference.")
        L.append("")

    # per-flight detail
    L.append("| Option | Date | Far | Track NM | Still-air | Actual | Wind | Avg TAS | Avg alt | Fuel |")
    L.append("|---|---|---|--:|--:|--:|--:|--:|--:|--:|")
    for cl in clusters:
        for f in sorted(cl, key=lambda x: x.date):
            wind = (f.still_air_s - f.time_s) if (f.still_air_s and f.time_s) else None
            wtag = "-"
            if wind is not None:
                wtag = f"{'tail' if wind > 0 else 'head'} {abs(wind)/60:.0f}m"
            L.append(
                f"| {f.label} | {f.date} | {f.far_ident or '?'} | {_f(f.track_nm)} | "
                f"{_ms(f.still_air_s)} | {_ms(f.time_s)} | {wtag} | "
                f"{_f(f.avg_tas,'{:.0f}')} | {_f(f.avg_alt,'{:.0f}')} | {_f(f.fuel_gal)} |"
            )
    L.append("")


def markdown(anchor_id, via_id, out_clusters, in_clusters) -> str:
    L = []
    L.append(f"# Corridor analysis — {anchor_id} ↔ {via_id}")
    L.append("")
    L.append(f"Flights through the **{anchor_id} ↔ {via_id}** corridor, grouped into "
             "routing options (auto-clustered by track shape, labeled by the most "
             "distinctive nav fix). All metrics are over the common "
             f"{anchor_id}↔{via_id} segment only, so the options are comparable.")
    L.append("")
    L.append("**Still-air time** = the segment time with the day's wind removed "
             "(∫ groundspeed/TAS dt) — the fair cross-day comparator. **Track NM** "
             "is the over-ground path length (the detour). **Avg TAS / alt** show "
             "the speed/altitude trade. *Actual* and *Wind* show what the day gave.")
    L.append("")
    _direction_section(L, f"Outbound ({anchor_id} → {via_id} → …)", out_clusters)
    _direction_section(L, f"Inbound (… → {via_id} → {anchor_id})", in_clusters)
    return "\n".join(L)


_COLORS = ["#1f77b4", "#d62728", "#2ca02c", "#9467bd", "#ff7f0e", "#8c564b"]


def save_map(anchor_id, via_id, anchor_ll, via_ll, out_clusters, in_clusters,
             path: str) -> Optional[str]:
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception:
        return None
    import math

    fig, axes = plt.subplots(1, 2, figsize=(16, 8))
    for ax, clusters, title in ((axes[0], out_clusters, f"Outbound {anchor_id}→{via_id}"),
                                (axes[1], in_clusters, f"Inbound {via_id}→{anchor_id}")):
        for cid, cl in enumerate(clusters):
            color = _COLORS[cid % len(_COLORS)]
            label = f"{cl[0].label} (n={len(cl)})" if cl else ""
            for k, f in enumerate(cl):
                ax.plot(f.lon, f.lat, "-", color=color, lw=0.9, alpha=0.7,
                        label=label if k == 0 else None)
        ax.plot([anchor_ll[1]], [anchor_ll[0]], "k^", ms=9)
        ax.annotate(anchor_id, (anchor_ll[1], anchor_ll[0]), fontsize=8,
                    xytext=(4, 4), textcoords="offset points")
        ax.plot([via_ll[1]], [via_ll[0]], "ks", ms=8)
        ax.annotate(via_id, (via_ll[1], via_ll[0]), fontsize=8,
                    xytext=(4, 4), textcoords="offset points")
        ax.set_title(title)
        ax.set_xlabel("Longitude"); ax.set_ylabel("Latitude")
        ax.grid(True, alpha=0.3)
        ax.legend(loc="best", fontsize=7)
        mid = math.radians((anchor_ll[0] + via_ll[0]) / 2)
        ax.set_aspect(1.0 / max(0.1, abs(math.cos(mid))))
    fig.tight_layout()
    fig.savefig(path, dpi=130)
    plt.close(fig)
    return path
