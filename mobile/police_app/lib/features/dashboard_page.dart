import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../core/app_api.dart';
import '../core/audio_buzzer.dart';
import '../core/luxury_theme.dart';
import 'profile_page.dart';

class PoliceDashboardPage extends StatefulWidget {
  final Future<void> Function() onLogout;
  const PoliceDashboardPage({super.key, required this.onLogout});
  @override
  State<PoliceDashboardPage> createState() => _PoliceDashboardPageState();
}

class _PoliceDashboardPageState extends State<PoliceDashboardPage> {
  final api = AppApi();
  final MapController _mapController = MapController();
  Timer? pollTimer;
  Timer? routeTimer;
  Timer? junctionTimer;
  Timer? buzzerTimer;
  Timer? clockTimer;
  StreamSubscription<Position>? locationSubscription;

  Map<String, dynamic> board = {};
  Map<String, dynamic>? routeData;
  String? selectedEmergencyId;
  List<Map<String, dynamic>> nearbyJunctions = [];
  bool fetchingJunctions = false;
  DateTime? junctionsUpdated;

  bool loading = true;
  bool busy = false;
  bool onDuty = true;
  String? error;
  double? myLat;
  double? myLon;

  bool _hasLoadedInitialBoard = false;
  Set<String> _knownNotificationKeys = <String>{};
  final Set<String> _dismissedEmergencyIds = <String>{};
  final Set<String> _selectedHistoryIds = <String>{};

  // Filter & Sort State: 'ACTIVE', 'ACKNOWLEDGED', 'CLEARED', 'HISTORY'
  String activeFilter = 'ACTIVE';
  String sortOrder = 'NEWEST'; // 'NEWEST' or 'OLDEST'
  String timeFilter = 'ALL'; // 'ALL', 'TODAY', 'THIS_MONTH'

  OverlayEntry? _noticeEntry;
  Timer? _noticeTimer;

  List<Map<String, dynamic>> _list(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList()
      : <Map<String, dynamic>>[];

  Map<String, dynamic>? get officer =>
      board['officer'] is Map ? Map<String, dynamic>.from(board['officer']) : null;

  List<Map<String, dynamic>> get allAlerts =>
      _list(board['alerts']).where((a) => !_dismissedEmergencyIds.contains(a['emergency_id']?.toString() ?? '')).toList();

  List<Map<String, dynamic>> get junctions => _list(board['junctions']);

  bool _isCompletedAlert(Map<String, dynamic> item) {
    if (item['traffic_cleared'] == true) return true;
    final status = (item['status'] ?? item['emergency_status'] ?? '').toString().toUpperCase();
    return const {'ARRIVED', 'COMPLETED', 'CLOSED', 'CANCELLED', 'RESOLVED'}.contains(status);
  }

  // Active counts for the 4 hero cards
  int get activeCount => allAlerts.where((a) => !_isCompletedAlert(a)).length;
  int get ackCount => allAlerts.where((a) => a['police_acknowledged'] == true).length;
  int get clearedCount => allAlerts.where((a) => a['traffic_cleared'] == true).length;
  int get historyCount => allAlerts.where(_isCompletedAlert).length;

  List<Map<String, dynamic>> get displayedAlerts {
    var list = allAlerts.where((a) {
      final completed = _isCompletedAlert(a);
      switch (activeFilter) {
        case 'ACTIVE':
          return !completed;
        case 'ACKNOWLEDGED':
          return a['police_acknowledged'] == true && !completed;
        case 'CLEARED':
          return a['traffic_cleared'] == true;
        case 'HISTORY':
          return completed;
        default:
          return !completed;
      }
    }).toList();

    final now = DateTime.now();
    if (timeFilter != 'ALL') {
      list = list.where((a) {
        final rawDate = a['alert_created_at'] ?? a['created_at'];
        if (rawDate == null) return true;
        final d = DateTime.tryParse(rawDate.toString())?.toLocal();
        if (d == null) return true;
        if (timeFilter == 'TODAY') {
          return d.year == now.year && d.month == now.month && d.day == now.day;
        } else if (timeFilter == 'THIS_MONTH') {
          return d.year == now.year && d.month == now.month;
        }
        return true;
      }).toList();
    }

    list.sort((a, b) {
      final aDate = DateTime.tryParse((a['alert_created_at'] ?? a['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse((b['alert_created_at'] ?? b['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return sortOrder == 'OLDEST' ? aDate.compareTo(bDate) : bDate.compareTo(aDate);
    });

    return list;
  }

  Map<String, dynamic>? get selected {
    for (final item in displayedAlerts) {
      if (item['emergency_id']?.toString() == selectedEmergencyId) return item;
    }
    return displayedAlerts.isEmpty ? null : displayedAlerts.first;
  }

  @override
  void initState() {
    super.initState();
    _load();
    pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
    routeTimer = Timer.periodic(const Duration(seconds: 20), (_) => _loadRoute());
    junctionTimer = Timer.periodic(const Duration(minutes: 1), (_) => _loadNearbyJunctions(force: true));
    clockTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
    _startLocation();
  }

  Future<void> _load() async {
    try {
      final raw = await api.get('/coordination/police/board');
      if (!mounted || raw is! Map) return;
      final next = Map<String, dynamic>.from(raw);
      final allNextAlerts = _list(next['alerts']);
      final nextAlerts = allNextAlerts
          .where((a) => !_dismissedEmergencyIds.contains(a['emergency_id']?.toString() ?? ''))
          .toList();

      final incomingNotificationKeys = <String>{};
      for (final alert in nextAlerts) {
        final emergencyKey = alert['emergency_id']?.toString();
        if (emergencyKey == null) continue;
        incomingNotificationKeys.add('$emergencyKey:alert');
        final relayKey = alert['relay_notification_id']?.toString();
        if (relayKey != null && relayKey.isNotEmpty) {
          incomingNotificationKeys.add('$emergencyKey:relay:$relayKey');
        }
      }

      final newNotificationKeys = _hasLoadedInitialBoard
          ? incomingNotificationKeys.difference(_knownNotificationKeys)
          : <String>{};
      _knownNotificationKeys = incomingNotificationKeys;
      _hasLoadedInitialBoard = true;

      String? id = selectedEmergencyId;
      if (id == null || !nextAlerts.any((e) => e['emergency_id']?.toString() == id)) {
        id = nextAlerts.isEmpty ? null : nextAlerts.first['emergency_id']?.toString();
      }

      final profile =
          next['officer'] is Map ? Map<String, dynamic>.from(next['officer']) : <String, dynamic>{};

      setState(() {
        board = next;
        selectedEmergencyId = id;
        onDuty = profile['duty_status'] == 'ON_DUTY';
        loading = false;
        error = null;
        if (myLat == null && profile['current_latitude'] is num && profile['current_longitude'] is num) {
          myLat = (profile['current_latitude'] as num).toDouble();
          myLon = (profile['current_longitude'] as num).toDouble();
        }
      });

      if (newNotificationKeys.isNotEmpty) {
        _buzzNewAlert();
        final newAlertItem = nextAlerts.firstWhere(
          (a) =>
              newNotificationKeys.contains('${a['emergency_id']}:alert') ||
              newNotificationKeys.any((k) => k.startsWith('${a['emergency_id']}:')),
          orElse: () => nextAlerts.first,
        );
        _showIncomingAlertMessageDialog(newAlertItem);
      }
      if (myLat != null && junctionsUpdated == null) _loadNearbyJunctions();
      if (id != null && (routeData == null || routeData!['emergency_id']?.toString() != id)) {
        await _loadRoute();
      }
    } catch (e) {
      if (mounted) setState(() {
        loading = false;
        error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _buzzNewAlert() {
    buzzerTimer?.cancel();
    unawaited(AudioBuzzer.playAlert());
    var repeatsRemaining = 2;
    buzzerTimer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (!mounted || repeatsRemaining == 0) {
        timer.cancel();
        buzzerTimer = null;
        return;
      }
      repeatsRemaining--;
      unawaited(AudioBuzzer.playAlert());
    });
  }

  Future<void> _loadRoute() async {
    final id = selectedEmergencyId ?? selected?['emergency_id']?.toString();
    if (id == null) {
      if (mounted) setState(() => routeData = null);
      return;
    }
    try {
      final raw = await api.get('/coordination/emergencies/$id/route');
      if (mounted && raw is Map) setState(() => routeData = Map<String, dynamic>.from(raw));
    } catch (_) {}
  }

  Future<void> _startLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _sendLocation(current);
      await _loadNearbyJunctions(force: true);
      locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
      ).listen((p) => _sendLocation(p), onError: (_) {});
    } catch (_) {}
  }

  Future<void> _sendLocation(Position p) async {
    if (!mounted) return;
    setState(() {
      myLat = p.latitude;
      myLon = p.longitude;
    });
    try {
      await api.put('/coordination/police/location', {'latitude': p.latitude, 'longitude': p.longitude});
    } catch (_) {}
  }

  Future<void> _loadNearbyJunctions({bool force = false}) async {
    if (fetchingJunctions || myLat == null || myLon == null) return;
    fetchingJunctions = true;
    try {
      final raw = await api.get('/coordination/police/junctions/nearby?latitude=$myLat&longitude=$myLon');
      if (mounted && raw is List) {
        setState(() {
          nearbyJunctions = raw.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
          junctionsUpdated = DateTime.now();
        });
      }
    } catch (_) {} finally {
      fetchingJunctions = false;
    }
  }

  Future<void> _assignJunction(Map<String, dynamic> junction) async {
    if (myLat == null || myLon == null) {
      _toast('Enable location to assign a nearby junction.', LuxuryTheme.amber);
      return;
    }
    try {
      await api.put('/coordination/police/location', {
        'latitude': myLat,
        'longitude': myLon,
        'junction_name': junction['name']?.toString() ?? 'Traffic junction',
        'junction_latitude': junction['latitude'],
        'junction_longitude': junction['longitude'],
      });
      _toast('Assigned to ${junction['name']}.', LuxuryTheme.green);
      await _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red);
    }
  }

  Future<void> _toggleDuty(bool value) async {
    if (!value && onDuty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Go Off-Duty / Offline?'),
          content: const Text(
            'Are you sure you want to go offline? While offline, live emergency dispatches, junction arrival ETAs, and active ambulance routes will not be displayed on your dashboard.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.amber),
              child: const Text('Confirm Offline'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => busy = true);
    try {
      await api.put('/coordination/police/duty', {'on_duty': value});
      setState(() => onDuty = value);
      await _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _action(String suffix, String success, {String? emergencyId}) async {
    final id = emergencyId ?? selected?['emergency_id']?.toString();
    if (id == null) return;
    setState(() => busy = true);
    try {
      await api.post('/coordination/police/emergencies/$id/$suffix', {});
      _toast(success, LuxuryTheme.green);
      await _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _relay({Map<String, dynamic>? alert}) async {
    final item = alert ?? selected;
    if (item == null) return;
    final selfId = officer?['id']?.toString();
    final candidates = junctions
        .where((j) => j['officer_id']?.toString() != selfId && (j['latitude'] is num) && (j['longitude'] is num))
        .toList();
    if (candidates.isEmpty) {
      _toast('No other on-duty junction officer with a known location is available.', LuxuryTheme.amber);
      return;
    }
    String? target = candidates.first['officer_id']?.toString();
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Relay to next junction'),
          content: DropdownButtonFormField<String>(
            initialValue: target,
            isExpanded: true,
            items: candidates
                .map((j) => DropdownMenuItem(
                      value: j['officer_id'].toString(),
                      child: Text('${j['junction_name']} • ${j['badge_number']}'),
                    ))
                .toList(),
            onChanged: (v) => setDialog(() => target = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, target), child: const Text('Relay alert')),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    setState(() => busy = true);
    try {
      await api.post('/coordination/police/emergencies/${item['emergency_id']}/relay', {
        'target_officer_id': chosen,
        'note': 'Prepare traffic clearance ahead of the ambulance.',
      });
      _toast('Alert relayed to the next junction.', LuxuryTheme.green);
      await _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // Active alert dismissal (moves to history)
  Future<void> _dismissAlert(Map<String, dynamic> item) async {
    final id = item['emergency_id']?.toString();
    if (id == null || id.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move to History?'),
        content: const Text(
          'This moves the active response out of the active dispatch view and saves it to the History cache.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.navy),
            child: const Text('Move to History'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      _dismissedEmergencyIds.add(id);
      if (selectedEmergencyId == id) {
        selectedEmergencyId = null;
        routeData = null;
      }
    });
    _toast('Moved to History cache.', LuxuryTheme.green);
  }

  // History permanent delete (deletes from database AND cache)
  Future<void> _deletePermanently(Map<String, dynamic> item) async {
    final id = item['emergency_id']?.toString();
    if (id == null || id.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Permanently from Database?'),
        content: const Text(
          'This will permanently delete this emergency clearance alert and all officer dispatch history from the database as well as device history cache.\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.red),
            child: const Text('Delete from Database'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => busy = true);
    try {
      await api.delete('/coordination/police/emergencies/$id');
      setState(() {
        _dismissedEmergencyIds.add(id);
        if (selectedEmergencyId == id) {
          selectedEmergencyId = null;
          routeData = null;
        }
      });
      _toast('Permanently deleted from database and cache.', LuxuryTheme.green);
      await _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // Batch delete multiple emergency alerts from database and cache
  Future<void> _batchDeleteHistory() async {
    if (_selectedHistoryIds.isEmpty) return;
    final count = _selectedHistoryIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.delete_forever_rounded, color: LuxuryTheme.red, size: 24),
            SizedBox(width: 8),
            Text('Delete Selected Dispatches?'),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete $count selected emergency clearance records from both the database and the device history cache?\n\nThis action cannot be undone.',
          style: const TextStyle(color: LuxuryTheme.muted, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogCtx, true),
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: Text('Delete $count Records'),
            style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.red),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => busy = true);
      try {
        final idsList = _selectedHistoryIds.toList();
        await api.post('/coordination/police/emergencies/batch-delete', {'emergency_ids': idsList});
        setState(() {
          _dismissedEmergencyIds.addAll(_selectedHistoryIds);
          if (_selectedHistoryIds.contains(selectedEmergencyId)) {
            selectedEmergencyId = null;
            routeData = null;
          }
          _selectedHistoryIds.clear();
        });
        _toast('$count emergency dispatches permanently deleted.', LuxuryTheme.green);
        await _load();
      } catch (e) {
        _toast('Batch delete failed: ${e.toString().replaceFirst("Exception: ", "")}', LuxuryTheme.red);
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
  }

  // Batch move active/acknowledged/cleared alerts to History cache
  Future<void> _batchArchiveActiveAlerts() async {
    if (_selectedHistoryIds.isEmpty) return;
    final count = _selectedHistoryIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.archive_outlined, color: LuxuryTheme.blue, size: 24),
            SizedBox(width: 8),
            Text('Move Selected to History?'),
          ],
        ),
        content: Text(
          'Move $count active emergency responses to the History cache? They will be preserved in History view.',
          style: const TextStyle(color: LuxuryTheme.muted, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogCtx, true),
            icon: const Icon(Icons.archive_rounded, size: 16),
            label: Text('Move $count to History'),
            style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.blue),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        _dismissedEmergencyIds.addAll(_selectedHistoryIds);
        if (_selectedHistoryIds.contains(selectedEmergencyId)) {
          selectedEmergencyId = null;
          routeData = null;
        }
        _selectedHistoryIds.clear();
      });
      _toast('$count alerts moved to History cache.', LuxuryTheme.blue);
      await _load();
    }
  }



  void _showIncomingAlertMessageDialog(Map<String, dynamic> alert) {
    final ambNumber = alert['ambulance_number']?.toString() ?? 'Ambulance';
    final hospital = alert['hospital_name']?.toString() ?? 'Assigned Hospital';
    final severity = alert['severity']?.toString() ?? 'HIGH';
    final condition = alert['condition']?.toString() ?? 'Emergency';
    final junctionEta = _duration(alert['junction_eta_seconds']);
    final id = alert['emergency_id']?.toString() ?? '';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: LuxuryTheme.red.withValues(alpha: .12), shape: BoxShape.circle),
              child: const Icon(Icons.emergency_rounded, color: LuxuryTheme.red, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🚨 INCOMING DISPATCH ALERT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: LuxuryTheme.red)),
                  Text('Paramedic informed police command', style: TextStyle(color: LuxuryTheme.muted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: LuxuryTheme.red.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: LuxuryTheme.red.withValues(alpha: .2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ambulance $ambNumber is approaching your junction!',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: LuxuryTheme.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Please prepare to clear traffic along the route towards $hospital.',
                    style: const TextStyle(color: LuxuryTheme.muted, fontSize: 12),
                  ),
                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Junction ETA: $junctionEta', style: const TextStyle(fontWeight: FontWeight.w800, color: LuxuryTheme.blue, fontSize: 12)),
                      Text('Severity: $severity', style: const TextStyle(fontWeight: FontWeight.w800, color: LuxuryTheme.red, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Condition: $condition', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Dismiss', style: TextStyle(color: LuxuryTheme.muted)),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogCtx);
              setState(() {
                selectedEmergencyId = id;
                activeFilter = 'ACTIVE';
              });
              _action('acknowledge', 'Alert acknowledged.', emergencyId: id);
            },
            icon: const Icon(Icons.check_circle_rounded, size: 16),
            label: const Text('Acknowledge Now'),
            style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.green),
          ),
        ],
      ),
    );
  }

  Widget _filterCard({
    required String filterKey,
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = activeFilter == filterKey;

    return InkWell(
      onTap: () {
        setState(() {
          activeFilter = filterKey;
          selectedEmergencyId = null;
          routeData = null;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: .30), blurRadius: 10, offset: const Offset(0, 4))]
              : const [BoxShadow(color: Color(0x0F000000), blurRadius: 4)],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? color : LuxuryTheme.muted,
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
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

  LatLng _point(dynamic lat, dynamic lon, {LatLng? fallback}) =>
      lat is num && lon is num ? LatLng(lat.toDouble(), lon.toDouble()) : fallback ?? const LatLng(12.9716, 77.5946);

  List<LatLng> _routePoints() {
    final raw = routeData?['polyline_points'];
    if (raw is! List) return [];
    return raw
        .whereType<List>()
        .where((e) => e.length >= 2 && e[0] is num && e[1] is num)
        .map((e) => LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble()))
        .toList();
  }

  Widget _map() {
    final s = selected;
    final center = s != null
        ? _point(s['ambulance_latitude'], s['ambulance_longitude'],
            fallback: myLat == null ? null : LatLng(myLat!, myLon!))
        : (myLat != null ? LatLng(myLat!, myLon!) : const LatLng(12.9716, 77.5946));
    final route = _routePoints();
    final markers = <Marker>[];
    if (s != null) {
      markers.add(Marker(
        point: _point(s['ambulance_latitude'], s['ambulance_longitude']),
        width: 48,
        height: 48,
        child: const _MapMarker(icon: Icons.emergency_rounded, color: LuxuryTheme.red),
      ));
      if (s['hospital_latitude'] is num && s['hospital_longitude'] is num) {
        markers.add(Marker(
          point: _point(s['hospital_latitude'], s['hospital_longitude']),
          width: 44,
          height: 44,
          child: const _MapMarker(icon: Icons.local_hospital_rounded, color: LuxuryTheme.green),
        ));
      }
    }
    for (final j in junctions) {
      if (j['latitude'] is num && j['longitude'] is num) {
        markers.add(Marker(
          point: _point(j['latitude'], j['longitude']),
          width: 38,
          height: 38,
          child: const _MapMarker(icon: Icons.traffic_rounded, color: LuxuryTheme.blue, small: true),
        ));
      }
      if (j['current_latitude'] is num && j['current_longitude'] is num) {
        markers.add(Marker(
          point: _point(j['current_latitude'], j['current_longitude']),
          width: 34,
          height: 34,
          child: const _MapMarker(icon: Icons.local_police_rounded, color: LuxuryTheme.cyan, small: true),
        ));
      }
    }
    for (final j in nearbyJunctions) {
      if (j['latitude'] is num && j['longitude'] is num) {
        markers.add(Marker(
          point: _point(j['latitude'], j['longitude']),
          width: 32,
          height: 32,
          child: const _MapMarker(icon: Icons.traffic_rounded, color: LuxuryTheme.amber, small: true),
        ));
      }
    }
    if (myLat != null && myLon != null) {
      markers.add(Marker(
        point: LatLng(myLat!, myLon!),
        width: 40,
        height: 40,
        child: const _MapMarker(icon: Icons.person_pin_circle_rounded, color: LuxuryTheme.cyan, small: true),
      ));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 330,
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: center, initialZoom: 12),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.rescupath.police',
            ),
            if (route.length > 1)
              PolylineLayer(polylines: [Polyline(points: route, strokeWidth: 5, color: LuxuryTheme.blue)]),
            if (route.isEmpty && s != null && s['hospital_latitude'] is num)
              PolylineLayer(polylines: [
                Polyline(
                  points: [center, _point(s['hospital_latitude'], s['hospital_longitude'])],
                  strokeWidth: 3,
                  color: LuxuryTheme.blue,
                )
              ]),
            MarkerLayer(markers: markers),
            RichAttributionWidget(attributions: const [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
      ),
    );
  }

  // Offline Full Screen Component
  Widget _buildOfflineState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: CommandCard(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: LuxuryTheme.amber.withValues(alpha: .15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.power_settings_new_rounded, color: LuxuryTheme.amber, size: 44),
                ),
                const SizedBox(height: 20),
                const Text(
                  'OFFICER OFFLINE',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: LuxuryTheme.ink,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'You are currently marked off duty. Emergency dispatches, incoming ambulance corridors, and junction traffic clearance alerts are hidden while offline.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: LuxuryTheme.muted, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: busy ? null : () => _toggleDuty(true),
                  icon: const Icon(Icons.radar_rounded, size: 20),
                  label: const Text(
                    'Go Online (On Duty)',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: LuxuryTheme.green,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1E36),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E3A8A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: onDuty ? LuxuryTheme.green : LuxuryTheme.amber,
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
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = selected;
    final off = officer ?? {};
    final list = displayedAlerts;

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
                          // App Bar / Officer Command Header
                          Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: LuxuryTheme.blue,
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: const Icon(Icons.shield_rounded, color: Colors.white, size: 25),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'RescuPath Police',
                                      style: TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 17),
                                    ),
                                    Text(
                                      '${off['station_name'] ?? 'Police Command'} • ${off['junction_name'] ?? 'Junction not assigned'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              // Online / Offline Indicator Pill
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: (onDuty ? LuxuryTheme.green : LuxuryTheme.amber).withValues(alpha: .10),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.circle, color: onDuty ? LuxuryTheme.green : LuxuryTheme.amber, size: 8),
                                    const SizedBox(width: 6),
                                    Text(
                                      onDuty ? 'On duty' : 'Off duty',
                                      style: TextStyle(
                                        color: onDuty ? LuxuryTheme.green : LuxuryTheme.amber,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              _buildLiveTimeBadge(),
                              const SizedBox(width: 10),
                              Switch(
                                value: onDuty,
                                onChanged: busy ? null : _toggleDuty,
                                activeThumbColor: LuxuryTheme.green,
                              ),
                              // Test Alert Buzzer Sound Button
                              IconButton(
                                tooltip: 'Test Alert Buzzer Sound',
                                onPressed: () {
                                  unawaited(AudioBuzzer.playAlert());
                                  unawaited(SystemSound.play(SystemSoundType.alert));
                                  HapticFeedback.vibrate();
                                  _toast('Alert buzzer sound triggered.', LuxuryTheme.blue);
                                },
                                icon: const Icon(Icons.notifications_active_rounded, color: LuxuryTheme.amber, size: 24),
                              ),
                              // Profile Page Button
                              IconButton(
                                tooltip: 'Officer Profile',
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PoliceProfilePage(
                                        officer: off,
                                        onDuty: onDuty,
                                        onToggleDuty: (v) => setState(() => onDuty = v),
                                        onRefresh: _load,
                                        onLogout: widget.onLogout,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.account_circle_rounded, color: LuxuryTheme.ink, size: 26),
                              ),
                              IconButton(
                                tooltip: 'Refresh',
                                onPressed: _load,
                                icon: const Icon(Icons.refresh_rounded, color: LuxuryTheme.ink),
                              ),
                              IconButton(
                                tooltip: 'Sign out',
                                onPressed: widget.onLogout,
                                icon: const Icon(Icons.logout_rounded, color: LuxuryTheme.ink),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // If Offline: Show clean offline screen and hide all dispatches
                          if (!onDuty)
                            _buildOfflineState()
                          else ...[
                            // Hero Command Banner with 4 Clickable Metric Filter Cards
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(26),
                                gradient: const LinearGradient(
                                  colors: [LuxuryTheme.navy, Color(0xFF1A3B69)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: const [
                                  BoxShadow(color: Color(0x220A1930), blurRadius: 22, offset: Offset(0, 8)),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: const [
                                          Text(
                                            'Ambulance Corridor Command',
                                            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Clear traffic corridors. Save emergency response lives.',
                                            style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 17),
                                  // Clickable 4-card Hero Filter Matrix
                                  LayoutBuilder(builder: (context, constraints) {
                                    final width = constraints.maxWidth >= 650
                                        ? (constraints.maxWidth - 24) / 4
                                        : (constraints.maxWidth - 8) / 2;
                                    return Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        SizedBox(
                                          width: width,
                                          child: _filterCard(
                                            filterKey: 'ACTIVE',
                                            value: '$activeCount',
                                            label: 'Active',
                                            icon: Icons.sos_rounded,
                                            color: LuxuryTheme.red,
                                          ),
                                        ),
                                        SizedBox(
                                          width: width,
                                          child: _filterCard(
                                            filterKey: 'ACKNOWLEDGED',
                                            value: '$ackCount',
                                            label: 'Acknowledged',
                                            icon: Icons.notifications_active_rounded,
                                            color: LuxuryTheme.green,
                                          ),
                                        ),
                                        SizedBox(
                                          width: width,
                                          child: _filterCard(
                                            filterKey: 'CLEARED',
                                            value: '$clearedCount',
                                            label: 'Traffic cleared',
                                            icon: Icons.traffic_rounded,
                                            color: LuxuryTheme.blue,
                                          ),
                                        ),
                                        SizedBox(
                                          width: width,
                                          child: _filterCard(
                                            filterKey: 'HISTORY',
                                            value: '$historyCount',
                                            label: 'History (Completed)',
                                            icon: Icons.history_rounded,
                                            color: LuxuryTheme.navy,
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),

                            if (error != null) ...[
                              const SizedBox(height: 12),
                              _error(error!),
                            ],

                            const SizedBox(height: 18),

                            // Sort Order & Time Filter Controls
                            Row(
                              children: [
                                Text(
                                  'Filter: $activeFilter (${list.length})',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: LuxuryTheme.ink),
                                ),
                                const Spacer(),
                                // Time Filter dropdown
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0x220A1930)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: timeFilter,
                                      isDense: true,
                                      style: const TextStyle(color: LuxuryTheme.ink, fontSize: 11, fontWeight: FontWeight.w700),
                                      items: const [
                                        DropdownMenuItem(value: 'ALL', child: Text('All Time')),
                                        DropdownMenuItem(value: 'TODAY', child: Text('Today')),
                                        DropdownMenuItem(value: 'THIS_MONTH', child: Text('This Month')),
                                      ],
                                      onChanged: (v) => setState(() => timeFilter = v ?? 'ALL'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Sort Order button
                                IconButton(
                                  tooltip: sortOrder == 'NEWEST' ? 'Sorted by Newest' : 'Sorted by Oldest',
                                  icon: Icon(
                                    sortOrder == 'NEWEST' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                    size: 18,
                                    color: LuxuryTheme.ink,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      sortOrder = sortOrder == 'NEWEST' ? 'OLDEST' : 'NEWEST';
                                    });
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Alerts Panel + Incident Map
                            LayoutBuilder(builder: (context, constraints) {
                              final alertsPanel = Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (list.isEmpty)
                                    CommandCard(
                                      child: Column(
                                        children: [
                                          Icon(
                                            activeFilter == 'HISTORY'
                                                ? Icons.history_rounded
                                                : Icons.verified_user_outlined,
                                            size: 40,
                                            color: LuxuryTheme.green,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            activeFilter == 'HISTORY'
                                                ? 'No completed emergency history'
                                                : 'No active police alerts in this view',
                                            style: const TextStyle(fontWeight: FontWeight.w900, color: LuxuryTheme.ink),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            activeFilter == 'HISTORY'
                                                ? 'Completed and cleared emergencies will be preserved here.'
                                                : 'When a paramedic requests traffic assistance, the incident appears here.',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(color: LuxuryTheme.muted, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    )
                                  else ...[
                                    if (list.isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        margin: const EdgeInsets.only(bottom: 12),
                                        decoration: BoxDecoration(
                                          color: (activeFilter == 'HISTORY' ? LuxuryTheme.navy : LuxuryTheme.blue).withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: LuxuryTheme.line),
                                        ),
                                        child: Row(
                                          children: [
                                            Text(
                                              _selectedHistoryIds.isEmpty
                                                  ? '${list.length} total • ${activeFilter == "HISTORY" ? "Archived Dispatches" : "Active Alerts"}'
                                                  : '${_selectedHistoryIds.length} of ${list.length} selected',
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: LuxuryTheme.ink),
                                            ),
                                            const Spacer(),
                                            if (_selectedHistoryIds.isNotEmpty) ...[
                                              if (activeFilter == 'HISTORY')
                                                FilledButton.icon(
                                                  onPressed: _batchDeleteHistory,
                                                  icon: const Icon(Icons.delete_forever_rounded, size: 15),
                                                  label: Text('Delete (${_selectedHistoryIds.length})'),
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: LuxuryTheme.red,
                                                    foregroundColor: Colors.white,
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                  ),
                                                )
                                              else
                                                FilledButton.icon(
                                                  onPressed: _batchArchiveActiveAlerts,
                                                  icon: const Icon(Icons.archive_outlined, size: 15),
                                                  label: Text('Move to History (${_selectedHistoryIds.length})'),
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: LuxuryTheme.blue,
                                                    foregroundColor: Colors.white,
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                  ),
                                                ),
                                              const SizedBox(width: 10),
                                            ],
                                            // Circle button at the right corner to toggle select all
                                            Builder(
                                              builder: (_) {
                                                final listIds = list
                                                    .map((item) => item['emergency_id']?.toString() ?? '')
                                                    .where((id) => id.isNotEmpty)
                                                    .toSet();
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
                                                            ? (activeFilter == 'HISTORY' ? LuxuryTheme.navy : LuxuryTheme.blue)
                                                            : Colors.transparent,
                                                        border: Border.all(
                                                          color: isAllSelected
                                                              ? (activeFilter == 'HISTORY' ? LuxuryTheme.navy : LuxuryTheme.blue)
                                                              : LuxuryTheme.muted.withValues(alpha: 0.5),
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
                                    ],
                                    ...list.map((a) => Padding(
                                          padding: const EdgeInsets.only(bottom: 10),
                                          child: _alertCard(a, selectedEmergencyId == a['emergency_id']),
                                        )),
                                  ],
                                ],
                              );

                              final mapPanel = Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Live incident map',
                                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: LuxuryTheme.ink),
                                        ),
                                      ),
                                      Text(
                                        myLat == null ? 'GPS unavailable' : 'GPS live',
                                        style: const TextStyle(color: LuxuryTheme.muted, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 9),
                                  _map(),
                                  if (s != null) ...[
                                    const SizedBox(height: 10),
                                    CommandCard(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.emergency_rounded, color: LuxuryTheme.red),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  '${s['ambulance_number'] ?? 'Ambulance'} • ${s['severity'] ?? 'HIGH'}',
                                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: LuxuryTheme.ink),
                                                ),
                                              ),
                                              _status(s['status']?.toString() ?? 'ACTIVE'),
                                            ],
                                          ),
                                          const SizedBox(height: 7),
                                          Text(
                                            '${s['condition'] ?? 'Emergency'} • ${s['hospital_name'] ?? 'Hospital pending'}',
                                            style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(child: _info('JUNCTION ETA', _duration(s['junction_eta_seconds']))),
                                              Expanded(child: _info('DISTANCE', s['junction_distance_km'] == null ? '—' : '${s['junction_distance_km']} km')),
                                              Expanded(child: _info('HOSPITAL ETA', _duration(s['eta_seconds']))),
                                            ],
                                          ),
                                          const SizedBox(height: 13),
                                          Row(
                                            children: [
                                              Icon(
                                                s['police_acknowledged'] == true ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                                                color: s['police_acknowledged'] == true ? LuxuryTheme.green : LuxuryTheme.amber,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 7),
                                              Expanded(
                                                child: Text(
                                                  s['traffic_cleared'] == true
                                                      ? 'Traffic clearance recorded'
                                                      : s['police_acknowledged'] == true
                                                          ? 'Acknowledged • assistance in progress'
                                                          : 'Waiting for officer acknowledgement',
                                                  style: TextStyle(
                                                    color: s['traffic_cleared'] == true ? LuxuryTheme.green : LuxuryTheme.ink,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (s['police_acknowledged'] == true)
                                            const Padding(
                                              padding: EdgeInsets.only(top: 8),
                                              child: Text('✓ Police acknowledgement recorded',
                                                  style: TextStyle(color: LuxuryTheme.green, fontWeight: FontWeight.w800, fontSize: 11)),
                                            ),
                                          if (s['traffic_cleared'] == true)
                                            const Padding(
                                              padding: EdgeInsets.only(top: 4),
                                              child: Text('✓ Junction clearance recorded',
                                                  style: TextStyle(color: LuxuryTheme.green, fontWeight: FontWeight.w800, fontSize: 11)),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (nearbyJunctions.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    CommandCard(
                                      padding: const EdgeInsets.all(13),
                                      child: ExpansionTile(
                                        tilePadding: EdgeInsets.zero,
                                        childrenPadding: EdgeInsets.zero,
                                        title: const Text('Nearby mapped junctions',
                                            style: TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 14)),
                                        subtitle: const Text('Assign this officer to a junction',
                                            style: TextStyle(color: LuxuryTheme.muted, fontSize: 10)),
                                        children: nearbyJunctions
                                            .take(8)
                                            .map((j) => ListTile(
                                                  contentPadding: EdgeInsets.zero,
                                                  dense: true,
                                                  leading: const Icon(Icons.traffic_rounded, color: LuxuryTheme.amber),
                                                  title: Text(j['name']?.toString() ?? 'Traffic junction',
                                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                                                  subtitle: Text('${j['junction_type'] ?? 'Junction'} • ${j['distance_km'] ?? '—'} km',
                                                      style: const TextStyle(fontSize: 10)),
                                                  trailing: TextButton(onPressed: () => _assignJunction(j), child: const Text('Assign')),
                                                ))
                                            .toList(),
                                      ),
                                    ),
                                  ],
                                ],
                              );

                              if (constraints.maxWidth >= 1080) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 7, child: alertsPanel),
                                    const SizedBox(width: 18),
                                    Expanded(flex: 5, child: mapPanel),
                                  ],
                                );
                              }
                              return Column(children: [alertsPanel, const SizedBox(height: 18), mapPanel]);
                            }),
                            const SizedBox(height: 15),
                            const Text(
                              'Junction ETAs use available route/location data and are approximate when traffic-aware routing is unavailable. Keep officer GPS enabled while on duty.',
                              style: TextStyle(color: LuxuryTheme.muted, fontSize: 10, height: 1.4),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _alertCard(Map<String, dynamic> a, bool active) {
    final id = a['emergency_id']?.toString() ?? '';
    final completed = _isCompletedAlert(a);
    final inHistory = activeFilter == 'HISTORY' || completed;
    return InkWell(
      onTap: inHistory
          ? () {
              if (id.isEmpty) return;
              setState(() {
                if (_selectedHistoryIds.contains(id)) {
                  _selectedHistoryIds.remove(id);
                } else {
                  _selectedHistoryIds.add(id);
                }
              });
            }
          : () async {
              setState(() {
                selectedEmergencyId = id;
                routeData = null;
              });
              await _loadRoute();
              final lat = a['ambulance_latitude'];
              final lon = a['ambulance_longitude'];
              if (mounted && lat is num && lon is num) {
                _mapController.move(LatLng(lat.toDouble(), lon.toDouble()), 13);
              }
            },
      borderRadius: BorderRadius.circular(20),
      child: CommandCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: _selectedHistoryIds.contains(id),
                  activeColor: activeFilter == 'HISTORY' ? LuxuryTheme.navy : LuxuryTheme.blue,
                  onChanged: (bool? val) {
                    if (id.isEmpty) return;
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
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: (completed ? LuxuryTheme.green : active ? LuxuryTheme.red : LuxuryTheme.blue).withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    completed ? Icons.task_alt_rounded : Icons.emergency_rounded,
                    color: completed ? LuxuryTheme.green : active ? LuxuryTheme.red : LuxuryTheme.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${a['ambulance_number'] ?? 'Ambulance'} • ${a['severity'] ?? 'HIGH'}',
                        style: const TextStyle(fontWeight: FontWeight.w900, color: LuxuryTheme.ink, fontSize: 13),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${a['condition'] ?? 'Emergency'} • ${a['hospital_name'] ?? 'Hospital pending'}',
                        style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a['relayed_to_me'] == true
                            ? 'RELAYED TO YOUR JUNCTION • ETA ${_duration(a['junction_eta_seconds'])}'
                            : 'Junction ETA ${_duration(a['junction_eta_seconds'])} • hospital ETA ${_duration(a['eta_seconds'])}',
                        style: TextStyle(
                          color: a['relayed_to_me'] == true ? LuxuryTheme.amber : LuxuryTheme.blue,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                // Delete / Dismiss Action
                if (completed || activeFilter == 'HISTORY')
                  IconButton(
                    tooltip: 'Permanently delete from database & cache',
                    onPressed: () => _deletePermanently(a),
                    icon: const Icon(Icons.delete_forever_rounded, color: LuxuryTheme.red),
                  )
                else
                  IconButton(
                    tooltip: 'Move to History cache',
                    onPressed: () => _dismissAlert(a),
                    icon: const Icon(Icons.archive_outlined, color: LuxuryTheme.muted),
                  ),
              ],
            ),
            if (!completed) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : () => _action('acknowledge', 'Alert acknowledged.', emergencyId: id),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
                    label: const Text('Acknowledge'),
                    style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.green, visualDensity: VisualDensity.compact),
                  ),
                  FilledButton.icon(
                    onPressed: busy ? null : () => _relay(alert: a),
                    icon: const Icon(Icons.forward_to_inbox_rounded, size: 17),
                    label: const Text('Relay to junction'),
                    style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.blue, visualDensity: VisualDensity.compact),
                  ),
                  FilledButton.icon(
                    onPressed: busy ? null : () => _action('clear', 'Junction marked clear.', emergencyId: id),
                    icon: const Icon(Icons.traffic_rounded, size: 17),
                    label: const Text('Traffic cleared'),
                    style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.navy, visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Operation completed • Saved in History.',
                  style: TextStyle(color: LuxuryTheme.green, fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _info(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: LuxuryTheme.muted, fontSize: 8, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: LuxuryTheme.ink, fontSize: 12, fontWeight: FontWeight.w900)),
        ],
      );

  Widget _status(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: LuxuryTheme.red.withValues(alpha: .09), borderRadius: BorderRadius.circular(99)),
        child: Text(text.replaceAll('_', ' '),
            style: const TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w900, fontSize: 9)),
      );

  Widget _error(String text) => CommandCard(
        child: Text(text, style: const TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w700)),
      );

  String _duration(dynamic raw) =>
      raw is num ? (raw < 60 ? '${raw.round()} sec' : '${(raw / 60).ceil()} min') : '—';

  void _toast(String text, Color color) {
    if (!mounted) return;
    _noticeTimer?.cancel();
    _noticeEntry?.remove();
    final screenWidth = MediaQuery.of(context).size.width;
    _noticeEntry = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + 14,
        right: 16,
        width: screenWidth < 420 ? screenWidth - 32 : 360,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x330A1930), blurRadius: 20, offset: Offset(0, 8))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_noticeEntry!);
    _noticeTimer = Timer(const Duration(seconds: 5), () {
      _noticeEntry?.remove();
      _noticeEntry = null;
      _noticeTimer = null;
    });
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _noticeEntry?.remove();
    pollTimer?.cancel();
    routeTimer?.cancel();
    junctionTimer?.cancel();
    buzzerTimer?.cancel();
    clockTimer?.cancel();
    locationSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }
}

class _MapMarker extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool small;
  const _MapMarker({required this.icon, required this.color, this.small = false});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x2A0A1930), blurRadius: 12)],
        ),
        child: Icon(icon, color: Colors.white, size: small ? 17 : 24),
      );
}
