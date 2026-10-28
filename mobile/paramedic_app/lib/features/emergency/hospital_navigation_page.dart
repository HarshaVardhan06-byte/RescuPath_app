import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/services/location_service.dart';
import '../../core/services/user_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

class HospitalNavigationPage extends StatefulWidget {
  final String emergencyId;
  final Map<String, dynamic> hospital;
  final Map<String, dynamic>? assignedEmergency;
  final String initialSeverity;
  const HospitalNavigationPage({super.key, required this.emergencyId, required this.hospital, this.assignedEmergency, this.initialSeverity = 'HIGH'});
  @override State<HospitalNavigationPage> createState() => _HospitalNavigationPageState();
}

class _HospitalNavigationPageState extends State<HospitalNavigationPage> {
  final api = ApiClient();
  final location = LocationService();
  final map = MapController();
  StreamSubscription<dynamic>? locationSubscription;
  Timer? routeTimer;
  Timer? statusTimer;
  Timer? hospitalResponseTimer;
  List<Map<String, dynamic>> hospitalResponses = [];
  Map<String, dynamic>? policeCoordination;
  LatLng? current; LatLng? destination;
  Map<String, dynamic>? route; Map<String, dynamic>? emergency;
  bool loading = true; bool refreshing = false; bool informingHospital = false; bool informingPolice = false;
  bool showDirections = true;
  String status = 'HOSPITAL_ASSIGNED'; DateTime? lastGpsUpdate; String? error;
  OverlayEntry? _toastEntry;
  Timer? _toastTimer;
  double currentSpeedMps = 0;

  String get hospitalName => widget.hospital['hospital_name']?.toString() ?? 'Selected Hospital';
  String? get hospitalPhone => widget.hospital['phone']?.toString();
  String get condition => (widget.hospital['condition']?.toString() ?? emergency?['condition']?.toString() ?? 'OTHER').toUpperCase();

  @override void initState() { super.initState(); emergency = widget.assignedEmergency; status = widget.assignedEmergency?['status']?.toString() ?? 'HOSPITAL_ASSIGNED'; _setDestination(widget.assignedEmergency); _initialize(); }

  Future<void> _initialize() async {
    try {
      final e = await api.get('/emergencies/${widget.emergencyId}');
      if (mounted) setState(() { emergency = Map<String, dynamic>.from(e); status = e['status']?.toString() ?? status; _setDestination(e); });
      final highAccuracy = await UserPreferences.highAccuracyGps;
      try { final p = await location.currentPosition(highAccuracy: highAccuracy); await _handleLocation(p.latitude, p.longitude, p.accuracy, p.speed, p.heading); } catch (_) {}
      await _refreshRoute();
      await _setEnRoute();
      _startTracking(highAccuracy);
      if (await UserPreferences.autoRouteRefresh) { routeTimer = Timer.periodic(const Duration(seconds: 12), (_) => _refreshRoute()); }
      statusTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshEmergency());
      hospitalResponseTimer = Timer.periodic(const Duration(seconds: 8), (_) { _refreshHospitalResponses(); _refreshPoliceStatus(); });
      await _refreshHospitalResponses();
      await _refreshPoliceStatus();
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => loading = false); }
  }

  void _setDestination(Map<String, dynamic>? e) {
    final lat = e?['destination_latitude'] ?? widget.hospital['latitude']; final lng = e?['destination_longitude'] ?? widget.hospital['longitude'];
    if (lat is num && lng is num) destination = LatLng(lat.toDouble(), lng.toDouble());
  }

  Future<void> _refreshEmergency() async { try { final e = await api.get('/emergencies/${widget.emergencyId}'); if (!mounted) return; setState(() { emergency = Map<String, dynamic>.from(e); status = e['status']?.toString() ?? status; _setDestination(e); }); } catch (_) {} }

  Future<void> _refreshHospitalResponses() async {
    try {
      final raw = await api.get('/coordination/emergencies/${widget.emergencyId}/hospital-availability');
      if (!mounted || raw is! List) return;
      final rows = raw.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
      final isFirstResponseLoad = hospitalResponses.isEmpty;
      final previousStatuses = <String, String>{
        for (final row in hospitalResponses)
          if (row['request_id'] != null)
            row['request_id'].toString(): row['status']?.toString() ?? 'REQUESTED',
      };
      final newlyResponded = rows.where((row) {
        final id = row['request_id']?.toString();
        final statusNow = row['status']?.toString() ?? 'REQUESTED';
        final hasTerminalResponse =
            statusNow == 'ACCEPTED' || statusNow == 'DECLINED';
        final changedFromPending =
            id != null &&
            previousStatuses.containsKey(id) &&
            previousStatuses[id] == 'REQUESTED';
        return id != null &&
            hasTerminalResponse &&
            (changedFromPending || isFirstResponseLoad) &&
            row['hospital_id']?.toString() ==
                widget.hospital['hospital_id']?.toString();
      }).toList();
      setState(() => hospitalResponses = rows);
      if (newlyResponded.isNotEmpty && mounted) {
        final response = newlyResponded.first;
        final accepted = response['status']?.toString() == 'ACCEPTED';
        final responseHospitalName = response['hospital_name']?.toString() ?? hospitalName;
        final responseNote = response['response_note']?.toString();
        final responseMessage = '$responseHospitalName ${accepted ? "accepted" : "declined"} the emergency arrival request${responseNote == null || responseNote.isEmpty ? "" : ": $responseNote"}';
        _toast(responseMessage, accepted ? AppTheme.green : AppTheme.red);
      }
    } catch (_) {}
  }

  Future<void> _refreshPoliceStatus() async {
    try {
      final raw = await api.get(
        '/coordination/emergencies/${widget.emergencyId}/police-status',
      );
      if (!mounted || raw is! Map) return;

      final next = Map<String, dynamic>.from(raw);
      final wasAcknowledged = policeCoordination?['acknowledged'] == true;
      final isAcknowledged = next['acknowledged'] == true;
      final wasCleared = policeCoordination?['traffic_cleared'] == true;
      final isCleared = next['traffic_cleared'] == true;

      setState(() => policeCoordination = next);

      if (!wasAcknowledged && isAcknowledged) {
        _toast(
          'Police acknowledged the ambulance alert.',
          AppTheme.green,
        );
      }
      if (!wasCleared && isCleared) {
        _toast(
          'Police reported traffic cleared along the route.',
          AppTheme.green,
        );
      }
    } catch (_) {}
  }

  Future<void> _setEnRoute() async {
    if (status == 'EN_ROUTE' || status == 'HOSPITAL_ALERTED') return;
    try { final result = await api.post('/emergencies/${widget.emergencyId}/status', {'status': 'EN_ROUTE'}); if (mounted) setState(() => status = result['status']?.toString() ?? 'EN_ROUTE'); } catch (_) {}
  }

  Future<void> _refreshRoute() async {
    if (refreshing || !mounted) return;
    setState(() => refreshing = true);
    try { final result = await api.get('/emergencies/${widget.emergencyId}/route'); if (!mounted) return; setState(() { route = Map<String, dynamic>.from(result as Map); _setDestination(route); }); }
    catch (e) { if (mounted && route == null) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => refreshing = false); }
  }

  void _startTracking(bool highAccuracy) {
    locationSubscription?.cancel();
    locationSubscription = location.stream(highAccuracy: highAccuracy).listen((p) => _handleLocation(p.latitude, p.longitude, p.accuracy, p.speed, p.heading));
  }

  Future<void> _handleLocation(double latitude, double longitude, double accuracy, double speed, double heading) async {
    final point = LatLng(latitude, longitude);
    if (!mounted) return;
    setState(() { current = point; currentSpeedMps = speed; lastGpsUpdate = DateTime.now(); });
    try { await api.post('/emergencies/${widget.emergencyId}/location', {'latitude': latitude, 'longitude': longitude, 'accuracy_meters': accuracy, 'speed_mps': speed, 'heading_degrees': heading, 'eta_seconds': route?['duration_seconds'] is num ? (route!['duration_seconds'] as num).round() : null}); } catch (_) {}
    if (mounted) map.move(point, map.camera.zoom < 13 ? 15 : map.camera.zoom);
  }

  Future<void> _informHospital() async {
    final id = widget.hospital['hospital_id']?.toString(); if (id == null || id.isEmpty || informingHospital) return;
    setState(() => informingHospital = true);
    try { final raw = route?['duration_seconds']; await api.post('/emergencies/${widget.emergencyId}/notify-hospital', {'hospital_id': id, 'eta_seconds': raw is num ? raw.round() : null, 'phone': hospitalPhone, 'note': 'Ambulance is en route to $hospitalName. Please confirm emergency department availability.'}); if (mounted) { setState(() => status = 'HOSPITAL_ALERTED'); _toast('Hospital informed • ETA ${_etaText()}. Waiting for their response.', AppTheme.green); await _refreshHospitalResponses(); } }
    catch (e) { if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''), AppTheme.red); }
    finally { if (mounted) setState(() => informingHospital = false); }
  }

  Future<void> _callHospital() async {
    final phone = hospitalPhone;
    if (phone == null || phone.trim().isEmpty) { _toast('No public phone is available in the live hospital data. Use Open Map to view the hospital listing.', AppTheme.amber); await _openGoogleMaps(); return; }
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    await launchUrl(Uri(scheme: 'tel', path: cleaned), mode: LaunchMode.externalApplication);
  }

  Future<void> _informPolice() async {
    if (informingPolice) return;
    setState(() => informingPolice = true);
    try { final routeEta = route?['duration_seconds']; await api.post('/emergencies/${widget.emergencyId}/notify-police', {'eta_seconds': routeEta is num ? routeEta.round() : null}); await _refreshPoliceStatus(); if (mounted) _toast('Traffic-clearance request sent to police with the latest ambulance GPS and route ETA.', AppTheme.orange); }
    catch (e) { if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''), AppTheme.red); }
    finally { if (mounted) setState(() => informingPolice = false); }
  }

  Future<void> _call112() async { await launchUrl(Uri(scheme: 'tel', path: '112'), mode: LaunchMode.externalApplication); }

  Future<void> _openGoogleMaps() async {
    final lat = widget.hospital['latitude']; final lng = widget.hospital['longitude']; if (lat is! num || lng is! num) return;
    final origin = current == null ? null : '${current!.latitude},${current!.longitude}';
    final query = <String, String>{'api': '1', 'destination': '${lat.toDouble()},${lng.toDouble()}', 'travelmode': 'driving', 'dir_action': 'navigate'};
    if (origin != null) query['origin'] = origin;
    final uri = Uri.https('www.google.com', '/maps/dir/', query);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _markArrived() async {
    try { final result = await api.post('/emergencies/${widget.emergencyId}/status', {'status': 'ARRIVED'}); if (mounted) { setState(() => status = result['status']?.toString() ?? 'ARRIVED'); _toast('Arrival recorded. Ambulance marked available after arrival.', AppTheme.green); } }
    catch (e) { if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''), AppTheme.red); }
  }

  List<LatLng> _routePoints() {
    final raw = route?['polyline_points']; if (raw is! List) return const [];
    return raw.whereType<List>().where((p) => p.length >= 2).map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble())).toList();
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const r = 6371000.0; final dLat = (b.latitude - a.latitude) * math.pi / 180; final dLng = (b.longitude - a.longitude) * math.pi / 180; final lat1 = a.latitude * math.pi / 180; final lat2 = b.latitude * math.pi / 180; final h = math.pow(math.sin(dLat / 2), 2) + math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2); return 2 * r * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  Map<String, dynamic>? _nextStep() {
    final raw = route?['steps']; if (raw is! List || raw.isEmpty) return null; if (current == null) return Map<String, dynamic>.from(raw.first as Map);
    Map<String, dynamic>? closest; double best = double.infinity;
    for (final item in raw.whereType<Map>()) { final lat = item['latitude']; final lng = item['longitude']; if (lat is! num || lng is! num) continue; final d = _distanceMeters(current!, LatLng(lat.toDouble(), lng.toDouble())); if (d >= 35 && d < best) { best = d; closest = Map<String, dynamic>.from(item); } }
    return closest ?? Map<String, dynamic>.from(raw.first as Map);
  }

  String _policyTitle() { switch (route?['route_profile']?.toString()) { case 'comfort_priority': return 'COMFORT PRIORITY'; case 'traffic_priority': return 'TRAFFIC PRIORITY'; default: return 'FASTEST AVAILABLE'; } }
  String _policyDetail() { if (route?['route_profile'] == 'comfort_priority') { final x = route?['rough_road_exposure']; return x is num ? 'Road-quality scoring is reducing rough-road exposure (${(x * 100).round()}%).' : 'Road-quality scoring is applied where mapped surface data is available.'; } if (route?['route_profile'] == 'traffic_priority') return route?['traffic_aware'] == true ? 'Traffic-aware routing is active for this cardiac response.' : 'Traffic data is unavailable; fastest road-network routing is being used.'; return 'Standard road-network routing.'; }
  String _etaText() { final raw = route?['duration_seconds']; return raw is num ? '${(raw / 60).ceil()} min' : '—'; }
  String _distanceText() { final raw = route?['distance_meters']; return raw is num ? raw >= 1000 ? '${(raw / 1000).toStringAsFixed(1)} km' : '${raw.round()} m' : '—'; }
  void _toast(String text, Color color) {
    if (!mounted) return;

    _toastTimer?.cancel();
    _toastEntry?.remove();
    _toastEntry = null;

    final overlay = Overlay.of(context, rootOverlay: true);
    final media = MediaQuery.of(context);
    final toastWidth =
        media.size.width < 500 ? media.size.width - 28.0 : 370.0;

    _toastEntry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: media.padding.top + 12,
        right: 14,
        width: toastWidth.clamp(220.0, 370.0).toDouble(),
        child: IgnorePointer(
          ignoring: true,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 13,
              ),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(17),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 20,
                    offset: Offset(0, 7),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.notifications_active_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_toastEntry!);
    _toastTimer = Timer(const Duration(seconds: 5), () {
      _toastEntry?.remove();
      _toastEntry = null;
      _toastTimer = null;
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _toastEntry?.remove();
    routeTimer?.cancel();
    statusTimer?.cancel();
    hospitalResponseTimer?.cancel();
    locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = _routePoints();
    final step = _nextStep();

    return Scaffold(
      backgroundColor: const Color(0xFF0A1020),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : LayoutBuilder(
              builder: (context, viewport) {
                final compact = viewport.maxHeight < 760;
                final panelLift = compact ? 222.0 : 242.0;

                return Stack(
                  children: [
                    // The map remains the main surface and fills the viewport.
                    Positioned.fill(
                      child: FlutterMap(
                        mapController: map,
                        options: MapOptions(
                          initialCenter: current ??
                              destination ??
                              const LatLng(12.9716, 77.5946),
                          initialZoom: 14,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: AppConfig.mapTileUrl,
                            userAgentPackageName:
                                'com.rescupath.paramedic_app',
                          ),
                          if (points.isNotEmpty)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: points,
                                  strokeWidth: 15,
                                  color: AppTheme.blue.withValues(alpha: .16),
                                ),
                                Polyline(
                                  points: points,
                                  strokeWidth: 8,
                                  color: AppTheme.blue,
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              if (current != null)
                                Marker(
                                  point: current!,
                                  width: 64,
                                  height: 64,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      border: Border.all(
                                        color: AppTheme.blue,
                                        width: 4,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x660A63FF),
                                          blurRadius: 24,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.navigation_rounded,
                                      color: AppTheme.blue,
                                      size: 32,
                                    ),
                                  ),
                                ),
                              if (destination != null)
                                Marker(
                                  point: destination!,
                                  width: 60,
                                  height: 60,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppTheme.red,
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x66FF3B4B),
                                          blurRadius: 24,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.local_hospital_rounded,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          RichAttributionWidget(
                            attributions: const [
                              TextSourceAttribution(
                                'OpenStreetMap contributors',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Dark floating header.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                          child: Row(
                            children: [
                              _glassButton(
                                Icons.arrow_back_rounded,
                                () => Navigator.pop(context),
                                'Back',
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xEE0A1930),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: .12,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: AppTheme.red,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.local_hospital_rounded,
                                          color: Colors.white,
                                          size: 19,
                                        ),
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              hospitalName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Text(
                                              'LIVE NAVIGATION',
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: .65,
                                                ),
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 9),
                              _glassButton(
                                Icons.map_rounded,
                                _openGoogleMaps,
                                'Open in Google Maps',
                                fill: AppTheme.red,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Next-turn card matching the navigation concept.
                    if (showDirections && step != null)
                      Positioned(
                        top: 100,
                        left: 14,
                        right: 14,
                        child: SurfaceCard(
                          color: Colors.white,
                          radius: 22,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: AppTheme.blue.withValues(alpha: .10),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.turn_right_rounded,
                                  color: AppTheme.blue,
                                  size: 29,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'NEXT TURN',
                                      style: TextStyle(
                                        color: AppTheme.muted,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      step['instruction']?.toString() ??
                                          'Continue on route',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.ink,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.navigation_rounded,
                                color: AppTheme.blue.withValues(alpha: .75),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Small map tools, away from the turn card.
                    Positioned(
                      top: showDirections && step != null ? 190 : 100,
                      right: 14,
                      child: Column(
                        children: [
                          _mapTool(
                            Icons.my_location_rounded,
                            () {
                              if (current != null) {
                                map.move(current!, 16);
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          _mapTool(
                            showDirections
                                ? Icons.visibility_off_rounded
                                : Icons.turn_right_rounded,
                            () => setState(() {
                              showDirections = !showDirections;
                            }),
                          ),
                        ],
                      ),
                    ),

                    // Speed indicator floats over the map.
                    Positioned(
                      left: 16,
                      bottom: panelLift + 5,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xEE0A1930),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .85),
                            width: 3,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x44000000),
                              blurRadius: 18,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              (currentSpeedMps * 3.6).round().toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Text(
                              'km/h',
                              style: TextStyle(
                                color: Color(0xFFBAC8E5),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Live GPS, ETA and distance bar.
                    Positioned(
                      left: 98,
                      right: 14,
                      bottom: panelLift + 18,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xEE0A1930),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .13),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x44000000),
                              blurRadius: 20,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _darkMetric(
                                Icons.wifi_rounded,
                                current == null ? 'Waiting' : 'Live',
                                'GPS',
                                AppTheme.green,
                              ),
                            ),
                            _metricDivider(),
                            Expanded(
                              child: _darkMetric(
                                Icons.schedule_rounded,
                                _etaText(),
                                'ETA',
                                AppTheme.blue,
                              ),
                            ),
                            _metricDivider(),
                            Expanded(
                              child: _darkMetric(
                                Icons.route_rounded,
                                _distanceText(),
                                'Distance',
                                const Color(0xFF9B7BFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Clean bottom action sheet: readiness status stays in the
                    // hospital card; response notifications use the 5s toast.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SafeArea(
                        top: false,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(28),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x220A1930),
                                blurRadius: 24,
                                offset: Offset(0, -6),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: AppTheme.blue.withValues(
                                        alpha: .08,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(
                                      Icons.local_hospital_rounded,
                                      color: AppTheme.red,
                                      size: 30,
                                    ),
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          hospitalName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppTheme.ink,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Hospital destination • ${_distanceText()}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppTheme.muted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 58,
                                    height: 60,
                                    child: OutlinedButton(
                                      onPressed: _callHospital,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppTheme.navy,
                                        side: const BorderSide(
                                          color: Color(0xFFDCE5F4),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        padding: EdgeInsets.zero,
                                      ),
                                      child: const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.call_rounded, size: 20),
                                          SizedBox(height: 2),
                                          Text(
                                            'Call',
                                            style: TextStyle(fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _action(
                                      Icons.local_hospital_rounded,
                                      'Inform Hospital',
                                      AppTheme.green,
                                      informingHospital
                                          ? null
                                          : _informHospital,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _action(
                                      Icons.phone_rounded,
                                      'Call Hospital',
                                      AppTheme.blue,
                                      _callHospital,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _action(
                                      Icons.shield_rounded,
                                      'Inform Police',
                                      const Color(0xFFFF991F),
                                      informingPolice
                                          ? null
                                          : _informPolice,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 48,
                                      child: FilledButton.icon(
                                        onPressed: _markArrived,
                                        icon: const Icon(
                                          Icons.flag_rounded,
                                          size: 20,
                                        ),
                                        label: const Text(
                                          'Mark Arrived',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppTheme.red,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 60,
                                    height: 48,
                                    child: FilledButton(
                                      onPressed: _call112,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppTheme.navy,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        padding: EdgeInsets.zero,
                                      ),
                                      child: const Text(
                                        '112',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Loading/route errors are transient and don't cover map.
                    if (error != null && route == null)
                      Positioned(
                        top: 200,
                        left: 18,
                        right: 18,
                        child: SurfaceCard(
                          color: Colors.white,
                          radius: 16,
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.wifi_off_rounded,
                                color: AppTheme.red,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  error!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.ink,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _refreshRoute,
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _darkMetric(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFBAC8E5),
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  Widget _metricDivider() => Container(
        width: 1,
        height: 38,
        color: Colors.white.withValues(alpha: .14),
      );

  Widget _metric(IconData icon, String value, String label, Color color) => Column(children: [Icon(icon, color: color, size: 20), const SizedBox(height: 4), Text(value, style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900)), Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 9))]);
  Widget _action(IconData icon, String label, Color color, VoidCallback? onTap) => SizedBox(height: 52, child: FilledButton.icon(onPressed: onTap, icon: Icon(icon, size: 19), label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10)), style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)), padding: const EdgeInsets.symmetric(horizontal: 9))));
  Widget _mapTool(IconData icon, VoidCallback onTap) => Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x330A1930), blurRadius: 18)]), child: IconButton(onPressed: onTap, icon: Icon(icon, color: AppTheme.ink)));
  Widget _glassButton(IconData icon, VoidCallback onTap, String tooltip, {Color? fill}) => Container(
        decoration: BoxDecoration(
          color: fill ?? const Color(0xEE0A1930),
          borderRadius: BorderRadius.circular(17),
          boxShadow: const [BoxShadow(color: Color(0x330A1930), blurRadius: 18)],
        ),
        child: TextButton.icon(
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white, size: 20),
          label: Text(tooltip == 'Open in Google Maps' ? 'Open Map' : '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          ),
        ),
      );
}
