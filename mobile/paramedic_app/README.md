# RescuPath — Luxury Production-Oriented Full-Stack Build

This package is the same RescuPath architecture rebuilt as a single development-ready workflow with a premium black/white/color-accent paramedic UI.

## Included

### Backend
- FastAPI
- PostgreSQL + PostGIS
- SQLAlchemy 2.x
- Alembic migration with the enum-creation bug fixed
- JWT login/register
- Secure password hashing
- `/auth/me`
- Paramedic profile creation at registration
- Ambulance assignment/listing for the logged-in paramedic
- Patient + emergency creation
- GPS location update endpoint
- Nearby hospital/resource filtering
- Google Routes API adapter for traffic-aware routing when configured
- Emergency event records
- WebSocket endpoint from the previous build
- Docker Compose with PostgreSQL 18 + PostGIS 3.6 and Redis 7
- Demo hospital seed script

### Flutter
- Luxury dark UI: black, white, cyan, purple, pink, green and red accents
- Login
- Registration
- Secure token storage
- Authenticated command center
- Ambulance/fleet view
- Current GPS permission + location fetch
- Emergency creation
- Automatic ambulance attachment when one is assigned
- Nearby hospital recommendations
- Responsive layouts for web/mobile

## Important production boundary

This is a **production-oriented codebase**, not a claim that a zip can be deployed to emergency operations without environment-specific work. Before real deployment you must configure real secrets, HTTPS/WSS, Google Maps/Routes keys, push notification infrastructure, platform signing, RBAC, monitoring, backups, privacy/legal controls, rate limiting and security/load testing.

## Recommended local workflow — Windows

### Option A: Docker database (recommended for a clean setup)

From the project root:

```powershell
docker compose up -d postgres redis
```

Docker's official PostGIS image currently provides `postgis/postgis:18-3.6`, matching PostgreSQL 18 and PostGIS 3.6. PostgreSQL 18 images use `/var/lib/postgresql` for the data volume. See the official image documentation: https://hub.docker.com/r/postgis/postgis

### Backend

```powershell
cd backend
copy .env.example .env
```

Edit `.env` and set at least:

```text
DATABASE_URL=postgresql+psycopg://rescupath:YOUR_PASSWORD@localhost:5432/rescupath
SECRET_KEY=YOUR_LONG_RANDOM_SECRET
```

Then:

```powershell
python -m venv .venv
.venv\Scripts\activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python -m alembic upgrade head
python scripts/seed_demo.py
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Open:

```text
http://127.0.0.1:8000/docs
```

Health:

```text
http://127.0.0.1:8000/health
```

### First login

You do **not** need to manually insert a user into PostgreSQL.

Use Flutter's **Create paramedic account** screen, or Swagger:

`POST /auth/register`

Example:

```json
{
  "full_name": "Demo Paramedic",
  "email": "paramedic@example.com",
  "phone": "+919999999999",
  "password": "ChangeThisToAStrongPassword123!"
}
```

The backend creates:

```text
users
└── paramedic_profiles
```

and returns a JWT.

### Assign a local demo ambulance

After logging in, authorize Swagger with the returned bearer token and call:

`POST /ambulances/dev-assign?vehicle_number=AMB-1001`

This endpoint is deliberately marked as a development bootstrap helper. Replace it with an authorized fleet-management workflow before public deployment.

### Seed hospitals

The seed script creates three Bengaluru demo hospitals with emergency resources:

```powershell
python scripts/seed_demo.py
```

### Flutter

```powershell
cd mobile\paramedic_app
flutter pub get
flutter run -d chrome
```

For the Android emulator, the default API URL is:

```text
http://10.0.2.2:8000
```

For Flutter Web on the same Windows machine:

```text
http://127.0.0.1:8000
```

For a physical Android device, pass your computer's LAN address:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

### If platform folders are missing

The archive intentionally keeps the Flutter application source portable. From `mobile/paramedic_app` run:

```powershell
.\setup_platforms.ps1
```

or:

```powershell
flutter create .
```

Then re-apply the included Android manifest if Flutter regenerated it.

### Google Maps / Routes

The backend's Google Routes adapter becomes traffic-aware when `GOOGLE_ROUTES_API_KEY` is configured. Without the key, hospital recommendations still return distance-based candidates but route duration is unavailable.

Android Maps key:

- Configure `MAPS_API_KEY` in your Android build configuration.
- Restrict the key by Android package/SHA-1 and enabled APIs.
- Never commit production keys to Git.

## Real workflow

```text
Register / Login
      ↓
JWT stored securely on device
      ↓
Paramedic command center
      ↓
Assigned ambulance
      ↓
Start emergency
      ↓
Request device GPS
      ↓
Create patient + emergency in PostgreSQL
      ↓
Record emergency event
      ↓
Find nearby hospitals with emergency capacity
      ↓
Google traffic-aware route when API key is configured
      ↓
Hospital assignment
      ↓
Live ambulance location updates
      ↓
WebSocket event channel
```

## Database migration note

The original starter migration explicitly created `user_role` and then SQLAlchemy attempted to create the same PostgreSQL enum again during `users` table creation. This build removes the duplicate explicit creation. That is why a clean database can now run:

```powershell
python -m alembic upgrade head
```

If an old development database already contains a partial `user_role` object, use a fresh development database or remove only that partial development state before rerunning the migration. Do not do this against production data.

## Production hardening still required

- Strong secrets and secret manager
- HTTPS/WSS
- Refresh-token rotation/revocation
- Fine-grained RBAC for paramedic/hospital/police/admin
- FCM/APNs push notifications
- Background location permissions and OS-specific policies
- Real fleet assignment/dispatch workflow
- Real hospital integration and acceptance status
- Police assistance workflow
- Redis-backed event fan-out/background jobs
- Rate limiting/WAF
- Audit logging and retention
- Database backups and restore testing
- Observability and incident alerting
- Android/iOS release signing
- Security, privacy, reliability and load testing
