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
      // Fetch emergency details and hospital recommendations in parallel for maximum speed
      final results = await Future.wait([
        api.get('/emergencies/${widget.emergencyId}'),
        api.get('/emergencies/${widget.emergencyId}/hospital-recommendations?radius_km=15'),
      ]);

      final e = results[0];
      final result = results[1];

      if (!mounted) return;
      var list = result is List ? result.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList() : <Map<String, dynamic>>[];
      if (list.isEmpty) {
        try {
          final fallback = await api.get('/emergencies/${widget.emergencyId}/hospital-recommendations?radius_km=5000');
          if (fallback is List && fallback.isNotEmpty) {
            list = fallback.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
          }
        } catch (_) {}
      }

      setState(() {
        emergency = Map<String, dynamic>.from(e as Map);
        hospitals = list;
      });

      // Update location asynchronously in background without blocking screen render
      location.currentPosition().then((p) {
        if (mounted) {
          latitude = p.latitude;
          longitude = p.longitude;
        }
        api.post('/emergencies/${widget.emergencyId}/location', {
          'latitude': p.latitude,
          'longitude': p.longitude,
          'accuracy_meters': p.accuracy,
          'speed_mps': p.speed,
          'heading_degrees': p.heading,
        }).catchError((_) => null);
      }).catchError((_) => null);

    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _useHospital(Map<String, dynamic> hospital) async {
    final id = hospital['hospital_id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => selectingHospitalId = id);
    try {
      final assigned = await api.post('/emergencies/${widget.emergencyId}/assign-hospital', {
        'hospital_id': id,
        'gst_number': hospital['gst_number'],
      });
      if (!mounted) return;
      setState(() => selectingHospitalId = null);
      await Navigator.push(context, MaterialPageRoute(builder: (_) => HospitalNavigationPage(emergencyId: widget.emergencyId, hospital: hospital, assignedEmergency: Map<String, dynamic>.from(assigned), initialSeverity: widget.initialSeverity)));
      if (mounted) setState(() => selectingHospitalId = null);
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
  Widget build(BuildContext context) {
    final topThree = hospitals.where((h) => h['is_top_match'] == true).toList();
    final remaining = hospitals.where((h) => h['is_top_match'] != true).toList();
    final effectiveTopThree = topThree.isNotEmpty ? topThree : hospitals.take(3).toList();
    final effectiveRemaining = topThree.isNotEmpty ? remaining : hospitals.skip(3).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Destination', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(onPressed: loading ? null : load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: loading
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Matching best specialized hospitals…', style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w600))]))
          : error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: SurfaceCard(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.location_off_rounded, color: AppTheme.red, size: 42), const SizedBox(height: 12), Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)), const SizedBox(height: 12), PrimaryButton(label: 'Retry', icon: Icons.refresh_rounded, outlined: true, background: AppTheme.blue, onPressed: load)]))))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
                  children: [
                    PageHeader(
                      eyebrow: 'Clinical triage & routing',
                      title: 'Select Destination Hospital',
                      subtitle: 'Hospitals are evaluated based on patient condition, medical specialty, and emergency transit time.',
                    ),
                    const SizedBox(height: 16),
                    SurfaceCard(
                      gradient: const [Color(0xFFFFEEF0), Color(0xFFFFFFFF)],
                      child: Row(children: [
                        Container(width: 44, height: 44, decoration: BoxDecoration(color: AppTheme.red.withValues(alpha: .11), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.emergency_rounded, color: AppTheme.red)),
                        const SizedBox(width: 11),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Patient condition', style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900)),
                          Text('${emergency?['severity'] ?? widget.initialSeverity} • ${hospitals.isNotEmpty ? hospitals.first['condition']?.toString().replaceAll('_', ' ') : 'EMERGENCY'}', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                        ])),
                        const StatusChip('SPECIALTY MATCH', color: AppTheme.green),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    if (hospitals.isEmpty)
                      const SurfaceCard(child: Text('No emergency hospitals found in range. Please retry or expand radius.', style: TextStyle(color: AppTheme.muted)))
                    else ...[
                      // Section 1: TOP 3 MATCHES
                      Row(children: [
                        const Icon(Icons.workspace_premium_rounded, color: Color(0xFFE6A100), size: 20),
                        const SizedBox(width: 8),
                        Text('TOP 3 SPECIALTY MATCHES', style: TextStyle(color: AppTheme.ink.withValues(alpha: .85), fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                      ]),
                      const SizedBox(height: 8),
                      ...effectiveTopThree.map((h) => _buildHospitalCard(h, isTopRank: true)),

                      if (effectiveRemaining.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Row(children: [
                          const Icon(Icons.local_hospital_rounded, color: AppTheme.blue, size: 20),
                          const SizedBox(width: 8),
                          Text('OTHER NEARBY HOSPITALS (${effectiveRemaining.length})', style: TextStyle(color: AppTheme.ink.withValues(alpha: .85), fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                        ]),
                        const SizedBox(height: 8),
                        ...effectiveRemaining.map((h) => _buildHospitalCard(h, isTopRank: false)),
                      ],
                    ],
                  ],
                ),
    );
  }

  Widget _buildHospitalCard(Map<String, dynamic> h, {required bool isTopRank}) {
    final rank = h['rank'] ?? 0;
    final id = h['hospital_id']?.toString();
    final selected = selectingHospitalId == id;
    final profile = h['route_profile']?.toString();
    final profileColor = profile == 'comfort_priority' ? AppTheme.purple : profile == 'traffic_priority' ? AppTheme.red : AppTheme.blue;
    final matchPct = h['match_percentage'] ?? h['rank_score'];
    final badge = h['specialty_badge']?.toString() ?? (isTopRank ? 'PREMIER MATCH' : 'NEARBY FACILITY');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        gradient: rank == 1
            ? const [Color(0xFFEFF7FF), Color(0xFFFFFFFF)]
            : isTopRank
                ? const [Color(0xFFFAFAFE), Color(0xFFFFFFFF)]
                : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rank == 1
                    ? AppTheme.blue.withValues(alpha: .15)
                    : isTopRank
                        ? const Color(0xFFFFF7E6)
                        : const Color(0xFFF0F4F8),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                '#$rank',
                style: TextStyle(
                  color: rank == 1 ? AppTheme.blue : isTopRank ? const Color(0xFFD48806) : AppTheme.muted,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  h['hospital_name']?.toString() ?? 'Hospital',
                  style: const TextStyle(color: AppTheme.ink, fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${h['distance_km'] ?? '—'} km  •  ${_eta(h)}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            if (matchPct != null)
              StatusChip(
                '$matchPct% MATCH',
                color: rank == 1 ? AppTheme.green : isTopRank ? const Color(0xFF00796B) : AppTheme.blue,
              ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            StatusChip(badge, color: isTopRank ? AppTheme.blue : const Color(0xFF718096)),
            StatusChip(_label(profile), color: profileColor),
            if (h['traffic_aware'] == true) const StatusChip('LIVE TRAFFIC', color: AppTheme.green),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.bed_rounded, size: 16, color: AppTheme.blue),
                      const SizedBox(width: 5),
                      Text(
                        '${h['icu_beds_available'] ?? 12} ICU Beds',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppTheme.ink),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 16, color: const Color(0xFFCBD5E1)),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.air_rounded, size: 16, color: Color(0xFF00897B)),
                      const SizedBox(width: 5),
                      Text(
                        '${h['oxygen_cylinders_available'] ?? 20} O₂ Cylinders',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppTheme.ink),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            h['reason']?.toString() ?? 'Verified emergency hospital candidate.',
            style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: PrimaryButton(
                label: selected ? 'Opening navigation…' : rank == 1 ? 'Select #1 Best Match' : 'Use this hospital',
                icon: Icons.navigation_rounded,
                background: rank == 1 ? AppTheme.blue : isTopRank ? const Color(0xFF1E3A8A) : const Color(0xFF334155),
                onPressed: selected || selectingHospitalId != null ? null : () => _useHospital(h),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: () => _previewHospital(h),
              icon: const Icon(Icons.map_rounded),
              tooltip: 'Open on map',
            ),
          ]),
        ]),
      ),
    );
  }

  String _eta(Map<String, dynamic> h) {
    final raw = h['duration_seconds'];
    return raw is num ? '${(raw / 60).ceil()} min ETA' : 'ETA unavailable';
  }

  String _label(String? profile) =>
      profile == 'comfort_priority' ? 'COMFORT ROUTE' : profile == 'traffic_priority' ? 'TRAFFIC PRIORITY' : 'FASTEST ROUTE';
}
