// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_map/flutter_map.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:latlong2/latlong.dart';
// import '../core/app_api.dart';
// import '../core/luxury_theme.dart';

// class PoliceDashboardPage extends StatefulWidget {
//   final Future<void> Function() onLogout;
//   const PoliceDashboardPage({super.key, required this.onLogout});
//   @override State<PoliceDashboardPage> createState() => _PoliceDashboardPageState();
// }

// class _PoliceDashboardPageState extends State<PoliceDashboardPage> {
//   final api = AppApi();
//   Timer? pollTimer; Timer? routeTimer; Timer? junctionTimer; Timer? buzzerTimer; StreamSubscription<Position>? locationSubscription;
//   Map<String, dynamic> board = {}; Map<String, dynamic>? routeData; String? selectedEmergencyId;
//   List<Map<String, dynamic>> nearbyJunctions = []; bool fetchingJunctions = false; DateTime? junctionsUpdated;
//   bool loading = true; bool busy = false; bool onDuty = true; String? error; double? myLat; double? myLon;
//   bool _hasLoadedInitialBoard = false;
//   Set<String> _knownNotificationKeys = <String>{};

//   List<Map<String, dynamic>> _list(dynamic raw) => raw is List ? raw.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList() : <Map<String, dynamic>>[];
//   Map<String, dynamic>? get officer => board['officer'] is Map ? Map<String, dynamic>.from(board['officer']) : null;
//   List<Map<String, dynamic>> get alerts => _list(board['alerts']);
//   List<Map<String, dynamic>> get junctions => _list(board['junctions']);
//   Map<String, dynamic>? get selected { for (final item in alerts) { if (item['emergency_id']?.toString() == selectedEmergencyId) return item; } return alerts.isEmpty ? null : alerts.first; }

//   @override void initState() {
//     super.initState();
//     _load();
//     pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
//     routeTimer = Timer.periodic(const Duration(seconds: 20), (_) => _loadRoute());
//     junctionTimer = Timer.periodic(const Duration(minutes: 1), (_) => _loadNearbyJunctions(force: true));
//     _startLocation();
//   }

//   Future<void> _load() async {
//     try {
//       final raw = await api.get('/coordination/police/board');
//       if (!mounted || raw is! Map) return;
//       final next = Map<String, dynamic>.from(raw);
//       final nextAlerts = _list(next['alerts']);
//       final incomingNotificationKeys = <String>{};
//       for (final alert in nextAlerts) {
//         final emergencyKey = alert['emergency_id']?.toString();
//         if (emergencyKey == null) continue;
//         incomingNotificationKeys.add('$emergencyKey:alert');
//         final relayKey = alert['relay_notification_id']?.toString();
//         if (relayKey != null && relayKey.isNotEmpty) {
//           incomingNotificationKeys.add('$emergencyKey:relay:$relayKey');
//         }
//       }
//       final newNotificationKeys = _hasLoadedInitialBoard
//           ? incomingNotificationKeys.difference(_knownNotificationKeys)
//           : <String>{};
//       _knownNotificationKeys = incomingNotificationKeys;
//       _hasLoadedInitialBoard = true;
//       String? id = selectedEmergencyId;
//       if (id == null || !nextAlerts.any((e) => e['emergency_id']?.toString() == id)) id = nextAlerts.isEmpty ? null : nextAlerts.first['emergency_id']?.toString();
//       final profile = next['officer'] is Map ? Map<String, dynamic>.from(next['officer']) : <String, dynamic>{};
//       setState(() {
//         board = next; selectedEmergencyId = id;
//         onDuty = profile['duty_status'] == 'ON_DUTY'; loading = false; error = null;
//         if (myLat == null && profile['current_latitude'] is num && profile['current_longitude'] is num) {
//           myLat = (profile['current_latitude'] as num).toDouble();
//           myLon = (profile['current_longitude'] as num).toDouble();
//         }
//       });
//       if (newNotificationKeys.isNotEmpty) {
//         // Audible + haptic alert for a newly dispatched or relayed alert while the app is open. OS push is separate.
//         _buzzNewAlert();
//       }
//       if (myLat != null && junctionsUpdated == null) _loadNearbyJunctions();
//       if (id != null && (routeData == null || routeData!['emergency_id']?.toString() != id)) await _loadRoute();
//     } catch (e) {
//       if (mounted) setState(() { loading = false; error = e.toString().replaceFirst('Exception: ', ''); });
//     }
//   }

//   void _buzzNewAlert() {
//     // Three short alert pulses; the first alert arrives immediately, then two repeats.
//     buzzerTimer?.cancel();
//     unawaited(SystemSound.play(SystemSoundType.alert));
//     HapticFeedback.vibrate();
//     var repeatsRemaining = 2;
//     buzzerTimer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
//       if (!mounted || repeatsRemaining == 0) {
//         timer.cancel();
//         buzzerTimer = null;
//         return;
//       }
//       repeatsRemaining--;
//       unawaited(SystemSound.play(SystemSoundType.alert));
//       HapticFeedback.vibrate();
//     });
//   }

//   Future<void> _loadRoute() async {
//     final id = selectedEmergencyId ?? selected?['emergency_id']?.toString();
//     if (id == null) { if (mounted) setState(() => routeData = null); return; }
//     try { final raw = await api.get('/coordination/emergencies/$id/route'); if (mounted && raw is Map) setState(() => routeData = Map<String, dynamic>.from(raw)); } catch (_) {}
//   }

//   Future<void> _startLocation() async {
//     try {
//       if (!await Geolocator.isLocationServiceEnabled()) return;
//       var permission = await Geolocator.checkPermission();
//       if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
//       if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
//       final current = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
//       await _sendLocation(current);
//       await _loadNearbyJunctions(force: true);
//       locationSubscription = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)).listen((p) => _sendLocation(p), onError: (_) {});
//     } catch (_) { /* Dashboard continues to load; location status remains unavailable. */ }
//   }

//   Future<void> _sendLocation(Position p) async {
//     if (!mounted) return;
//     setState(() { myLat = p.latitude; myLon = p.longitude; });
//     try { await api.put('/coordination/police/location', {'latitude': p.latitude, 'longitude': p.longitude}); } catch (_) {}
//   }

//   Future<void> _loadNearbyJunctions({bool force = false}) async {
//     if (fetchingJunctions || myLat == null || myLon == null) return;
//     if (!force && junctionsUpdated != null && DateTime.now().difference(junctionsUpdated!) < const Duration(minutes: 1)) return;
//     fetchingJunctions = true;
//     try {
//       final result = await api.get('/coordination/police/nearby-junctions?latitude=$myLat&longitude=$myLon&radius_km=3');
//       if (mounted && result is Map) {
//         final rows = result['junctions'] is List ? (result['junctions'] as List).whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList() : <Map<String, dynamic>>[];
//         setState(() { nearbyJunctions = rows; junctionsUpdated = DateTime.now(); });
//       }
//     } catch (_) { if (mounted) setState(() => junctionsUpdated = DateTime.now()); }
//     finally { fetchingJunctions = false; }
//   }

//   Future<void> _assignJunction(Map<String, dynamic> junction) async {
//     if (myLat == null || myLon == null) { _toast('Enable location to assign a nearby junction.', LuxuryTheme.amber); return; }
//     try {
//       await api.put('/coordination/police/location', {
//         'latitude': myLat, 'longitude': myLon,
//         'junction_name': junction['name']?.toString() ?? 'Traffic junction',
//         'junction_latitude': junction['latitude'],
//         'junction_longitude': junction['longitude'],
//       });
//       _toast('Assigned to ${junction['name']}.', LuxuryTheme.green);
//       await _load();
//     } catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red); }
//   }

//   Future<void> _toggleDuty(bool value) async {
//     setState(() => busy = true);
//     try { await api.put('/coordination/police/duty', {'on_duty': value}); setState(() => onDuty = value); await _load(); }
//     catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red); }
//     finally { if (mounted) setState(() => busy = false); }
//   }

//   Future<void> _action(String suffix, String success) async {
//     final id = selected?['emergency_id']?.toString(); if (id == null) return;
//     setState(() => busy = true);
//     try { await api.post('/coordination/police/emergencies/$id/$suffix', {}); _toast(success, LuxuryTheme.green); await _load(); }
//     catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red); }
//     finally { if (mounted) setState(() => busy = false); }
//   }

//   Future<void> _relay() async {
//     final item = selected; if (item == null) return;
//     final selfId = officer?['id']?.toString();
//     final candidates = junctions.where((j) => j['officer_id']?.toString() != selfId && (j['latitude'] is num) && (j['longitude'] is num)).toList();
//     if (candidates.isEmpty) { _toast('No other on-duty junction officer with a known location is available.', LuxuryTheme.amber); return; }
//     String? target = candidates.first['officer_id']?.toString();
//     final chosen = await showDialog<String>(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
//       title: const Text('Relay to next junction'), content: DropdownButtonFormField<String>(initialValue: target, isExpanded: true, items: candidates.map((j) => DropdownMenuItem(value: j['officer_id'].toString(), child: Text('${j['junction_name']} • ${j['badge_number']}'))).toList(), onChanged: (v) => setDialog(() => target = v)),
//       actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, target), child: const Text('Relay alert'))],
//     )));
//     if (chosen == null) return;
//     setState(() => busy = true);
//     try { await api.post('/coordination/police/emergencies/${item['emergency_id']}/relay', {'target_officer_id': chosen, 'note': 'Prepare traffic clearance ahead of the ambulance.'}); _toast('Alert relayed to the next junction.', LuxuryTheme.green); await _load(); }
//     catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red); }
//     finally { if (mounted) setState(() => busy = false); }
//   }

//   LatLng _point(dynamic lat, dynamic lon, {LatLng? fallback}) => lat is num && lon is num ? LatLng(lat.toDouble(), lon.toDouble()) : fallback ?? const LatLng(12.9716, 77.5946);
//   List<LatLng> _routePoints() { final raw = routeData?['polyline_points']; if (raw is! List) return []; return raw.whereType<List>().where((e) => e.length >= 2 && e[0] is num && e[1] is num).map((e) => LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble())).toList(); }

//   Widget _map() {
//     final s = selected;
//     final center = s != null ? _point(s['ambulance_latitude'], s['ambulance_longitude'], fallback: myLat == null ? null : LatLng(myLat!, myLon!)) : (myLat != null ? LatLng(myLat!, myLon!) : const LatLng(12.9716, 77.5946));
//     final route = _routePoints();
//     final markers = <Marker>[];
//     if (s != null) {
//       markers.add(Marker(point: _point(s['ambulance_latitude'], s['ambulance_longitude']), width: 48, height: 48, child: const _MapMarker(icon: Icons.emergency_rounded, color: LuxuryTheme.red)));
//       if (s['hospital_latitude'] is num && s['hospital_longitude'] is num) markers.add(Marker(point: _point(s['hospital_latitude'], s['hospital_longitude']), width: 44, height: 44, child: const _MapMarker(icon: Icons.local_hospital_rounded, color: LuxuryTheme.green)));
//     }
//     for (final j in junctions) {
//       if (j['latitude'] is num && j['longitude'] is num) markers.add(Marker(point: _point(j['latitude'], j['longitude']), width: 38, height: 38, child: const _MapMarker(icon: Icons.traffic_rounded, color: LuxuryTheme.blue, small: true)));
//       if (j['current_latitude'] is num && j['current_longitude'] is num) markers.add(Marker(point: _point(j['current_latitude'], j['current_longitude']), width: 34, height: 34, child: const _MapMarker(icon: Icons.local_police_rounded, color: LuxuryTheme.cyan, small: true)));
//     }
//     for (final j in nearbyJunctions) { if (j['latitude'] is num && j['longitude'] is num) markers.add(Marker(point: _point(j['latitude'], j['longitude']), width: 32, height: 32, child: const _MapMarker(icon: Icons.traffic_rounded, color: LuxuryTheme.amber, small: true))); }
//     if (myLat != null && myLon != null) markers.add(Marker(point: LatLng(myLat!, myLon!), width: 40, height: 40, child: const _MapMarker(icon: Icons.person_pin_circle_rounded, color: LuxuryTheme.cyan, small: true)));
//     return ClipRRect(borderRadius: BorderRadius.circular(22), child: SizedBox(height: 330, child: FlutterMap(
//       options: MapOptions(initialCenter: center, initialZoom: 12),
//       children: [
//         TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.rescupath.police'),
//         if (route.length > 1) PolylineLayer(polylines: [Polyline(points: route, strokeWidth: 5, color: LuxuryTheme.blue)]),
//         if (route.isEmpty && s != null && s['hospital_latitude'] is num) PolylineLayer(polylines: [Polyline(points: [center, _point(s['hospital_latitude'], s['hospital_longitude'])], strokeWidth: 3, color: LuxuryTheme.blue)]),
//         MarkerLayer(markers: markers),
//         RichAttributionWidget(attributions: const [TextSourceAttribution('OpenStreetMap contributors')]),
//       ],
//     )));
//   }

//   @override
//   Widget build(BuildContext context) {
//     final s = selected; final off = officer ?? {};
//     return Scaffold(
//       appBar: AppBar(title: const Text('Police Command', style: TextStyle(fontWeight: FontWeight.w900)), actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)), IconButton(tooltip: 'Sign out', onPressed: widget.onLogout, icon: const Icon(Icons.logout_rounded))]),
//       body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
//         BrandHeader(title: 'RescuPath Police', subtitle: '${off['station_name'] ?? 'Police station'} • ${off['junction_name'] ?? 'Junction not assigned'}', icon: Icons.local_police_rounded),
//         const SizedBox(height: 12),
//         CommandCard(child: Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: LuxuryTheme.blue.withValues(alpha: .1), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.badge_outlined, color: LuxuryTheme.blue, size: 26)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(off['full_name']?.toString() ?? 'Officer', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: LuxuryTheme.ink)), Text('Badge ${off['badge_number'] ?? '—'} • ${myLat == null ? 'GPS unavailable' : 'GPS live'}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11))])), const Text('ON DUTY', style: TextStyle(color: LuxuryTheme.green, fontWeight: FontWeight.w900, fontSize: 10)), Switch(value: onDuty, onChanged: busy ? null : _toggleDuty, activeThumbColor: LuxuryTheme.green)])),
//         if (error != null) ...[const SizedBox(height: 10), _error(error!)],
//         const SizedBox(height: 12),
//         Row(children: [Expanded(child: _metric('ACTIVE ALERTS', '${alerts.length}', Icons.sos_rounded, LuxuryTheme.red)), const SizedBox(width: 10), Expanded(child: _metric('JUNCTIONS ONLINE', '${junctions.length}', Icons.traffic_rounded, LuxuryTheme.blue))]),
//         const SizedBox(height: 14),
//         Row(children: [const Expanded(child: Text('Live incident map', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: LuxuryTheme.ink))), if (board['server_time'] != null) Text('Refreshes every 5s', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 10))]),
//         const SizedBox(height: 10), _map(),
//         if (nearbyJunctions.isNotEmpty) ...[
//           const SizedBox(height: 12),
//           CommandCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//             const Text('Mapped junctions near you', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: LuxuryTheme.ink)),
//             const SizedBox(height: 4), const Text('OpenStreetMap traffic signals and roundabouts • refreshes every minute', style: TextStyle(color: LuxuryTheme.muted, fontSize: 10)),
//             const SizedBox(height: 8),
//             ...nearbyJunctions.take(8).map((j) => Padding(padding: const EdgeInsets.only(top: 7), child: Row(children: [const Icon(Icons.traffic_rounded, color: LuxuryTheme.amber, size: 20), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(j['name']?.toString() ?? 'Traffic junction', style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w800, fontSize: 12)), Text('${j['junction_type'] ?? 'Junction'} • ${j['distance_km'] ?? '—'} km', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 10))])), TextButton(onPressed: () => _assignJunction(j), child: const Text('Assign'))]))),
//           ])),
//         ],
//         const SizedBox(height: 16), const Text('Incoming ambulance alerts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: LuxuryTheme.ink)), const SizedBox(height: 10),
//         if (alerts.isEmpty) CommandCard(child: Column(children: [const Icon(Icons.verified_user_outlined, size: 38, color: LuxuryTheme.green), const SizedBox(height: 8), const Text('No active police alerts', style: TextStyle(fontWeight: FontWeight.w900, color: LuxuryTheme.ink)), const SizedBox(height: 4), const Text('When a paramedic requests traffic assistance, the emergency appears here.', textAlign: TextAlign.center, style: TextStyle(color: LuxuryTheme.muted, fontSize: 12))]))
//         else ...alerts.map((a) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _alertCard(a, selectedEmergencyId == a['emergency_id']))),
//         if (s != null) ...[
//           const SizedBox(height: 6), CommandCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//             Row(children: [const Icon(Icons.emergency_rounded, color: LuxuryTheme.red), const SizedBox(width: 8), Expanded(child: Text('${s['ambulance_number'] ?? 'Ambulance'} • ${s['severity'] ?? 'HIGH'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: LuxuryTheme.ink))), _status(s['status']?.toString() ?? 'ACTIVE')]),
//             const SizedBox(height: 10), Text('${s['condition'] ?? 'Emergency'} • ${s['hospital_name'] ?? 'Hospital not selected'}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 12)),
//             if (s['relayed_to_me'] == true) Container(margin: const EdgeInsets.only(top: 9), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: LuxuryTheme.amber.withValues(alpha: .12), borderRadius: BorderRadius.circular(12), border: Border.all(color: LuxuryTheme.amber.withValues(alpha: .35))), child: Row(children: [const Icon(Icons.forward_to_inbox_rounded, color: LuxuryTheme.amber), const SizedBox(width: 8), Expanded(child: Text('RELAYED TO YOUR JUNCTION${s['relay_from_junction'] == null ? '' : ' • FROM ${s['relay_from_junction']}'}', style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 10)))])),
//             const SizedBox(height: 12), Row(children: [Expanded(child: _info('ETA TO ${s['junction_name'] ?? 'JUNCTION'}', _duration(s['junction_eta_seconds']))), Expanded(child: _info('DISTANCE', s['junction_distance_km'] == null ? '—' : '${s['junction_distance_km']} km')), Expanded(child: _info('HOSPITAL ETA', _duration(s['eta_seconds'])))]),
//             const SizedBox(height: 4), Text('Target: ${s['junction_eta_target'] ?? 'assigned junction'} • ${s['junction_eta_basis'] ?? 'ETA basis unavailable'}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 10)),
//             const SizedBox(height: 6), Text('Live ambulance GPS: ${_coordinate(s['ambulance_latitude'])}, ${_coordinate(s['ambulance_longitude'])}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11)),
//             Text('Hospital route ETA: ${s['eta_basis']?.toString() ?? 'not available'}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 10)),
//             const SizedBox(height: 14),
//             Wrap(spacing: 8, runSpacing: 8, children: [FilledButton.icon(onPressed: busy ? null : () => _action('acknowledge', 'Alert acknowledged.'), icon: const Icon(Icons.check_circle_outline), label: const Text('Acknowledge')), FilledButton.icon(onPressed: busy ? null : _relay, icon: const Icon(Icons.forward_to_inbox_rounded), label: const Text('Relay to junction')), FilledButton.icon(onPressed: busy ? null : () => _action('clear', 'Junction marked clear.'), icon: const Icon(Icons.traffic_rounded), label: const Text('Traffic cleared'))]),
//             if (s['police_acknowledged'] == true) const Padding(padding: EdgeInsets.only(top: 8), child: Text('✓ Police acknowledgement recorded', style: TextStyle(color: LuxuryTheme.green, fontWeight: FontWeight.w800, fontSize: 11))),
//             if (s['traffic_cleared'] == true) const Padding(padding: EdgeInsets.only(top: 4), child: Text('✓ Junction clearance recorded', style: TextStyle(color: LuxuryTheme.green, fontWeight: FontWeight.w800, fontSize: 11))),
//           ])),
//         ],
//         const SizedBox(height: 12), const Text('ETAs to a junction use approximate distance unless a traffic-aware provider is explicitly available. Keep officer GPS enabled while on duty.', style: TextStyle(color: LuxuryTheme.muted, fontSize: 10, height: 1.4)),
//       ])),
//     );
//   }

//   Widget _alertCard(Map<String, dynamic> a, bool active) => InkWell(onTap: () async { setState(() { selectedEmergencyId = a['emergency_id']?.toString(); routeData = null; }); await _loadRoute(); }, borderRadius: BorderRadius.circular(20), child: CommandCard(padding: const EdgeInsets.all(14), child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: (active ? LuxuryTheme.red : LuxuryTheme.blue).withValues(alpha: .1), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.emergency_rounded, color: active ? LuxuryTheme.red : LuxuryTheme.blue)), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${a['ambulance_number'] ?? 'Ambulance'} • ${a['severity'] ?? 'HIGH'}', style: const TextStyle(fontWeight: FontWeight.w900, color: LuxuryTheme.ink)), const SizedBox(height: 3), Text('${a['condition'] ?? 'Emergency'} • ${a['hospital_name'] ?? 'Hospital pending'}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11)), const SizedBox(height: 4), Text(a['relayed_to_me'] == true ? 'RELAYED TO YOUR JUNCTION • ETA ${_duration(a['junction_eta_seconds'])}' : 'Junction ETA ${_duration(a['junction_eta_seconds'])} • hospital ETA ${_duration(a['eta_seconds'])}', style: TextStyle(color: a['relayed_to_me'] == true ? LuxuryTheme.amber : LuxuryTheme.blue, fontWeight: FontWeight.w800, fontSize: 11))])), Icon(active ? Icons.radio_button_checked : Icons.chevron_right, color: active ? LuxuryTheme.red : LuxuryTheme.muted)])));
//   Widget _metric(String label, String value, IconData icon, Color color) => CommandCard(child: Row(children: [Icon(icon, color: color, size: 25), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 23, color: LuxuryTheme.ink)), Text(label, style: const TextStyle(color: LuxuryTheme.muted, fontSize: 9, fontWeight: FontWeight.w800))]))]));
//   Widget _info(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: LuxuryTheme.muted, fontSize: 8, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(value, style: const TextStyle(color: LuxuryTheme.ink, fontSize: 12, fontWeight: FontWeight.w900))]);
//   Widget _status(String text) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: LuxuryTheme.red.withValues(alpha: .09), borderRadius: BorderRadius.circular(99)), child: Text(text.replaceAll('_', ' '), style: const TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w900, fontSize: 9)));
//   Widget _error(String text) => CommandCard(child: Text(text, style: const TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w700)));
//   String _duration(dynamic raw) => raw is num ? raw < 60 ? '${raw.round()} sec' : '${(raw / 60).ceil()} min' : '—';
//   String _coordinate(dynamic raw) => raw is num ? raw.toStringAsFixed(5) : '—';
//   void _toast(String text, Color color) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: color, content: Text(text))); }
//   @override void dispose() { pollTimer?.cancel(); routeTimer?.cancel(); junctionTimer?.cancel(); buzzerTimer?.cancel(); locationSubscription?.cancel(); super.dispose(); }
// }

// class _MapMarker extends StatelessWidget {
//   final IconData icon; final Color color; final bool small;
//   const _MapMarker({required this.icon, required this.color, this.small = false});
//   @override Widget build(BuildContext context) => Container(decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Color(0x2A0A1930), blurRadius: 12)]), child: Icon(icon, color: Colors.white, size: small ? 17 : 24));
// }
 import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../core/app_api.dart';
import '../core/luxury_theme.dart';

class PoliceDashboardPage extends StatefulWidget {
  final Future<void> Function() onLogout;
  const PoliceDashboardPage({super.key, required this.onLogout});
  @override State<PoliceDashboardPage> createState() => _PoliceDashboardPageState();
}

class _PoliceDashboardPageState extends State<PoliceDashboardPage> {
  final api = AppApi();
  final MapController _mapController = MapController();
  Timer? pollTimer; Timer? routeTimer; Timer? junctionTimer; Timer? buzzerTimer; StreamSubscription<Position>? locationSubscription;
  Map<String, dynamic> board = {}; Map<String, dynamic>? routeData; String? selectedEmergencyId;
  List<Map<String, dynamic>> nearbyJunctions = []; bool fetchingJunctions = false; DateTime? junctionsUpdated;
  bool loading = true; bool busy = false; bool onDuty = true; String? error; double? myLat; double? myLon;
  bool _hasLoadedInitialBoard = false;
  Set<String> _knownNotificationKeys = <String>{};
  final Set<String> _dismissedEmergencyIds = <String>{};
  OverlayEntry? _noticeEntry;
  Timer? _noticeTimer;

  List<Map<String, dynamic>> _list(dynamic raw) => raw is List ? raw.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList() : <Map<String, dynamic>>[];
  Map<String, dynamic>? get officer => board['officer'] is Map ? Map<String, dynamic>.from(board['officer']) : null;
  List<Map<String, dynamic>> get alerts => _list(board['alerts']).where((a) => !_dismissedEmergencyIds.contains(a['emergency_id']?.toString() ?? '')).toList();
  List<Map<String, dynamic>> get junctions => _list(board['junctions']);
  Map<String, dynamic>? get selected { for (final item in alerts) { if (item['emergency_id']?.toString() == selectedEmergencyId) return item; } return alerts.isEmpty ? null : alerts.first; }

  @override void initState() {
    super.initState();
    _load();
    pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
    routeTimer = Timer.periodic(const Duration(seconds: 20), (_) => _loadRoute());
    junctionTimer = Timer.periodic(const Duration(minutes: 1), (_) => _loadNearbyJunctions(force: true));
    _startLocation();
  }

  Future<void> _load() async {
    try {
      final raw = await api.get('/coordination/police/board');
      if (!mounted || raw is! Map) return;
      final next = Map<String, dynamic>.from(raw);
      final allNextAlerts = _list(next['alerts']);
      final nextAlerts = allNextAlerts.where((a) => !_dismissedEmergencyIds.contains(a['emergency_id']?.toString() ?? '')).toList();
      final incomingNotificationKeys = <String>{};
      for (final alert in nextAlerts) {
        final emergencyKey = alert['emergency_id']?.toString();
        if (emergencyKey == null) continue;
        incomingNotificationKeys.add('$emergencyKey:alert');
        final relayKey = alert['relay_notification_id']?.toString();
        if (relayKey != null && relayKey.isNotEmpty) {
          incomingNotificationKeys.add('$emergencyKey:relay:$relayKey');
        }
      }
      final newNotificationKeys = _hasLoadedInitialBoard
          ? incomingNotificationKeys.difference(_knownNotificationKeys)
          : <String>{};
      _knownNotificationKeys = incomingNotificationKeys;
      _hasLoadedInitialBoard = true;
      String? id = selectedEmergencyId;
      if (id == null || !nextAlerts.any((e) => e['emergency_id']?.toString() == id)) id = nextAlerts.isEmpty ? null : nextAlerts.first['emergency_id']?.toString();
      final profile = next['officer'] is Map ? Map<String, dynamic>.from(next['officer']) : <String, dynamic>{};
      setState(() {
        board = next; selectedEmergencyId = id;
        onDuty = profile['duty_status'] == 'ON_DUTY'; loading = false; error = null;
        if (myLat == null && profile['current_latitude'] is num && profile['current_longitude'] is num) {
          myLat = (profile['current_latitude'] as num).toDouble();
          myLon = (profile['current_longitude'] as num).toDouble();
        }
      });
      if (newNotificationKeys.isNotEmpty) {
        // Audible + haptic alert for a newly dispatched or relayed alert while the app is open. OS push is separate.
        _buzzNewAlert();
      }
      if (myLat != null && junctionsUpdated == null) _loadNearbyJunctions();
      if (id != null && (routeData == null || routeData!['emergency_id']?.toString() != id)) await _loadRoute();
    } catch (e) {
      if (mounted) setState(() { loading = false; error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  void _buzzNewAlert() {
    // Three short alert pulses; the first alert arrives immediately, then two repeats.
    buzzerTimer?.cancel();
    unawaited(SystemSound.play(SystemSoundType.alert));
    HapticFeedback.vibrate();
    var repeatsRemaining = 2;
    buzzerTimer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (!mounted || repeatsRemaining == 0) {
        timer.cancel();
        buzzerTimer = null;
        return;
      }
      repeatsRemaining--;
      unawaited(SystemSound.play(SystemSoundType.alert));
      HapticFeedback.vibrate();
    });
  }

  Future<void> _loadRoute() async {
    final id = selectedEmergencyId ?? selected?['emergency_id']?.toString();
    if (id == null) { if (mounted) setState(() => routeData = null); return; }
    try { final raw = await api.get('/coordination/emergencies/$id/route'); if (mounted && raw is Map) setState(() => routeData = Map<String, dynamic>.from(raw)); } catch (_) {}
  }

  Future<void> _startLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final current = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      await _sendLocation(current);
      await _loadNearbyJunctions(force: true);
      locationSubscription = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)).listen((p) => _sendLocation(p), onError: (_) {});
    } catch (_) { /* Dashboard continues to load; location status remains unavailable. */ }
  }

  Future<void> _sendLocation(Position p) async {
    if (!mounted) return;
    setState(() { myLat = p.latitude; myLon = p.longitude; });
    try { await api.put('/coordination/police/location', {'latitude': p.latitude, 'longitude': p.longitude}); } catch (_) {}
  }

  Future<void> _loadNearbyJunctions({bool force = false}) async {
    if (fetchingJunctions || myLat == null || myLon == null) return;
    if (!force && junctionsUpdated != null && DateTime.now().difference(junctionsUpdated!) < const Duration(minutes: 1)) return;
    fetchingJunctions = true;
    try {
      final result = await api.get('/coordination/police/nearby-junctions?latitude=$myLat&longitude=$myLon&radius_km=3');
      if (mounted && result is Map) {
        final rows = result['junctions'] is List ? (result['junctions'] as List).whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList() : <Map<String, dynamic>>[];
        setState(() { nearbyJunctions = rows; junctionsUpdated = DateTime.now(); });
      }
    } catch (_) { if (mounted) setState(() => junctionsUpdated = DateTime.now()); }
    finally { fetchingJunctions = false; }
  }

  Future<void> _assignJunction(Map<String, dynamic> junction) async {
    if (myLat == null || myLon == null) { _toast('Enable location to assign a nearby junction.', LuxuryTheme.amber); return; }
    try {
      await api.put('/coordination/police/location', {
        'latitude': myLat, 'longitude': myLon,
        'junction_name': junction['name']?.toString() ?? 'Traffic junction',
        'junction_latitude': junction['latitude'],
        'junction_longitude': junction['longitude'],
      });
      _toast('Assigned to ${junction['name']}.', LuxuryTheme.green);
      await _load();
    } catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red); }
  }

  Future<void> _toggleDuty(bool value) async {
    setState(() => busy = true);
    try { await api.put('/coordination/police/duty', {'on_duty': value}); setState(() => onDuty = value); await _load(); }
    catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _action(String suffix, String success, {String? emergencyId}) async {
    final id = emergencyId ?? selected?['emergency_id']?.toString(); if (id == null) return;
    setState(() => busy = true);
    try { await api.post('/coordination/police/emergencies/$id/$suffix', {}); _toast(success, LuxuryTheme.green); await _load(); }
    catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _relay({Map<String, dynamic>? alert}) async {
    final item = alert ?? selected; if (item == null) return;
    final selfId = officer?['id']?.toString();
    final candidates = junctions.where((j) => j['officer_id']?.toString() != selfId && (j['latitude'] is num) && (j['longitude'] is num)).toList();
    if (candidates.isEmpty) { _toast('No other on-duty junction officer with a known location is available.', LuxuryTheme.amber); return; }
    String? target = candidates.first['officer_id']?.toString();
    final chosen = await showDialog<String>(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
      title: const Text('Relay to next junction'), content: DropdownButtonFormField<String>(value: target, isExpanded: true, items: candidates.map((j) => DropdownMenuItem(value: j['officer_id'].toString(), child: Text('${j['junction_name']} • ${j['badge_number']}'))).toList(), onChanged: (v) => setDialog(() => target = v)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, target), child: const Text('Relay alert'))],
    )));
    if (chosen == null) return;
    setState(() => busy = true);
    try { await api.post('/coordination/police/emergencies/${item['emergency_id']}/relay', {'target_officer_id': chosen, 'note': 'Prepare traffic clearance ahead of the ambulance.'}); _toast('Alert relayed to the next junction.', LuxuryTheme.green); await _load(); }
    catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red); }
    finally { if (mounted) setState(() => busy = false); }
  }

  bool _isCompletedAlert(Map<String, dynamic> item) {
    // Traffic clearance is also a handled/completed police operation.
    if (item['traffic_cleared'] == true) return true;
    final status = (item['status'] ?? item['emergency_status'] ?? '').toString().toUpperCase();
    return const {'ARRIVED', 'COMPLETED', 'CLOSED', 'CANCELLED', 'RESOLVED'}.contains(status);
  }

  Future<void> _dismissAlert(Map<String, dynamic> item) async {
    if (!_isCompletedAlert(item)) return;
    final id = item['emergency_id']?.toString();
    if (id == null || id.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove completed ambulance?'),
        content: const Text('This removes the completed alert from this dashboard view only. The emergency and dispatch history remain saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      _dismissedEmergencyIds.add(id);
      if (selectedEmergencyId == id) { selectedEmergencyId = null; routeData = null; }
    });
    _toast('Completed ambulance removed from this view.', LuxuryTheme.green);
  }

  Widget _summaryMetric(String value, String label, IconData icon, Color color) => Container(
    constraints: const BoxConstraints(minHeight: 62),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .96), borderRadius: BorderRadius.circular(15)),
    child: Row(children: [
      Container(width: 32, height: 32, decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: color, size: 18)),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(value, style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 18)), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: LuxuryTheme.muted, fontSize: 9, fontWeight: FontWeight.w700))])),
    ]),
  );

  LatLng _point(dynamic lat, dynamic lon, {LatLng? fallback}) => lat is num && lon is num ? LatLng(lat.toDouble(), lon.toDouble()) : fallback ?? const LatLng(12.9716, 77.5946);
  List<LatLng> _routePoints() { final raw = routeData?['polyline_points']; if (raw is! List) return []; return raw.whereType<List>().where((e) => e.length >= 2 && e[0] is num && e[1] is num).map((e) => LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble())).toList(); }

  Widget _map() {
    final s = selected;
    final center = s != null ? _point(s['ambulance_latitude'], s['ambulance_longitude'], fallback: myLat == null ? null : LatLng(myLat!, myLon!)) : (myLat != null ? LatLng(myLat!, myLon!) : const LatLng(12.9716, 77.5946));
    final route = _routePoints();
    final markers = <Marker>[];
    if (s != null) {
      markers.add(Marker(point: _point(s['ambulance_latitude'], s['ambulance_longitude']), width: 48, height: 48, child: const _MapMarker(icon: Icons.emergency_rounded, color: LuxuryTheme.red)));
      if (s['hospital_latitude'] is num && s['hospital_longitude'] is num) markers.add(Marker(point: _point(s['hospital_latitude'], s['hospital_longitude']), width: 44, height: 44, child: const _MapMarker(icon: Icons.local_hospital_rounded, color: LuxuryTheme.green)));
    }
    for (final j in junctions) {
      if (j['latitude'] is num && j['longitude'] is num) markers.add(Marker(point: _point(j['latitude'], j['longitude']), width: 38, height: 38, child: const _MapMarker(icon: Icons.traffic_rounded, color: LuxuryTheme.blue, small: true)));
      if (j['current_latitude'] is num && j['current_longitude'] is num) markers.add(Marker(point: _point(j['current_latitude'], j['current_longitude']), width: 34, height: 34, child: const _MapMarker(icon: Icons.local_police_rounded, color: LuxuryTheme.cyan, small: true)));
    }
    for (final j in nearbyJunctions) { if (j['latitude'] is num && j['longitude'] is num) markers.add(Marker(point: _point(j['latitude'], j['longitude']), width: 32, height: 32, child: const _MapMarker(icon: Icons.traffic_rounded, color: LuxuryTheme.amber, small: true))); }
    if (myLat != null && myLon != null) markers.add(Marker(point: LatLng(myLat!, myLon!), width: 40, height: 40, child: const _MapMarker(icon: Icons.person_pin_circle_rounded, color: LuxuryTheme.cyan, small: true)));
    return ClipRRect(borderRadius: BorderRadius.circular(22), child: SizedBox(height: 330, child: FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: center, initialZoom: 12),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.rescupath.police'),
        if (route.length > 1) PolylineLayer(polylines: [Polyline(points: route, strokeWidth: 5, color: LuxuryTheme.blue)]),
        if (route.isEmpty && s != null && s['hospital_latitude'] is num) PolylineLayer(polylines: [Polyline(points: [center, _point(s['hospital_latitude'], s['hospital_longitude'])], strokeWidth: 3, color: LuxuryTheme.blue)]),
        MarkerLayer(markers: markers),
        RichAttributionWidget(attributions: const [TextSourceAttribution('OpenStreetMap contributors')]),
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    final s = selected;
    final off = officer ?? {};
    final activeAlerts = alerts.where((a) => !_isCompletedAlert(a)).toList();
    final completedAlerts = alerts.where(_isCompletedAlert).toList();
    final acknowledged = alerts.where((a) => a['police_acknowledged'] == true).length;
    final cleared = alerts.where((a) => a['traffic_cleared'] == true).length;

    return Scaffold(
      backgroundColor: LuxuryTheme.bg,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1460),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(width: 46, height: 46, decoration: BoxDecoration(color: LuxuryTheme.blue, borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.shield_rounded, color: Colors.white, size: 25)),
                          const SizedBox(width: 11),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('RescuPath', style: TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 17)), Text('${off['station_name'] ?? 'Police Command'} • ${off['junction_name'] ?? 'Junction not assigned'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11))])),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: (onDuty ? LuxuryTheme.green : LuxuryTheme.amber).withValues(alpha: .10), borderRadius: BorderRadius.circular(99)), child: Row(children: [Icon(Icons.circle, color: onDuty ? LuxuryTheme.green : LuxuryTheme.amber, size: 8), const SizedBox(width: 6), Text(onDuty ? 'On duty' : 'Off duty', style: TextStyle(color: onDuty ? LuxuryTheme.green : LuxuryTheme.amber, fontWeight: FontWeight.w800, fontSize: 10))])),
                          Switch(value: onDuty, onChanged: busy ? null : _toggleDuty, activeColor: LuxuryTheme.green),
                          IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded, color: LuxuryTheme.ink)),
                          IconButton(tooltip: 'Sign out', onPressed: widget.onLogout, icon: const Icon(Icons.logout_rounded, color: LuxuryTheme.ink)),
                        ]),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            gradient: const LinearGradient(colors: [LuxuryTheme.navy, Color(0xFF1A3B69)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            boxShadow: const [BoxShadow(color: Color(0x220A1930), blurRadius: 22, offset: Offset(0, 8))],
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Active Ambulance Alerts', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            const Text('Clear traffic. Save lives.', style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12)),
                            const SizedBox(height: 17),
                            LayoutBuilder(builder: (context, constraints) {
                              final width = constraints.maxWidth >= 650 ? (constraints.maxWidth - 24) / 4 : (constraints.maxWidth - 8) / 2;
                              return Wrap(spacing: 8, runSpacing: 8, children: [
                                SizedBox(width: width, child: _summaryMetric('${activeAlerts.length}', 'Active', Icons.sos_rounded, LuxuryTheme.red)),
                                SizedBox(width: width, child: _summaryMetric('$acknowledged', 'Acknowledged', Icons.notifications_active_rounded, LuxuryTheme.green)),
                                SizedBox(width: width, child: _summaryMetric('$cleared', 'Traffic cleared', Icons.traffic_rounded, LuxuryTheme.blue)),
                                SizedBox(width: width, child: _summaryMetric('${alerts.length}', 'Total on board', Icons.assessment_rounded, LuxuryTheme.ink)),
                              ]);
                            }),
                          ]),
                        ),
                        if (error != null) ...[const SizedBox(height: 12), _error(error!)],
                        const SizedBox(height: 21),
                        LayoutBuilder(builder: (context, constraints) {
                          final alertsPanel = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Row(children: [Expanded(child: Text('Active Alerts (${activeAlerts.length})', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: LuxuryTheme.ink))), TextButton(onPressed: _load, child: const Text('View latest'))]),
                            const SizedBox(height: 8),
                            if (activeAlerts.isEmpty) CommandCard(child: Column(children: [const Icon(Icons.verified_user_outlined, size: 40, color: LuxuryTheme.green), const SizedBox(height: 8), const Text('No active police alerts', style: TextStyle(fontWeight: FontWeight.w900, color: LuxuryTheme.ink)), const SizedBox(height: 4), const Text('When a paramedic requests traffic assistance, the incident will appear here.', textAlign: TextAlign.center, style: TextStyle(color: LuxuryTheme.muted, fontSize: 12))]))
                            else ...activeAlerts.map((a) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _alertCard(a, selectedEmergencyId == a['emergency_id']))),
                            if (completedAlerts.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text('Recently Completed (${completedAlerts.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: LuxuryTheme.ink)),
                              const SizedBox(height: 8),
                              ...completedAlerts.map((a) => Padding(padding: const EdgeInsets.only(bottom: 9), child: _alertCard(a, selectedEmergencyId == a['emergency_id']))),
                            ],
                          ]);
                          final mapPanel = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Row(children: [const Expanded(child: Text('Live incident map', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: LuxuryTheme.ink))), Text(myLat == null ? 'GPS unavailable' : 'GPS live', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 10))]),
                            const SizedBox(height: 9),
                            _map(),
                            if (s != null) ...[
                              const SizedBox(height: 10),
                              CommandCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [const Icon(Icons.emergency_rounded, color: LuxuryTheme.red), const SizedBox(width: 8), Expanded(child: Text('${s['ambulance_number'] ?? 'Ambulance'} • ${s['severity'] ?? 'HIGH'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: LuxuryTheme.ink))), _status(s['status']?.toString() ?? 'ACTIVE')]),
                                const SizedBox(height: 7),
                                Text('${s['condition'] ?? 'Emergency'} • ${s['hospital_name'] ?? 'Hospital pending'}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11)),
                                const SizedBox(height: 12),
                                Row(children: [Expanded(child: _info('JUNCTION ETA', _duration(s['junction_eta_seconds']))), Expanded(child: _info('DISTANCE', s['junction_distance_km'] == null ? '—' : '${s['junction_distance_km']} km')), Expanded(child: _info('HOSPITAL ETA', _duration(s['eta_seconds'])))]),
                                const SizedBox(height: 13),
                                Row(children: [
                                  Icon(s['police_acknowledged'] == true ? Icons.check_circle_rounded : Icons.hourglass_top_rounded, color: s['police_acknowledged'] == true ? LuxuryTheme.green : LuxuryTheme.amber, size: 18),
                                  const SizedBox(width: 7),
                                  Expanded(child: Text(s['traffic_cleared'] == true ? 'Traffic clearance recorded' : s['police_acknowledged'] == true ? 'Acknowledged • assistance in progress' : 'Waiting for officer acknowledgement', style: TextStyle(color: s['traffic_cleared'] == true ? LuxuryTheme.green : LuxuryTheme.ink, fontWeight: FontWeight.w800, fontSize: 11))),
                                  if (_isCompletedAlert(s)) TextButton.icon(onPressed: () => _dismissAlert(s), icon: const Icon(Icons.delete_outline_rounded, color: LuxuryTheme.red), label: const Text('Remove')),
                                ]),
                                if (s['police_acknowledged'] == true) const Padding(padding: EdgeInsets.only(top: 8), child: Text('✓ Police acknowledgement recorded', style: TextStyle(color: LuxuryTheme.green, fontWeight: FontWeight.w800, fontSize: 11))),
                                if (s['traffic_cleared'] == true) const Padding(padding: EdgeInsets.only(top: 4), child: Text('✓ Junction clearance recorded', style: TextStyle(color: LuxuryTheme.green, fontWeight: FontWeight.w800, fontSize: 11))),
                              ])),
                            ],
                            if (nearbyJunctions.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              CommandCard(padding: const EdgeInsets.all(13), child: ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                childrenPadding: EdgeInsets.zero,
                                title: const Text('Nearby mapped junctions', style: TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 14)),
                                subtitle: const Text('Assign this officer to a junction', style: TextStyle(color: LuxuryTheme.muted, fontSize: 10)),
                                children: nearbyJunctions.take(8).map((j) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  leading: const Icon(Icons.traffic_rounded, color: LuxuryTheme.amber),
                                  title: Text(j['name']?.toString() ?? 'Traffic junction', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                                  subtitle: Text('${j['junction_type'] ?? 'Junction'} • ${j['distance_km'] ?? '—'} km', style: const TextStyle(fontSize: 10)),
                                  trailing: TextButton(onPressed: () => _assignJunction(j), child: const Text('Assign')),
                                )).toList(),
                              )),
                            ],
                          ]);
                          if (constraints.maxWidth >= 1080) return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 7, child: alertsPanel), const SizedBox(width: 18), Expanded(flex: 5, child: mapPanel)]);
                          return Column(children: [alertsPanel, const SizedBox(height: 18), mapPanel]);
                        }),
                        const SizedBox(height: 15),
                        const Text('Junction ETAs use the available route/location data and may be approximate when traffic-aware routing is unavailable. Keep officer GPS enabled while on duty.', style: TextStyle(color: LuxuryTheme.muted, fontSize: 10, height: 1.4)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _alertCard(Map<String, dynamic> a, bool active) {
    final id = a['emergency_id']?.toString() ?? '';
    final completed = _isCompletedAlert(a);
    return InkWell(
      onTap: () async { setState(() { selectedEmergencyId = id; routeData = null; }); await _loadRoute(); final lat = a['ambulance_latitude']; final lon = a['ambulance_longitude']; if (mounted && lat is num && lon is num) _mapController.move(LatLng(lat.toDouble(), lon.toDouble()), 13); },
      borderRadius: BorderRadius.circular(20),
      child: CommandCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 43, height: 43, decoration: BoxDecoration(color: (completed ? LuxuryTheme.green : active ? LuxuryTheme.red : LuxuryTheme.blue).withValues(alpha: .10), borderRadius: BorderRadius.circular(14)), child: Icon(completed ? Icons.task_alt_rounded : Icons.emergency_rounded, color: completed ? LuxuryTheme.green : active ? LuxuryTheme.red : LuxuryTheme.blue)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${a['ambulance_number'] ?? 'Ambulance'} • ${a['severity'] ?? 'HIGH'}', style: const TextStyle(fontWeight: FontWeight.w900, color: LuxuryTheme.ink, fontSize: 13)),
              const SizedBox(height: 3),
              Text('${a['condition'] ?? 'Emergency'} • ${a['hospital_name'] ?? 'Hospital pending'}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11)),
              const SizedBox(height: 4),
              Text(a['relayed_to_me'] == true ? 'RELAYED TO YOUR JUNCTION • ETA ${_duration(a['junction_eta_seconds'])}' : 'Junction ETA ${_duration(a['junction_eta_seconds'])} • hospital ETA ${_duration(a['eta_seconds'])}', style: TextStyle(color: a['relayed_to_me'] == true ? LuxuryTheme.amber : LuxuryTheme.blue, fontWeight: FontWeight.w800, fontSize: 10)),
            ])),
            if (completed) IconButton(tooltip: 'Remove completed ambulance', onPressed: () => _dismissAlert(a), icon: const Icon(Icons.delete_outline_rounded, color: LuxuryTheme.red))
            else Icon(active ? Icons.radio_button_checked : Icons.chevron_right, color: active ? LuxuryTheme.red : LuxuryTheme.muted),
          ]),
          if (!completed) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 7, runSpacing: 7, children: [
              FilledButton.icon(onPressed: busy ? null : () => _action('acknowledge', 'Alert acknowledged.', emergencyId: id), icon: const Icon(Icons.check_circle_outline_rounded, size: 17), label: const Text('Acknowledge'), style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.green, visualDensity: VisualDensity.compact)),
              FilledButton.icon(onPressed: busy ? null : () => _relay(alert: a), icon: const Icon(Icons.forward_to_inbox_rounded, size: 17), label: const Text('Relay to junction'), style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.blue, visualDensity: VisualDensity.compact)),
              FilledButton.icon(onPressed: busy ? null : () => _action('clear', 'Junction marked clear.', emergencyId: id), icon: const Icon(Icons.traffic_rounded, size: 17), label: const Text('Traffic cleared'), style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.navy, visualDensity: VisualDensity.compact)),
            ]),
          ] else
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('Operation completed • remove this item to clear the dashboard.', style: TextStyle(color: LuxuryTheme.green, fontSize: 10, fontWeight: FontWeight.w800))),
        ]),
      ),
    );
  }

  Widget _info(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: LuxuryTheme.muted, fontSize: 8, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(value, style: const TextStyle(color: LuxuryTheme.ink, fontSize: 12, fontWeight: FontWeight.w900))]);
  Widget _status(String text) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: LuxuryTheme.red.withValues(alpha: .09), borderRadius: BorderRadius.circular(99)), child: Text(text.replaceAll('_', ' '), style: const TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w900, fontSize: 9)));
  Widget _error(String text) => CommandCard(child: Text(text, style: const TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w700)));
  String _duration(dynamic raw) => raw is num ? raw < 60 ? '${raw.round()} sec' : '${(raw / 60).ceil()} min' : '—';
  String _coordinate(dynamic raw) => raw is num ? raw.toStringAsFixed(5) : '—';
  void _toast(String text, Color color) {
    if (!mounted) return;
    _noticeTimer?.cancel();
    _noticeEntry?.remove();
    final screenWidth = MediaQuery.of(context).size.width;
    _noticeEntry = OverlayEntry(builder: (_) => Positioned(
      top: MediaQuery.of(context).padding.top + 14,
      right: 16,
      width: screenWidth < 420 ? screenWidth - 32 : 360,
      child: IgnorePointer(child: Material(color: Colors.transparent, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x330A1930), blurRadius: 20, offset: Offset(0, 8))]),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20), const SizedBox(width: 9), Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, height: 1.3))) ]),
      ))),
    ));
    Overlay.of(context, rootOverlay: true).insert(_noticeEntry!);
    _noticeTimer = Timer(const Duration(seconds: 5), () { _noticeEntry?.remove(); _noticeEntry = null; _noticeTimer = null; });
  }
  @override void dispose() { _noticeTimer?.cancel(); _noticeEntry?.remove(); pollTimer?.cancel(); routeTimer?.cancel(); junctionTimer?.cancel(); buzzerTimer?.cancel(); locationSubscription?.cancel(); _mapController.dispose(); super.dispose(); }
}

class _MapMarker extends StatelessWidget {
  final IconData icon; final Color color; final bool small;
  const _MapMarker({required this.icon, required this.color, this.small = false});
  @override Widget build(BuildContext context) => Container(decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Color(0x2A0A1930), blurRadius: 12)]), child: Icon(icon, color: Colors.white, size: small ? 17 : 24));
}
