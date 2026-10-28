# RescuPath Production Checklist

## Product / UX
- [x] Premium clinical UI
- [x] Emergency creation workflow
- [x] Explicit hospital selection
- [x] Live navigation UI
- [x] Open in Google Maps action
- [x] Profile / personal information
- [x] Settings
- [x] Notifications
- [x] Help & Support
- [x] Secure logout

## Runtime integrations
- [x] Live GPS stream
- [x] Backend location updates
- [x] Route refresh
- [x] Hospital discovery
- [x] Condition-aware route profile
- [x] Inform hospital backend event
- [x] Direct hospital call when a public number exists
- [x] Inform police backend event
- [x] Police officer Flutter dashboard with OSM junction lookup and route map
- [x] Hospital operator Flutter dashboard with live ambulance request, ETA/map, accept/decline response and resource availability
- [x] Durable hospital availability requests and police relay/acknowledgement events
- [x] Paramedic response status refresh for police and hospital
- [x] 112 emergency dialer action
- [x] Mark-arrived lifecycle update

## Required before public release
- [ ] Replace development `.env` values with deployment secrets
- [ ] HTTPS/WSS
- [ ] Managed PostgreSQL + backups (PostGIS is not required by the current base migration)
- [ ] Redis or managed equivalent where required
- [ ] Production Google Routes credentials and billing controls if traffic-aware routing is used
- [ ] Production tile/map provider and usage policy
- [ ] Verified Google/Apple OAuth configuration
- [ ] SMTP or transactional email provider
- [ ] FCM/APNs push notification service
- [ ] Background-location policy review and store disclosures
- [ ] Android release keystore + signing
- [ ] Organization-owned Android application ID
- [ ] Apple signing/team/bundle configuration
- [ ] Monitoring, logging, alerting, rate limits and security review
- [ ] Real-device QA on Android/iOS, including GPS loss, permissions, weak network, offline/online transitions and app backgrounding

## Multi-agency integrations
- [x] Separate Police Flutter app under `mobile/police_app`
- [x] Separate Hospital Flutter app under `mobile/hospital_app`
- [x] Shared backend request/event flow documented in `COORDINATION_INTEGRATION.md`
- [ ] Complete live PostgreSQL + Flutter web/android end-to-end test on the target machine
- [ ] Configure FCM/APNs or the organization-approved push provider for background/terminated-app alerts
- [ ] Provision/verify real officer and hospital operator identities before production
