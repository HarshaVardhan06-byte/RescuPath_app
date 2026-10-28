from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from math import atan2, cos, radians, sin, sqrt
from typing import Any, Iterable

import httpx

from app.core.config import settings
from app.services.rough_road import get_rough_road_points


@dataclass
class RouteResult:
    distance_meters: float | None
    duration_seconds: int | None
    encoded_polyline: str | None = None
    steps: list[dict] | None = None
    provider: str = "none"
    traffic_aware: bool = False
    route_profile: str = "fastest"
    comfort_applied: bool = False
    comfort_score: float | None = None
    rough_road_exposure: float | None = None
    alternatives_considered: int = 1
    route_label: str | None = None


@dataclass
class RouteOption:
    result: RouteResult
    rough_exposure: float = 0.0


def _decode_polyline(encoded: str | None) -> list[list[float]]:
    if not encoded:
        return []

    points: list[list[float]] = []
    index = 0
    latitude = 0
    longitude = 0

    try:
        while index < len(encoded):
            shift = 0
            result = 0
            while True:
                b = ord(encoded[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            latitude += ~(result >> 1) if result & 1 else result >> 1

            shift = 0
            result = 0
            while True:
                b = ord(encoded[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            longitude += ~(result >> 1) if result & 1 else result >> 1

            points.append([latitude / 1e5, longitude / 1e5])
    except (IndexError, ValueError):
        return []

    return points


def _haversine_meters(
    lat1: float,
    lon1: float,
    lat2: float,
    lon2: float,
) -> float:
    earth_radius_m = 6_371_000.0
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = (
        sin(dlat / 2) ** 2
        + cos(radians(lat1))
        * cos(radians(lat2))
        * sin(dlon / 2) ** 2
    )
    return 2 * earth_radius_m * atan2(sqrt(a), sqrt(max(1.0 - a, 0.0)))


def _roughness_exposure(
    encoded_polyline: str | None,
    rough_points: Iterable[dict[str, float]] | None,
) -> float:
    """Return a 0..1 mapped rough-road exposure index for a route.

    OSM smoothness/surface tags are sparse in many areas, so missing tags are
    treated as unknown rather than smooth. The index is used to compare routes,
    not as a clinical or safety guarantee.
    """
    route_points = _decode_polyline(encoded_polyline)
    if not route_points:
        return 0.0

    points = list(rough_points or [])
    if not points:
        return 0.0

    hits = 0.0
    for rough in points:
        rlat = float(rough.get("latitude", 0.0))
        rlon = float(rough.get("longitude", 0.0))
        nearest = min(
            _haversine_meters(rlat, rlon, point[0], point[1])
            for point in route_points
        )
        if nearest <= 100.0:
            hits += max(0.0, 1.0 - nearest / 100.0)

    # Normalise against route length so a longer route does not automatically
    # appear worse solely because it crosses more mapped road segments.
    if len(route_points) >= 2:
        length_km = sum(
            _haversine_meters(
                route_points[i - 1][0],
                route_points[i - 1][1],
                route_points[i][0],
                route_points[i][1],
            )
            for i in range(1, len(route_points))
        ) / 1000.0
    else:
        length_km = 1.0

    normalised = hits / max(length_km, 1.0)
    return round(min(1.0, normalised / 2.0), 4)


def _route_profile(condition: str | None) -> str:
    normalized = (condition or "OTHER").strip().upper()
    if normalized in {"BROKEN_RIBS", "BROKEN RIBS", "RIB FRACTURE"}:
        return "comfort_priority"
    if normalized in {"CARDIAC", "CHEST PAIN", "HEART ATTACK"}:
        return "traffic_priority"
    return "fastest"


def _build_result_from_google(
    route: dict[str, Any],
    *,
    route_label: str | None,
    traffic_aware: bool,
    route_profile: str,
    rough_exposure: float = 0.0,
    alternatives_considered: int = 1,
) -> RouteResult:
    raw_duration = str(route.get("duration", ""))
    seconds = int(float(raw_duration[:-1])) if raw_duration.endswith("s") else None
    polyline = route.get("polyline", {}).get("encodedPolyline")

    steps: list[dict] = []
    for leg in route.get("legs", []):
        for step in leg.get("steps", []):
            instruction = step.get("navigationInstruction", {}) or {}
            text = instruction.get("instructions")
            maneuver = instruction.get("maneuver")
            end_location = (step.get("endLocation") or {}).get("latLng") or {}
            if text:
                item = {
                    "instruction": text,
                    "maneuver": maneuver,
                }
                if end_location.get("latitude") is not None and end_location.get("longitude") is not None:
                    item["latitude"] = end_location["latitude"]
                    item["longitude"] = end_location["longitude"]
                steps.append(item)

    comfort_score = round(1.0 - rough_exposure, 4) if route_profile == "comfort_priority" else None

    return RouteResult(
        route.get("distanceMeters"),
        seconds,
        polyline,
        steps,
        "google",
        traffic_aware,
        route_profile,
        route_profile == "comfort_priority",
        comfort_score,
        rough_exposure if route_profile == "comfort_priority" else None,
        alternatives_considered,
        route_label,
    )


class RoutingProvider:
    async def route(
        self,
        origin_lat: float,
        origin_lng: float,
        destination_lat: float,
        destination_lng: float,
    ) -> RouteResult:
        raise NotImplementedError

    async def route_for_condition(
        self,
        origin_lat: float,
        origin_lng: float,
        destination_lat: float,
        destination_lng: float,
        condition: str,
        rough_road_points: list[dict[str, float]] | None = None,
    ) -> RouteResult:
        return await self.route(
            origin_lat,
            origin_lng,
            destination_lat,
            destination_lng,
        )


class GoogleRoutesProvider(RoutingProvider):
    async def _compute_routes(
        self,
        origin_lat: float,
        origin_lng: float,
        destination_lat: float,
        destination_lng: float,
        *,
        traffic_optimal: bool,
        alternatives: bool,
    ) -> list[dict[str, Any]]:
        url = f"{settings.google_routes_base_url}/directions/v2:computeRoutes"
        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": settings.google_routes_api_key or "",
            "X-Goog-FieldMask": (
                "routes.distanceMeters,routes.duration,routes.routeLabels,"
                "routes.polyline.encodedPolyline,"
                "routes.legs.steps.distanceMeters,"
                "routes.legs.steps.navigationInstruction.instructions,"
                "routes.legs.steps.navigationInstruction.maneuver,"
                "routes.legs.steps.endLocation.latLng"
            ),
        }
        payload = {
            "origin": {
                "location": {
                    "latLng": {
                        "latitude": origin_lat,
                        "longitude": origin_lng,
                    }
                }
            },
            "destination": {
                "location": {
                    "latLng": {
                        "latitude": destination_lat,
                        "longitude": destination_lng,
                    }
                }
            },
            "travelMode": "DRIVE",
            "routingPreference": (
                "TRAFFIC_AWARE_OPTIMAL" if traffic_optimal else "TRAFFIC_AWARE"
            ),
            "departureTime": datetime.now(timezone.utc).isoformat().replace(
                "+00:00", "Z"
            ),
            "computeAlternativeRoutes": alternatives,
            "languageCode": "en-US",
            "units": "METRIC",
        }

        async with httpx.AsyncClient(timeout=15) as client:
            response = await client.post(url, headers=headers, json=payload)
            response.raise_for_status()
            data = response.json()

        return data.get("routes", [])

    async def route(self, origin_lat, origin_lng, destination_lat, destination_lng):
        if not settings.google_routes_api_key:
            return RouteResult(None, None, None, [], "google", False)

        routes = await self._compute_routes(
            origin_lat,
            origin_lng,
            destination_lat,
            destination_lng,
            traffic_optimal=False,
            alternatives=False,
        )
        if not routes:
            return RouteResult(None, None, None, [], "google", True)

        return _build_result_from_google(
            routes[0],
            route_label=(routes[0].get("routeLabels") or [None])[0],
            traffic_aware=True,
            route_profile="fastest",
        )

    async def route_for_condition(
        self,
        origin_lat,
        origin_lng,
        destination_lat,
        destination_lng,
        condition,
        rough_road_points=None,
    ):
        if not settings.google_routes_api_key:
            return await OsrmFallbackProvider().route_for_condition(
                origin_lat,
                origin_lng,
                destination_lat,
                destination_lng,
                condition,
                rough_road_points,
            )

        profile = _route_profile(condition)
        routes = await self._compute_routes(
            origin_lat,
            origin_lng,
            destination_lat,
            destination_lng,
            traffic_optimal=profile == "traffic_priority",
            alternatives=True,
        )
        if not routes:
            return RouteResult(None, None, None, [], "google", True, profile)

        options: list[RouteOption] = []
        for route_index, raw_route in enumerate(routes):
            rough_exposure = _roughness_exposure(
                raw_route.get("polyline", {}).get("encodedPolyline"),
                rough_road_points,
            )
            result = _build_result_from_google(
                raw_route,
                route_label=(raw_route.get("routeLabels") or [None])[0],
                traffic_aware=True,
                route_profile=profile,
                rough_exposure=rough_exposure,
                alternatives_considered=len(routes),
            )
            options.append(RouteOption(result, rough_exposure))

        chosen = _select_condition_option(options, profile)
        return chosen.result


class OsrmFallbackProvider(RoutingProvider):
    """Free public fallback. Real road geometry/turn steps, but no live traffic."""

    async def _compute_routes(
        self,
        origin_lat,
        origin_lng,
        destination_lat,
        destination_lng,
    ) -> list[dict[str, Any]]:
        url = (
            "https://router.project-osrm.org/route/v1/driving/"
            f"{origin_lng},{origin_lat};{destination_lng},{destination_lat}"
        )
        params = {
            "overview": "full",
            "geometries": "polyline",
            "steps": "true",
            "alternatives": "2",
        }

        async with httpx.AsyncClient(timeout=15) as client:
            response = await client.get(url, params=params)
            response.raise_for_status()
            data = response.json()

        return data.get("routes", [])

    def _result(self, route: dict[str, Any], profile: str, rough_exposure: float, alternatives_count: int) -> RouteResult:
        steps: list[dict] = []
        for leg in route.get("legs", []):
            for step in leg.get("steps", []):
                maneuver = step.get("maneuver", {}) or {}
                name = step.get("name")
                modifier = maneuver.get("modifier")
                step_type = maneuver.get("type")
                parts = []
                if step_type and step_type != "turn":
                    parts.append(step_type.replace("_", " ").title())
                if modifier:
                    parts.append(modifier.replace("-", " ").title())
                if name:
                    parts.append(f"onto {name}")
                instruction = " ".join(parts)
                location = maneuver.get("location") or []
                if instruction:
                    item = {
                        "instruction": instruction,
                        "maneuver": modifier or step_type,
                    }
                    if len(location) >= 2:
                        item["longitude"] = location[0]
                        item["latitude"] = location[1]
                    steps.append(item)

        return RouteResult(
            route.get("distance"),
            int(route["duration"]) if route.get("duration") is not None else None,
            route.get("geometry"),
            steps,
            "osrm",
            False,
            profile,
            profile == "comfort_priority",
            round(1.0 - rough_exposure, 4) if profile == "comfort_priority" else None,
            rough_exposure if profile == "comfort_priority" else None,
            alternatives_count,
            None,
        )

    async def route(self, origin_lat, origin_lng, destination_lat, destination_lng):
        routes = await self._compute_routes(
            origin_lat,
            origin_lng,
            destination_lat,
            destination_lng,
        )
        if not routes:
            return RouteResult(None, None, None, [], "osrm", False)
        return self._result(routes[0], "fastest", 0.0, len(routes))

    async def route_for_condition(
        self,
        origin_lat,
        origin_lng,
        destination_lat,
        destination_lng,
        condition,
        rough_road_points=None,
    ):
        profile = _route_profile(condition)
        routes = await self._compute_routes(
            origin_lat,
            origin_lng,
            destination_lat,
            destination_lng,
        )
        if not routes:
            return RouteResult(None, None, None, [], "osrm", False, profile)

        options: list[RouteOption] = []
        for raw_route in routes:
            rough_exposure = _roughness_exposure(
                raw_route.get("geometry"),
                rough_road_points,
            )
            options.append(
                RouteOption(
                    self._result(raw_route, profile, rough_exposure, len(routes)),
                    rough_exposure,
                )
            )

        return _select_condition_option(options, profile).result


class FallbackRoutingProvider(RoutingProvider):
    def __init__(self):
        self.google = GoogleRoutesProvider()
        self.osrm = OsrmFallbackProvider()

    async def route(self, origin_lat, origin_lng, destination_lat, destination_lng):
        if settings.google_routes_api_key:
            try:
                result = await self.google.route(
                    origin_lat,
                    origin_lng,
                    destination_lat,
                    destination_lng,
                )
                if result.duration_seconds is not None:
                    return result
            except Exception:
                pass

        return await self.osrm.route(
            origin_lat,
            origin_lng,
            destination_lat,
            destination_lng,
        )

    async def route_for_condition(
        self,
        origin_lat,
        origin_lng,
        destination_lat,
        destination_lng,
        condition,
        rough_road_points=None,
    ):
        if settings.google_routes_api_key:
            try:
                result = await self.google.route_for_condition(
                    origin_lat,
                    origin_lng,
                    destination_lat,
                    destination_lng,
                    condition,
                    rough_road_points,
                )
                if result.duration_seconds is not None:
                    return result
            except Exception:
                pass

        return await self.osrm.route_for_condition(
            origin_lat,
            origin_lng,
            destination_lat,
            destination_lng,
            condition,
            rough_road_points,
        )


def _select_condition_option(options: list[RouteOption], profile: str) -> RouteOption:
    if not options:
        raise ValueError("No route options available")

    if profile == "traffic_priority":
        # Cardiac routing chooses the lowest current traffic-aware ETA when the
        # provider supplies live traffic; otherwise it explicitly remains a
        # fastest-road fallback and is marked as traffic-unaware.
        return min(
            options,
            key=lambda option: option.result.duration_seconds
            if option.result.duration_seconds is not None
            else float("inf"),
        )

    if profile == "comfort_priority":
        durations = [
            option.result.duration_seconds
            for option in options
            if option.result.duration_seconds is not None
        ]
        baseline = min(durations) if durations else None

        def cost(option: RouteOption) -> tuple[float, int]:
            duration = option.result.duration_seconds or baseline or 0
            if baseline:
                time_penalty = min(2.0, duration / max(baseline, 1)) - 1.0
            else:
                time_penalty = 0.0
            # Heavily penalise mapped rough-road exposure but keep a modest time
            # component so an extreme detour is not selected blindly.
            combined = 0.75 * option.rough_exposure + 0.25 * max(time_penalty, 0.0)
            return combined, duration

        return min(options, key=cost)

    return min(
        options,
        key=lambda option: option.result.duration_seconds
        if option.result.duration_seconds is not None
        else float("inf"),
    )


def get_routing_provider():
    return FallbackRoutingProvider()


def route_points(result: RouteResult) -> list[list[float]]:
    return _decode_polyline(result.encoded_polyline)
