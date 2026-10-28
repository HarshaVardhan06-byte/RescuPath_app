# RescuPath — Final Premium Paramedic Build

This package is the integrated RescuPath paramedic application: premium clinical UI, live emergency workflow, hospital selection, condition-aware routing, GPS tracking, communication actions, Google Maps handoff, profile, settings, notifications and support.

## Final UI
- Premium clinical white/light dashboard with a dark cinematic navigation map.
- Red = emergency, blue = navigation, green = hospital/status, amber = police/traffic.
- Ambulance hero imagery on Home and My Ambulance.
- Clear cards and large touch targets for fast use by responders.
- Live Navigation includes a visible **Open Map** button in the top-right, next-turn guidance, GPS/ETA/distance, route-policy details, hospital information and response actions.

## Core paramedic flow
1. Authenticate.
2. Create an emergency and capture live GPS.
3. Receive real nearby hospital recommendations.
4. Explicitly choose **Use this hospital**.
5. Enter dedicated live navigation.
6. Upload live ambulance GPS while en route.
7. Refresh the route periodically when enabled.
8. Broken-rib responses use comfort/rough-road scoring from available mapped road-quality data.
9. Cardiac responses use traffic-aware alternative routing when Google Routes is configured; otherwise the UI clearly reports the fastest road-network fallback.
10. Inform Hospital records the arrival-notification event for the hospital workflow; Call Hospital opens the device dialer when a public phone is available.
11. Inform Police records a traffic-clearance dispatch event; 112 opens the emergency dialer.
12. Mark Arrived closes the arrival stage and releases the ambulance when allowed by the backend lifecycle.

## Account and utility flows
- Personal profile editing saves through `PUT /auth/me`.
- Duty mode synchronizes the responder and ambulance availability through `PUT /auth/duty`.
- Notification, high-accuracy GPS and route-refresh preferences are stored in secure device storage.
- Notifications reads real emergency event history from the backend.
- Help & Support includes FAQs, support email/phone actions, and the 112 emergency action.
- Logout clears the secure access token and signs out Google when applicable.

## Backend
FastAPI + PostgreSQL + Alembic + JWT + OAuth hooks + hospital/resource matching + emergency lifecycle/events + GPS updates + routing + WebSocket channel. Spatial extensions are not required by the current base migration.

## Local development
### 1. Backend
```powershell
cd backend
if (!(Test-Path .env)) { Copy-Item .env.example .env }
# Keep your existing .env and database credentials if already configured.
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python -m alembic upgrade head
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

Open Swagger at `http://127.0.0.1:8000/docs`. `127.0.0.1` is the browser URL for this computer; `0.0.0.0` is a server bind address and should not be opened as a browser URL.

### 2. All three Flutter apps
Run `flutter pub get` once in each app directory, then use one terminal per app:

```cmd
cd mobile\paramedic_app
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5050
```

```cmd
cd mobile\police_app
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5051
```

```cmd
cd mobile\hospital_app
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5052
```

Or, after the setup above, use `scripts/start_all_local.ps1` to launch the backend and all three apps. All three browser apps call `http://127.0.0.1:8000` by default.

For an Android physical device, point the app to the PC LAN address:
```cmd
flutter run --dart-define=API_BASE_URL=http://YOUR_PC_IP:8000
```

## Runtime configuration
Flutter `--dart-define` values:
- `API_BASE_URL`
- `MAP_TILE_URL`
- `GOOGLE_WEB_CLIENT_ID`
- `APPLE_SERVICE_ID`
- `SUPPORT_EMAIL`
- `SUPPORT_PHONE`

Backend environment values include:
- `DATABASE_URL`
- `SECRET_KEY`
- `CORS_ORIGINS`
- `GOOGLE_ROUTES_API_KEY`
- SMTP credentials for real password-reset emails
- production database and Redis endpoints

## Production gate
This build is the final integrated source structure, but a public production emergency deployment still requires organization-owned credentials and infrastructure. In particular, provide HTTPS/WSS, managed Postgres/PostGIS, production secrets, a commercial/contracted map and tile provider where required, real OAuth credentials, SMTP, push notifications, observability, backups, security review, privacy/legal review, store signing, and device/network QA. Do not publish the Android release while it is still using the placeholder/debug signing setup or the `com.example.paramedic_app` application ID.

## Multi-agency integrated build (paramedic + police + hospital)

This archive also includes two new separate Flutter applications: `mobile/police_app` and `mobile/hospital_app`. Both use the same luxury RescuPath design tokens and share the FastAPI/PostgreSQL API with the paramedic app.

- Police: GPS-based OSM junction discovery, officer duty/location profile, active ambulance alerts, selected-hospital route map, approximate ETA to the officer's junction, acknowledge/relay/traffic-cleared actions, and in-app sound/haptic alert on a new incident while the app is open.
- Hospital: facility operator profile, live ambulance marker/route and ETA, arrival availability requests, accept/decline response, and emergency intake/resource capacity updates.
- Paramedic: GPS/location updates carry route ETA to the backend and the navigation page polls for hospital availability responses and police acknowledgement/clearance/relay status.

See [`COORDINATION_INTEGRATION.md`](COORDINATION_INTEGRATION.md) for the end-to-end workflow, migration steps, three frontend commands, test plan, and production limitations. To open all four terminal windows together after setting up the backend environment and running `flutter pub get` in each Flutter app, launch `scripts/start_all_local.ps1` from PowerShell.

For local web testing, use backend port `8000`, paramedic frontend `5050`, police frontend `5051`, and hospital frontend `5052`. Do not open `0.0.0.0` in the browser; use `127.0.0.1`.
"# RescuPath_app" 
