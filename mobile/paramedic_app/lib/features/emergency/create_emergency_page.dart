import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/services/location_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../hospitals/hospital_selection_page.dart';

class CreateEmergencyPage extends StatefulWidget {
  const CreateEmergencyPage({super.key});
  @override
  State<CreateEmergencyPage> createState() => _CreateEmergencyPageState();
}

class _CreateEmergencyPageState extends State<CreateEmergencyPage> {
  final name = TextEditingController();
  final age = TextEditingController();
  final notes = TextEditingController();
  final api = ApiClient();
  final location = LocationService();

  String severity = 'HIGH';
  String sex = 'Male';
  String blood = 'Unknown';
  String condition = 'CARDIAC';
  double? lat;
  double? lng;
  bool loading = false;
  bool locating = false;
  String? message;

  static const conditions = <String, String>{
    'CARDIAC': 'Cardiac / Heart',
    'STROKE': 'Stroke / Neurological',
    'TRAUMA': 'Major Trauma',
    'BROKEN_RIBS': 'Broken Ribs',
    'SPINAL_INJURY': 'Spinal Injury',
    'RESPIRATORY': 'Respiratory',
    'BURNS': 'Burns',
    'OTHER': 'Other',
  };

  @override
  void initState() {
    super.initState();
    locate();
  }

  Future<void> locate() async {
    setState(() => locating = true);
    try {
      final p = await location.currentPosition();
      if (!mounted) return;
      setState(() {
        lat = p.latitude;
        lng = p.longitude;
      });
    } catch (e) {
      if (mounted && lat == null) {
        setState(() {
          lat = 12.9239;
          lng = 77.6111;
        });
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> create() async {
    if (lat == null || lng == null) await locate();
    if (lat == null || lng == null) {
      lat = 12.9239;
      lng = 77.6111;
    }
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final result = await api.post('/emergencies/', {
        'patient': {
          'full_name': name.text.trim().isEmpty ? null : name.text.trim(),
          'age': int.tryParse(age.text.trim()),
          'sex': sex,
          'blood_group': blood,
          'medical_notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        },
        'condition': condition,
        'severity': severity,
        'pickup_latitude': lat,
        'pickup_longitude': lng,
      });
      final id = result['id']?.toString();
      if (id == null) throw Exception('Emergency was created without an id.');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HospitalSelectionPage(
            emergencyId: id,
            initialSeverity: severity,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => message = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create Emergency Response',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                const PageHeader(
                  eyebrow: 'Clinical triage & intake',
                  title: 'Patient Profile',
                  subtitle: 'Provide patient condition and vitals for hospital capacity matching.',
                ),
                const SizedBox(height: 16),

                // Patient Details
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Patient Information',
                        style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'Patient full name (optional)',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 340;
                          return isNarrow
                              ? Column(
                                  children: [
                                    TextField(
                                      controller: age,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Age (years)',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<String>(
                                      initialValue: sex,
                                      decoration: const InputDecoration(labelText: 'Sex / Gender'),
                                      items: const ['Male', 'Female', 'Other', 'Unknown']
                                          .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                                          .toList(),
                                      onChanged: (v) => setState(() => sex = v ?? sex),
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: age,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Age (years)',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: sex,
                                        decoration: const InputDecoration(labelText: 'Sex / Gender'),
                                        items: const ['Male', 'Female', 'Other', 'Unknown']
                                            .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                                            .toList(),
                                        onChanged: (v) => setState(() => sex = v ?? sex),
                                      ),
                                    ),
                                  ],
                                );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Clinical Profile
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Clinical Condition',
                        style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Select the primary clinical presentation for immediate specialist triage:',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: conditions.entries.map((e) {
                          final selected = condition == e.key;
                          return ChoiceChip(
                            label: Text(e.value),
                            selected: selected,
                            onSelected: (_) => setState(() => condition = e.key),
                            selectedColor: AppTheme.blue.withValues(alpha: .18),
                            labelStyle: TextStyle(
                              color: selected ? AppTheme.blue : AppTheme.muted,
                              fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                              fontSize: 13,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: selected ? AppTheme.blue : const Color(0xFFE2E8F0),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: severity,
                              decoration: const InputDecoration(labelText: 'Severity Level'),
                              items: const ['HIGH', 'MEDIUM', 'LOW']
                                  .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                                  .toList(),
                              onChanged: (v) => setState(() => severity = v ?? severity),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: blood,
                              decoration: const InputDecoration(labelText: 'Blood Group'),
                              items: const ['Unknown', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                                  .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                                  .toList(),
                              onChanged: (v) => setState(() => blood = v ?? blood),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notes,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Clinical Observations / Notes (Optional)',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Live GPS Location
                SurfaceCard(
                  gradient: const [Color(0xFFEAF8FF), Colors.white],
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.blue.withValues(alpha: .11),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(Icons.gps_fixed_rounded, color: AppTheme.blue),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Live Pickup Location',
                              style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                            Text(
                              lat == null
                                  ? 'Acquiring GPS location…'
                                  : '${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}',
                              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: locating ? null : locate,
                        icon: const Icon(Icons.my_location_rounded, size: 16),
                        label: Text(locating ? '…' : 'Locate'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                PrimaryButton(
                  label: loading ? 'Creating Emergency…' : 'Create Emergency',
                  icon: Icons.bolt_rounded,
                  background: AppTheme.red,
                  onPressed: loading ? null : create,
                ),

                if (message != null) ...[
                  const SizedBox(height: 14),
                  SurfaceCard(
                    child: Text(
                      message!,
                      style: const TextStyle(color: AppTheme.red, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    name.dispose();
    age.dispose();
    notes.dispose();
    super.dispose();
  }
}
