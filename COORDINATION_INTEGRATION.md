# RescuPath multi-agency integration

This build contains three separate Flutter apps sharing one FastAPI/PostgreSQL backend:

- `mobile/paramedic_app`: create an emergency, select a hospital, send police traffic-clearance request, send hospital availability request, and publish live ambulance GPS plus the latest route ETA.
- `mobile/police_app`: officer profile/duty status, live GPS, nearby mapped traffic-signal/roundabout lookup (OpenStreetMap), active ambulance alerts, route/hospital display, approximate ETA to officer junction, acknowledge, relay and mark traffic cleared. New alerts trigger an in-app system alert sound and haptic feedback while the app is open.
- `mobile/hospital_app`: facility/operator profile, incoming requests for the selected hospital, live ambulance GPS and latest ETA, shared route map, accept/decline actions, and update emergency intake/resources.

## Shared flow

1. The paramedic signs in and creates an emergency.
2. The paramedic selects a hospital and enters live navigation.
3. `Inform hospital` calls `POST /emergencies/{id}/notify-hospital`. FastAPI stores/refreshes a `hospital_availability_requests` row, with the live ambulance coordinates and most recent route ETA, for that selected facility. The Hospital Dashboard polls the request queue every five seconds and raises an in-app alert for a newly arrived request. This action does not notify police; use the separate `Inform police` action for traffic clearance.
4. Hospital staff can accept or decline using `POST /coordination/hospital/requests/{request_id}/respond`. The result is persisted and appears on the paramedic navigation screen through `GET /coordination/emergencies/{id}/hospital-availability`; the paramedic page polls for the response and shows a message when REQUESTED changes to ACCEPTED or DECLINED.
5. `Inform police` calls `POST /emergencies/{id}/notify-police`. It stores a traffic-clearance alert with the latest live ambulance coordinates and last route ETA. The Police Dashboard polls about every five seconds, raises an in-app sound/haptic alert for a new request, shows the live ambulance map and an approximate ETA from the current ambulance GPS to the officer's assigned junction, and allows the officer to acknowledge, relay to another on-duty officer, and mark traffic cleared. The paramedic sees status via `GET /coordination/emergencies/{id}/police-status`.
6. Ambulance GPS posts go to `POST /emergencies/{id}/location`. The backend updates the current ambulance position and refreshes any open hospital request and police event with the newest location and route ETA. Hospital and police dashboards read from the shared database and refresh about every five seconds. Junction ETA remains an approximate straight-line estimate unless a trusted junction-routing/traffic provider is integrated.

## Local setup

### Backend

From the project root, open CMD and prepare the backend once. If you already have a working `backend/.env`, keep it; only copy the example if `.env` does not exist. Edit `DATABASE_URL` and `SECRET_KEY` before starting the server.

```cmd
cd backend
if not exist .env copy .env.example .env
py -m venv .venv
.venv\Scripts\activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python -m alembic upgrade head
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

The `py -m venv .venv` line only needs to run when the environment does not already exist. PostgreSQL must be running and the configured database/user must exist before applying migrations.

Check `http://127.0.0.1:8000/health` and `http://127.0.0.1:8000/docs`.

Keep the database URL and secret key from the existing working installation instead of overwriting them. Migration `0002_police_hospital_coordination` creates the officer profiles, hospital operator profiles, and durable hospital availability requests.

### Frontends (each in its own terminal)

Run `flutter pub get` once in each app directory, then start each app:

```cmd
cd mobile\paramedic_app
flutter pub get
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5050
```

```cmd
cd mobile\police_app
flutter pub get
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5051
```

```cmd
cd mobile\hospital_app
flutter pub get
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5052
```

All web apps call `http://127.0.0.1:8000` by default. For an Android emulator, they use `http://10.0.2.2:8000`. A physical device must use the host PC's LAN IP via `--dart-define=API_BASE_URL=http://YOUR_PC_LAN_IP:8000` and must be able to reach the PC on the local network. Browser geolocation normally requires localhost or a secure HTTPS origin.

## Local test procedure

1. Confirm backend health and database connectivity.
2. In the paramedic app, register/sign in, allow GPS, create an emergency and select a hospital.
3. Register a police test account in the Police app and allow location; use **Assign** on a nearby mapped junction if OSM returns data.
4. Register a hospital operator in the Hospital app. Use the same facility name as the recommended hospital (case-insensitive) and accurate coordinates. Live hospital discovery reuses an exactly named nearby operator facility within 5 km so requests target the facility the operator is logged into. Do not use an unrelated facility name for a test account.
5. From ambulance navigation press **Inform hospital**. Within the next dashboard refresh, the request should appear in Hospital app. Accept or decline and verify that the paramedic app shows the response.
6. Press **Inform police**. Within the next refresh, the alert should appear in Police app. Acknowledge, relay (requires another registered on-duty officer with a known location), or mark traffic cleared. Verify police status in the paramedic app.
7. While the ambulance moves or its GPS simulation changes, verify the map markers and latest ETA update in both dashboards.
8. Mark the emergency arrived/completed and verify it is removed from active boards.

## Registration policy

`ALLOW_PUBLIC_OPERATIONS_REGISTRATION=true` is for local development only. Set it to `false` in any shared or production environment and provision/verify Police and Hospital accounts administratively. The development registration endpoint is not an identity-verification mechanism.

## ETA, map, notification and safety boundaries

- Dashboard refresh uses authenticated HTTP polling (about 5 seconds). It is not currently a WebSocket/fanout or operating-system push-notification guarantee. Push notifications/background alerting requires a configured and tested provider such as FCM/APNs.
- Police ETA to a junction is currently a distance-based approximation. The destination-hospital ETA is the latest route ETA sent by the paramedic when available; fallback ETA explicitly states that it is not traffic-aware. Do not use those fallbacks as a dispatch guarantee.
- Nearby junction discovery depends on public OpenStreetMap/Overpass availability and coverage; a mapped traffic signal is not proof of an officially staffed police post.
- The OSM tile URL is suitable for development/testing subject to OSM tile usage policy. Use an approved production tile provider and cache policy for launch.
- This source package is an integrated development candidate, not certified emergency dispatch software. Before real deployment, complete security review, organization-backed operator identity verification, HTTPS/WSS, production secrets, managed database/backups, push-notification setup, access audit, privacy and clinical/legal review, and end-to-end device/network testing.
