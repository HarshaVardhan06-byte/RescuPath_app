import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/services/location_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../emergency/hospital_navigation_page.dart';

class HospitalSelectionPage extends StatefulWidget {
  final String emergencyId;
  final String initialSeverity;
  const HospitalSelectionPage({super.key, required this.emergencyId, this.initialSeverity = 'HIGH'});
  @override State<HospitalSelectionPage> createState() => _HospitalSelectionPageState();
}

class _HospitalSelectionPageState extends State<HospitalSelectionPage> {
  final api = ApiClient();
  final location = LocationService();
  List<Map<String, dynamic>> hospitals = [];
  Map<String, dynamic>? emergency;
  double? latitude;
  double? longitude;
  bool loading = true;
  String? error;
  String? selectingHospitalId;

  @override void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final e = await api.get('/emergencies/${widget.emergencyId}');
      final p = await location.currentPosition();
      latitude = p.latitude; longitude = p.longitude;
      await api.post('/emergencies/${widget.emergencyId}/location', {'latitude': p.latitude, 'longitude': p.longitude, 'accuracy_meters': p.accuracy, 'speed_mps': p.speed, 'heading_degrees': p.heading});
      final result = await api.get('/emergencies/${widget.emergencyId}/hospital-recommendations?radius_km=15');
      if (!mounted) return;
      setState(() { emergency = Map<String, dynamic>.from(e); hospitals = result is List ? result.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList() : []; });
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> _useHospital(Map<String, dynamic> hospital) async {
    final id = hospital['hospital_id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => selectingHospitalId = id);
    try {
      final assigned = await api.post('/emergencies/${widget.emergencyId}/assign-hospital', {'hospital_id': id});
      if (!mounted) return;
      await Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HospitalNavigationPage(emergencyId: widget.emergencyId, hospital: hospital, assignedEmergency: Map<String, dynamic>.from(assigned), initialSeverity: widget.initialSeverity)));
    } catch (e) {
      if (mounted) { setState(() => selectingHospitalId = null); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
    }
  }

  Future<void> _previewHospital(Map<String, dynamic> hospital) async {
    final lat = hospital['latitude']; final lng = hospital['longitude'];
    if (lat is! num || lng is! num) return;
    final uri = Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': '${lat.toDouble()},${lng.toDouble()}', 'travelmode': 'driving'});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Choose Hospital', style: TextStyle(fontWeight: FontWeight.w900)), actions: [IconButton(onPressed: loading ? null : load, icon: const Icon(Icons.refresh_rounded))]),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: SurfaceCard(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.location_off_rounded, color: AppTheme.red, size: 42), const SizedBox(height: 12), Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)), const SizedBox(height: 12), PrimaryButton(label: 'Retry', icon: Icons.refresh_rounded, outlined: true, background: AppTheme.blue, onPressed: load)]))))
                : ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 30), children: [
                    PageHeader(eyebrow: 'Destination matching', title: 'Select the hospital', subtitle: 'RescuPath compares real nearby hospitals against the patient condition and route profile. The destination is never auto-selected.'),
                    const SizedBox(height: 16),
                    SurfaceCard(gradient: const [Color(0xFFFFEEF0), Color(0xFFFFFFFF)], child: Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(color: AppTheme.red.withValues(alpha: .11), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.emergency_rounded, color: AppTheme.red)), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Patient profile', style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900)), Text('${emergency?['severity'] ?? widget.initialSeverity} • ${hospitals.isNotEmpty ? hospitals.first['condition']?.toString().replaceAll('_', ' ') : 'Emergency'}', style: const TextStyle(color: AppTheme.muted, fontSize: 11))])), StatusChip('GPS LIVE', color: AppTheme.green)])),
                    const SizedBox(height: 14),
                    if (hospitals.isEmpty) const SurfaceCard(child: Text('No emergency-capable hospital was returned by the live public hospital source. Refresh and try again.', style: TextStyle(color: AppTheme.muted)))
                    else ...hospitals.asMap().entries.map((entry) {
                      final index = entry.key + 1; final h = entry.value;
                      final id = h['hospital_id']?.toString(); final selected = selectingHospitalId == id;
                      final profile = h['route_profile']?.toString();
                      final profileColor = profile == 'comfort_priority' ? AppTheme.purple : profile == 'traffic_priority' ? AppTheme.red : AppTheme.blue;
                      final score = h['comfort_score'];
                      return Padding(padding: const EdgeInsets.only(bottom: 12), child: SurfaceCard(gradient: index == 1 ? const [Color(0xFFEFF7FF), Color(0xFFFFFFFF)] : null, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: index == 1 ? AppTheme.blue.withValues(alpha: .10) : const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(15)), child: Text('#$index', style: TextStyle(color: index == 1 ? AppTheme.blue : AppTheme.muted, fontWeight: FontWeight.w900))), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(h['hospital_name']?.toString() ?? 'Hospital', style: const TextStyle(color: AppTheme.ink, fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('${h['distance_km'] ?? '—'} km  •  ${_eta(h)}', style: const TextStyle(color: AppTheme.muted, fontSize: 12))])), if (h['recommended'] == true) const StatusChip('MATCHED', color: AppTheme.green)]),
                        const SizedBox(height: 11), Wrap(spacing: 7, runSpacing: 7, children: [StatusChip((h['condition']?.toString() ?? 'OTHER').replaceAll('_', ' '), color: AppTheme.blue), StatusChip(_label(profile), color: profileColor), if (h['traffic_aware'] == true) const StatusChip('LIVE TRAFFIC', color: AppTheme.green), if (score is num) StatusChip('COMFORT ${((score.toDouble()) * 100).round()}%', color: AppTheme.purple)]),
                        const SizedBox(height: 10), Text(h['reason']?.toString() ?? 'Live hospital candidate.', style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
                        if (h['phone'] != null) Padding(padding: const EdgeInsets.only(top: 7), child: Row(children: [const Icon(Icons.phone_rounded, color: AppTheme.green, size: 16), const SizedBox(width: 6), Text(h['phone'].toString(), style: const TextStyle(color: AppTheme.green, fontSize: 11, fontWeight: FontWeight.w700))])),
                        const SizedBox(height: 14),
                        Row(children: [Expanded(child: PrimaryButton(label: selected ? 'Opening navigation…' : 'Use this hospital', icon: Icons.navigation_rounded, background: AppTheme.blue, onPressed: selected || selectingHospitalId != null ? null : () => _useHospital(h))), const SizedBox(width: 8), IconButton.filledTonal(onPressed: () => _previewHospital(h), icon: const Icon(Icons.map_rounded), tooltip: 'Open on map')]),
                      ])));
                    }),
                  ],
              ),
      );

  String _eta(Map<String, dynamic> h) { final raw = h['duration_seconds']; return raw is num ? '${(raw / 60).ceil()} min ETA' : 'ETA unavailable'; }
  String _label(String? profile) => profile == 'comfort_priority' ? 'COMFORT ROUTE' : profile == 'traffic_priority' ? 'TRAFFIC PRIORITY' : 'FASTEST ROUTE';
}
