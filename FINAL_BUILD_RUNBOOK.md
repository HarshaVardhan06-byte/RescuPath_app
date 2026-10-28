# RescuPath — Final Integrated Build Runbook

This package contains the final integrated paramedic-app UI and the previously implemented emergency, hospital, routing, GPS, profile, settings, notification, and communication workflows.

## UI direction
- Premium clinical/light dashboard with emergency red, navigation blue, status green, and amber communication accents.
- Ambulance hero imagery.
- Hospital selection with explicit **Use This Hospital** action.
- Live navigation page with a dominant map, next-turn card, GPS/ETA/distance, route-policy card, and colorful response actions.
- Google Maps handoff shown as **Open Map** in the top-right of live mapping.
- Profile with personal information, settings, notifications, help/support, and secure sign-out.

## Functional workflow
1. Login/Register/Forgot Password.
2. Create emergency and capture live GPS.
3. Discover hospital candidates.
4. Select a hospital explicitly.
5. Enter live navigation and send periodic ambulance location updates.
6. Refresh route automatically when enabled.
7. Broken-rib cases use comfort/rough-road scoring where mapped road-quality data exists.
8. Cardiac cases use traffic-aware alternative routing when Google Routes is configured; otherwise the app clearly falls back to fastest road-network routing.
9. Inform hospital records the hospital-arrival event on the backend; Call Hospital opens the device dialer when a public phone exists.
10. Inform Police records the traffic-clearance request; 112 opens the device emergency dialer.
11. Mark Arrived updates the emergency lifecycle.
12. Profile, settings, help/support, notifications and logout are wired to actual UI actions/backend calls.

## Windows local run
### Backend
```powershell
cd backend
copy .env.example .env
# edit backend/.env for your database and secrets
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
# or use scripts/start_backend.ps1
python -m alembic upgrade head
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Flutter
```cmd
cd mobile\paramedic_app
flutter clean
flutter pub get
flutter run -d chrome
```
For Android/iOS physical-device GPS testing, use a real device and pass the backend LAN URL, e.g. `--dart-define=API_BASE_URL=http://YOUR_PC_IP:8000`.

## Optional production/runtime configuration
The Flutter app accepts: `API_BASE_URL`, `MAP_TILE_URL`, `GOOGLE_WEB_CLIENT_ID`, `APPLE_SERVICE_ID`, `SUPPORT_EMAIL`, and `SUPPORT_PHONE` through `--dart-define`.
The backend accepts the matching environment settings in `backend/.env`, including `GOOGLE_ROUTES_API_KEY`, SMTP settings, production database URL, secret key, and explicit CORS origins.

## Production release gate
This repository is structured for production hardening, but it cannot honestly be called ready for public emergency-service deployment until your organization supplies and verifies its own production credentials, HTTPS/WSS, managed database, map/tile provider, OAuth credentials, SMTP, push notifications, monitoring, backups, security review, and app-store signing.

The Android release configuration intentionally does not contain a developer keystore. Add the organization’s release signing configuration before publishing. The `applicationId` should also be set to the organization-owned package ID.
