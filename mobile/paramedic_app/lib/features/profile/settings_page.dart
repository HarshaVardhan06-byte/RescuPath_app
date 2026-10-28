import 'package:flutter/material.dart';

import '../../core/services/user_preferences.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final api = ApiClient();
  bool duty = true; bool notifications = true; bool highGps = true; bool autoRefresh = true; bool loading = true;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { duty = await UserPreferences.dutyMode; notifications = await UserPreferences.notificationsEnabled; highGps = await UserPreferences.highAccuracyGps; autoRefresh = await UserPreferences.autoRouteRefresh; if (mounted) setState(() => loading = false); }

  @override Widget build(BuildContext c) => Scaffold(appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w900))), body: loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(18), children: [
    const PageHeader(eyebrow: 'Controls', title: 'Response settings', subtitle: 'These controls are stored securely on this device and affect the live paramedic workflow.'),
    const SizedBox(height: 16),
    SurfaceCard(child: Column(children: [
      _switch(Icons.badge_rounded, 'Duty mode', 'Sync responder and ambulance availability', duty, (v) async { await UserPreferences.setDutyMode(v); try { await api.put('/auth/duty', {'enabled': v}); if (mounted) setState(() => duty = v); } catch (e) { if (mounted) { setState(() => duty = !v); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); } } }),
      const Divider(height: 1),
      _switch(Icons.notifications_active_rounded, 'Notifications', 'Allow in-app response alerts', notifications, (v) async { await UserPreferences.setNotificationsEnabled(v); setState(() => notifications = v); }),
      const Divider(height: 1),
      _switch(Icons.gps_fixed_rounded, 'High-accuracy GPS', 'Use higher location accuracy for navigation', highGps, (v) async { await UserPreferences.setHighAccuracyGps(v); setState(() => highGps = v); }),
      const Divider(height: 1),
      _switch(Icons.sync_rounded, 'Auto route refresh', 'Refresh the route periodically while en route', autoRefresh, (v) async { await UserPreferences.setAutoRouteRefresh(v); setState(() => autoRefresh = v); }),
    ])),
    const SizedBox(height: 14),
    SurfaceCard(gradient: const [Color(0xFFEFF7FF), Colors.white], child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.info_outline_rounded, color: AppTheme.blue), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [Text('Operational note', style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900)), SizedBox(height: 4), Text('High-accuracy GPS is recommended for real emergency navigation. Device permissions and OS location settings still control availability.', style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35))]))])) ,
  ]));

  Widget _switch(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: AppTheme.blue.withValues(alpha: .08), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: AppTheme.blue)), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w800)), Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 10))])), Switch.adaptive(value: value, onChanged: onChanged)]));
}
