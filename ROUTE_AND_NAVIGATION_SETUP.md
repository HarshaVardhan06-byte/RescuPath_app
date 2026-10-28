# RescuPath — Real Hospital Selection + Condition-Aware Navigation

This update changes the paramedic flow to:

`Create Emergency -> Live GPS -> Hospital matching -> Use This Hospital -> Dedicated Live Navigation`

## 1. Hospital selection is manual

Creating an emergency no longer auto-selects the first hospital. The app displays live hospital candidates and the paramedic chooses **USE THIS HOSPITAL**.

Each candidate includes live road ETA when routing is available, hospital condition-fit signals, emergency-service metadata, contact data when present in OSM, and the route policy used for ranking.

## 2. Route policy

### Cardiac

`CARDIAC`, `CHEST PAIN`, and `HEART ATTACK` use a **traffic-priority** route policy.

- Google Routes: traffic-aware optimal routing + alternative routes when `GOOGLE_ROUTES_API_KEY` is configured.
- Free fallback: OSRM alternative routes. This is real road-network routing but does not provide live traffic data.
- The chosen route is the option with the lowest available traffic-aware ETA.

### Broken ribs

`BROKEN_RIBS`, `BROKEN RIBS`, and `RIB FRACTURE` use a **comfort-priority** route policy.

- Up to three route options are compared when the routing provider returns alternatives.
- OpenStreetMap `smoothness` and `surface` tags are used as mapped rough-road signals.
- Rough-road exposure is penalized heavily, with a modest travel-time penalty so the app does not blindly choose an extreme detour.
- Missing OSM road-quality data is treated as unknown; it is not treated as proof that a road is smooth.

This is an operational routing heuristic, not a clinically validated medical model.

## 3. Live navigation page

After hospital selection the app opens `HospitalNavigationPage`.

It contains:

- live ambulance GPS marker
- selected hospital destination marker
- live route polyline
- next maneuver / turn instruction
- live GPS state
- ETA
- remaining distance
- route policy and mapped route-quality details
- Inform Hospital
- Call Hospital, when a public phone number is available
- Inform Police / Clear Traffic
- Call 112
- Open with Google Maps
- Mark Arrived at Hospital

The app refreshes the route periodically while GPS updates are sent to the backend.

## 4. Open with Google Maps

The button uses a Google Maps Directions URL with the selected hospital latitude/longitude, `travelmode=driving`, and `dir_action=navigate`. Google Maps can then perform its own active turn-by-turn navigation using the device's current location.

No Google Maps SDK/API key is required for this external Maps URL. A Google Routes API key is separate and only affects RescuPath's own traffic-aware route calculation.

## 5. Configuration

The backend reads `GOOGLE_ROUTES_API_KEY` from `backend/.env`.

Leave it blank to use free OSRM routing. Add a valid Google Routes API key to enable RescuPath's traffic-aware route calculation and alternative-route comparison.

The mobile app does not need a Google Maps SDK key for the **OPEN WITH GOOGLE MAPS** button.

## 6. Run

Backend:

```powershell
cd backend
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Flutter:

```powershell
cd mobile\paramedic_app
flutter clean
flutter pub get
flutter run
```

For real device GPS and external phone/Maps actions, test on an Android/iOS device. Chrome is useful for UI testing but is not the production GPS target.
