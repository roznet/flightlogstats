"""Compare routing options along a corridor across many logged flights.

    python -m flightreconcile.corridor_cli [--anchor EGTF] [--via BILGO] \
        [--dir LOGDIR] [--db NAV.DB] [--pdf out.pdf | --html out.html | -o out.md]

Defaults: anchor EGTF, via BILGO, the flightlogstats iCloud log directory, and
the flyfun nav.db. Finds every flight that flies the anchor<->via corridor,
auto-clusters the common segment into routing options, labels each by a
distinctive nav fix, and compares them with wind-adjusted metrics.
"""
from __future__ import annotations

import argparse
import os
import sys

from . import corridor as C
from . import corridor_report as R


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--anchor", default="EGTF", help="anchor airport/fix (default EGTF)")
    ap.add_argument("--via", default="BILGO", help="common via point (default BILGO)")
    ap.add_argument("--dir", default=C.DEFAULT_LOG_DIR, help="directory of G1000 logs")
    ap.add_argument("--db", default=C.DEFAULT_DB, help="euro_aip nav database")
    ap.add_argument("--cluster", action="store_true",
                    help="group by track-shape clustering instead of route rules")
    ap.add_argument("--cluster-rms", type=float, default=12.0,
                    help="clustering threshold in nm (with --cluster)")
    ap.add_argument("-o", "--out", help="markdown output path")
    ap.add_argument("--pdf", dest="pdf_path", help="PDF output path")
    ap.add_argument("--html", dest="html_path", help="HTML output path")
    ap.add_argument("--map", dest="map_path", help="map PNG output path")
    ap.add_argument("--no-cache", action="store_true", help="ignore the scan cache")
    args = ap.parse_args(argv)

    model = C.navmodel(args.db)
    anchor = C.resolve(model, args.anchor)
    via = C.resolve(model, args.via, ref=anchor)
    if anchor is None or via is None:
        print(f"could not resolve anchor '{args.anchor}' or via '{args.via}'")
        return 1
    print(f"corridor {args.anchor} <-> {args.via}: scanning {args.dir} ...")
    flights = C.scan_corridor(args.dir, anchor, via, model=model,
                              cache=not args.no_cache)
    print(f"  {len(flights)} corridor flights")
    fixes = C.corridor_fixes(model, anchor, via)

    def grouped(direction):
        fs = [f for f in flights if f.direction == direction]
        if args.cluster:
            cls = C.cluster(fs, rms_thresh_nm=args.cluster_rms)
            C.label_clusters(cls, fixes, anchor, via)
        else:
            cls = C.classify(fs)  # rule-based on flown fixes (OCAS / Airways / ...)
        return cls

    out_cl, in_cl = grouped("out"), grouped("in")

    md = R.markdown(args.anchor, args.via, out_cl, in_cl)
    if args.out:
        with open(args.out, "w") as f:
            f.write(md)
        print(f"wrote {args.out}")
    if not any((args.out, args.pdf_path, args.html_path)):
        print(md)

    map_path = args.map_path
    if map_path is None:
        base = args.pdf_path or args.html_path or args.out
        if base:
            map_path = os.path.splitext(base)[0] + ".png"
    map_written = None
    if map_path:
        map_written = R.save_map(args.anchor, args.via, anchor, via,
                                 out_cl, in_cl, map_path)
        print(f"wrote {map_written}" if map_written else "map skipped")

    if args.pdf_path:
        from .pdf import render_markdown_pdf
        render_markdown_pdf(md, args.pdf_path, map_path=map_written,
                            title=f"Corridor {args.anchor}-{args.via}")
        print(f"wrote {args.pdf_path}")
    if args.html_path:
        from .report import _md_to_html, _CSS
        inner = _md_to_html(md)
        if map_written:
            img = f'<img src="{os.path.basename(map_written)}" style="max-width:100%">'
            idx = inner.find("</p>")
            inner = inner[:idx + 4] + img + inner[idx + 4:] if idx != -1 else inner + img
        with open(args.html_path, "w") as f:
            f.write(f"<!doctype html><html><head><meta charset='utf-8'>"
                    f"<title>Corridor {args.anchor}-{args.via}</title>"
                    f"<style>{_CSS}</style></head><body>{inner}</body></html>")
        print(f"wrote {args.html_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
