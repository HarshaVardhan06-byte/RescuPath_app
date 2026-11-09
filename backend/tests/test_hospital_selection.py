import pytest
import pytest_asyncio
from app.db.session import SessionLocal
from app.services.hospital_selection import find_candidates

@pytest.mark.asyncio
async def test_find_candidates_always_returns_hospitals():
    db = SessionLocal()
    try:
        # Test 1: Within Bangalore
        res1 = await find_candidates(db, 12.9716, 77.5946, radius_km=15.0, condition="CARDIAC")
        assert len(res1) >= 3, f"Expected at least 3 hospitals, got {len(res1)}"
        assert res1[0]["rank"] == 1
        assert res1[0]["recommended"] is True
        assert res1[0]["is_top_match"] is True

        # Test 2: Outside Bangalore (e.g. Chennai or remote location)
        res2 = await find_candidates(db, 13.0827, 80.2707, radius_km=15.0, condition="STROKE")
        assert len(res2) >= 3, f"Expected fallback candidates, got {len(res2)}"
        assert res2[0]["rank"] == 1
        assert "hospital_name" in res2[0]
        assert "distance_km" in res2[0]
    finally:
        db.close()
