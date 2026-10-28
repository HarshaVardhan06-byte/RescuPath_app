from app.models.emergency import EmergencyEvent


def record_event(db, emergency_id, event_type: str, payload: dict | None = None):
    event = EmergencyEvent(
        emergency_id=emergency_id,
        event_type=event_type,
        payload=payload,
    )
    db.add(event)
    return event
