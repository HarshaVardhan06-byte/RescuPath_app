import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../emergency/create_emergency_page.dart';
import '../emergency/active_emergency_page.dart';
import '../profile/profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  final api = ApiClient();
  Map<String, dynamic> summary = {};
  Timer? _clockTimer;
  Timer? _summaryTimer;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildLiveTimeBadge() {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final min = now.minute.toString().padLeft(2, '0');
    final sec = now.second.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]} ${now.year}';
    final timeStr = '$hour:$min:$sec $ampm';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1E36),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E3A8A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF22C55E),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE  $timeStr • $dateStr',
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> load() async {
    try {
      final r = await api.get('/dashboard/summary');
      if (mounted) setState(() => summary = Map<String, dynamic>.from(r));
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    load();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _summaryTimer = Timer.periodic(const Duration(seconds: 10), (_) => load());
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _summaryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _home(),
      const _EmergencyList(),
      const ProfilePage(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: tab, children: pages)),
      bottomNavigationBar: BottomNav(index: tab, onTap: (i) => setState(() => tab = i)),
    );
  }

  Widget _home() => RefreshIndicator(
        onRefresh: load,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = MediaQuery.sizeOf(context).width;
            final circleSize = (screenWidth * 0.56).clamp(190.0, 240.0);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 18),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        const Text(
                                          'READY FOR RESPONSE',
                                          style: TextStyle(
                                            color: AppTheme.blue,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.4,
                                          ),
                                        ),
                                        _buildLiveTimeBadge(),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '$_greeting, ${summary['user_name'] ?? 'Paramedic'}',
                                      style: const TextStyle(
                                        color: AppTheme.ink,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        height: 1.15,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const StatusChip(
                                      'ON DUTY • DISPATCH UNIT ACTIVE',
                                      color: AppTheme.green,
                                    ),
                                  ],
                                ),
                              ),
                              AppIconButton(
                                icon: Icons.notifications_none_rounded,
                                tooltip: 'Notifications',
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  '/notifications',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 36),

                          // Large prominent round circle button: Create an Emergency / SOS
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFFDC2626).withValues(alpha: .28),
                                      width: 3.0,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFDC2626).withValues(alpha: .14),
                                        blurRadius: 48,
                                        spreadRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const CreateEmergencyPage(),
                                        ),
                                      ),
                                      customBorder: const CircleBorder(),
                                      splashColor: Colors.white.withValues(alpha: .28),
                                      highlightColor: Colors.white.withValues(alpha: .18),
                                      child: Ink(
                                        width: circleSize,
                                        height: circleSize,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: const LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color(0xFFEF4444),
                                              Color(0xFFDC2626),
                                              Color(0xFF991B1B),
                                            ],
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFDC2626).withValues(alpha: .48),
                                              blurRadius: 32,
                                              offset: const Offset(0, 12),
                                            ),
                                            BoxShadow(
                                              color: const Color(0xFFDC2626).withValues(alpha: .24),
                                              blurRadius: 64,
                                              spreadRadius: 6,
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.emergency_rounded,
                                              size: 58,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(height: 10),
                                            // Highlighted pill badge
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(22),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Color(0x33000000),
                                                    blurRadius: 8,
                                                    offset: Offset(0, 3),
                                                  ),
                                                ],
                                              ),
                                              child: const Text(
                                                'CREATE AN EMERGENCY',
                                                style: TextStyle(
                                                  color: Color(0xFFDC2626),
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 12,
                                                  letterSpacing: 1.3,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            const Text(
                                              'CREATE SOS',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 22,
                                                letterSpacing: 2.0,
                                                shadows: [
                                                  Shadow(
                                                    color: Color(0x66000000),
                                                    blurRadius: 4,
                                                    offset: Offset(0, 1),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              'Tap to dispatch incident',
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: .88),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 36),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x0A000000),
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.green,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'GPS Live • Hospital Network Online • Police Relay Active',
                                        style: TextStyle(
                                          color: AppTheme.ink,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Tap the Emergency tab below at any time to view active responses & history',
                                  style: TextStyle(
                                    color: AppTheme.muted.withValues(alpha: .85),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _EmergencyList extends StatefulWidget {
  const _EmergencyList();
  @override
  State<_EmergencyList> createState() => _EmergencyListState();
}

class _EmergencyListState extends State<_EmergencyList> {
  final api = ApiClient();
  List<dynamic> items = [];
  bool loading = true;
  String? error;
  int emergencyFilter = 0; // 0: Active, 1: History
  final Set<String> _selectedHistoryIds = {};
  final Set<String> _localHistoryIds = {};

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await api.get('/dashboard/emergencies');
      if (mounted) setState(() => items = r is List ? r : []);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Timer? _listClockTimer;
  Timer? _listPollTimer;

  @override
  void initState() {
    super.initState();
    load();
    _listClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _listPollTimer = Timer.periodic(const Duration(seconds: 10), (_) => load());
  }

  @override
  void dispose() {
    _listClockTimer?.cancel();
    _listPollTimer?.cancel();
    super.dispose();
  }

  bool _isCompleted(Map<String, dynamic> e) {
    final status = (e['status']?.toString() ?? '').toUpperCase();
    final id = e['id']?.toString() ?? '';
    return _localHistoryIds.contains(id) ||
        status == 'COMPLETED' ||
        status == 'RESOLVED' ||
        status == 'CANCELLED';
  }

  Future<void> _confirmCompleteEmergency(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Completion', style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Text(
          'Mark this emergency response as completed and move it to History?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm & Move to History'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await api.post('/emergencies/$id/status', {'status': 'COMPLETED'});
      setState(() {
        _localHistoryIds.add(id);
        _selectedHistoryIds.remove(id);
      });
      _toast('Emergency marked completed and moved to History.', AppTheme.green);
      await load();
    } catch (e) {
      setState(() {
        _localHistoryIds.add(id);
        _selectedHistoryIds.remove(id);
      });
      _toast('Moved to History cache.', AppTheme.green);
    }
  }

  Future<void> _batchArchiveActive() async {
    if (_selectedHistoryIds.isEmpty) return;
    final idsToArchive = List<String>.from(_selectedHistoryIds);
    for (final id in idsToArchive) {
      try {
        await api.post('/emergencies/$id/status', {'status': 'COMPLETED'});
      } catch (_) {}
    }
    setState(() {
      _localHistoryIds.addAll(idsToArchive);
      _selectedHistoryIds.clear();
    });
    _toast('${idsToArchive.length} emergencies moved to History.', AppTheme.green);
    await load();
  }

  Future<void> _batchDeleteHistory() async {
    if (_selectedHistoryIds.isEmpty) return;
    final idsToDelete = List<String>.from(_selectedHistoryIds);
    final count = idsToDelete.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete from Database & Cache?', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Text(
          'Permanently delete $count emergency records from database and cache? This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await api.post('/emergencies/batch-delete', {'emergency_ids': idsToDelete});
      setState(() {
        items.removeWhere((e) => e is Map && idsToDelete.contains(e['id']?.toString()));
        _selectedHistoryIds.clear();
      });
      _toast('${idsToDelete.length} records permanently deleted from database and cache.', AppTheme.red);
      await load();
    } catch (e) {
      for (final id in idsToDelete) {
        try {
          await api.delete('/emergencies/$id');
        } catch (_) {}
      }
      setState(() {
        items.removeWhere((e) => e is Map && idsToDelete.contains(e['id']?.toString()));
        _selectedHistoryIds.clear();
      });
      _toast('Deleted selected history records.', AppTheme.red);
      await load();
    }
  }

  void _toast(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        backgroundColor: bg,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildHeroFilterCard({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : AppTheme.line,
            width: isSelected ? 2.5 : 1.2,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: .25), blurRadius: 10, offset: const Offset(0, 4))]
              : const [BoxShadow(color: Color(0x0A000000), blurRadius: 4)],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    count,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.ink),
                  ),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: isSelected ? color : AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeItems = items.where((e) {
      final map = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
      return !_isCompleted(map);
    }).toList();

    final historyItems = items.where((e) {
      final map = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
      return _isCompleted(map);
    }).toList();

    final displayedList = emergencyFilter == 0 ? activeItems : historyItems;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
      children: [
        const PageHeader(
          eyebrow: 'Response center',
          title: 'Emergencies',
          subtitle: 'Monitor active responses and completed mission history.',
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Create new emergency',
          icon: Icons.add_alert_rounded,
          background: AppTheme.red,
          onPressed: () => Navigator.pushNamed(context, '/emergency'),
        ),
        const SizedBox(height: 16),

        // Hero Section: Active vs History Filter Cards (No circle here)
        Row(
          children: [
            Expanded(
              child: _buildHeroFilterCard(
                title: 'ACTIVE',
                count: '${activeItems.length}',
                icon: Icons.emergency_rounded,
                color: AppTheme.red,
                isSelected: emergencyFilter == 0,
                onTap: () => setState(() => emergencyFilter = 0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildHeroFilterCard(
                title: 'HISTORY',
                count: '${historyItems.length}',
                icon: Icons.history_rounded,
                color: AppTheme.navy,
                isSelected: emergencyFilter == 1,
                onTap: () => setState(() => emergencyFilter = 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (loading)
          const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
        else if (error != null)
          SurfaceCard(
            child: Column(
              children: [
                const Icon(Icons.cloud_off_rounded, color: AppTheme.red, size: 36),
                const SizedBox(height: 10),
                Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)),
                const SizedBox(height: 12),
                TextButton.icon(onPressed: load, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
              ],
            ),
          )
        else if (displayedList.isEmpty)
          SurfaceCard(
            child: Row(
              children: [
                Icon(
                  emergencyFilter == 0 ? Icons.check_circle_outline_rounded : Icons.history_rounded,
                  color: emergencyFilter == 0 ? AppTheme.green : AppTheme.navy,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    emergencyFilter == 0
                        ? 'No active emergencies right now.'
                        : 'No completed emergency history.',
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                ),
              ],
            ),
          )
        else ...[
          // List View Header Toolbar with Right-Corner Circle Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: (emergencyFilter == 0 ? AppTheme.blue : AppTheme.navy).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedHistoryIds.isEmpty
                        ? '${displayedList.length} total • ${emergencyFilter == 0 ? "Active Responses" : "Completed History"}'
                        : '${_selectedHistoryIds.length} of ${displayedList.length} selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.ink),
                  ),
                ),
                const SizedBox(width: 8),
                if (_selectedHistoryIds.isNotEmpty) ...[
                  if (emergencyFilter == 0)
                    FilledButton.icon(
                      onPressed: _batchArchiveActive,
                      icon: const Icon(Icons.archive_outlined, size: 15),
                      label: Text('Move to History (${_selectedHistoryIds.length})'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _batchDeleteHistory,
                      icon: const Icon(Icons.delete_forever_rounded, size: 15),
                      label: Text('Delete (${_selectedHistoryIds.length})'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  const SizedBox(width: 10),
                ],
                // Small Circle toggle button at the right corner
                Builder(
                  builder: (_) {
                    final listIds = displayedList.map((e) {
                      final m = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
                      return m['id']?.toString() ?? '';
                    }).where((id) => id.isNotEmpty).toSet();
                    final isAllSelected = listIds.isNotEmpty && listIds.every(_selectedHistoryIds.contains);
                    return Tooltip(
                      message: isAllSelected ? 'Deselect all' : 'Select all (${listIds.length})',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () {
                          setState(() {
                            if (isAllSelected) {
                              _selectedHistoryIds.removeAll(listIds);
                            } else {
                              _selectedHistoryIds.addAll(listIds);
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isAllSelected
                                ? (emergencyFilter == 0 ? AppTheme.blue : AppTheme.navy)
                                : Colors.transparent,
                            border: Border.all(
                              color: isAllSelected
                                  ? (emergencyFilter == 0 ? AppTheme.blue : AppTheme.navy)
                                  : AppTheme.muted.withValues(alpha: 0.5),
                              width: 2,
                            ),
                          ),
                          child: isAllSelected
                              ? const Icon(Icons.check, size: 15, color: Colors.white)
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          ...displayedList.map((e) {
            final map = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
            final id = map['id']?.toString() ?? 'unknown';
            final isCompleted = _isCompleted(map);
            final routeLabel = (map['route_label']?.toString().isNotEmpty ?? false)
                ? map['route_label'].toString()
                : '${map["pickup_label"] ?? "Pickup Scene"} → ${map["hospital_name"] ?? "Hospital"}';
            final conditionText = map['condition']?.toString() ?? 'Emergency';
            final severityText = map['severity']?.toString() ?? 'HIGH';
            final statusText = map['status']?.toString() ?? (isCompleted ? 'COMPLETED' : 'DISPATCHED');

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SurfaceCard(
                onTap: isCompleted
                    ? () {
                        setState(() {
                          if (_selectedHistoryIds.contains(id)) {
                            _selectedHistoryIds.remove(id);
                          } else {
                            _selectedHistoryIds.add(id);
                          }
                        });
                      }
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ActiveEmergencyPage(
                              emergencyId: id,
                              initialSeverity: map['severity']?.toString() ?? 'HIGH',
                            ),
                          ),
                        ),
                child: Row(
                  children: [
                    Checkbox(
                      value: _selectedHistoryIds.contains(id),
                      activeColor: emergencyFilter == 0 ? AppTheme.blue : AppTheme.navy,
                      onChanged: (bool? val) {
                        setState(() {
                          if (val == true) {
                            _selectedHistoryIds.add(id);
                          } else {
                            _selectedHistoryIds.remove(id);
                          }
                        });
                      },
                    ),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: (isCompleted ? AppTheme.navy : AppTheme.red).withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isCompleted ? Icons.history_rounded : Icons.emergency_rounded,
                        color: isCompleted ? AppTheme.navy : AppTheme.red,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            routeLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900, fontSize: 14),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$severityText • $conditionText • $statusText',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (!isCompleted) ...[
                      Tooltip(
                        message: 'Confirm Completed & Move to History',
                        child: FilledButton.tonalIcon(
                          onPressed: () => _confirmCompleteEmergency(id),
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                          label: const Text('Complete'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.green.withValues(alpha: 0.12),
                            foregroundColor: AppTheme.green,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    const Icon(Icons.chevron_right_rounded, color: AppTheme.ink),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
