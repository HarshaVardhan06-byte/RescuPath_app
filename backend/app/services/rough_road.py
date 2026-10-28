from __future__ import annotations

import asyncio
import time
from typing import Iterable

import httpx


OVERPASS_ENDPOINTS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
)

ROUGH_SMOOTHNESS = (
    "bad",
    "very_bad",
    "horrible",
    "very_horrible",
    "impassable",
)

ROUGH_SURFACES = (
    "unpaved",
    "gravel",
    "fine_gravel",
    "pebblestone",
    "cobblestone",
    "sett",
    "dirt",
    "earth",
    "mud",
    "sand",
    "ground",
)

_CACHE: dict[
    tuple[float, float, int],
    tuple[float, list[dict[str, float]]],
] = {}

_CACHE_TTL_SECONDS = 120.0


def _regex(values: Iterable[str]) -> str:
    return "^(" + "|".join(values) + ")$"


def _build_query(
    latitude: float,
    longitude: float,
    radius_meters: int,
) -> str:
    smoothness = _regex(ROUGH_SMOOTHNESS)
    surfaces = _regex(ROUGH_SURFACES)

    return f"""
[out:json][timeout:18];
(
  way(around:{radius_meters},{latitude},{longitude})
    [highway]
    [smoothness~"{smoothness}"];

  way(around:{radius_meters},{latitude},{longitude})
    [highway]
    [surface~"{surfaces}"];
);
out center tags;
"""


async def _fetch(
    endpoint: str,
    query: str,
) -> list[dict[str, float]]:
    async with httpx.AsyncClient(
        timeout=httpx.Timeout(
            12.0,
            connect=5.0,
        ),
        headers={
            "User-Agent": (
                "RescuPath/1.0 "
                "(emergency-response-project)"
            )
        },
    ) as client:
        response = await client.post(
            endpoint,
            data={"data": query},
        )

        response.raise_for_status()

        payload = response.json()

    points: list[dict[str, float]] = []
    seen: set[int] = set()

    for element in payload.get("elements", []):
        way_id = element.get("id")
        center = element.get("center") or {}

        lat = center.get("lat")
        lon = center.get("lon")

        if not isinstance(way_id, int):
            continue

        if way_id in seen:
            continue

        if not isinstance(lat, (float, int)):
            continue

        if not isinstance(lon, (float, int)):
            continue

        seen.add(way_id)

        points.append(
            {
                "latitude": float(lat),
                "longitude": float(lon),
            }
        )

    return points[:35]


async def get_rough_road_points(
    latitude: float,
    longitude: float,
    radius_km: float = 8.0,
) -> list[dict[str, float]]:
    radius_meters = max(
        1500,
        min(
            int(radius_km * 1000),
            12000,
        ),
    )

    key = (
        round(latitude, 3),
        round(longitude, 3),
        radius_meters,
    )

    cached = _CACHE.get(key)

    if cached:
        timestamp, points = cached

        if (
            time.monotonic() - timestamp
            < _CACHE_TTL_SECONDS
        ):
            return points

    query = _build_query(
        latitude,
        longitude,
        radius_meters,
    )

    tasks = [
        _fetch(endpoint, query)
        for endpoint in OVERPASS_ENDPOINTS
    ]

    for task in asyncio.as_completed(tasks):
        try:
            points = await task

            _CACHE[key] = (
                time.monotonic(),
                points,
            )

            return points

        except Exception:
            continue

    _CACHE[key] = (
        time.monotonic(),
        [],
    )

    return []