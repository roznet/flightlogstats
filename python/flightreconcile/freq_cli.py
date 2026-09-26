"""Guess the ATC frequencies you are likely to get, from your own past logs.

    # the frequency sequence you can expect along a route
    python -m flightreconcile.freq_cli route EGTF OCK MID BILGO LFAT --alt 9000

    # what am I on now, and what comes next, at a position
    python -m flightreconcile.freq_cli at 51.32 -0.49 --alt 3000 --trk 90 \
        --current 125.250

    # how good is the model? leave-one-flight-out over the whole corpus
    python -m flightreconcile.freq_cli eval

    # which frequencies appear in the logs, where, and at what level
    python -m flightreconcile.freq_cli list --names

The first run scans the log directory (a few minutes for ~1000 logs) and caches
the result in ~/.cache/flightreconcile, so later runs start instantly.
"""
from __future__ import annotations

import argparse
import math
import sys

from . import freq as F


def _corpus(args):
    def progress(n, total):
        print(f"  scanning {n}/{total} logs ...", file=sys.stderr, flush=True)
    c = F.scan_logs(args.dir, cache=not args.no_cache, progress=progress)
    print(f"{len(c.files)} logs, {len(c)} indexed points, "
          f"{len(c.freqs)} distinct COM1 frequencies, "
          f"{len(c.segments)} frequency segments", file=sys.stderr)
    return c


def _model(args, corpus):
    return F.FreqModel(corpus, k=args.k, blend=args.blend, since_date=args.since)


def _nav(args):
    if args.no_names:
        return None
    try:
        from . import corridor as C
        return C.navmodel(args.db)
    except Exception as e:
        print(f"(no nav database, frequencies will not be placed: {e})",
              file=sys.stderr)
        return None


def cmd_route(args) -> int:
    nav = _nav(args)
    if nav is None:
        print("route mode needs the nav database to resolve idents "
              "(pass --db, or use 'at' with a position)")
        return 1
    from . import corridor as C
    pts, names, ref = [], [], None
    for ident in args.route:
        ll = C.resolve(nav, ident, ref=ref)
        if ll is None:
            print(f"could not resolve '{ident}'")
            return 1
        pts.append(ll)
        names.append(ident)
        ref = ll
    corpus = _corpus(args)
    model = _model(args, corpus)

    total = sum(F.geo.haversine_nm(a[0], a[1], b[0], b[1])
                for a, b in zip(pts, pts[1:]))
    print(f"\n{' '.join(names)}   {total:.0f} nm at {args.alt:.0f} ft\n")
    rungs = F.route_ladder(model, pts, args.alt, step_nm=args.step,
                           min_rung_nm=args.min_rung, field_alt=args.field_alt,
                           climb_nm_per_1000ft=args.climb_nm_per_1000ft)
    if not rungs:
        print("no prediction: no logged flights near this route")
        return 0
    print(f"{'from':>7} {'to':>7} {'freq':>9} {'conf':>6} {'flights':>8} "
          f"{'alt':>7}  also likely")
    for r in rungs:
        alts = " ".join(r.alternates[:2])
        print(f"{r.from_nm:7.0f} {r.to_nm:7.0f} {r.freq:>9} "
              f"{r.confidence * 100:4.0f}% {r.support:8d} {r.alt:7.0f}  {alts}")
    print("\nconf = share of the neighbour vote; flights = how many past flights "
          "back it.\nRead it as a watch list, not a clearance.")
    return 0


def cmd_at(args) -> int:
    corpus = _corpus(args)
    model = _model(args, corpus)
    cur = model.current(args.lat, args.lon, args.alt, args.trk, top=args.top)
    if not cur:
        print("no logged flights anywhere near this position")
        return 0
    print(f"\nat {args.lat:.4f},{args.lon:.4f}  {args.alt:.0f} ft"
          + (f"  track {args.trk:.0f}" if args.trk is not None else "")
          + (f"  on {args.current}" if args.current else "") + "\n")
    print("probably on now:")
    for g in cur:
        nm = f"  handoff in ~{g.nm_to_change:.0f} nm" if math.isfinite(g.nm_to_change) else ""
        print(f"  {g.freq:>9}  {g.prob * 100:4.0f}%  ({g.support} flights){nm}")
    known = args.current or cur[0].freq
    nxt = model.next(args.lat, args.lon, args.alt, args.trk, current=known,
                     top=args.top)
    when = model.when(args.lat, args.lon, args.alt, args.trk)
    tag = "given" if args.current else "assuming"
    print(f"\nnext, {tag} {known}"
          + (f" (in ~{when:.0f} nm):" if math.isfinite(when) else ":"))
    for g in nxt:
        print(f"  {g.freq:>9}  {g.prob * 100:4.0f}%  ({g.support} flights)")
    return 0


def cmd_eval(args) -> int:
    corpus = _corpus(args)
    model = _model(args, corpus)
    r = F.evaluate(model, per_flight=args.per_flight, top=args.top)
    print(f"\nleave-one-flight-out over {r['queries']} airborne query points "
          f"from {r['flights']} flights, {r['freqs']} distinct frequencies\n")
    rows = [("most common frequency (baseline)", "prior"),
            ("current frequency", "current"),
            ("next frequency (current known)", "next"),
            ("next frequency (position only)", "next_no_current")]
    print(f"{'':36}{'top-1':>8}{f'top-{args.top}':>8}")
    for label, key in rows:
        if key in r:
            d = r[key]
            print(f"{label:36}{d['top1'] * 100:7.1f}%{d[f'top{args.top}'] * 100:7.1f}%")
    if "nm_error_median" in r:
        print(f"\ndistance to the next handoff: median error "
              f"{r['nm_error_median']:.1f} nm, p90 {r['nm_error_p90']:.1f} nm")
    return 0


def cmd_list(args) -> int:
    corpus = _corpus(args)
    nav = _nav(args)
    places = F.frequency_places(corpus, nav, min_uses=args.min_uses)
    print(f"\n{len(places)} frequencies used on at least {args.min_uses} flights\n")
    print(f"{'freq':>9} {'flights':>8} {'alt band':>16}  used around")
    for freq, d in sorted(places.items(), key=lambda kv: -kv[1]["uses"])[:args.limit]:
        band = f"{d['alt_p10']:.0f}-{d['alt_p90']:.0f} ft"
        where = d["near"] or f"{d['lat']:.2f},{d['lon']:.2f}"
        print(f"{freq:>9} {d['uses']:8d} {band:>16}  {where}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        prog="python -m flightreconcile.freq_cli", description=__doc__,
        formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--dir", default=F.DEFAULT_LOG_DIR, help="directory of G1000 logs")
    ap.add_argument("--db", default=F.DEFAULT_DB, help="euro_aip nav database")
    ap.add_argument("--no-cache", action="store_true", help="rescan the logs")
    ap.add_argument("--no-names", action="store_true", help="skip the nav database")
    ap.add_argument("-k", type=int, default=F.K_NEIGHBOURS,
                    help=f"neighbours in the vote (default {F.K_NEIGHBOURS})")
    ap.add_argument("--blend", type=float, default=F.BLEND_TRANSITION,
                    help="weight of the transition table vs the spatial vote "
                         f"(default {F.BLEND_TRANSITION})")
    ap.add_argument("--since", help="ignore flights before this date (YYYY-MM-DD)")
    ap.add_argument("--top", type=int, default=3, help="how many guesses to show")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("route", help="predicted frequency sequence along a route")
    p.add_argument("route", nargs="+", help="idents, e.g. EGTF OCK MID LFAT")
    p.add_argument("--alt", type=float, default=6000.0, help="cruise altitude ft")
    p.add_argument("--field-alt", type=float, default=1000.0,
                   help="altitude to start the climb / end the descent at")
    p.add_argument("--step", type=float, default=4.0, help="sample spacing nm")
    p.add_argument("--min-rung", type=float, default=8.0,
                   help="drop predicted sectors shorter than this (nm)")
    p.add_argument("--climb", type=float, default=F.CLIMB_NM_PER_1000FT,
                   dest="climb_nm_per_1000ft",
                   help="climb/descent gradient, track nm per 1000 ft "
                        f"(default {F.CLIMB_NM_PER_1000FT})")
    p.set_defaults(func=cmd_route)

    p = sub.add_parser("at", help="predict at one position")
    p.add_argument("lat", type=float)
    p.add_argument("lon", type=float)
    p.add_argument("--alt", type=float, required=True, help="altitude ft msl")
    p.add_argument("--trk", type=float, help="track degrees true")
    p.add_argument("--current", help="the frequency you are on now")
    p.set_defaults(func=cmd_at)

    p = sub.add_parser("eval", help="leave-one-flight-out accuracy")
    p.add_argument("--per-flight", type=int, default=10,
                   help="query points sampled per flight")
    p.set_defaults(func=cmd_eval)

    p = sub.add_parser("list", help="frequencies in the corpus, and where")
    p.add_argument("--min-uses", type=int, default=3)
    p.add_argument("--limit", type=int, default=40)
    p.add_argument("--names", action="store_true", help="(default) place them by fix")
    p.set_defaults(func=cmd_list)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
