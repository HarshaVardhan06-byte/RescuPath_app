import uuid

from pydantic import BaseModel, Field


class PatientCreate(BaseModel):
    full_name: str | None = None
    age: int | None = Field(default=None, ge=0, le=130)
    sex: str | None = None
    blood_group: str | None = None
    medical_notes: str | None = None


class EmergencyCreate(BaseModel):
    patient: PatientCreate

    ambulance_id: uuid.UUID | None = None

    condition: str = "OTHER"

    severity: str = "HIGH"

    pickup_latitude: float = Field(
        ge=-90,
        le=90,
    )

    pickup_longitude: float = Field(
        ge=-180,
        le=180,
    )


class EmergencyResponse(BaseModel):
    id: uuid.UUID

    patient_id: uuid.UUID

    ambulance_id: uuid.UUID | None

    hospital_id: uuid.UUID | None

    severity: str

    status: str

    pickup_latitude: float

    pickup_longitude: float

    destination_latitude: float | None = None

    destination_longitude: float | None = None

    model_config = {
        "from_attributes": True
    }


class LocationUpdate(BaseModel):
    latitude: float = Field(
        ge=-90,
        le=90,
    )

    longitude: float = Field(
        ge=-180,
        le=180,
    )

    accuracy_meters: float | None = Field(
        default=None,
        ge=0,
    )

    speed_mps: float | None = Field(
        default=None,
        ge=0,
    )

    heading_degrees: float | None = Field(
        default=None,
        ge=0,
        le=360,
    )

    eta_seconds: int | None = Field(
        default=None,
        ge=0,
        le=86400,
    )


class AssignHospitalRequest(BaseModel):
    hospital_id: uuid.UUID


class StatusUpdateRequest(BaseModel):
    status: str


class PoliceNotificationRequest(BaseModel):
    """Latest route ETA to attach to a police traffic-clearance alert."""
    eta_seconds: int | None = Field(default=None, ge=0, le=86400)


class HospitalArrivalNotificationRequest(BaseModel):
    hospital_id: uuid.UUID

    eta_seconds: int | None = Field(
        default=None,
        ge=0,
    )

    phone: str | None = None

    note: str | None = None