"""CLI: reconcile a ForeFlight navlog PDF against a Garmin G1000 CSV log.

    python -m flightreconcile.cli navlog.pdf log.csv -o report.md [--map map.png]
"""
from __future__ import annotations

import argparse
import os
import sys

from .navlog_parser import parse_navlog
from .navlog_html_parser import parse_navlog_html
from .g1000_parser import parse_g1000
from .reconcile import reconcile
from .logfinder import find_logs
from . import report


def _resolve_log(nav, directory):
    """Auto-select the G1000 log matching the navlog; print the decision."""
    date = nav.date.isoformat() if nav.date else "?"
    print(f"Matching {nav.departure}->{nav.destination} ({date}) "
          f"against logs in {directory} ...")
    matches, ranked = find_logs(nav, directory)
    if not ranked:
        print("  no candidate logs found.")
        return None
    if matches:
        best = matches[0]
        print(f"  MATCH: {os.path.basename(best.path)}  "
              f"(start {best.start_dist_nm:.1f} nm from origin, "
              f"end {best.end_dist_nm:.1f} nm from dest, started {best.start_time})")
        if len(matches) > 1:
            print(f"  ({len(matches)} candidates matched; using the closest)")
        return best.path
    print("  no log matched start≈origin AND end≈destination. Closest:")
    for m in ranked[:5]:
        print(f"    {os.path.basename(m.path)}  start {m.start_dist_nm:.1f} nm / "
              f"end {m.end_dist_nm:.1f} nm")
    return None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("navlog", help="ForeFlight navlog (.html preferred, or .pdf)")
    ap.add_argument("log", help="Garmin G1000 CSV log, OR a directory of logs to "
                               "auto-match against the navlog")
    ap.add_argument("-o", "--out", help="output markdown report path")
    ap.add_argument("--pdf", dest="pdf_path", help="output PDF report path")
    ap.add_argument("--html", dest="html_path", help="output HTML report path")
    ap.add_argument("--map", dest="map_path", help="output route map PNG path")
    args = ap.parse_args(argv)

    ext = os.path.splitext(args.navlog)[1].lower()
    nav = (parse_navlog_html(args.navlog) if ext in (".html", ".htm")
           else parse_navlog(args.navlog))

    log_path = args.log
    if os.path.isdir(log_path):
        log_path = _resolve_log(nav, args.log)
        if log_path is None:
            return 1

    log = parse_g1000(log_path)
    rec = reconcile(nav, log)

    md = report.markdown(rec)
    if args.out:
        with open(args.out, "w") as f:
            f.write(md)
        print(f"wrote {args.out}")
    if not any((args.out, args.html_path, args.pdf_path)):
        print(md)

    # default map path next to whichever report was requested
    map_path = args.map_path
    if map_path is None:
        base = args.pdf_path or args.html_path or args.out
        if base:
            map_path = os.path.splitext(base)[0] + ".png"
    map_written = report.save_map(rec, map_path) if map_path else None
    if map_path:
        print(f"wrote {map_written}" if map_written
              else "map skipped (matplotlib unavailable)")

    if args.pdf_path:
        from . import pdf
        pdf.save_pdf(rec, args.pdf_path, map_written)
        print(f"wrote {args.pdf_path}")

    if args.html_path:
        map_rel = os.path.basename(map_written) if map_written else None
        with open(args.html_path, "w") as f:
            f.write(report.html(rec, map_rel))
        print(f"wrote {args.html_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
