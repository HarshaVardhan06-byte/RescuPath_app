import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/services/location_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../emergency/hospital_navigation_page.dart';

class HospitalSelectionPage extends StatefulWidget {
  final String emergencyId;
  final String initialSeverity;
  const HospitalSelectionPage({
    super.key,
    required this.emergencyId,
    this.initialSeverity = 'HIGH',
  });
  @override
  State<HospitalSelectionPage> createState() => _HospitalSelectionPageState();
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
  String? selectedHospitalId;
  int filterIndex = 0; // 0: Recommended, 1: Nearest, 2: Available

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait([
        api.get('/emergencies/${widget.emergencyId}'),
        api.get('/emergencies/${widget.emergencyId}/hospital-recommendations?radius_km=15'),
      ]);

      final e = results[0];
      final result = results[1];

      if (!mounted) return;
      var list = result is List
          ? result.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList()
          : <Map<String, dynamic>>[];

      if (list.isEmpty) {
        try {
          final fallback = await api.get(
            '/emergencies/${widget.emergencyId}/hospital-recommendations?radius_km=5000',
          );
          if (fallback is List && fallback.isNotEmpty) {
            list = fallback.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
          }
        } catch (_) {}
      }

      setState(() {
        emergency = Map<String, dynamic>.from(e as Map);
        hospitals = list;
        if (list.isNotEmpty && selectedHospitalId == null) {
          selectedHospitalId = list.first['hospital_id']?.toString() ?? list.first['id']?.toString();
        }
      });

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
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> get _sortedHospitals {
    final list = List<Map<String, dynamic>>.from(hospitals);
    if (filterIndex == 1) {
      // Nearest
      list.sort((a, b) {
        final dA = (a['distance_km'] is num) ? (a['distance_km'] as num).toDouble() : 999.0;
        final dB = (b['distance_km'] is num) ? (b['distance_km'] as num).toDouble() : 999.0;
        return dA.compareTo(dB);
      });
    } else if (filterIndex == 2) {
      // Available (ICU beds desc)
      list.sort((a, b) {
        final bA = (a['icu_beds_available'] is num) ? (a['icu_beds_available'] as num).toInt() : 0;
        final bB = (b['icu_beds_available'] is num) ? (b['icu_beds_available'] as num).toInt() : 0;
        return bB.compareTo(bA);
      });
    } else {
      // Recommended (by rank / score)
      list.sort((a, b) {
        final rA = (a['rank'] is num) ? (a['rank'] as num).toInt() : 99;
        final rB = (b['rank'] is num) ? (b['rank'] as num).toInt() : 99;
        return rA.compareTo(rB);
      });
    }
    return list;
  }

  Map<String, dynamic>? get _selectedHospital {
    if (hospitals.isEmpty) return null;
    if (selectedHospitalId == null) return hospitals.first;
    try {
      return hospitals.firstWhere(
        (h) => (h['hospital_id']?.toString() ?? h['id']?.toString()) == selectedHospitalId,
        orElse: () => hospitals.first,
      );
    } catch (_) {
      return hospitals.first;
    }
  }

  Future<void> _useHospital(Map<String, dynamic> hospital) async {
    final id = hospital['hospital_id']?.toString() ?? hospital['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => selectingHospitalId = id);
    try {
      final assigned = await api.post('/emergencies/${widget.emergencyId}/assign-hospital', {
        'hospital_id': id,
        'gst_number': hospital['gst_number'],
      });
      if (!mounted) return;
      setState(() => selectingHospitalId = null);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HospitalNavigationPage(
            emergencyId: widget.emergencyId,
            hospital: hospital,
            assignedEmergency: Map<String, dynamic>.from(assigned),
            initialSeverity: widget.initialSeverity,
          ),
        ),
      );
      if (mounted) setState(() => selectingHospitalId = null);
    } catch (e) {
      if (mounted) {
        setState(() => selectingHospitalId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final conditionText = (emergency?['condition']?.toString() ??
            (hospitals.isNotEmpty ? hospitals.first['condition']?.toString() : null) ??
            'Cardiac')
        .replaceAll('_', ' ');
    final severityText = (emergency?['severity']?.toString() ?? widget.initialSeverity).toUpperCase();

    final sortedList = _sortedHospitals;
    final selectedHospital = _selectedHospital;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Color(0xFF0F172A),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Select Destination Hospital',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Hospitals are recommended based on patient condition, specialty and ETA.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content Body
            Expanded(
              child: loading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF2563EB)),
                          SizedBox(height: 12),
                          Text(
                            'Matching best specialized hospitals…',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: SurfaceCard(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.location_off_rounded,
                                    color: AppTheme.red,
                                    size: 42,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: AppTheme.muted),
                                  ),
                                  const SizedBox(height: 12),
                                  PrimaryButton(
                                    label: 'Retry',
                                    icon: Icons.refresh_rounded,
                                    outlined: true,
                                    background: AppTheme.blue,
                                    onPressed: load,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                          children: [
                            // Patient Condition Card (matches reference image)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1F2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFFECDD3),
                                  width: 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFEF4444),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.monitor_heart_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Patient Condition',
                                          style: TextStyle(
                                            color: Color(0xFF0F172A),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$severityText • $conditionText',
                                          style: const TextStyle(
                                            color: Color(0xFFDC2626),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Filter Tabs: Recommended, Nearest, Available
                            Row(
                              children: [
                                _buildFilterTab(0, 'Recommended'),
                                const SizedBox(width: 8),
                                _buildFilterTab(1, 'Nearest'),
                                const SizedBox(width: 8),
                                _buildFilterTab(2, 'Available'),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Hospital Cards
                            if (sortedList.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: const Center(
                                  child: Text(
                                    'No hospitals found within range. Please expand range or retry.',
                                    style: TextStyle(color: Color(0xFF64748B)),
                                  ),
                                ),
                              )
                            else
                              ...sortedList.map((h) => _buildHospitalCard(h)),
                          ],
                        ),
            ),

            // Bottom Sticky "Proceed to Navigation >" Action Bar
            if (!loading && sortedList.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFF1F5F9), width: 1.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x0C0F172A),
                      blurRadius: 16,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selectedHospital != null && selectingHospitalId == null
                        ? () => _useHospital(selectedHospital)
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0A2540),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          selectingHospitalId != null
                              ? 'Opening navigation…'
                              : 'Proceed to Navigation',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTab(int index, String label) {
    final isSelected = filterIndex == index;
    return GestureDetector(
      onTap: () => setState(() => filterIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0A2540) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF64748B),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildHospitalCard(Map<String, dynamic> h) {
    final id = h['hospital_id']?.toString() ?? h['id']?.toString() ?? '';
    final isSelected = selectedHospitalId == id;
    final isBestMatch = (h['rank'] == 1 || h['is_top_match'] == true);
    final hospitalName = h['hospital_name']?.toString() ?? 'Hospital';
    final distance = h['distance_km']?.toString() ?? '—';
    final eta = _eta(h);
    final icuBeds = h['icu_beds_available'] ?? 3;
    final o2Cylinders = h['oxygen_cylinders_available'] ?? 14;

    return GestureDetector(
      onTap: () => setState(() => selectedHospitalId = id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? const Color(0x142563EB) : const Color(0x06000000),
              blurRadius: isSelected ? 12 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Thumbnail, Title + Best Match Badge, Distance • ETA, Radio Button
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildHospitalThumbnail(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              hospitalName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (isBestMatch) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Best Match',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$distance km  •  $eta',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Radio Button
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1),
                      width: isSelected ? 2.0 : 1.5,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2563EB),
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),

            // Divider line
            Container(
              height: 1,
              color: const Color(0xFFF1F5F9),
              margin: const EdgeInsets.symmetric(vertical: 12),
            ),

            // Bottom stats row: ICU Beds and O2 Cylinders
            Row(
              children: [
                const Icon(
                  Icons.bed_rounded,
                  size: 16,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Text(
                  '$icuBeds ICU Beds',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 20),
                const Icon(
                  Icons.air_rounded,
                  size: 16,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Text(
                  '$o2Cylinders O₂ Cylinders',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHospitalThumbnail() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDBEAFE)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Sky gradient
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFBAE6FD), Color(0xFFE0F2FE)],
                ),
              ),
            ),
            // Modern building graphic
            Positioned(
              bottom: 0,
              child: Container(
                width: 38,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A8A),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(
                        3,
                        (_) => Container(
                          width: 6,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFF93C5FD),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(
                        3,
                        (_) => Container(
                          width: 6,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFF93C5FD),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Red cross on roof
            Positioned(
              top: 4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add,
                  size: 10,
                  color: Color(0xFFDC2626),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _eta(Map<String, dynamic> h) {
    final raw = h['duration_seconds'];
    return raw is num ? '${(raw / 60).ceil()} min ETA' : 'ETA unavailable';
  }
}
