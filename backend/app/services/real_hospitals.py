from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from uuid import NAMESPACE_URL, UUID, uuid5

import httpx


# Public Overpass instances with global OSM coverage. The list intentionally
# includes multiple independent operators so one overloaded server does not
# block the emergency workflow.
OVERPASS_ENDPOINTS = (
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
    "https://overpass-api.de/api/interpreter",
    "https://z.overpass-api.de/api/interpreter",
    "https://lz4.overpass-api.de/api/interpreter",
)

_CACHE: dict[tuple[float, float, int], tuple[float, list["LiveHospital"], str, datetime]] = {}
_CACHE_TTL_SECONDS = 180.0


@dataclass(frozen=True)
class LiveHospital:
    osm_type: str
    osm_id: int
    name: str
    latitude: float
    longitude: float
    tags: dict[str, str]
    emergency_status: str
    beds_total: int | None
    hospital_uuid: UUID | None = None

    @property
    def hospital_id(self) -> UUID:
        if self.hospital_uuid is not None:
            return self.hospital_uuid
        return uuid5(
            NAMESPACE_URL,
            f"https://www.openstreetmap.org/{self.osm_type}/{self.osm_id}",
        )


def _parse_int(value: str | None) -> int | None:
    if not value:
        return None
    digits = "".join(ch for ch in value if ch.isdigit())
    if not digits:
        return None
    try:
        return int(digits)
    except ValueError:
        return None


def _emergency_status(tags: dict[str, str]) -> str:
    emergency = tags.get("emergency", "").strip().lower()
    emergency_room = tags.get("emergency_room", "").strip().lower()
    speciality = (
        tags.get("healthcare:speciality", "")
        + " "
        + tags.get("healthcare:specialty", "")
    ).lower()

    if emergency == "no" or emergency_room == "no":
        return "NOT_EMERGENCY"

    if (
        emergency == "yes"
        or emergency_room in {"yes", "24/7"}
        or "emergency" in speciality
    ):
        return "VERIFIED_EMERGENCY"

    return "UNVERIFIED"


def _coordinates(element: dict) -> tuple[float | None, float | None]:
    if element.get("type") == "node":
        return element.get("lat"), element.get("lon")
    center = element.get("center") or {}
    return center.get("lat"), center.get("lon")


def _build_query(latitude: float, longitude: float, radius_meters: int) -> str:
    return f"""
[out:json][timeout:6];
(
  nwr(around:{radius_meters},{latitude},{longitude})[amenity=hospital][name];
  nwr(around:{radius_meters},{latitude},{longitude})[healthcare=hospital][name];
);
out center tags qt;
"""


def _dedupe(hospitals: list[LiveHospital]) -> list[LiveHospital]:
    seen: set[tuple[str, int]] = set()
    result: list[LiveHospital] = []
    for hospital in hospitals:
        key = (hospital.osm_type, hospital.osm_id)
        if key in seen:
            continue
        seen.add(key)
        result.append(hospital)
    return result


async def _fetch_one(
    client: httpx.AsyncClient,
    endpoint: str,
    query: str,
) -> tuple[str, list[LiveHospital], datetime]:
    response = await client.post(
        endpoint,
        data={"data": query},
        headers={"Accept": "application/json"},
    )
    response.raise_for_status()
    payload = response.json()

    metadata = payload.get("osm3s", {})
    raw_timestamp = metadata.get("timestamp_osm_base")
    try:
        data_timestamp = (
            datetime.fromisoformat(raw_timestamp.replace("Z", "+00:00"))
            if raw_timestamp
            else datetime.now(timezone.utc)
        )
    except (AttributeError, ValueError):
        data_timestamp = datetime.now(timezone.utc)

    hospitals: list[LiveHospital] = []

    for element in payload.get("elements", []):
        osm_type = str(element.get("type", ""))
        osm_id = element.get("id")
        if not osm_type or not isinstance(osm_id, int):
            continue

        tags = {
            str(k): str(v)
            for k, v in (element.get("tags") or {}).items()
        }
        lat, lon = _coordinates(element)
        if lat is None or lon is None:
            continue

        name = (tags.get("name") or tags.get("official_name") or "").strip()
        if not name:
            continue

        hospitals.append(
            LiveHospital(
                osm_type=osm_type,
                osm_id=osm_id,
                name=name,
                latitude=float(lat),
                longitude=float(lon),
                tags=tags,
                emergency_status=_emergency_status(tags),
                beds_total=_parse_int(tags.get("beds")),
            )
        )

    return endpoint, _dedupe(hospitals), data_timestamp


async def _race(
    latitude: float,
    longitude: float,
    radius_meters: int,
) -> tuple[list[LiveHospital], str, datetime] | None:
    query = _build_query(latitude, longitude, radius_meters)
    timeout = httpx.Timeout(5.5, connect=2.0, read=4.5, write=2.0, pool=2.0)

    async with httpx.AsyncClient(
        timeout=timeout,
        headers={
            "User-Agent": "RescuPath/1.0 (emergency-response-project)",
        },
        follow_redirects=True,
    ) as client:
        tasks = [
            asyncio.create_task(_fetch_one(client, endpoint, query))
            for endpoint in OVERPASS_ENDPOINTS
        ]

        try:
            for task in asyncio.as_completed(tasks):
                try:
                    endpoint, hospitals, timestamp = await task
                    if hospitals:
                        return hospitals, endpoint, timestamp
                except Exception:
                    continue
        finally:
            for task in tasks:
                if not task.done():
                    task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

    return None


async def fetch_real_hospitals(
    latitude: float,
    longitude: float,
    radius_km: float = 10.0,
) -> tuple[list[LiveHospital], str, datetime]:
    """Fetch real nearby hospitals quickly from public OSM/Overpass data.

    A small-radius race is attempted first because most ambulance searches
    need hospitals close to the current GPS point. A wider race is only used
    when the small search finds nothing. Results are cached briefly to prevent
    repeated emergency-screen refreshes from hammering public services.
    """
    requested_radius = max(2.0, min(radius_km, 30.0))

    # First attempt: 7 km around the live ambulance position.
    first_radius_m = min(int(requested_radius * 1000), 7000)
    key = (round(latitude, 4), round(longitude, 4), first_radius_m)

    cached = _CACHE.get(key)
    if cached and (time.monotonic() - cached[0]) < _CACHE_TTL_SECONDS:
        _, hospitals, endpoint, timestamp = cached
        return hospitals, endpoint, timestamp

    result = await _race(latitude, longitude, first_radius_m)
    if result is not None and result[0]:
        hospitals, endpoint, timestamp = result
        _CACHE[key] = (time.monotonic(), hospitals, endpoint, timestamp)
        return hospitals, endpoint, timestamp

    # Second attempt: requested radius, capped at 15 km for responsiveness.
    wide_radius_m = min(int(requested_radius * 1000), 15000)
    wide_key = (round(latitude, 4), round(longitude, 4), wide_radius_m)

    cached = _CACHE.get(wide_key)
    if cached and (time.monotonic() - cached[0]) < _CACHE_TTL_SECONDS:
        _, hospitals, endpoint, timestamp = cached
        return hospitals, endpoint, timestamp

    if wide_radius_m != first_radius_m:
        result = await _race(latitude, longitude, wide_radius_m)
        if result is not None:
            hospitals, endpoint, timestamp = result
            _CACHE[wide_key] = (time.monotonic(), hospitals, endpoint, timestamp)
            return hospitals, endpoint, timestamp

    raise RuntimeError("Live OSM hospital lookup unavailable")
