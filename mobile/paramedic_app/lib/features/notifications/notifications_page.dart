import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final api = ApiClient();
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> feed = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final records = await api.get('/dashboard/emergencies');
      final list = records is List ? records : <dynamic>[];
      final next = <Map<String, dynamic>>[];
      for (final item in list.take(5)) {
        if (item is! Map) continue;
        final id = item['id']?.toString();
        if (id == null || id.isEmpty) continue;
        try {
          final events = await api.get('/emergencies/$id/events');
          if (events is List) {
            for (final event in events.take(8)) {
              if (event is Map) {
                final e = Map<String, dynamic>.from(event);
                e['emergency_id'] = id;
                next.add(e);
              }
            }
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        feed = next;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString().replaceFirst('Exception: ', '');
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
        ),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const PageHeader(eyebrow: 'Alerts', title: 'Response feed', subtitle: 'Live emergency events recorded by your RescuPath workspace.'),
            const SizedBox(height: 16),
            if (loading)
              const Center(child: Padding(padding: EdgeInsets.all(36), child: CircularProgressIndicator()))
            else if (error != null)
              SurfaceCard(child: Column(children: [const Icon(Icons.cloud_off_rounded, color: AppTheme.red, size: 36), const SizedBox(height: 10), Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)), const SizedBox(height: 12), TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again'))]))
            else if (feed.isEmpty)
              const SurfaceCard(child: Row(children: [Icon(Icons.check_circle_outline_rounded, color: AppTheme.green), SizedBox(width: 10), Expanded(child: Text('No emergency events to show yet.', style: TextStyle(color: AppTheme.muted))) ]))
            else
              ...feed.map((event) => _event(event)),
          ],
        ),
      );

  Widget _event(Map<String, dynamic> event) {
    final type = event['event_type']?.toString() ?? 'EVENT';
    final payload = event['payload'];
    final detail = payload is Map ? (payload['reason'] ?? payload['message'] ?? payload['hospital_name'] ?? '').toString() : '';
    final created = event['created_at']?.toString() ?? '';
    final color = type.contains('POLICE') ? AppTheme.amber : type.contains('HOSPITAL') ? AppTheme.green : type.contains('LOCATION') ? AppTheme.blue : AppTheme.red;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SurfaceCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(15)), child: Icon(Icons.notifications_active_rounded, color: color)),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(type.replaceAll('_', ' '), style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900, fontSize: 12)), if (detail.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(detail, style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.3))), if (created.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(created.replaceFirst('T', ' '), style: const TextStyle(color: AppTheme.muted, fontSize: 9)))])),
          ],
        ),
      ),
    );
  }
}
