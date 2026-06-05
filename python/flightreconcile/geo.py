"""Geographic helpers: coordinate parsing and great-circle math.

Self-contained (only stdlib) so the package has no hard dependency beyond
pdfplumber/pandas used elsewhere.
"""
from __future__ import annotations

import math
import re
from typing import Optional, Tuple

NM_PER_KM = 1.0 / 1.852
EARTH_R_NM = 6371.0088 * NM_PER_KM  # mean earth radius in nautical miles

# ForeFlight coordinate token, e.g. "N5120.9/W00033.5"
#   lat = DDMM.m  (2 degree digits), lon = DDDMM.m (3 degree digits)
_COORD_RE = re.compile(
    r"^([NS])(\d{2})(\d{2}\.\d)/([EW])(\d{3})(\d{2}\.\d)$"
)


def parse_ff_coord(token: str) -> Optional[Tuple[float, float]]:
    """Parse a ForeFlight DDMM.m coordinate token into (lat, lon) decimal deg.

    Returns None if the token is not a coordinate.
    """
    m = _COORD_RE.match(token.strip())
    if not m:
        return None
    ns, lat_d, lat_m, ew, lon_d, lon_m = m.groups()
    lat = int(lat_d) + float(lat_m) / 60.0
    lon = int(lon_d) + float(lon_m) / 60.0
    if ns == "S":
        lat = -lat
    if ew == "W":
        lon = -lon
    return lat, lon


def is_coord(token: str) -> bool:
    return _COORD_RE.match(token.strip()) is not None


def haversine_nm(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in nautical miles."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    )
    return 2 * EARTH_R_NM * math.asin(min(1.0, math.sqrt(a)))


def initial_bearing(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Initial true bearing (deg, 0-360) from point 1 to point 2."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


def cross_track_nm(
    lat: float, lon: float,
    lat1: float, lon1: float,
    lat2: float, lon2: float,
) -> float:
    """Signed cross-track distance (NM) of point P from great-circle path 1->2.

    Positive = right of track. Useful for "how far off the planned leg".
    """
    d13 = haversine_nm(lat1, lon1, lat, lon) / EARTH_R_NM  # angular
    th13 = math.radians(initial_bearing(lat1, lon1, lat, lon))
    th12 = math.radians(initial_bearing(lat1, lon1, lat2, lon2))
    return math.asin(math.sin(d13) * math.sin(th13 - th12)) * EARTH_R_NM


def angle_diff(a: float, b: float) -> float:
    """Smallest signed difference a-b in degrees, range (-180, 180]."""
    d = (a - b + 180.0) % 360.0 - 180.0
    return d + 360.0 if d <= -180.0 else d


def wind_components(
    wind_dir_from: float, wind_speed: float, course: float
) -> Tuple[float, float]:
    """Return (headwind, crosswind) components in same units as wind_speed.

    wind_dir_from is the direction the wind blows FROM (met convention).
    headwind > 0 means a headwind (slows you), < 0 a tailwind.
    """
    # angle between where wind comes from and where we're heading
    ang = math.radians(wind_dir_from - course)
    headwind = wind_speed * math.cos(ang)
    crosswind = wind_speed * math.sin(ang)
    return headwind, crosswind
