import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/services/location_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

class AmbulancePage extends StatefulWidget {
  const AmbulancePage({super.key});
  @override
  State<AmbulancePage> createState() => _AmbulancePageState();
}

class _AmbulancePageState extends State<AmbulancePage> {
  final api = ApiClient();
  final locationService = LocationService();
  Map<String, dynamic>? ambulance;
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await api.get('/ambulances/mine');
      if (mounted && r is List && r.isNotEmpty) {
        setState(() => ambulance = Map<String, dynamic>.from(r.first));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openEditDialog() async {
    if (ambulance == null) return;
    int fuelVal = (ambulance?['fuel_percentage'] as num?)?.toInt() ?? 85;
    String statusVal = ambulance?['status']?.toString() ?? 'AVAILABLE';
    final latCtrl = TextEditingController(text: '${ambulance?['current_latitude'] ?? 12.9716}');
    final lonCtrl = TextEditingController(text: '${ambulance?['current_longitude'] ?? 77.5946}');
    int o2Val = (ambulance?['oxygen_cylinders'] as num?)?.toInt() ?? 2;
    final notesCtrl = TextEditingController(text: ambulance?['equipment_notes']?.toString() ?? 'Full Trauma & Oxygen Kit Configured');
    bool detectingGps = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppTheme.line,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.blue.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.local_shipping_rounded, color: AppTheme.blue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ambulance?['vehicle_number']?.toString() ?? 'Ambulance Unit',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppTheme.ink),
                          ),
                          const Text('Edit Telemetry & Vehicle Readiness', style: TextStyle(color: AppTheme.muted, fontSize: 11)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // Operational Status
                const Text('OPERATIONAL STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.muted, letterSpacing: 0.6)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['AVAILABLE', 'ON_CALL', 'REFUELING', 'MAINTENANCE'].map((st) {
                    final sel = statusVal == st;
                    final color = st == 'AVAILABLE' ? AppTheme.green : st == 'ON_CALL' ? AppTheme.blue : st == 'REFUELING' ? AppTheme.amber : AppTheme.red;
                    return ChoiceChip(
                      label: Text(st.replaceAll('_', ' '), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: sel ? Colors.white : AppTheme.ink)),
                      selected: sel,
                      selectedColor: color,
                      onSelected: (val) {
                        if (val) setModalState(() => statusVal = st);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Fuel Level Controller
                Row(
                  children: [
                    const Icon(Icons.local_gas_station_rounded, color: AppTheme.green, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('FUEL LEVEL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.muted, letterSpacing: 0.6)),
                    ),
                    Text('$fuelVal% (~${(fuelVal * 4.2).round()} km)', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppTheme.green)),
                  ],
                ),
                Slider(
                  value: fuelVal.toDouble(),
                  min: 5,
                  max: 100,
                  divisions: 19,
                  activeColor: fuelVal > 30 ? AppTheme.green : AppTheme.red,
                  onChanged: (v) => setModalState(() => fuelVal = v.round()),
                ),
                const SizedBox(height: 12),

                // Active GPS Coordinates
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: AppTheme.blue, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('ACTIVE GPS LOCATION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.muted, letterSpacing: 0.6)),
                    ),
                    TextButton.icon(
                      onPressed: detectingGps ? null : () async {
                        setModalState(() => detectingGps = true);
                        try {
                          final pos = await locationService.currentPosition();
                          latCtrl.text = pos.latitude.toStringAsFixed(5);
                          lonCtrl.text = pos.longitude.toStringAsFixed(5);
                          _toast('Device GPS captured: ${latCtrl.text}, ${lonCtrl.text}', AppTheme.green);
                        } catch (e) {
                          _toast('Could not read device GPS: $e', AppTheme.red);
                        } finally {
                          setModalState(() => detectingGps = false);
                        }
                      },
                      icon: detectingGps ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location_rounded, size: 14),
                      label: const Text('Use Device GPS', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: TextField(controller: latCtrl, decoration: const InputDecoration(labelText: 'Latitude', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: lonCtrl, decoration: const InputDecoration(labelText: 'Longitude', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)))),
                  ],
                ),
                const SizedBox(height: 16),

                // Medical Equipment & Oxygen
                Row(
                  children: [
                    const Icon(Icons.gas_meter_outlined, color: AppTheme.purple, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('PORTABLE O₂ CYLINDERS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.muted, letterSpacing: 0.6)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      onPressed: o2Val > 0 ? () => setModalState(() => o2Val--) : null,
                    ),
                    Text('$o2Val', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.ink)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      onPressed: () => setModalState(() => o2Val++),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Equipment & Trauma Readiness Notes',
                    hintText: 'e.g. Ventilator & AED configured, Full trauma kit ready',
                  ),
                ),
                const SizedBox(height: 22),

                // Save button
                PrimaryButton(
                  label: saving ? 'Saving...' : 'Save & Update Telemetry',
                  icon: Icons.save_rounded,
                  background: AppTheme.blue,
                  onPressed: saving ? null : () async {
                    final nav = Navigator.of(context);
                    setState(() => saving = true);
                    try {
                      final lat = double.tryParse(latCtrl.text);
                      final lon = double.tryParse(lonCtrl.text);
                      final updated = await api.put('/ambulances/mine', {
                        'fuel_percentage': fuelVal,
                        'status': statusVal,
                        'current_latitude': lat,
                        'current_longitude': lon,
                        'oxygen_cylinders': o2Val,
                        'equipment_notes': notesCtrl.text.trim(),
                      });
                      if (mounted) {
                        setState(() {
                          ambulance = Map<String, dynamic>.from(updated);
                        });
                        nav.pop();
                        _toast('Ambulance details & telemetry updated.', AppTheme.green);
                      }
                    } catch (e) {
                      _toast(e.toString().replaceFirst('Exception: ', ''), AppTheme.red);
                    } finally {
                      if (mounted) setState(() => saving = false);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toast(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: color, content: Text(text)));
  }

  @override
  Widget build(BuildContext c) {
    final fuel = (ambulance?['fuel_percentage'] as num?)?.toInt() ?? 85;
    final o2 = (ambulance?['oxygen_cylinders'] as num?)?.toInt() ?? 2;
    final equipment = ambulance?['equipment_notes']?.toString() ?? 'Full Trauma & Oxygen Kit Configured';
    final lat = ambulance?['current_latitude'];
    final lon = ambulance?['current_longitude'];
    final gpsText = (lat is num && lon is num) ? '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}' : 'GPS Active';

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Ambulance', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                PageHeader(
                  eyebrow: 'Vehicle',
                  title: 'My ambulance',
                  subtitle: 'Live vehicle status, telemetry, and equipment readiness.',
                ),
                const SizedBox(height: 16),
                SurfaceCard(
                  gradient: const [Color(0xFF0D2342), Color(0xFF173F70)],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: const Color(0x22FFFFFF),
                          image: const DecorationImage(
                            image: AssetImage('assets/ambulance_hero.png'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              ambulance?['vehicle_number']?.toString() ?? 'AMBULANCE',
                              style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900),
                            ),
                          ),
                          StatusChip(
                            (ambulance?['status']?.toString() ?? 'AVAILABLE').replaceAll('_', ' '),
                            color: ambulance?['status'] == 'AVAILABLE' ? AppTheme.green : AppTheme.amber,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SurfaceCard(
                  child: Column(
                    children: [
                      _line(Icons.local_gas_station_rounded, 'Fuel status', '$fuel% capacity (~${(fuel * 4.2).round()} km range)', AppTheme.green),
                      const Divider(height: 1),
                      _line(Icons.location_on_rounded, 'Current location', 'Live GPS ($gpsText)', AppTheme.blue),
                      const Divider(height: 1),
                      _line(Icons.build_circle_outlined, 'Service status', (ambulance?['status']?.toString() ?? 'AVAILABLE').replaceAll('_', ' '), AppTheme.purple),
                      const Divider(height: 1),
                      _line(Icons.medical_services_outlined, 'Emergency equipment', '$o2 O₂ Cylinders • $equipment', AppTheme.red),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Edit Vehicle, Fuel & GPS Details',
                  icon: Icons.edit_note_rounded,
                  background: AppTheme.blue,
                  onPressed: _openEditDialog,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/location'),
                  icon: const Icon(Icons.map_rounded),
                  label: const Text('View live GPS map'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _line(IconData i, String a, String b, Color color) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(13)),
          child: Icon(i, color: color),
        ),
        title: Text(a, style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w800)),
        subtitle: Text(b, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      );
}
