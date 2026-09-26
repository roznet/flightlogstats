"""Draw the predicted frequency ladder on a map.

Mirrors ``corridor_report.save_map``: matplotlib, no basemap dependency, one
PNG next to whatever else the CLI writes. Doubles as the reference for how the
iOS page should paint the same thing on MKMapView.
"""
from __future__ import annotations

import math
from typing import List, Optional, Sequence, Tuple

from . import freq as F

# Distinct, print-and-screen safe. Reused cyclically along the route.
_COLORS = ["#1f77b4", "#d62728", "#2ca02c", "#ff7f0e", "#9467bd",
           "#8c564b", "#e377c2", "#17becf", "#bcbd22", "#7f7f7f"]


def save_route_map(rungs: Sequence[F.Rung], points: Sequence[Tuple[float, float]],
                   names: Sequence[str], path: str, cruise_alt: float,
                   corpus: Optional[F.FreqCorpus] = None,
                   position_nm: Optional[float] = None,
                   step_nm: float = 2.0) -> Optional[str]:
    """Route coloured by predicted frequency, labelled at each handoff.

    ``corpus`` (optional) paints the flights that actually contributed, faintly,
    so thin coverage is visible rather than implied. ``position_nm`` marks a
    current position along the route.
    """
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from matplotlib.lines import Line2D
    except Exception:
        return None

    samples = F.sample_route(points, step_nm)
    if not samples or not rungs:
        return None

    lats = [p[0] for p in points]; lons = [p[1] for p in points]
    pad_la = max(0.6, (max(lats) - min(lats)) * 0.12)
    pad_lo = max(0.6, (max(lons) - min(lons)) * 0.12)
    bbox = (min(lats) - pad_la, max(lats) + pad_la,
            min(lons) - pad_lo, max(lons) + pad_lo)

    fig, ax = plt.subplots(figsize=(15, 10))

    # Faint background: only the logged points near this route, so the reader
    # sees where the corpus is thick and where the model is extrapolating. The
    # clip matters - a frequency used elsewhere would otherwise blow out the view.
    if corpus is not None:
        order = {r.freq: i for i, r in enumerate(rungs)}
        near = ((corpus.lat >= bbox[0]) & (corpus.lat <= bbox[1])
                & (corpus.lon >= bbox[2]) & (corpus.lon <= bbox[3]))
        for fi, freq in enumerate(corpus.freqs):
            if freq not in order:
                continue
            sel = near & (corpus.freq_i == fi)
            if not sel.any():
                continue
            ax.plot(corpus.lon[sel], corpus.lat[sel], ".", ms=2.0, alpha=0.18,
                    color=_COLORS[order[freq] % len(_COLORS)], zorder=1)

    # The route, one colour per rung, numbered at each handoff. Labels are NOT
    # drawn on the line: on a diagonal route they collide into an unreadable
    # pile. The number ties each leg to the list on the right instead, which is
    # also how the map and the table cross-reference each other in the app.
    legend_rows = []
    for i, r in enumerate(rungs):
        color = _COLORS[i % len(_COLORS)]
        seg = [(la, lo) for la, lo, _, nm in samples if r.from_nm <= nm <= r.to_nm]
        if len(seg) >= 2:
            ax.plot([p[1] for p in seg], [p[0] for p in seg], "-", color=color,
                    lw=5.5, alpha=0.95, solid_capstyle="round", zorder=3)
        b = min(samples, key=lambda s: abs(s[3] - r.from_nm))
        ax.plot([b[1]], [b[0]], "o", ms=17, mfc=color, mec="white", mew=2, zorder=6)
        ax.annotate(str(i + 1), (b[1], b[0]), fontsize=9, ha="center", va="center",
                    color="white", fontweight="bold", zorder=7)
        legend_rows.append(
            Line2D([0], [0], color=color, lw=5,
                   label=f"{i + 1}. {r.freq}   {r.confidence * 100:3.0f}%  "
                         f"{r.support:2d} flt   {r.from_nm:3.0f}-{r.to_nm:3.0f} nm"))

    for (la, lo), nm in zip(points, names):
        ax.plot([lo], [la], "k^", ms=8, zorder=8)
        ax.annotate(nm, (lo, la), fontsize=9, xytext=(6, -12),
                    textcoords="offset points", zorder=8,
                    bbox=dict(boxstyle="round,pad=0.2", fc="white", ec="none", alpha=0.75))

    if position_nm is not None:
        p = min(samples, key=lambda s: abs(s[3] - position_nm))
        ax.plot([p[1]], [p[0]], marker="*", ms=30, color="#111111",
                mec="white", mew=1.5, zorder=9)

    ax.set_ylim(bbox[0], bbox[1]); ax.set_xlim(bbox[2], bbox[3])
    ax.set_title(f"{' '.join(names)}   {samples[-1][3]:.0f} nm at "
                 f"{cruise_alt:,.0f} ft - predicted frequencies", fontsize=14)
    ax.set_xlabel("Longitude"); ax.set_ylabel("Latitude")
    ax.grid(True, alpha=0.3)
    ax.legend(handles=legend_rows, loc="center left", bbox_to_anchor=(1.01, 0.5),
              fontsize=10, title="in route order", title_fontsize=10,
              prop={"family": "monospace"})
    mid_lat = math.radians(sum(lats) / len(lats))
    ax.set_aspect(1.0 / max(0.1, abs(math.cos(mid_lat))))
    fig.tight_layout()
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return path
