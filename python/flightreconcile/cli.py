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
from . import report


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("navlog", help="ForeFlight navlog PDF")
    ap.add_argument("log", help="Garmin G1000 CSV log")
    ap.add_argument("-o", "--out", help="output markdown report path")
    ap.add_argument("--pdf", dest="pdf_path", help="output PDF report path")
    ap.add_argument("--html", dest="html_path", help="output HTML report path")
    ap.add_argument("--map", dest="map_path", help="output route map PNG path")
    args = ap.parse_args(argv)

    ext = os.path.splitext(args.navlog)[1].lower()
    nav = (parse_navlog_html(args.navlog) if ext in (".html", ".htm")
           else parse_navlog(args.navlog))
    log = parse_g1000(args.log)
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
