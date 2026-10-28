import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/services/location_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../hospitals/hospital_selection_page.dart';

class CreateEmergencyPage extends StatefulWidget { const CreateEmergencyPage({super.key}); @override State<CreateEmergencyPage> createState() => _CreateEmergencyPageState(); }

class _CreateEmergencyPageState extends State<CreateEmergencyPage> {
  final name = TextEditingController(); final age = TextEditingController(); final notes = TextEditingController(); final api = ApiClient(); final location = LocationService();
  String severity = 'HIGH'; String sex = 'Male'; String blood = 'Unknown'; String condition = 'OTHER'; double? lat; double? lng; bool loading = false; bool locating = false; String? message;
  static const conditions = <String, String>{'CARDIAC': 'Cardiac / Heart', 'STROKE': 'Stroke / Neurological', 'TRAUMA': 'Major Trauma', 'BROKEN_RIBS': 'Broken Ribs', 'SPINAL_INJURY': 'Spinal Injury', 'RESPIRATORY': 'Respiratory', 'BURNS': 'Burns', 'OTHER': 'Other'};

  Future<void> locate() async { setState(() => locating = true); try { final p = await location.currentPosition(); if (!mounted) return; setState(() { lat = p.latitude; lng = p.longitude; }); } catch (e) { if (mounted) setState(() => message = e.toString().replaceFirst('Exception: ', '')); } finally { if (mounted) setState(() => locating = false); } }

  Future<void> create() async {
    if (lat == null || lng == null) await locate();
    if (lat == null || lng == null) return;
    setState(() { loading = true; message = null; });
    try {
      final result = await api.post('/emergencies/', {'patient': {'full_name': name.text.trim().isEmpty ? null : name.text.trim(), 'age': int.tryParse(age.text.trim()), 'sex': sex, 'blood_group': blood, 'medical_notes': notes.text.trim().isEmpty ? null : notes.text.trim()}, 'condition': condition, 'severity': severity, 'pickup_latitude': lat, 'pickup_longitude': lng});
      final id = result['id']?.toString(); if (id == null) throw Exception('Emergency was created without an id.');
      if (!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HospitalSelectionPage(emergencyId: id, initialSeverity: severity)));
    } catch (e) { if (mounted) setState(() => message = e.toString().replaceFirst('Exception: ', '')); } finally { if (mounted) setState(() => loading = false); }
  }

  @override Widget build(BuildContext c) => Scaffold(appBar: AppBar(title: const Text('New Emergency', style: TextStyle(fontWeight: FontWeight.w900))), body: ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 30), children: [
    const PageHeader(eyebrow: 'Emergency intake', title: 'Start a response', subtitle: 'Capture only the information needed for dispatch and hospital matching.'),
    const SizedBox(height: 16),
    SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Patient details', style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900, fontSize: 16)), const SizedBox(height: 12), TextField(controller: name, decoration: const InputDecoration(labelText: 'Patient name (optional)', prefixIcon: Icon(Icons.person_outline))), const SizedBox(height: 10), Row(children: [Expanded(child: TextField(controller: age, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Age', prefixIcon: Icon(Icons.cake_outlined)))), const SizedBox(width: 10), Expanded(child: DropdownButtonFormField<String>(initialValue: sex, decoration: const InputDecoration(labelText: 'Sex'), items: const ['Male', 'Female', 'Other', 'Unknown'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: (v) => setState(() => sex = v ?? sex)))])])) ,
    const SizedBox(height: 12),
    SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Clinical profile', style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900, fontSize: 16)), const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: conditions.entries.map((e) => ChoiceChip(label: Text(e.value), selected: condition == e.key, onSelected: (_) => setState(() => condition = e.key), selectedColor: AppTheme.blue.withValues(alpha: .18), labelStyle: TextStyle(color: condition == e.key ? AppTheme.blue : AppTheme.muted, fontWeight: FontWeight.w800))).toList()), const SizedBox(height: 12), DropdownButtonFormField<String>(initialValue: severity, decoration: const InputDecoration(labelText: 'Severity'), items: const ['HIGH', 'MEDIUM', 'LOW'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: (v) => setState(() => severity = v ?? severity)), const SizedBox(height: 10), DropdownButtonFormField<String>(initialValue: blood, decoration: const InputDecoration(labelText: 'Blood group'), items: const ['Unknown', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: (v) => setState(() => blood = v ?? blood)), const SizedBox(height: 10), TextField(controller: notes, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Medical notes / observations', alignLabelWithHint: true))])),
    const SizedBox(height: 12),
    SurfaceCard(gradient: const [Color(0xFFEAF8FF), Colors.white], child: Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(color: AppTheme.blue.withValues(alpha: .11), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.gps_fixed_rounded, color: AppTheme.blue)), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Live pickup location', style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900)), Text(lat == null ? 'Location is required before dispatch.' : '${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}', style: const TextStyle(color: AppTheme.muted, fontSize: 11))])), TextButton.icon(onPressed: locating ? null : locate, icon: const Icon(Icons.my_location_rounded), label: Text(locating ? '…' : 'Locate'))])),
    const SizedBox(height: 14),
    PrimaryButton(label: loading ? 'Creating emergency…' : 'Create emergency', icon: Icons.bolt_rounded, background: AppTheme.red, onPressed: loading ? null : create),
    if (message != null) Padding(padding: const EdgeInsets.only(top: 12), child: SurfaceCard(child: Text(message!, style: const TextStyle(color: AppTheme.red, fontWeight: FontWeight.w700)))),
  ]),);

  @override void dispose() { name.dispose(); age.dispose(); notes.dispose(); super.dispose(); }
}
