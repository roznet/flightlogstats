#!/usr/bin/env python3
"""Build the bundled nav.db from the flyfun-apps navigation database.

Replaces the old ourairports-derived ``airports.db``. That one had no waypoints,
so route fixes like BILGO or SAPRE could not be resolved on device, and it used
the pre-rename column names (``ident`` / ``airport_ident``) that RZFlight's
current model code no longer reads.

The source is worldwide and carries tables this app does not use, so we take
airports, runways and the waypoints inside a Europe box. The result is smaller
than the database it replaces while adding ~28k waypoints:

    airports.db  13 MB, 55,318 airports, no waypoints
    nav.db      5.3 MB,  8,877 airports, 27,764 waypoints

Coverage note: the source holds only Europe and North America. Of the 83
airfields appearing in this author's logs, 82 are present (LCPH, Cyprus, is not).

    ./venv/bin/python make_nav_db.py [--source PATH] [--out nav.db]
"""
from __future__ import annotations

import argparse
import os
import sqlite3
import sys

DEFAULT_SOURCE = os.path.expanduser(
    "~/Developer/public/flyfun-apps/main/data/nav.db")
DEFAULT_OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "nav.db")

# Europe, generously drawn: Iceland to the Urals, North Cape to the Canaries.
LAT_MIN, LAT_MAX = 35.0, 72.0
LON_MIN, LON_MAX = -25.0, 45.0


def build(source: str, out: str) -> None:
    if not os.path.exists(source):
        raise SystemExit(f"source database not found: {source}")
    if os.path.exists(out):
        os.remove(out)

    con = sqlite3.connect(source)
    con.execute("ATTACH ? AS out", (out,))
    # Airports and runways are already curated in the source; the waypoints
    # table is worldwide (117k) and is the only one worth clipping.
    con.execute("CREATE TABLE out.airports AS SELECT * FROM airports")
    con.execute("CREATE TABLE out.runways AS SELECT * FROM runways")
    con.execute(
        "CREATE TABLE out.waypoints AS "
        "SELECT name, latitude_deg, longitude_deg, point_type, source "
        "FROM waypoints "
        "WHERE latitude_deg BETWEEN ? AND ? AND longitude_deg BETWEEN ? AND ?",
        (LAT_MIN, LAT_MAX, LON_MIN, LON_MAX))
    # KnownWaypoints looks up by name; KnownAirports.addRunways by airport.
    con.execute("CREATE INDEX out.idx_waypoints_name ON waypoints(name)")
    con.execute("CREATE INDEX out.idx_runways_airport ON runways(airport_icao)")
    con.execute("CREATE INDEX out.idx_airports_icao ON airports(icao_code)")
    con.commit()

    counts = {t: con.execute(f"SELECT COUNT(*) FROM out.{t}").fetchone()[0]
              for t in ("airports", "runways", "waypoints")}
    con.close()

    # VACUUM needs its own connection with nothing attached.
    vac = sqlite3.connect(out)
    vac.execute("VACUUM")
    vac.close()

    size_mb = os.path.getsize(out) / (1024 * 1024)
    print(f"wrote {out}  ({size_mb:.1f} MB)")
    for table, n in counts.items():
        print(f"  {table:10} {n:,}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--source", default=DEFAULT_SOURCE,
                    help="flyfun-apps navigation database")
    ap.add_argument("--out", default=DEFAULT_OUT, help="database to write")
    args = ap.parse_args(argv)
    build(args.source, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
