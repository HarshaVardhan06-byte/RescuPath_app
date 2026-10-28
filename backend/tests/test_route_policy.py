from app.services.routing import RouteOption, RouteResult, _select_condition_option


def _option(duration: int, rough: float, traffic: bool, profile: str) -> RouteOption:
    return RouteOption(
        RouteResult(
            distance_meters=1000,
            duration_seconds=duration,
            encoded_polyline=None,
            steps=[],
            provider="test",
            traffic_aware=traffic,
            route_profile=profile,
            comfort_applied=profile == "comfort_priority",
            comfort_score=1 - rough if profile == "comfort_priority" else None,
            rough_road_exposure=rough if profile == "comfort_priority" else None,
            alternatives_considered=2,
        ),
        rough,
    )


def test_cardiac_prefers_lowest_live_traffic_eta():
    slow = _option(900, 0.0, True, "traffic_priority")
    fast = _option(600, 0.8, True, "traffic_priority")
    assert _select_condition_option([slow, fast], "traffic_priority") is fast


def test_broken_ribs_can_prefer_smoother_route():
    rough_fast = _option(600, 0.9, False, "comfort_priority")
    smoother = _option(720, 0.1, False, "comfort_priority")
    assert _select_condition_option([rough_fast, smoother], "comfort_priority") is smoother
