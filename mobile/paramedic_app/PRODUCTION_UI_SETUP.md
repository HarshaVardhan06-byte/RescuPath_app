# RescuPath production UI build

This build replaces the application UI with the Premium Clinical / Command Center direction while retaining the emergency, hospital, GPS and routing APIs.

## Apply / run

1. Run the backend with your configured database and environment.
2. In `mobile/paramedic_app`, run `flutter clean` and `flutter pub get`.
3. For web: `flutter run -d chrome`.
4. For real GPS: run on a physical Android/iOS device and grant location permission.

## Production configuration

Build with a real API base URL:

`flutter build apk --dart-define=API_BASE_URL=https://api.yourdomain.example --dart-define=SUPPORT_EMAIL=... --dart-define=SUPPORT_PHONE=...`

Configure the backend `GOOGLE_ROUTES_API_KEY` when live traffic-aware routing is required for cardiac responses. Without it, the routing layer intentionally falls back to OSRM road-network routing.

Google OAuth / Apple Sign In require their platform credentials.

## UX flow

Create Emergency → live GPS → real hospital matching → Use This Hospital → live navigation → Google Maps handoff / hospital / police actions → Mark Arrived.

## Production hardening still required before public launch

- Use HTTPS for API and websocket traffic.
- Configure production database, migrations, secrets, CORS origins and push notification credentials.
- Configure verified support email/phone and production OAuth credentials.
- Test location, telephony, background execution, permissions, GPS loss, route-provider outages and emergency-call behavior on target Android/iOS devices.
- Replace development-only public routing services with a provider/SLA appropriate for your expected operational load if required.
