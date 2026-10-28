# RescuPath agency coordination changes

## Intended end-to-end behavior

### Inform hospital
1. The paramedic app posts `POST /emergencies/{emergency_id}/notify-hospital` with the selected hospital UUID, the latest available route ETA and a message asking the emergency department to confirm availability.
2. The backend creates or refreshes one durable `hospital_availability_requests` row for that emergency/facility and stores the current ambulance coordinates.
3. The matching hospital operator dashboard polls `/coordination/hospital/board` about every five seconds. A newly appearing request raises an in-app banner and sound/haptic alert where supported, and the card shows severity, condition, current coordinates and ETA.
4. Hospital staff use Accept or Decline. The response persists as `ACCEPTED` or `DECLINED`.
5. The paramedic navigation screen polls `/coordination/emergencies/{emergency_id}/hospital-availability`, displays the status, and shows a message when a pending request receives a decision.
6. This button does not silently notify police. The two actions are kept separate.

### Inform police
1. The paramedic app posts `POST /emergencies/{emergency_id}/notify-police`.
2. The backend writes an idempotent `POLICE_TRAFFIC_CLEARANCE_REQUESTED` event containing current ambulance GPS and the latest known route ETA.
3. The police dashboard polls `/coordination/police/board` about every five seconds. A new alert triggers in-app sound/haptic feedback where supported.
4. The police incident card shows live ambulance coordinates on the map, hospital route ETA when available, distance from the ambulance to the officer's assigned junction, and a junction-arrival ETA.
5. The junction ETA is deliberately labelled an approximate straight-line speed estimate; it is not traffic-aware. The officer can Acknowledge, Relay to another on-duty officer, and mark Traffic Cleared.
6. Ambulance GPS updates refresh the shared ambulance row, open hospital-request coordinates/ETA, and the existing police event metadata. The police board reads the newest live location and recalculates the ETA each refresh.
7. Paramedic navigation polls `/coordination/emergencies/{emergency_id}/police-status` and shows acknowledgement, relay, and clearance state.

## Important account and data setup

- All apps must use the same backend URL/database. Local web default: `http://127.0.0.1:8000`.
- Paramedic app: `http://127.0.0.1:5050`; Police app: `http://127.0.0.1:5051`; Hospital app: `http://127.0.0.1:5052`.
- Log in to all three apps separately. Each operator app needs a registered account with the correct `POLICE` or `HOSPITAL` role.
- Hospital operator registration should use the same facility name as the recommended hospital, case-insensitive, and accurate coordinates. During live discovery, an exactly named nearby operator facility within 5 km is reused to avoid sending a request to a duplicate database UUID.
- PostgreSQL migration `0002_police_hospital_coordination` must be applied. The startup script applies Alembic migrations before launching the backend.
- Dashboards use authenticated HTTP polling. This provides an in-app notification while the respective app is open; it is not a promise of OS notifications when the app is closed. Production push notifications require a configured provider.
- Real live hospital discovery still depends on public Overpass availability. Coordination changes handle the hospital/police workflow after a hospital is selected; they do not eliminate a public map provider outage.

## Run locally

From the project root, prepare `.env`, Python requirements/migrations, and run `flutter pub get` once in each of the three mobile app folders. Then launch the backend and frontends using `scripts/start_all_local.ps1` from PowerShell. Keep your existing `backend/.env` and database credentials; do not replace working secrets with example values.
