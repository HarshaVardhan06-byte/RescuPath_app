import uuid
from pydantic import BaseModel, Field


class HospitalCreate(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    status: str = "ACTIVE"
    is_emergency_available: bool = True


class HospitalResponse(HospitalCreate):
    id: uuid.UUID

    model_config = {"from_attributes": True}


class HospitalResourceCreate(BaseModel):
    icu_beds_available: int = Field(default=0, ge=0)
    emergency_beds_available: int = Field(default=0, ge=0)
    ventilators_available: int = Field(default=0, ge=0)
    oxygen_available: bool = True
    trauma_capable: bool = False
    cardiac_capable: bool = False


class HospitalResourceResponse(HospitalResourceCreate):
    id: uuid.UUID
    hospital_id: uuid.UUID

    model_config = {"from_attributes": True}


class HospitalCandidate(BaseModel):
    hospital_id: uuid.UUID
    hospital_name: str
    rank_score: float | None = None
    model_score: float | None = None
    model_version: str | None = None
    rank: int | None = None
    recommended: bool = False
    condition: str | None = None
    condition_score: float | None = None
    distance_km: float
    duration_seconds: int | None = None
    route_provider: str | None = None
    traffic_aware: bool = False
    route_profile: str | None = None
    comfort_score: float | None = None
    rough_road_exposure: float | None = None
    alternatives_considered: int | None = None
    route_policy_score: float | None = None
    emergency_service_status: str | None = None
    availability_confidence: str | None = None
    beds_total_listed: int | None = None
    phone: str | None = None
    website: str | None = None
    opening_hours: str | None = None
    address: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    source: str | None = None
    source_timestamp: str | None = None
    availability_note: str | None = None
    reason: str | None = None
