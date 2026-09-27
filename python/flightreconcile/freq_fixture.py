"""Export a parity fixture so the Swift port cannot drift from this model.

The app's `FrequencyModel` is a port of `freq.py`. Without a shared set of
expected answers the two implementations drift and there is no way to tell
which is wrong, so this writes a JSON file that `TestFrequencyModel` in
flightlogstatsTests replays:

  * the scanned **segments** per log, to check the Swift scan (debounce, the
    first/last run rule, durations and distances) against this one;
  * the **point index** itself, rounded, so the model half of the test runs on
    exactly the corpus the expectations were computed on, independent of any
    small parsing difference between the two CSV readers;
  * **queries** with the expected top-3 for `current`, `next` (with and without
    the current frequency) and `when`, each with and without its own flight
    held out;
  * **route ladders** along logged flights, one with an unsettled band, and a
    **live ladder** with its rejoin index.

Regenerate after any change to the model or its constants:

    python -m flightreconcile.freq_cli --dir ../flightlogstatsTests/TestAssets \\
        fixture ../flightlogstatsTests/TestAssets/freq_fixture.json
"""
from __future__ import annotations

import json
import math
import os
import random
from typing import List, Optional

import numpy as np

from . import freq as F


def _num(x: float, nd: int) -> Optional[float]:
    return None if x is None or not math.isfinite(x) else round(float(x), nd)


def _round_corpus(c: F.FreqCorpus) -> F.FreqCorpus:
    """Round the stored values to what the JSON carries, then re-project.

    Expectations are computed on the rounded corpus, so the Swift side, which
    loads the rounded values, is asked the exact same question.
    """
    c.lat = np.round(c.lat, 6)
    c.lon = np.round(c.lon, 6)
    c.alt = np.round(c.alt, 1)
    c.trk = np.round(c.trk, 1)
    c.gs = np.round(c.gs, 1)
    c.nm_to_next = np.where(np.isfinite(c.nm_to_next), np.round(c.nm_to_next, 3), np.nan)
    return F._project(c)


def _guesses(gs: List[F.Guess]) -> list:
    return [{"freq": g.freq, "prob": _num(g.prob, 12), "support": g.support,
             "nm": _num(g.nm_to_change, 9)} for g in gs]


def _rungs(rs: List[F.Rung]) -> list:
    return [{"freq": r.freq, "from": _num(r.from_nm, 9), "to": _num(r.to_nm, 9),
             "confidence": _num(r.confidence, 12), "support": r.support,
             "alt": _num(r.alt, 6), "alternates": list(r.alternates),
             "unsettled": bool(r.unsettled)} for r in rs]


def build(directory: str, per_flight: int = 6, seed: int = 7) -> dict:
    c = F.scan_logs(directory, cache=False)
    c = _round_corpus(c)
    model = F.FreqModel(c)
    rng = random.Random(seed)

    queries = []
    for fl in range(len(c.files)):
        ix = [int(i) for i in np.nonzero((c.flight == fl) & (c.alt >= 800.0))[0]]
        for qi in sorted(rng.sample(ix, min(per_flight, len(ix)))):
            la, lo, al, tk = (float(c.lat[qi]), float(c.lon[qi]),
                              float(c.alt[qi]), float(c.trk[qi]))
            cur = c.freqs[int(c.freq_i[qi])]
            # every third query without a track: the model must handle both
            trk = None if len(queries) % 3 == 2 else tk
            q = {"lat": la, "lon": lo, "alt": al, "trk": trk,
                 "file": c.files[fl], "on": cur}
            for tag, ex in (("all", None), ("held_out", fl)):
                q[tag] = {
                    "current": _guesses(model.current(la, lo, al, trk, exclude_flight=ex)),
                    "next": _guesses(model.next(la, lo, al, trk, current=cur,
                                                exclude_flight=ex)),
                    "next_no_current": _guesses(model.next(la, lo, al, trk,
                                                           exclude_flight=ex)),
                    "when": _num(model.when(la, lo, al, trk, exclude_flight=ex), 9),
                }
            queries.append(q)

    # Routes along logged flights: each track thinned to a handful of waypoints.
    # The flight with the most frequency changes at its median airborne altitude,
    # then one whose arrival has no settled answer, so the unsettled band (the
    # rule that stops the ladder overstating) is covered too.
    def route_of(name: str):
        ix = np.nonzero(c.flight == c.files.index(name))[0]
        pick = np.linspace(0, len(ix) - 1, 9).round().astype(int)
        return ix, [(float(c.lat[ix[i]]), float(c.lon[ix[i]])) for i in pick]

    per_file = {}
    for s in c.segments:
        per_file[s.file] = per_file.get(s.file, 0) + 1
    busiest = max(per_file, key=lambda f: per_file[f])
    ix, route = route_of(busiest)
    airborne = c.alt[ix][c.alt[ix] > 3000.0]
    cruise = float(round(np.median(airborne) / 500.0) * 500.0) if len(airborne) else 6000.0
    routes = [{"file": busiest, "points": [list(p) for p in route], "cruise": cruise,
               "rungs": _rungs(F.route_ladder(model, route, cruise))}]
    for name in c.files:
        if name == busiest:
            continue
        _, other = route_of(name)
        rungs = F.route_ladder(model, other, 9000.0)
        if any(r.unsettled for r in rungs):
            routes.append({"file": name, "points": [list(p) for p in other],
                           "cruise": 9000.0, "rungs": _rungs(rungs)})
            break

    mid = ix[len(ix) // 2]
    live_q = dict(lat=float(c.lat[mid]) + 0.05, lon=float(c.lon[mid]) - 0.05,
                  alt=float(c.alt[mid]), trk=float(c.trk[mid]), from_index=2)
    live, live_idx = F.live_ladder(model, route, live_q["lat"], live_q["lon"],
                                   live_q["alt"], live_q["trk"],
                                   from_index=live_q["from_index"])

    segments = [{"file": s.file, "freq": s.freq, "dur_s": s.dur_s,
                 "nm": _num(s.nm, 6), "prev": s.prev_freq, "next": s.next_freq}
                for s in c.segments]
    points = [[_num(c.lat[i], 6), _num(c.lon[i], 6), _num(c.alt[i], 1),
               _num(c.trk[i], 1), _num(c.gs[i], 1), int(c.freq_i[i]),
               int(c.next_i[i]), _num(c.nm_to_next[i], 3), int(c.flight[i])]
              for i in range(len(c))]

    return {
        "about": "Generated by python/flightreconcile/freq_fixture.py; do not edit.",
        "constants": {"step": F.STEP, "min_dwell_s": F.MIN_DWELL_S,
                      "min_gs_kt": F.MIN_GS_KT,
                      "alt_nm_per_1000ft": F.ALT_NM_PER_1000FT,
                      "dir_penalty_nm": F.DIR_PENALTY_NM, "k": F.K_NEIGHBOURS,
                      "soften_nm": F.SOFTEN_NM, "blend": F.BLEND_TRANSITION,
                      "climb_nm_per_1000ft": F.CLIMB_NM_PER_1000FT},
        "files": c.files,
        "freqs": c.freqs,
        "segments": segments,
        "points": points,
        "queries": queries,
        "routes": routes,
        "live": dict(live_q, rejoin=live_idx, rungs=_rungs(live)),
    }


def write(directory: str, path: str) -> dict:
    data = build(directory)
    with open(path, "w") as f:
        json.dump(data, f, separators=(",", ":"))
        f.write("\n")
    return data
