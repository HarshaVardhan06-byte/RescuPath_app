import uuid
import pytest
from datetime import datetime, timezone, timedelta
from app.db.session import SessionLocal
from app.models.user import User, UserRole
from app.models.emergency import Emergency, EmergencyEvent
from app.models.patient import Patient
from app.models.police_officer import PoliceOfficerProfile
from app.core.security import hash_password
from app.api.coordination import _distance_km, police_board
from app.services.routing import OsrmFallbackProvider, _decode_polyline, _encode_polyline


def test_distance_km_accuracy():
    # Koramangala to MG Road (~4.9 km)
    d = _distance_km(12.9352, 77.6245, 12.9756, 77.6066)
    assert 4.5 < d < 5.5

    # Within 250 meters
    d_close = _distance_km(12.9352, 77.6245, 12.9360, 77.6250)
    assert d_close < 0.3
    assert d_close <= 1.0

    # 15 km away
    d_far = _distance_km(12.9352, 77.6245, 13.0600, 77.6000)
    assert d_far > 14.0


def test_encode_decode_polyline_roundtrip():
    coords = [[12.93201, 77.60802], [12.93355, 77.60921], [12.93500, 77.61500]]
    encoded = _encode_polyline(coords)
    assert len(encoded) > 0
    decoded = _decode_polyline(encoded)
    assert [[round(p[0], 5), round(p[1], 5)] for p in decoded] == coords


@pytest.mark.asyncio
async def test_emergency_routing_one_way_exemption():
    provider = OsrmFallbackProvider()
    # SG Palya to Jayadeva Hospital
    res = await provider.route_for_condition(12.9320, 77.6080, 12.9172, 77.5924, "CARDIAC")
    assert res.distance_meters is not None and res.distance_meters > 0
    assert res.duration_seconds is not None and res.duration_seconds > 0
    assert res.encoded_polyline is not None
    assert len(res.steps or []) > 0
    # Decoded points should form a continuous path
    pts = _decode_polyline(res.encoded_polyline)
    assert len(pts) > 5


def test_police_board_1km_radius_and_profile_isolation():
    db = SessionLocal()
    try:
        # Create a test patient
        patient = Patient(
            full_name="Radius Test Patient",
            age=45,
            sex="MALE",
        )
        db.add(patient)
        db.flush()

        # Create a test paramedic
        paramedic = User(
            full_name="Radius Test Paramedic",
            email=f"paramedic.{uuid.uuid4().hex[:6]}@rescupath.com",
            password_hash=hash_password("pw123"),
            role=UserRole.PARAMEDIC,
            is_active=True,
        )
        db.add(paramedic)
        db.flush()

        # 1. Create a test emergency at SG Palya (12.9320, 77.6080)
        amb_lat = 12.9320
        amb_lon = 77.6080
        em = Emergency(
            patient_id=patient.id,
            created_by=paramedic.id,
            pickup_latitude=amb_lat,
            pickup_longitude=amb_lon,
            severity="HIGH",
            status="EN_ROUTE",
        )
        db.add(em)
        db.commit()

        # Record clearance request
        db.add(EmergencyEvent(
            emergency_id=em.id,
            event_type="POLICE_TRAFFIC_CLEARANCE_REQUESTED",
            payload={
                "ambulance_latitude": amb_lat,
                "ambulance_longitude": amb_lon,
                "severity": "HIGH",
            },
            created_at=datetime.now(timezone.utc),
        ))
        db.commit()

        # 2. Create Officers within 1 km (e.g. 200m away in SG Palya)
        close_user = User(
            full_name="SG Palya Nearby Officer",
            email=f"close.officer.{uuid.uuid4().hex[:6]}@police.gov.in",
            password_hash=hash_password("pw123"),
            role=UserRole.POLICE,
            is_active=True,
        )
        db.add(close_user)
        db.flush()
        db.add(PoliceOfficerProfile(
            user_id=close_user.id,
            badge_number=f"BADGE-{uuid.uuid4().hex[:4].upper()}",
            station_name="SG Palya Traffic",
            junction_name="SG Palya Main Junction",
            current_latitude=12.9330,
            current_longitude=77.6090,
            junction_latitude=12.9330,
            junction_longitude=77.6090,
            duty_status="ON_DUTY",
        ))
        db.commit()

        # 3. Create Officer Far (15 km away in Yelahanka)
        far_user = User(
            full_name="Distant Officer (15km)",
            email=f"far.officer.{uuid.uuid4().hex[:6]}@police.gov.in",
            password_hash=hash_password("pw123"),
            role=UserRole.POLICE,
            is_active=True,
        )
        db.add(far_user)
        db.flush()
        db.add(PoliceOfficerProfile(
            user_id=far_user.id,
            badge_number=f"BADGE-{uuid.uuid4().hex[:4].upper()}",
            station_name="Yelahanka Traffic",
            junction_name="Yelahanka Bypass",
            current_latitude=13.0600,
            current_longitude=77.6000,
            junction_latitude=13.0600,
            junction_longitude=77.6000,
            duty_status="ON_DUTY",
        ))
        db.commit()

        # 4. Check Nearby Officer Board: MUST have the alert!
        close_board = police_board(db=db, user=close_user)
        close_alert_ids = [a["emergency_id"] for a in close_board["alerts"]]
        assert str(em.id) in close_alert_ids

        # 5. Check Distant Officer Board (15 km away): MUST NOT have the alert!
        far_board = police_board(db=db, user=far_user)
        far_alert_ids = [a["emergency_id"] for a in far_board["alerts"]]
        assert str(em.id) not in far_alert_ids, "Distant officer (15 km away) must not receive ambulance alerts > 1 km"

        # 6. Test Profile Isolation for Acknowledgement
        # Close officer acknowledges the alert
        db.add(EmergencyEvent(
            emergency_id=em.id,
            event_type="POLICE_ALERT_ACKNOWLEDGED",
            payload={"officer_id": str(close_user.id), "junction": "SG Palya Main Junction"},
            created_at=datetime.now(timezone.utc),
        ))
        db.commit()

        # Verify close officer sees police_acknowledged = True
        close_board_updated = police_board(db=db, user=close_user)
        close_card = next(a for a in close_board_updated["alerts"] if a["emergency_id"] == str(em.id))
        assert close_card["police_acknowledged"] is True

        # Another nearby officer in SG Palya created now should see police_acknowledged = False for their own profile
        another_user = User(
            full_name="Second SG Palya Officer",
            email=f"second.officer.{uuid.uuid4().hex[:6]}@police.gov.in",
            password_hash=hash_password("pw123"),
            role=UserRole.POLICE,
            is_active=True,
        )
        db.add(another_user)
        db.flush()
        db.add(PoliceOfficerProfile(
            user_id=another_user.id,
            badge_number=f"BADGE-{uuid.uuid4().hex[:4].upper()}",
            station_name="SG Palya Traffic",
            junction_name="Dairy Circle Post",
            current_latitude=12.9340,
            current_longitude=77.6070,
            duty_status="ON_DUTY",
        ))
        db.commit()

        second_board = police_board(db=db, user=another_user)
        second_card = next(a for a in second_board["alerts"] if a["emergency_id"] == str(em.id))
        # Both officers in SG Palya receive it because both are within 1 km
        assert second_card["police_acknowledged"] is False
        assert second_card["any_police_acknowledged"] is True

        # 7. Test Ambulance Arrival Notice Delivery to Police
        # Paramedic marks status as ARRIVED
        em.status = "ARRIVED"
        db.add(EmergencyEvent(
            emergency_id=em.id,
            event_type="POLICE_AMBULANCE_ARRIVED",
            payload={
                "emergency_id": str(em.id),
                "ambulance_number": "KA-01-AMB-108",
                "hospital_name": "Sri Jayadeva Hospital",
                "message": "Ambulance KA-01-AMB-108 has successfully arrived at Sri Jayadeva Hospital. Traffic clearance concluded.",
                "arrived_at": datetime.now(timezone.utc).isoformat(),
                "status": "ARRIVED",
            },
            created_at=datetime.now(timezone.utc),
        ))
        db.commit()

        # Check that police board still delivers the arrived emergency and includes arrival notice
        arrival_board = police_board(db=db, user=close_user)
        arrived_card = next((a for a in arrival_board["alerts"] if a["emergency_id"] == str(em.id)), None)
        assert arrived_card is not None, "Ambulance in ARRIVED status must not be dropped before police clearance"
        assert arrived_card["is_arrived"] is True
        assert "arrived at Sri Jayadeva" in arrived_card["arrival_message"]
        assert arrived_card["arrival_notification_id"] is not None

    finally:
        db.close()
