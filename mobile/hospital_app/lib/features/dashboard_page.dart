// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_map/flutter_map.dart';
// import 'package:latlong2/latlong.dart';
// import '../core/app_api.dart';
// import '../core/luxury_theme.dart';

// class HospitalDashboardPage extends StatefulWidget {
//   final Future<void> Function() onLogout;
//   const HospitalDashboardPage({super.key, required this.onLogout});
//   @override State<HospitalDashboardPage> createState() => _HospitalDashboardPageState();
// }
// class _HospitalDashboardPageState extends State<HospitalDashboardPage> {
//   final api = AppApi();
//   final icu = TextEditingController(text: '0'); final erBeds = TextEditingController(text: '0'); final vents = TextEditingController(text: '0');
//   final FocusNode _icuFocus = FocusNode(); final FocusNode _erFocus = FocusNode(); final FocusNode _ventsFocus = FocusNode();
//   Timer? pollTimer; Timer? routeTimer;
//   Map<String, dynamic> board = {}; Map<String, dynamic>? routeData; String? selectedRequestId;
//   bool loading = true; bool saving = false; bool availabilityDirty = false; bool emergencyAvailable = true; bool oxygenAvailable = true; bool traumaCapable = false; bool cardiacCapable = false; String? error;
//   bool _hasLoadedInitialRequests = false;
//   Set<String> _knownRequestIds = <String>{};
//   List<Map<String, dynamic>> _list(dynamic raw) => raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
//   Map<String, dynamic>? get hospital => board['hospital'] is Map ? Map<String, dynamic>.from(board['hospital']) : null;
//   List<Map<String, dynamic>> get requests => _list(board['requests']);
//   Map<String, dynamic>? get selected { for (final r in requests) { if (r['request_id']?.toString() == selectedRequestId) return r; } return requests.isEmpty ? null : requests.first; }

//   @override void initState() { super.initState(); _load(); pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load()); routeTimer = Timer.periodic(const Duration(seconds: 20), (_) => _loadRoute()); }
//   Future<void> _load() async {
//     try {
//       final raw = await api.get('/coordination/hospital/board'); if (!mounted || raw is! Map) return;
//       final next = Map<String, dynamic>.from(raw); final nextRequests = _list(next['requests']);
//       final incomingRequestIds = nextRequests.map((r) => r['request_id']?.toString()).whereType<String>().toSet();
//       final newRequestIds = _hasLoadedInitialRequests ? incomingRequestIds.difference(_knownRequestIds) : <String>{};
//       _knownRequestIds = incomingRequestIds;
//       _hasLoadedInitialRequests = true;
//       String? id = selectedRequestId; if (id == null || !nextRequests.any((r) => r['request_id']?.toString() == id)) id = nextRequests.isEmpty ? null : nextRequests.first['request_id']?.toString();
//       final h = next['hospital'] is Map ? Map<String, dynamic>.from(next['hospital']) : <String, dynamic>{};
//       final res = h['resources'] is Map ? Map<String, dynamic>.from(h['resources']) : <String, dynamic>{};
//       setState(() {
//         board = next;
//         selectedRequestId = id;
//         if (!availabilityDirty) {
//           emergencyAvailable = h['emergency_available'] == true;
//           icu.text = '${res['icu_beds_available'] ?? 0}';
//           erBeds.text = '${res['emergency_beds_available'] ?? 0}';
//           vents.text = '${res['ventilators_available'] ?? 0}';
//           oxygenAvailable = res['oxygen_available'] == true;
//           traumaCapable = res['trauma_capable'] == true;
//           cardiacCapable = res['cardiac_capable'] == true;
//         }
//         loading = false;
//         error = null;
//       });
//       if (newRequestIds.isNotEmpty) {
//         final newest = nextRequests.firstWhere((r) => newRequestIds.contains(r['request_id']?.toString()), orElse: () => nextRequests.first);
//         _notifyIncomingRequest(newest);
//       }
//       if (id != null && (routeData == null || routeData!['emergency_id']?.toString() != selected?['emergency_id']?.toString())) await _loadRoute();
//     } catch (e) { if (mounted) setState(() { loading = false; error = e.toString().replaceFirst('Exception: ', ''); }); }
//   }
//   void _notifyIncomingRequest(Map<String, dynamic> request) {
//     // In-app alert: the dashboard also retains the request card until the
//     // emergency is closed, so an officer/operator opening later can still see it.
//     unawaited(SystemSound.play(SystemSoundType.alert));
//     HapticFeedback.vibrate();
//     if (!mounted) return;
//     final ambulance = request['ambulance_number']?.toString() ?? 'Ambulance';
//     final condition = request['condition']?.toString() ?? 'Emergency';
//     final eta = _duration(request['eta_seconds']);
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         backgroundColor: LuxuryTheme.red,
//         duration: const Duration(seconds: 6),
//         content: Text('NEW AMBULANCE REQUEST • $ambulance • $condition • ETA $eta'),
//       ),
//     );
//   }

//   Future<void> _loadRoute() async {
//     final id = selected?['emergency_id']?.toString(); if (id == null) { if (mounted) setState(() => routeData = null); return; }
//     try { final raw = await api.get('/coordination/emergencies/$id/route'); if (mounted && raw is Map) setState(() => routeData = Map<String, dynamic>.from(raw)); } catch (_) {}
//   }
//   Future<void> _saveAvailability() async {
//     setState(() => saving = true);
//     try {
//       await api.put('/coordination/hospital/availability', {'emergency_available': emergencyAvailable, 'icu_beds_available': int.tryParse(icu.text) ?? 0, 'emergency_beds_available': int.tryParse(erBeds.text) ?? 0, 'ventilators_available': int.tryParse(vents.text) ?? 0, 'oxygen_available': oxygenAvailable, 'trauma_capable': traumaCapable, 'cardiac_capable': cardiacCapable});
//       if (mounted) setState(() => availabilityDirty = false);
//       _toast('Hospital capacity updated.', LuxuryTheme.green); await _load();
//     } catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red); }
//     finally { if (mounted) setState(() => saving = false); }
//   }
//   Future<void> _respond(String decision) async {
//     final request = selected; if (request == null) return;
//     setState(() => saving = true);
//     try { await api.post('/coordination/hospital/requests/${request['request_id']}/respond', {'decision': decision, 'note': decision == 'ACCEPTED' ? 'Emergency department is preparing for arrival.' : 'Unable to accept this arrival request at this time.'}); _toast(decision == 'ACCEPTED' ? 'Arrival accepted. Paramedic response updated.' : 'Request declined. Paramedic response updated.', decision == 'ACCEPTED' ? LuxuryTheme.green : LuxuryTheme.red); await _load(); }
//     catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red); }
//     finally { if (mounted) setState(() => saving = false); }
//   }
//   LatLng _point(dynamic lat, dynamic lon, {LatLng? fallback}) => lat is num && lon is num ? LatLng(lat.toDouble(), lon.toDouble()) : fallback ?? const LatLng(12.9716, 77.5946);
//   List<LatLng> _routePoints() { final raw = routeData?['polyline_points']; if (raw is! List) return []; return raw.whereType<List>().where((e) => e.length >= 2 && e[0] is num && e[1] is num).map((e) => LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble())).toList(); }
//   Widget _map() {
//     final r = selected; final h = hospital ?? {}; final center = r == null ? _point(h['latitude'], h['longitude']) : _point(r['ambulance_latitude'], r['ambulance_longitude'], fallback: _point(h['latitude'], h['longitude'])); final pts = _routePoints();
//     final markers = <Marker>[];
//     if (r != null) markers.add(Marker(point: _point(r['ambulance_latitude'], r['ambulance_longitude']), width: 48, height: 48, child: const _MapMarker(icon: Icons.emergency_rounded, color: LuxuryTheme.red)));
//     markers.add(Marker(point: _point(h['latitude'], h['longitude']), width: 44, height: 44, child: const _MapMarker(icon: Icons.local_hospital_rounded, color: LuxuryTheme.green)));
//     return ClipRRect(borderRadius: BorderRadius.circular(22), child: SizedBox(height: 330, child: FlutterMap(options: MapOptions(initialCenter: center, initialZoom: 12), children: [
//       TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.rescupath.hospital'),
//       if (pts.length > 1) PolylineLayer(polylines: [Polyline(points: pts, strokeWidth: 5, color: LuxuryTheme.blue)]),
//       if (pts.isEmpty && r != null) PolylineLayer(polylines: [Polyline(points: [center, _point(h['latitude'], h['longitude'])], strokeWidth: 3, color: LuxuryTheme.blue)]),
//       MarkerLayer(markers: markers), RichAttributionWidget(attributions: const [TextSourceAttribution('OpenStreetMap contributors')]),
//     ])));
//   }
//   @override Widget build(BuildContext context) {
//     final h = hospital ?? {}; final r = selected;
//     return Scaffold(appBar: AppBar(title: const Text('Hospital Command', style: TextStyle(fontWeight: FontWeight.w900)), actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)), IconButton(tooltip: 'Sign out', onPressed: widget.onLogout, icon: const Icon(Icons.logout_rounded))]),
//       body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
//         BrandHeader(title: 'RescuPath Hospital', subtitle: '${h['hospital_name'] ?? 'Registered facility'} • ${h['department'] ?? 'Emergency Department'}', icon: Icons.local_hospital_rounded),
//         const SizedBox(height: 12), if (error != null) _message(error!, LuxuryTheme.red),
//         CommandCard(child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Emergency intake status', style: TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 16)), const SizedBox(height: 4), Text(emergencyAvailable ? 'Ready to receive an ambulance' : 'Not currently accepting emergency arrivals', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 12))])), Switch(value: emergencyAvailable, onChanged: saving ? null : (v) => setState(() { emergencyAvailable = v; availabilityDirty = true; }), activeThumbColor: LuxuryTheme.green)])),
//         const SizedBox(height: 10), CommandCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Live resources', style: TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 16)), const SizedBox(height: 10), Row(children: [Expanded(child: _numberField('ICU beds', icu, _icuFocus)), const SizedBox(width: 8), Expanded(child: _numberField('ER beds', erBeds, _erFocus)), const SizedBox(width: 8), Expanded(child: _numberField('Ventilators', vents, _ventsFocus))]), const SizedBox(height: 8), Wrap(spacing: 10, runSpacing: 2, children: [FilterChip(label: const Text('Oxygen available'), selected: oxygenAvailable, onSelected: (v) => setState(() { oxygenAvailable = v; availabilityDirty = true; })), FilterChip(label: const Text('Trauma capable'), selected: traumaCapable, onSelected: (v) => setState(() { traumaCapable = v; availabilityDirty = true; })), FilterChip(label: const Text('Cardiac capable'), selected: cardiacCapable, onSelected: (v) => setState(() { cardiacCapable = v; availabilityDirty = true; }))]), Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: saving ? null : _saveAvailability, icon: const Icon(Icons.save_outlined), label: Text(saving ? 'Saving…' : 'Save capacity')))])),
//         const SizedBox(height: 14), Row(children: [const Expanded(child: Text('Live ambulance map', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: LuxuryTheme.ink))), const Text('Updates every 5s', style: TextStyle(color: LuxuryTheme.muted, fontSize: 10))]), const SizedBox(height: 10), _map(),
//         const SizedBox(height: 16), const Text('Incoming availability requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: LuxuryTheme.ink)), const SizedBox(height: 10),
//         if (requests.isEmpty) CommandCard(child: Column(children: [const Icon(Icons.mark_email_read_outlined, color: LuxuryTheme.green, size: 38), const SizedBox(height: 8), const Text('No active arrival requests', style: TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900)), const SizedBox(height: 5), const Text('When the paramedic requests this facility, patient severity, ambulance location and ETA will appear here.', textAlign: TextAlign.center, style: TextStyle(color: LuxuryTheme.muted, fontSize: 12))])) else ...requests.map((item) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _requestCard(item, selectedRequestId == item['request_id']))),
//         if (r != null) ...[
//           const SizedBox(height: 4), CommandCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Icon(Icons.emergency_rounded, color: LuxuryTheme.red), const SizedBox(width: 8), Expanded(child: Text('${r['ambulance_number'] ?? 'Ambulance'} • ${r['severity'] ?? 'HIGH'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: LuxuryTheme.ink))), _status(r['request_status']?.toString() ?? 'REQUESTED')]), const SizedBox(height: 8), Text('${r['condition'] ?? 'Emergency'} • ${r['status'] ?? 'ACTIVE'}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 12)), const SizedBox(height: 12), Row(children: [Expanded(child: _info('AMBULANCE ETA', _duration(r['eta_seconds']))), Expanded(child: _info('LIVE GPS', '${_coord(r['ambulance_latitude'])}, ${_coord(r['ambulance_longitude'])}'))]), const SizedBox(height: 7), Text(r['eta_basis']?.toString() ?? '', style: const TextStyle(fontSize: 10, color: LuxuryTheme.muted)), if (r['response_note'] != null) Padding(padding: const EdgeInsets.only(top: 7), child: Text('Response: ${r['response_note']}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11))), const SizedBox(height: 14), if (r['request_status'] == 'REQUESTED') Row(children: [Expanded(child: FilledButton.icon(onPressed: saving ? null : () => _respond('ACCEPTED'), icon: const Icon(Icons.check_circle_outline), label: const Text('Accept arrival'), style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.green))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: saving ? null : () => _respond('DECLINED'), icon: const Icon(Icons.cancel_outlined), label: const Text('Decline')))]) else Text(r['request_status'] == 'ACCEPTED' ? '✓ Your facility accepted this arrival. The paramedic can see your response.' : 'This request was declined. The paramedic can see your response.', style: TextStyle(color: r['request_status'] == 'ACCEPTED' ? LuxuryTheme.green : LuxuryTheme.red, fontWeight: FontWeight.w800, fontSize: 12))]))
//         ],
//         const SizedBox(height: 10), const Text('The ETA follows the last route estimate sent by the paramedic. If it is unavailable, the app labels any fallback estimate; map routing is not a substitute for local clinical/dispatch procedures.', style: TextStyle(color: LuxuryTheme.muted, fontSize: 10, height: 1.4)),
//       ])),
//     );
//   }
//   Widget _requestCard(Map<String, dynamic> item, bool active) => InkWell(onTap: () async { setState(() { selectedRequestId = item['request_id']?.toString(); routeData = null; }); await _loadRoute(); }, borderRadius: BorderRadius.circular(20), child: CommandCard(child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: (active ? LuxuryTheme.blue : LuxuryTheme.cyan).withValues(alpha: .1), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.emergency_rounded, color: LuxuryTheme.red)), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${item['ambulance_number'] ?? 'Ambulance'} • ${item['severity'] ?? 'HIGH'}', style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('${item['condition'] ?? 'Emergency'} • ETA ${_duration(item['eta_seconds'])}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11)), const SizedBox(height: 4), Text('Request: ${item['request_status'] ?? 'REQUESTED'}', style: const TextStyle(color: LuxuryTheme.blue, fontWeight: FontWeight.w900, fontSize: 10))])), Icon(active ? Icons.radio_button_checked : Icons.chevron_right, color: LuxuryTheme.blue)])));
//   Widget _numberField(String label, TextEditingController controller, FocusNode focusNode) => TextField(focusNode: focusNode, controller: controller, onChanged: (_) { availabilityDirty = true; }, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: label, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)));
//   Widget _info(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: LuxuryTheme.muted, fontSize: 9, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(value, style: const TextStyle(color: LuxuryTheme.ink, fontSize: 12, fontWeight: FontWeight.w900))]);
//   Widget _status(String text) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: (text == 'ACCEPTED' ? LuxuryTheme.green : text == 'DECLINED' ? LuxuryTheme.red : LuxuryTheme.amber).withValues(alpha: .11), borderRadius: BorderRadius.circular(99)), child: Text(text.replaceAll('_', ' '), style: TextStyle(color: text == 'ACCEPTED' ? LuxuryTheme.green : text == 'DECLINED' ? LuxuryTheme.red : LuxuryTheme.amber, fontWeight: FontWeight.w900, fontSize: 9)));
//   Widget _message(String message, Color color) => CommandCard(child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.w700)));
//   String _duration(dynamic raw) => raw is num ? raw < 60 ? '${raw.round()} sec' : '${(raw / 60).ceil()} min' : 'Awaiting ETA';
//   String _coord(dynamic raw) => raw is num ? raw.toStringAsFixed(5) : '—';
//   void _toast(String text, Color color) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: color, content: Text(text))); }
//   @override void dispose() { pollTimer?.cancel(); routeTimer?.cancel(); icu.dispose(); erBeds.dispose(); vents.dispose(); _icuFocus.dispose(); _erFocus.dispose(); _ventsFocus.dispose(); super.dispose(); }
// }
// class _MapMarker extends StatelessWidget { final IconData icon; final Color color; const _MapMarker({required this.icon, required this.color}); @override Widget build(BuildContext context) => Container(decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Color(0x2A0A1930), blurRadius: 12)]), child: Icon(icon, color: Colors.white, size: 24)); }
// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter_map/flutter_map.dart';
// import 'package:latlong2/latlong.dart';
// import '../core/app_api.dart';
// import '../core/luxury_theme.dart';

// class HospitalDashboardPage extends StatefulWidget {
//   final Future<void> Function() onLogout;
//   const HospitalDashboardPage({super.key, required this.onLogout});
//   @override State<HospitalDashboardPage> createState() => _HospitalDashboardPageState();
// }
// class _HospitalDashboardPageState extends State<HospitalDashboardPage> {
//   final api = AppApi();
//   final icu = TextEditingController(text: '0'); final erBeds = TextEditingController(text: '0'); final vents = TextEditingController(text: '0');
//   final FocusNode _icuFocus = FocusNode(); final FocusNode _erFocus = FocusNode(); final FocusNode _ventsFocus = FocusNode();
//   Timer? pollTimer; Timer? routeTimer;
//   Map<String, dynamic> board = {}; Map<String, dynamic>? routeData; String? selectedRequestId;
//   final Set<String> _hiddenEmergencyIds = <String>{};
//   bool loading = true; bool saving = false; bool availabilityDirty = false; bool emergencyAvailable = true; bool oxygenAvailable = true; bool traumaCapable = false; bool cardiacCapable = false; String? error;
//   List<Map<String, dynamic>> _list(dynamic raw) => raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
//   Map<String, dynamic>? get hospital => board['hospital'] is Map ? Map<String, dynamic>.from(board['hospital']) : null;
//   List<Map<String, dynamic>> get requests => _list(board['requests'])
//       .where((r) => !_hiddenEmergencyIds.contains(
//           r['emergency_id']?.toString() ?? r['request_id']?.toString() ?? ''))
//       .toList();

//   void _hideRequest(Map<String, dynamic> item) {
//     final id = item['emergency_id']?.toString() ??
//         item['request_id']?.toString();
//     if (id == null || id.isEmpty) return;
//     setState(() {
//       _hiddenEmergencyIds.add(id);
//       if (selectedRequestId == item['request_id']?.toString()) {
//         selectedRequestId = null;
//         routeData = null;
//       }
//     });
//     _toast('Ambulance removed from this dashboard. The emergency record was not deleted.', LuxuryTheme.green);
//   }
//   Map<String, dynamic>? get selected { for (final r in requests) { if (r['request_id']?.toString() == selectedRequestId) return r; } return requests.isEmpty ? null : requests.first; }

//   @override void initState() { super.initState(); _load(); pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load()); routeTimer = Timer.periodic(const Duration(seconds: 20), (_) => _loadRoute()); }
//   Future<void> _load() async {
//     try {
//       final raw = await api.get('/coordination/hospital/board'); if (!mounted || raw is! Map) return;
//       final next = Map<String, dynamic>.from(raw); final nextRequests = _list(next['requests']);
//       String? id = selectedRequestId; if (id == null || !nextRequests.any((r) => r['request_id']?.toString() == id)) id = nextRequests.isEmpty ? null : nextRequests.first['request_id']?.toString();
//       final h = next['hospital'] is Map ? Map<String, dynamic>.from(next['hospital']) : <String, dynamic>{};
//       final res = h['resources'] is Map ? Map<String, dynamic>.from(h['resources']) : <String, dynamic>{};
//       setState(() {
//         board = next;
//         selectedRequestId = id;
//         if (!availabilityDirty) {
//           emergencyAvailable = h['emergency_available'] == true;
//           icu.text = '${res['icu_beds_available'] ?? 0}';
//           erBeds.text = '${res['emergency_beds_available'] ?? 0}';
//           vents.text = '${res['ventilators_available'] ?? 0}';
//           oxygenAvailable = res['oxygen_available'] == true;
//           traumaCapable = res['trauma_capable'] == true;
//           cardiacCapable = res['cardiac_capable'] == true;
//         }
//         loading = false;
//         error = null;
//       });
//       if (id != null && (routeData == null || routeData!['emergency_id']?.toString() != selected?['emergency_id']?.toString())) await _loadRoute();
//     } catch (e) { if (mounted) setState(() { loading = false; error = e.toString().replaceFirst('Exception: ', ''); }); }
//   }
//   Future<void> _loadRoute() async {
//     final id = selected?['emergency_id']?.toString(); if (id == null) { if (mounted) setState(() => routeData = null); return; }
//     try { final raw = await api.get('/coordination/emergencies/$id/route'); if (mounted && raw is Map) setState(() => routeData = Map<String, dynamic>.from(raw)); } catch (_) {}
//   }
//   Future<void> _saveAvailability() async {
//     setState(() => saving = true);
//     try {
//       await api.put('/coordination/hospital/availability', {'emergency_available': emergencyAvailable, 'icu_beds_available': int.tryParse(icu.text) ?? 0, 'emergency_beds_available': int.tryParse(erBeds.text) ?? 0, 'ventilators_available': int.tryParse(vents.text) ?? 0, 'oxygen_available': oxygenAvailable, 'trauma_capable': traumaCapable, 'cardiac_capable': cardiacCapable});
//       if (mounted) setState(() => availabilityDirty = false);
//       _toast('Hospital capacity updated.', LuxuryTheme.green); await _load();
//     } catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red); }
//     finally { if (mounted) setState(() => saving = false); }
//   }
//   Future<void> _respond(String decision) async {
//     final request = selected; if (request == null) return;
//     setState(() => saving = true);
//     try { await api.post('/coordination/hospital/requests/${request['request_id']}/respond', {'decision': decision, 'note': decision == 'ACCEPTED' ? 'Emergency department is preparing for arrival.' : 'Unable to accept this arrival request at this time.'}); _toast(decision == 'ACCEPTED' ? 'Arrival accepted. Paramedic response updated.' : 'Request declined. Paramedic response updated.', decision == 'ACCEPTED' ? LuxuryTheme.green : LuxuryTheme.red); await _load(); }
//     catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red); }
//     finally { if (mounted) setState(() => saving = false); }
//   }
//   LatLng _point(dynamic lat, dynamic lon, {LatLng? fallback}) => lat is num && lon is num ? LatLng(lat.toDouble(), lon.toDouble()) : fallback ?? const LatLng(12.9716, 77.5946);
//   List<LatLng> _routePoints() { final raw = routeData?['polyline_points']; if (raw is! List) return []; return raw.whereType<List>().where((e) => e.length >= 2 && e[0] is num && e[1] is num).map((e) => LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble())).toList(); }
//   Widget _map() {
//     final r = selected; final h = hospital ?? {}; final center = r == null ? _point(h['latitude'], h['longitude']) : _point(r['ambulance_latitude'], r['ambulance_longitude'], fallback: _point(h['latitude'], h['longitude'])); final pts = _routePoints();
//     final markers = <Marker>[];
//     if (r != null) markers.add(Marker(point: _point(r['ambulance_latitude'], r['ambulance_longitude']), width: 48, height: 48, child: const _MapMarker(icon: Icons.emergency_rounded, color: LuxuryTheme.red)));
//     markers.add(Marker(point: _point(h['latitude'], h['longitude']), width: 44, height: 44, child: const _MapMarker(icon: Icons.local_hospital_rounded, color: LuxuryTheme.green)));
//     return ClipRRect(borderRadius: BorderRadius.circular(22), child: SizedBox(height: 330, child: FlutterMap(options: MapOptions(initialCenter: center, initialZoom: 12), children: [
//       TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.rescupath.hospital'),
//       if (pts.length > 1) PolylineLayer(polylines: [Polyline(points: pts, strokeWidth: 5, color: LuxuryTheme.blue)]),
//       if (pts.isEmpty && r != null) PolylineLayer(polylines: [Polyline(points: [center, _point(h['latitude'], h['longitude'])], strokeWidth: 3, color: LuxuryTheme.blue)]),
//       MarkerLayer(markers: markers), RichAttributionWidget(attributions: const [TextSourceAttribution('OpenStreetMap contributors')]),
//     ])));
//   }
//   @override Widget build(BuildContext context) {
//     final h = hospital ?? {}; final r = selected;
//     return Scaffold(appBar: AppBar(title: const Text('Hospital Command', style: TextStyle(fontWeight: FontWeight.w900)), actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)), IconButton(tooltip: 'Sign out', onPressed: widget.onLogout, icon: const Icon(Icons.logout_rounded))]),
//       body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
//         BrandHeader(title: 'RescuPath Hospital', subtitle: '${h['hospital_name'] ?? 'Registered facility'} • ${h['department'] ?? 'Emergency Department'}', icon: Icons.local_hospital_rounded),
//         const SizedBox(height: 12), if (error != null) _message(error!, LuxuryTheme.red),
//         CommandCard(child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Emergency intake status', style: TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 16)), const SizedBox(height: 4), Text(emergencyAvailable ? 'Ready to receive an ambulance' : 'Not currently accepting emergency arrivals', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 12))])), Switch(value: emergencyAvailable, onChanged: saving ? null : (v) => setState(() { emergencyAvailable = v; availabilityDirty = true; }), activeColor: LuxuryTheme.green)])),
//         const SizedBox(height: 10), CommandCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Live resources', style: TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 16)), const SizedBox(height: 10), Row(children: [Expanded(child: _numberField('ICU beds', icu, _icuFocus)), const SizedBox(width: 8), Expanded(child: _numberField('ER beds', erBeds, _erFocus)), const SizedBox(width: 8), Expanded(child: _numberField('Ventilators', vents, _ventsFocus))]), const SizedBox(height: 8), Wrap(spacing: 10, runSpacing: 2, children: [FilterChip(label: const Text('Oxygen available'), selected: oxygenAvailable, onSelected: (v) => setState(() { oxygenAvailable = v; availabilityDirty = true; })), FilterChip(label: const Text('Trauma capable'), selected: traumaCapable, onSelected: (v) => setState(() { traumaCapable = v; availabilityDirty = true; })), FilterChip(label: const Text('Cardiac capable'), selected: cardiacCapable, onSelected: (v) => setState(() { cardiacCapable = v; availabilityDirty = true; }))]), Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: saving ? null : _saveAvailability, icon: const Icon(Icons.save_outlined), label: Text(saving ? 'Saving…' : 'Save capacity')))])),
//         const SizedBox(height: 14), Row(children: [const Expanded(child: Text('Live ambulance map', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: LuxuryTheme.ink))), const Text('Updates every 5s', style: TextStyle(color: LuxuryTheme.muted, fontSize: 10))]), const SizedBox(height: 10), _map(),
//         const SizedBox(height: 16), const Text('Incoming availability requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: LuxuryTheme.ink)), const SizedBox(height: 10),
//         if (requests.isEmpty) CommandCard(child: Column(children: [const Icon(Icons.mark_email_read_outlined, color: LuxuryTheme.green, size: 38), const SizedBox(height: 8), const Text('No active arrival requests', style: TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900)), const SizedBox(height: 5), const Text('When the paramedic requests this facility, patient severity, ambulance location and ETA will appear here.', textAlign: TextAlign.center, style: TextStyle(color: LuxuryTheme.muted, fontSize: 12))])) else ...requests.map((item) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _requestCard(item, selectedRequestId == item['request_id']))),
//         if (r != null) ...[
//           const SizedBox(height: 4), CommandCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Icon(Icons.emergency_rounded, color: LuxuryTheme.red), const SizedBox(width: 8), Expanded(child: Text('${r['ambulance_number'] ?? 'Ambulance'} • ${r['severity'] ?? 'HIGH'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: LuxuryTheme.ink))), _status(r['request_status']?.toString() ?? 'REQUESTED')]), const SizedBox(height: 8), Text('${r['condition'] ?? 'Emergency'} • ${r['status'] ?? 'ACTIVE'}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 12)), const SizedBox(height: 12), Row(children: [Expanded(child: _info('AMBULANCE ETA', _duration(r['eta_seconds']))), Expanded(child: _info('LIVE GPS', '${_coord(r['ambulance_latitude'])}, ${_coord(r['ambulance_longitude'])}'))]), const SizedBox(height: 7), Text(r['eta_basis']?.toString() ?? '', style: const TextStyle(fontSize: 10, color: LuxuryTheme.muted)), if (r['response_note'] != null) Padding(padding: const EdgeInsets.only(top: 7), child: Text('Response: ${r['response_note']}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11))), const SizedBox(height: 14), if (r['request_status'] == 'REQUESTED') Row(children: [Expanded(child: FilledButton.icon(onPressed: saving ? null : () => _respond('ACCEPTED'), icon: const Icon(Icons.check_circle_outline), label: const Text('Accept arrival'), style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.green))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: saving ? null : () => _respond('DECLINED'), icon: const Icon(Icons.cancel_outlined), label: const Text('Decline')))]) else Text(r['request_status'] == 'ACCEPTED' ? '✓ Your facility accepted this arrival. The paramedic can see your response.' : 'This request was declined. The paramedic can see your response.', style: TextStyle(color: r['request_status'] == 'ACCEPTED' ? LuxuryTheme.green : LuxuryTheme.red, fontWeight: FontWeight.w800, fontSize: 12))]))
//         ],
//         const SizedBox(height: 10), const Text('The ETA follows the last route estimate sent by the paramedic. If it is unavailable, the app labels any fallback estimate; map routing is not a substitute for local clinical/dispatch procedures.', style: TextStyle(color: LuxuryTheme.muted, fontSize: 10, height: 1.4)),
//       ])),
//     );
//   }
//   Widget _requestCard(Map<String, dynamic> item, bool active) => InkWell(onTap: () async { setState(() { selectedRequestId = item['request_id']?.toString(); routeData = null; }); await _loadRoute(); }, borderRadius: BorderRadius.circular(20), child: CommandCard(child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: (active ? LuxuryTheme.blue : LuxuryTheme.cyan).withValues(alpha: .1), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.emergency_rounded, color: LuxuryTheme.red)), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${item['ambulance_number'] ?? 'Ambulance'} • ${item['severity'] ?? 'HIGH'}', style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('${item['condition'] ?? 'Emergency'} • ETA ${_duration(item['eta_seconds'])}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11)), const SizedBox(height: 4), Text('Request: ${item['request_status'] ?? 'REQUESTED'}', style: const TextStyle(color: LuxuryTheme.blue, fontWeight: FontWeight.w900, fontSize: 10))])), Column(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         Icon(active ? Icons.radio_button_checked : Icons.chevron_right, color: LuxuryTheme.blue),
//         if ((item['request_status']?.toString() ?? '') != 'REQUESTED')
//           IconButton(
//             tooltip: 'Remove ambulance from dashboard',
//             visualDensity: VisualDensity.compact,
//             onPressed: () => _hideRequest(item),
//             icon: const Icon(Icons.delete_outline_rounded, color: LuxuryTheme.red),
//           ),
//       ],
//     )])));
//   Widget _numberField(String label, TextEditingController controller, FocusNode focusNode) => TextField(focusNode: focusNode, controller: controller, onChanged: (_) { availabilityDirty = true; }, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: label, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)));
//   Widget _info(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: LuxuryTheme.muted, fontSize: 9, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(value, style: const TextStyle(color: LuxuryTheme.ink, fontSize: 12, fontWeight: FontWeight.w900))]);
//   Widget _status(String text) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: (text == 'ACCEPTED' ? LuxuryTheme.green : text == 'DECLINED' ? LuxuryTheme.red : LuxuryTheme.amber).withValues(alpha: .11), borderRadius: BorderRadius.circular(99)), child: Text(text.replaceAll('_', ' '), style: TextStyle(color: text == 'ACCEPTED' ? LuxuryTheme.green : text == 'DECLINED' ? LuxuryTheme.red : LuxuryTheme.amber, fontWeight: FontWeight.w900, fontSize: 9)));
//   Widget _message(String message, Color color) => CommandCard(child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.w700)));
//   String _duration(dynamic raw) => raw is num ? raw < 60 ? '${raw.round()} sec' : '${(raw / 60).ceil()} min' : 'Awaiting ETA';
//   String _coord(dynamic raw) => raw is num ? raw.toStringAsFixed(5) : '—';
//   void _toast(String text, Color color) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: color, content: Text(text))); }
//   @override void dispose() { pollTimer?.cancel(); routeTimer?.cancel(); icu.dispose(); erBeds.dispose(); vents.dispose(); _icuFocus.dispose(); _erFocus.dispose(); _ventsFocus.dispose(); super.dispose(); }
// }
// class _MapMarker extends StatelessWidget { final IconData icon; final Color color; const _MapMarker({required this.icon, required this.color}); @override Widget build(BuildContext context) => Container(decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Color(0x2A0A1930), blurRadius: 12)]), child: Icon(icon, color: Colors.white, size: 24)); }
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/app_api.dart';
import '../core/luxury_theme.dart';

class HospitalDashboardPage extends StatefulWidget {
  final Future<void> Function() onLogout;
  const HospitalDashboardPage({super.key, required this.onLogout});
  @override State<HospitalDashboardPage> createState() => _HospitalDashboardPageState();
}
class _HospitalDashboardPageState extends State<HospitalDashboardPage> {
  final api = AppApi();
  final MapController _mapController = MapController();
  final icu = TextEditingController(text: '0'); final erBeds = TextEditingController(text: '0'); final vents = TextEditingController(text: '0');
  final FocusNode _icuFocus = FocusNode(); final FocusNode _erFocus = FocusNode(); final FocusNode _ventsFocus = FocusNode();
  Timer? pollTimer; Timer? routeTimer;
  Map<String, dynamic> board = {}; Map<String, dynamic>? routeData; String? selectedRequestId;
  bool loading = true; bool saving = false; bool availabilityDirty = false; bool emergencyAvailable = true; bool oxygenAvailable = true; bool traumaCapable = false; bool cardiacCapable = false; String? error;
  bool _hasLoadedInitialRequests = false;
  Set<String> _knownRequestIds = <String>{};
  final Set<String> _dismissedRequestIds = <String>{};
  OverlayEntry? _noticeEntry;
  Timer? _noticeTimer;
  List<Map<String, dynamic>> _list(dynamic raw) => raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
  Map<String, dynamic>? get hospital => board['hospital'] is Map ? Map<String, dynamic>.from(board['hospital']) : null;
  List<Map<String, dynamic>> get requests => _list(board['requests']).where((r) => !_dismissedRequestIds.contains(r['request_id']?.toString() ?? '')).toList();
  Map<String, dynamic>? get selected { for (final r in requests) { if (r['request_id']?.toString() == selectedRequestId) return r; } return requests.isEmpty ? null : requests.first; }

  @override void initState() { super.initState(); _load(); pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load()); routeTimer = Timer.periodic(const Duration(seconds: 20), (_) => _loadRoute()); }
  Future<void> _load() async {
    try {
      final raw = await api.get('/coordination/hospital/board'); if (!mounted || raw is! Map) return;
      final next = Map<String, dynamic>.from(raw); final nextRequests = _list(next['requests']).where((r) => !_dismissedRequestIds.contains(r['request_id']?.toString() ?? '')).toList();
      final incomingRequestIds = nextRequests.map((r) => r['request_id']?.toString()).whereType<String>().toSet();
      final newRequestIds = _hasLoadedInitialRequests ? incomingRequestIds.difference(_knownRequestIds) : <String>{};
      _knownRequestIds = incomingRequestIds;
      _hasLoadedInitialRequests = true;
      String? id = selectedRequestId; if (id == null || !nextRequests.any((r) => r['request_id']?.toString() == id)) id = nextRequests.isEmpty ? null : nextRequests.first['request_id']?.toString();
      final h = next['hospital'] is Map ? Map<String, dynamic>.from(next['hospital']) : <String, dynamic>{};
      final res = h['resources'] is Map ? Map<String, dynamic>.from(h['resources']) : <String, dynamic>{};
      setState(() {
        board = next;
        selectedRequestId = id;
        if (!availabilityDirty) {
          emergencyAvailable = h['emergency_available'] == true;
          icu.text = '${res['icu_beds_available'] ?? 0}';
          erBeds.text = '${res['emergency_beds_available'] ?? 0}';
          vents.text = '${res['ventilators_available'] ?? 0}';
          oxygenAvailable = res['oxygen_available'] == true;
          traumaCapable = res['trauma_capable'] == true;
          cardiacCapable = res['cardiac_capable'] == true;
        }
        loading = false;
        error = null;
      });
      if (newRequestIds.isNotEmpty) {
        final newest = nextRequests.firstWhere((r) => newRequestIds.contains(r['request_id']?.toString()), orElse: () => nextRequests.first);
        _notifyIncomingRequest(newest);
      }
      if (id != null && (routeData == null || routeData!['emergency_id']?.toString() != selected?['emergency_id']?.toString())) await _loadRoute();
    } catch (e) { if (mounted) setState(() { loading = false; error = e.toString().replaceFirst('Exception: ', ''); }); }
  }
  void _notifyIncomingRequest(Map<String, dynamic> request) {
    // In-app alert: the dashboard also retains the request card until the
    // emergency is closed, so an officer/operator opening later can still see it.
    unawaited(SystemSound.play(SystemSoundType.alert));
    HapticFeedback.vibrate();
    if (!mounted) return;
    final ambulance = request['ambulance_number']?.toString() ?? 'Ambulance';
    final condition = request['condition']?.toString() ?? 'Emergency';
    final eta = _duration(request['eta_seconds']);
    _toast('NEW AMBULANCE REQUEST • $ambulance • $condition • ETA $eta', LuxuryTheme.red);
  }

  Future<void> _loadRoute() async {
    final id = selected?['emergency_id']?.toString(); if (id == null) { if (mounted) setState(() => routeData = null); return; }
    try { final raw = await api.get('/coordination/emergencies/$id/route'); if (mounted && raw is Map) setState(() => routeData = Map<String, dynamic>.from(raw)); } catch (_) {}
  }
  Future<void> _saveAvailability() async {
    setState(() => saving = true);
    try {
      await api.put('/coordination/hospital/availability', {'emergency_available': emergencyAvailable, 'icu_beds_available': int.tryParse(icu.text) ?? 0, 'emergency_beds_available': int.tryParse(erBeds.text) ?? 0, 'ventilators_available': int.tryParse(vents.text) ?? 0, 'oxygen_available': oxygenAvailable, 'trauma_capable': traumaCapable, 'cardiac_capable': cardiacCapable});
      if (mounted) setState(() => availabilityDirty = false);
      _toast('Hospital capacity updated.', LuxuryTheme.green); await _load();
    } catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red); }
    finally { if (mounted) setState(() => saving = false); }
  }
  Future<void> _respond(String decision, {Map<String, dynamic>? request}) async {
    final item = request ?? selected; if (item == null) return;
    setState(() => saving = true);
    try { await api.post('/coordination/hospital/requests/${item['request_id']}/respond', {'decision': decision, 'note': decision == 'ACCEPTED' ? 'Emergency department is preparing for arrival.' : 'Unable to accept this arrival request at this time.'}); _toast(decision == 'ACCEPTED' ? 'Arrival accepted. Paramedic response updated.' : 'Request declined. Paramedic response updated.', decision == 'ACCEPTED' ? LuxuryTheme.green : LuxuryTheme.red); await _load(); }
    catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red); }
    finally { if (mounted) setState(() => saving = false); }
  }
  bool _isCompletedRequest(Map<String, dynamic> item) {
    final status = (item['status'] ?? item['emergency_status'] ?? '').toString().toUpperCase();
    return const {'ARRIVED', 'COMPLETED', 'CLOSED', 'CANCELLED', 'RESOLVED'}.contains(status);
  }

  // A request can be removed once the hospital has responded or the
  // emergency itself has reached a terminal status. This only dismisses the
  // item from this dashboard; it does not delete the central emergency record.
  bool _canDismissRequest(Map<String, dynamic> item) {
    final requestStatus = (item['request_status'] ?? '').toString().toUpperCase();
    return _isCompletedRequest(item) ||
        const {'ACCEPTED', 'DECLINED'}.contains(requestStatus);
  }

  Future<void> _dismissRequest(Map<String, dynamic> item) async {
    if (!_canDismissRequest(item)) return;
    final id = item['request_id']?.toString();
    if (id == null || id.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove completed ambulance?'),
        content: const Text('This hides the completed request from this dashboard only. The emergency record and coordination history remain saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      _dismissedRequestIds.add(id);
      if (selectedRequestId == id) {
        selectedRequestId = null;
        routeData = null;
      }
    });
    _toast('Completed ambulance removed from this view.', LuxuryTheme.green);
  }

  Future<void> _showCapacityEditor() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Facility readiness', style: TextStyle(fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: emergencyAvailable,
                    onChanged: (value) {
                      setState(() { emergencyAvailable = value; availabilityDirty = true; });
                      setDialogState(() {});
                    },
                    title: const Text('Accepting emergency arrivals'),
                    activeColor: LuxuryTheme.green,
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _numberField('ICU beds', icu, _icuFocus)),
                    const SizedBox(width: 8),
                    Expanded(child: _numberField('ER beds', erBeds, _erFocus)),
                    const SizedBox(width: 8),
                    Expanded(child: _numberField('Ventilators', vents, _ventsFocus)),
                  ]),
                  const SizedBox(height: 10),
                  StatefulBuilder(
                    builder: (context, setChips) => Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        FilterChip(label: const Text('Oxygen'), selected: oxygenAvailable, onSelected: (v) { setState(() { oxygenAvailable = v; availabilityDirty = true; }); setChips(() {}); }),
                        FilterChip(label: const Text('Trauma'), selected: traumaCapable, onSelected: (v) { setState(() { traumaCapable = v; availabilityDirty = true; }); setChips(() {}); }),
                        FilterChip(label: const Text('Cardiac'), selected: cardiacCapable, onSelected: (v) { setState(() { cardiacCapable = v; availabilityDirty = true; }); setChips(() {}); }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: saving ? null : () async {
                await _saveAvailability();
                if (mounted) Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.save_rounded),
              label: Text(saving ? 'Saving…' : 'Save capacity'),
            ),
          ],
        ),
      ),
    );
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

  Widget _selectedRequestDetails(Map<String, dynamic> r) => CommandCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.emergency_rounded, color: LuxuryTheme.red), const SizedBox(width: 8), Expanded(child: Text('${r['ambulance_number'] ?? 'Ambulance'} • ${r['severity'] ?? 'HIGH'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: LuxuryTheme.ink))), _status(r['request_status']?.toString() ?? 'REQUESTED')]),
      const SizedBox(height: 9),
      Text('${r['condition'] ?? 'Emergency'} • ${r['status'] ?? 'ACTIVE'}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 12)),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: _info('AMBULANCE ETA', _duration(r['eta_seconds']))), Expanded(child: _info('LIVE GPS', '${_coord(r['ambulance_latitude'])}, ${_coord(r['ambulance_longitude'])}'))]),
      if (r['response_note'] != null) Padding(padding: const EdgeInsets.only(top: 9), child: Text(r['response_note'].toString(), style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11))),
      const SizedBox(height: 12),
      Row(children: [
        Icon(r['request_status'] == 'ACCEPTED' ? Icons.check_circle_rounded : r['request_status'] == 'DECLINED' ? Icons.cancel_rounded : Icons.hourglass_top_rounded, color: r['request_status'] == 'ACCEPTED' ? LuxuryTheme.green : r['request_status'] == 'DECLINED' ? LuxuryTheme.red : LuxuryTheme.amber, size: 18),
        const SizedBox(width: 7),
        Expanded(child: Text('Request: ${(r['request_status']?.toString() ?? 'REQUESTED').replaceAll('_', ' ')} • ETA ${_duration(r['eta_seconds'])}', style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w800, fontSize: 11))),
      ]),
    ]),
  );

  LatLng _point(dynamic lat, dynamic lon, {LatLng? fallback}) => lat is num && lon is num ? LatLng(lat.toDouble(), lon.toDouble()) : fallback ?? const LatLng(12.9716, 77.5946);
  List<LatLng> _routePoints() { final raw = routeData?['polyline_points']; if (raw is! List) return []; return raw.whereType<List>().where((e) => e.length >= 2 && e[0] is num && e[1] is num).map((e) => LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble())).toList(); }
  Widget _map() {
    final r = selected; final h = hospital ?? {}; final center = r == null ? _point(h['latitude'], h['longitude']) : _point(r['ambulance_latitude'], r['ambulance_longitude'], fallback: _point(h['latitude'], h['longitude'])); final pts = _routePoints();
    final markers = <Marker>[];
    if (r != null) markers.add(Marker(point: _point(r['ambulance_latitude'], r['ambulance_longitude']), width: 48, height: 48, child: const _MapMarker(icon: Icons.emergency_rounded, color: LuxuryTheme.red)));
    markers.add(Marker(point: _point(h['latitude'], h['longitude']), width: 44, height: 44, child: const _MapMarker(icon: Icons.local_hospital_rounded, color: LuxuryTheme.green)));
    return ClipRRect(borderRadius: BorderRadius.circular(22), child: SizedBox(height: 330, child: FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: center, initialZoom: 12), children: [
      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.rescupath.hospital'),
      if (pts.length > 1) PolylineLayer(polylines: [Polyline(points: pts, strokeWidth: 5, color: LuxuryTheme.blue)]),
      if (pts.isEmpty && r != null) PolylineLayer(polylines: [Polyline(points: [center, _point(h['latitude'], h['longitude'])], strokeWidth: 3, color: LuxuryTheme.blue)]),
      MarkerLayer(markers: markers), RichAttributionWidget(attributions: const [TextSourceAttribution('OpenStreetMap contributors')]),
    ])));
  }
  @override
  Widget build(BuildContext context) {
    final h = hospital ?? {};
    final r = selected;
    final pending = requests.where((x) => (x['request_status']?.toString() ?? 'REQUESTED') == 'REQUESTED').length;
    final accepted = requests.where((x) => x['request_status']?.toString() == 'ACCEPTED').length;
    final inTreatment = requests.where((x) => const {'ARRIVED', 'IN_TREATMENT'}.contains((x['status'] ?? '').toString().toUpperCase())).length;
    final completed = requests.where(_isCompletedRequest).length;

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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(width: 46, height: 46, decoration: BoxDecoration(color: LuxuryTheme.blue, borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 25)),
                            const SizedBox(width: 11),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('RescuPath', style: TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 17)), Text('${h['hospital_name'] ?? 'Hospital Portal'} • Emergency Department', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11))])),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: LuxuryTheme.green.withValues(alpha: .10), borderRadius: BorderRadius.circular(99)), child: const Row(children: [Icon(Icons.circle, color: LuxuryTheme.green, size: 8), SizedBox(width: 6), Text('Online', style: TextStyle(color: LuxuryTheme.green, fontWeight: FontWeight.w800, fontSize: 10))])),
                            const SizedBox(width: 6),
                            IconButton(tooltip: 'Facility capacity', onPressed: _showCapacityEditor, icon: const Icon(Icons.tune_rounded, color: LuxuryTheme.ink)),
                            IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded, color: LuxuryTheme.ink)),
                            IconButton(tooltip: 'Sign out', onPressed: widget.onLogout, icon: const Icon(Icons.logout_rounded, color: LuxuryTheme.ink)),
                          ]),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(26),
                              gradient: const LinearGradient(colors: [Color(0xFF1D70F5), Color(0xFF59A4FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                              boxShadow: const [BoxShadow(color: Color(0x222477FF), blurRadius: 22, offset: Offset(0, 8))],
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Emergency Arrivals', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 3),
                              Text('Real-time ambulance requests • ${h['hospital_name'] ?? 'Your facility'}', style: TextStyle(color: Colors.white.withValues(alpha: .86), fontSize: 12)),
                              const SizedBox(height: 17),
                              LayoutBuilder(builder: (context, constraints) {
                                final wide = constraints.maxWidth >= 650;
                                final width = wide ? (constraints.maxWidth - 24) / 4 : (constraints.maxWidth - 8) / 2;
                                return Wrap(spacing: 8, runSpacing: 8, children: [
                                  SizedBox(width: width, child: _summaryMetric('$pending', 'Pending', Icons.notifications_active_rounded, LuxuryTheme.red)),
                                  SizedBox(width: width, child: _summaryMetric('$accepted', 'Accepted', Icons.check_circle_rounded, LuxuryTheme.green)),
                                  SizedBox(width: width, child: _summaryMetric('$inTreatment', 'In treatment', Icons.medical_services_rounded, LuxuryTheme.blue)),
                                  SizedBox(width: width, child: _summaryMetric('$completed', 'Completed', Icons.task_alt_rounded, Colors.deepPurple)),
                                ]);
                              }),
                            ]),
                          ),
                          if (error != null) ...[const SizedBox(height: 12), _message(error!, LuxuryTheme.red)],
                          const SizedBox(height: 21),
                          Row(children: [
                            Expanded(child: Text('Incoming Requests (${requests.length})', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: LuxuryTheme.ink))),
                            TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
                          ]),
                          const SizedBox(height: 10),
                          LayoutBuilder(builder: (context, constraints) {
                            final requestList = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              if (requests.isEmpty)
                                CommandCard(child: Column(children: [const Icon(Icons.mark_email_read_outlined, color: LuxuryTheme.green, size: 42), const SizedBox(height: 9), const Text('No active arrival requests', style: TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900)), const SizedBox(height: 5), const Text('A paramedic request will appear here automatically.', textAlign: TextAlign.center, style: TextStyle(color: LuxuryTheme.muted, fontSize: 12))]))
                              else ...requests.map((item) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _requestCard(item, selectedRequestId == item['request_id']))),
                            ]);
                            final mapPanel = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Row(children: [const Expanded(child: Text('Live ambulance map', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: LuxuryTheme.ink))), Text('5s refresh', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 10))]),
                              const SizedBox(height: 9),
                              _map(),
                              if (r != null) ...[const SizedBox(height: 10), _selectedRequestDetails(r)],
                              const SizedBox(height: 10),
                              CommandCard(padding: const EdgeInsets.all(13), child: Row(children: [const Icon(Icons.health_and_safety_rounded, color: LuxuryTheme.green, size: 23), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Facility readiness', style: TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900)), Text(emergencyAvailable ? 'Accepting emergency arrivals' : 'Not accepting arrivals right now', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11))])), TextButton(onPressed: _showCapacityEditor, child: const Text('Manage'))])),
                            ]);
                            if (constraints.maxWidth >= 1080) {
                              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 7, child: requestList), const SizedBox(width: 18), Expanded(flex: 5, child: mapPanel)]);
                            }
                            return Column(children: [requestList, const SizedBox(height: 18), mapPanel]);
                          }),
                          const SizedBox(height: 15),
                          const Text('Live ETA is based on the latest route estimate sent by the paramedic. Bed and resource figures are maintained by your facility team.', style: TextStyle(color: LuxuryTheme.muted, fontSize: 10, height: 1.4)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _requestCard(Map<String, dynamic> item, bool active) {
    final requestStatus = (item['request_status']?.toString() ?? 'REQUESTED').toUpperCase();
    final terminal = _isCompletedRequest(item);
    final canDismiss = _canDismissRequest(item);
    final id = item['request_id']?.toString() ?? '';
    return InkWell(
      onTap: () async {
        setState(() { selectedRequestId = id; routeData = null; });
        await _loadRoute();
        final lat = item['ambulance_latitude'];
        final lon = item['ambulance_longitude'];
        if (mounted && lat is num && lon is num) {
          _mapController.move(LatLng(lat.toDouble(), lon.toDouble()), 13);
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: CommandCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 43, height: 43, decoration: BoxDecoration(color: (active ? LuxuryTheme.blue : LuxuryTheme.cyan).withValues(alpha: .10), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.emergency_rounded, color: LuxuryTheme.red, size: 23)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${item['ambulance_number'] ?? 'Ambulance'}', style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(height: 3),
              Text('${item['condition'] ?? 'Emergency'} • ETA ${_duration(item['eta_seconds'])}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11)),
            ])),
            _status(requestStatus),
            if (canDismiss)
              IconButton(
                tooltip: 'Remove ambulance from dashboard',
                onPressed: () => _dismissRequest(item),
                icon: const Icon(Icons.delete_outline_rounded, color: LuxuryTheme.red),
              )
            else
              Icon(active ? Icons.radio_button_checked : Icons.chevron_right_rounded, color: active ? LuxuryTheme.blue : LuxuryTheme.muted),
          ]),
          const SizedBox(height: 9),
          Row(children: [
            const Icon(Icons.priority_high_rounded, color: LuxuryTheme.red, size: 16),
            const SizedBox(width: 4),
            Text('${item['severity'] ?? 'HIGH'} priority', style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w800, fontSize: 10)),
            const SizedBox(width: 12),
            const Icon(Icons.location_on_outlined, color: LuxuryTheme.muted, size: 15),
            const SizedBox(width: 3),
            Expanded(child: Text('${_coord(item['ambulance_latitude'])}, ${_coord(item['ambulance_longitude'])}', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          if (requestStatus == 'REQUESTED' && !terminal) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () async { setState(() { selectedRequestId = id; routeData = null; }); await _loadRoute(); final lat = item['ambulance_latitude']; final lon = item['ambulance_longitude']; if (mounted && lat is num && lon is num) _mapController.move(LatLng(lat.toDouble(), lon.toDouble()), 13); }, child: const Text('View details'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(onPressed: saving ? null : () => _respond('ACCEPTED', request: item), icon: const Icon(Icons.check_rounded, size: 18), label: const Text('Accept'), style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.green))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(onPressed: saving ? null : () => _respond('DECLINED', request: item), icon: const Icon(Icons.close_rounded, size: 18), label: const Text('Decline'), style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.red))),
            ]),
          ] else if (requestStatus == 'ACCEPTED') ...[
            const SizedBox(height: 8),
            const Row(children: [Icon(Icons.check_circle_rounded, color: LuxuryTheme.green, size: 17), SizedBox(width: 6), Expanded(child: Text('Accepted — emergency team preparing for arrival', style: TextStyle(color: LuxuryTheme.green, fontSize: 10, fontWeight: FontWeight.w800)))]),
          ],
        ]),
      ),
    );
  }

  Widget _numberField(String label, TextEditingController controller, FocusNode focusNode) => TextField(focusNode: focusNode, controller: controller, onChanged: (_) { availabilityDirty = true; }, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: label, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)));
  Widget _info(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: LuxuryTheme.muted, fontSize: 9, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(value, style: const TextStyle(color: LuxuryTheme.ink, fontSize: 12, fontWeight: FontWeight.w900))]);
  Widget _status(String text) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: (text == 'ACCEPTED' ? LuxuryTheme.green : text == 'DECLINED' ? LuxuryTheme.red : LuxuryTheme.amber).withValues(alpha: .11), borderRadius: BorderRadius.circular(99)), child: Text(text.replaceAll('_', ' '), style: TextStyle(color: text == 'ACCEPTED' ? LuxuryTheme.green : text == 'DECLINED' ? LuxuryTheme.red : LuxuryTheme.amber, fontWeight: FontWeight.w900, fontSize: 9)));
  Widget _message(String message, Color color) => CommandCard(child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.w700)));
  String _duration(dynamic raw) => raw is num ? raw < 60 ? '${raw.round()} sec' : '${(raw / 60).ceil()} min' : 'Awaiting ETA';
  String _coord(dynamic raw) => raw is num ? raw.toStringAsFixed(5) : '—';
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
  @override void dispose() { _noticeTimer?.cancel(); _noticeEntry?.remove(); pollTimer?.cancel(); routeTimer?.cancel(); _mapController.dispose(); icu.dispose(); erBeds.dispose(); vents.dispose(); _icuFocus.dispose(); _erFocus.dispose(); _ventsFocus.dispose(); super.dispose(); }
}
class _MapMarker extends StatelessWidget { final IconData icon; final Color color; const _MapMarker({required this.icon, required this.color}); @override Widget build(BuildContext context) => Container(decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Color(0x2A0A1930), blurRadius: 12)]), child: Icon(icon, color: Colors.white, size: 24)); }
