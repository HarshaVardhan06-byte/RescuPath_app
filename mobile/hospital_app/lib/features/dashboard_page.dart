import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/app_api.dart';
import '../core/audio_buzzer.dart';
import '../core/luxury_theme.dart';

class HospitalDashboardPage extends StatefulWidget {
  final Future<void> Function() onLogout;
  const HospitalDashboardPage({super.key, required this.onLogout});
  @override
  State<HospitalDashboardPage> createState() => _HospitalDashboardPageState();
}

class _HospitalDashboardPageState extends State<HospitalDashboardPage> {
  final api = AppApi();
  final MapController _mapController = MapController();

  final icu = TextEditingController(text: '0');
  final erBeds = TextEditingController(text: '0');
  final vents = TextEditingController(text: '0');
  final o2Cylinders = TextEditingController(text: '20');

  final FocusNode _icuFocus = FocusNode();
  final FocusNode _erFocus = FocusNode();
  final FocusNode _ventsFocus = FocusNode();
  final FocusNode _o2Focus = FocusNode();

  Timer? pollTimer;
  Timer? routeTimer;
  Timer? clockTimer;
  Map<String, dynamic> board = {};
  Map<String, dynamic>? routeData;
  String? selectedRequestId;

  bool loading = true;
  bool saving = false;
  bool availabilityDirty = false;
  bool emergencyAvailable = true;
  bool oxygenAvailable = true;
  bool traumaCapable = false;
  bool cardiacCapable = false;
  String? error;

  bool _hasLoadedInitialRequests = false;
  Set<String> _knownRequestIds = <String>{};
  final Set<String> _expandedRequestIds = <String>{};
  final Set<String> _selectedHistoryIds = <String>{};

  // Filter & Sort State
  // Active Filter: 'PENDING', 'ACCEPTED', 'DECLINED', 'HISTORY'
  String activeFilter = 'PENDING';
  String sortOrder = 'NEWEST'; // 'NEWEST' or 'OLDEST'
  String timeFilter = 'ALL'; // 'ALL', 'TODAY', 'THIS_MONTH', 'THIS_YEAR'

  OverlayEntry? _noticeEntry;
  Timer? _noticeTimer;

  List<Map<String, dynamic>> _list(dynamic raw) =>
      raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

  Map<String, dynamic>? get hospital =>
      board['hospital'] is Map ? Map<String, dynamic>.from(board['hospital']) : null;

  List<Map<String, dynamic>> get allRequests => _list(board['requests']);

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // Filtered requests based on activeFilter, timeFilter, and sortOrder
  List<Map<String, dynamic>> get displayedRequests {
    var list = allRequests.where((r) {
      final status = (r['request_status']?.toString() ?? 'REQUESTED').toUpperCase();
      final isDismissed = r['is_dismissed'] == true;
      switch (activeFilter) {
        case 'PENDING':
          return status == 'REQUESTED' && !isDismissed;
        case 'ACCEPTED':
          return status == 'ACCEPTED' && !isDismissed;
        case 'DECLINED':
          return status == 'DECLINED' && !isDismissed;
        case 'HISTORY':
        default:
          return true; // History includes all requests (dismissed, closed, completed, etc.)
      }
    }).toList();

    if (activeFilter != 'PENDING') {
      final now = DateTime.now();
      if (timeFilter != 'ALL') {
        list = list.where((r) {
          final rawDate = r['request_created_at'] ?? r['created_at'];
          if (rawDate == null) return true;
          final d = DateTime.tryParse(rawDate.toString())?.toLocal();
          if (d == null) return true;
          if (timeFilter == 'TODAY') {
            return d.year == now.year && d.month == now.month && d.day == now.day;
          } else if (timeFilter == 'THIS_MONTH') {
            return d.year == now.year && d.month == now.month;
          } else if (timeFilter == 'THIS_YEAR') {
            return d.year == now.year;
          }
          return true;
        }).toList();
      }

      list.sort((a, b) {
        final aDate = DateTime.tryParse((a['request_created_at'] ?? a['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse((b['request_created_at'] ?? b['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        if (sortOrder == 'OLDEST') {
          return aDate.compareTo(bDate);
        } else {
          return bDate.compareTo(aDate);
        }
      });
    }

    return list;
  }

  // Active counts for the 4 filter cards
  int get pendingCount => allRequests.where((r) =>
      (r['request_status']?.toString() ?? 'REQUESTED').toUpperCase() == 'REQUESTED' && r['is_dismissed'] != true).length;

  int get acceptedCount => allRequests.where((r) =>
      (r['request_status']?.toString() ?? '').toUpperCase() == 'ACCEPTED' && r['is_dismissed'] != true).length;

  int get declinedCount => allRequests.where((r) =>
      (r['request_status']?.toString() ?? '').toUpperCase() == 'DECLINED' && r['is_dismissed'] != true).length;

  int get historyCount => allRequests.length;

  bool get hasActiveRequests => allRequests.any((x) {
        final status = (x['request_status'] ?? '').toString().toUpperCase();
        final isDismissed = x['is_dismissed'] == true;
        return !isDismissed && (status == 'REQUESTED' || status == 'ACCEPTED');
      });

  Map<String, dynamic>? get selected {
    final list = displayedRequests;
    for (final r in list) {
      if (r['request_id']?.toString() == selectedRequestId) return r;
    }
    return list.isEmpty ? null : list.first;
  }

  @override
  void initState() {
    super.initState();
    _load();
    pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
    routeTimer = Timer.periodic(const Duration(seconds: 20), (_) => _loadRoute());
    clockTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
  }

  Future<void> _load() async {
    try {
      final raw = await api.get('/coordination/hospital/board');
      if (!mounted || raw is! Map) return;
      final next = Map<String, dynamic>.from(raw);
      final nextRequests = _list(next['requests']);
      final incomingRequestIds =
          nextRequests.map((r) => r['request_id']?.toString()).whereType<String>().toSet();
      final newRequestIds =
          _hasLoadedInitialRequests ? incomingRequestIds.difference(_knownRequestIds) : <String>{};
      _knownRequestIds = incomingRequestIds;
      _hasLoadedInitialRequests = true;

      String? id = selectedRequestId;
      if (id == null || !nextRequests.any((r) => r['request_id']?.toString() == id)) {
        id = nextRequests.isEmpty ? null : nextRequests.first['request_id']?.toString();
      }

      final h = next['hospital'] is Map ? Map<String, dynamic>.from(next['hospital']) : <String, dynamic>{};
      final res = h['resources'] is Map ? Map<String, dynamic>.from(h['resources']) : <String, dynamic>{};

      setState(() {
        board = next;
        selectedRequestId = id;
        if (!availabilityDirty) {
          emergencyAvailable = h['emergency_available'] == true;
          icu.text = '${res['icu_beds_available'] ?? 0}';
          erBeds.text = '${res['emergency_beds_available'] ?? 0}';
          vents.text = '${res['ventilators_available'] ?? 0}';
          o2Cylinders.text = '${res['oxygen_cylinders_available'] ?? 20}';
          oxygenAvailable = res['oxygen_available'] == true;
          traumaCapable = res['trauma_capable'] == true;
          cardiacCapable = res['cardiac_capable'] == true;
        }
        loading = false;
        error = null;
      });

      if (newRequestIds.isNotEmpty) {
        final newest = nextRequests.firstWhere(
            (r) => newRequestIds.contains(r['request_id']?.toString()),
            orElse: () => nextRequests.first);
        _notifyIncomingRequest(newest);
      }
      if (id != null &&
          (routeData == null ||
              routeData!['emergency_id']?.toString() != selected?['emergency_id']?.toString())) {
        await _loadRoute();
      }
    } catch (e) {
      if (mounted) setState(() {
        loading = false;
        error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _notifyIncomingRequest(Map<String, dynamic> request) {
    unawaited(AudioBuzzer.playAlert());
    unawaited(SystemSound.play(SystemSoundType.alert));
    HapticFeedback.vibrate();
    if (!mounted) return;
    final ambulance = request['ambulance_number']?.toString() ?? 'Ambulance';
    final condition = request['condition']?.toString() ?? 'Emergency';
    final eta = _duration(request['eta_seconds']);
    _toast('NEW AMBULANCE REQUEST • $ambulance • $condition • ETA $eta', LuxuryTheme.red);
    _showIncomingAmbulanceMessageDialog(request);
  }

  void _showIncomingAmbulanceMessageDialog(Map<String, dynamic> request) {
    final ambulance = request['ambulance_number']?.toString() ?? 'Ambulance';
    final ambId = request['ambulance_id']?.toString() ?? 'Unknown';
    final condition = request['condition']?.toString() ?? 'Emergency';
    final eta = _duration(request['eta_seconds']);
    final reqId = request['request_id']?.toString() ?? '';

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
              child: const Icon(Icons.local_hospital_rounded, color: LuxuryTheme.red, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🚨 INCOMING AMBULANCE INTIMATION', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: LuxuryTheme.red)),
                  Text('Paramedic informed hospital emergency department', style: TextStyle(color: LuxuryTheme.muted, fontSize: 11)),
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
                    'Ambulance $ambulance is inbound to your hospital!',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: LuxuryTheme.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Please confirm availability for emergency department and ICU intake.',
                    style: const TextStyle(color: LuxuryTheme.muted, fontSize: 12),
                  ),
                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('ETA: $eta', style: const TextStyle(fontWeight: FontWeight.w800, color: LuxuryTheme.blue, fontSize: 13)),
                      Text('ID: $ambId', style: const TextStyle(fontWeight: FontWeight.w800, color: LuxuryTheme.ink, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Patient Condition: $condition', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 12)),
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
                selectedRequestId = reqId;
                activeFilter = 'PENDING';
                _expandedRequestIds.add(reqId);
              });
              _respond('ACCEPTED', request: request);
            },
            icon: const Icon(Icons.check_circle_rounded, size: 16),
            label: const Text('Accept Arrival Immediately'),
            style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.green),
          ),
        ],
      ),
    );
  }

  Future<void> _loadRoute() async {
    final id = selected?['emergency_id']?.toString();
    if (id == null) {
      if (mounted) setState(() => routeData = null);
      return;
    }
    try {
      final raw = await api.get('/coordination/emergencies/$id/route');
      if (mounted && raw is Map) setState(() => routeData = Map<String, dynamic>.from(raw));
    } catch (_) {}
  }

  Future<void> _respond(String decision, {Map<String, dynamic>? request}) async {
    final item = request ?? selected;
    if (item == null) return;
    setState(() => saving = true);
    try {
      if (decision == 'ACCEPTED') {
        final currentIcu = int.tryParse(icu.text) ?? 0;
        final currentO2 = int.tryParse(o2Cylinders.text) ?? 0;
        final nextIcu = currentIcu > 0 ? currentIcu - 1 : 0;
        final nextO2 = currentO2 > 0 ? currentO2 - 1 : 0;
        icu.text = '$nextIcu';
        o2Cylinders.text = '$nextO2';

        await api.put('/coordination/hospital/availability', {
          'emergency_available': emergencyAvailable,
          'icu_beds_available': nextIcu,
          'emergency_beds_available': int.tryParse(erBeds.text) ?? 0,
          'ventilators_available': int.tryParse(vents.text) ?? 0,
          'oxygen_cylinders_available': nextO2,
          'oxygen_available': oxygenAvailable,
          'trauma_capable': traumaCapable,
          'cardiac_capable': cardiacCapable,
        });

        await api.post('/coordination/hospital/requests/${item['request_id']}/respond', {
          'decision': decision,
          'note':
              'Emergency department accepted arrival. 1 ICU Bed and 1 O₂ cylinder reserved. Remaining: $nextIcu ICU beds, $nextO2 O₂ cylinders.'
        });
        _toast('Arrival accepted! 1 ICU bed & 1 O₂ reserved. Remaining: $nextIcu ICU, $nextO2 O₂.',
            LuxuryTheme.green);
      } else {
        await api.post('/coordination/hospital/requests/${item['request_id']}/respond', {
          'decision': decision,
          'note': 'Unable to accept this arrival request at this time.'
        });
        _toast('Request declined. Paramedic response updated.', LuxuryTheme.red);
      }
      await _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  bool _isCompletedRequest(Map<String, dynamic> item) {
    final status = (item['status'] ?? item['emergency_status'] ?? '').toString().toUpperCase();
    return const {'ARRIVED', 'COMPLETED', 'CLOSED', 'CANCELLED', 'RESOLVED'}.contains(status);
  }

  Future<void> _dismissRequest(Map<String, dynamic> item) async {
    final id = item['request_id']?.toString();
    if (id == null || id.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.archive_outlined, color: LuxuryTheme.red, size: 24),
            SizedBox(width: 8),
            Text('Move Ambulance to History?'),
          ],
        ),
        content: const Text(
          'This permanently removes the ambulance from active incoming arrivals and archives it in the hospital database History records. It will never reappear on refresh.',
          style: TextStyle(color: LuxuryTheme.muted, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.archive_rounded, size: 16),
            label: const Text('Archive to History'),
            style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.red),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => saving = true);
    try {
      await api.post('/coordination/hospital/requests/$id/dismiss', {});
      if (selectedRequestId == id) {
        selectedRequestId = null;
        routeData = null;
      }
      _toast('Ambulance archived to History permanently.', LuxuryTheme.green);
      await _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _deleteRequestPermanently(Map<String, dynamic> item) async {
    final id = item['request_id']?.toString();
    if (id == null || id.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.delete_forever_rounded, color: LuxuryTheme.red, size: 24),
            SizedBox(width: 8),
            Text('Permanently Delete from Database?'),
          ],
        ),
        content: const Text(
          'This will permanently delete this emergency availability record and patient intake history from the hospital database and cache.\n\nThis action cannot be undone.',
          style: TextStyle(color: LuxuryTheme.muted, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text('Delete from Database'),
            style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.red),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => saving = true);
    try {
      await api.delete('/coordination/hospital/requests/$id');
      if (selectedRequestId == id) {
        selectedRequestId = null;
        routeData = null;
      }
      _toast('Permanently deleted from database and cache.', LuxuryTheme.green);
      await _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  // Batch delete multiple emergency requests from database and cache
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
            Text('Delete Selected History?'),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete $count selected ambulance arrival records from both the database and the cache?\n\nThis action cannot be undone.',
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
      setState(() => saving = true);
      try {
        final idsList = _selectedHistoryIds.toList();
        await api.post('/coordination/hospital/requests/batch-delete', {'request_ids': idsList});
        if (_selectedHistoryIds.contains(selectedRequestId)) {
          selectedRequestId = null;
          routeData = null;
        }
        _selectedHistoryIds.clear();
        _toast('$count records permanently deleted from database and cache.', LuxuryTheme.green);
        await _load();
      } catch (e) {
        _toast('Batch delete failed: ${e.toString().replaceFirst("Exception: ", "")}', LuxuryTheme.red);
      } finally {
        if (mounted) setState(() => saving = false);
      }
    }
  }

  // Batch archive active/pending/accepted/declined requests to History
  Future<void> _batchArchiveActiveRequests() async {
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
            Text('Archive Selected Requests?'),
          ],
        ),
        content: Text('Are you sure you want to archive $count ambulance requests to the History records?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogCtx, true),
            icon: const Icon(Icons.archive_rounded, size: 16),
            label: Text('Archive $count Requests'),
            style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.blue),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => saving = true);
      try {
        final idsList = _selectedHistoryIds.toList();
        for (final id in idsList) {
          try {
            await api.post('/coordination/hospital/requests/$id/dismiss', {});
          } catch (_) {}
        }
        _selectedHistoryIds.clear();
        _toast('$count requests archived to History.', LuxuryTheme.blue);
        await _load();
      } catch (e) {
        _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red);
      } finally {
        if (mounted) setState(() => saving = false);
      }
    }
  }

  // Patient Intake / Entry handler
  Future<void> _recordIntake(String requestId) async {
    setState(() => saving = true);
    try {
      await api.post('/coordination/hospital/requests/$requestId/intake', {});
      _toast('Patient arrival & intake recorded in hospital database.', LuxuryTheme.green);
      await _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  // Patient Exit / Discharge handler
  Future<void> _recordDischarge(String requestId) async {
    final notesCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.outbox_rounded, color: LuxuryTheme.blue, size: 22),
            SizedBox(width: 8),
            Text('Record Patient Exit / Discharge'),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recording patient discharge saves the exit timestamp to the database and automatically restores 1 ICU Bed and 1 O₂ Cylinder back to available facility inventory.',
                style: TextStyle(color: LuxuryTheme.muted, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Discharge Notes / Destination (optional)',
                  hintText: 'e.g. Stabilized and discharged home / transferred to step-down ward',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Confirm Exit & Restock Bed'),
            style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.blue),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => saving = true);
    try {
      await api.post('/coordination/hospital/requests/$requestId/discharge', {
        'notes': notesCtrl.text.trim(),
      });
      _toast('Patient exit recorded and ICU / O₂ inventory replenished!', LuxuryTheme.green);
      await _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  // Sign out confirmation dialog
  Future<void> _confirmSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.logout_rounded, color: LuxuryTheme.red, size: 24),
            SizedBox(width: 10),
            Text('Sign Out Confirmation', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Are you sure you want to sign out of the Hospital Portal?\n\nYou will need to authenticate again with your GST ID or email to access live emergency coordination and facility availability.',
          style: TextStyle(color: LuxuryTheme.ink, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogCtx, true),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Sign Out'),
            style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.red),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      widget.onLogout();
    }
  }

  Future<void> _showHospitalAccountDialog() async {
    final h = hospital ?? {};
    final res = (h['resources'] is Map ? Map<String, dynamic>.from(h['resources']) : <String, dynamic>{});

    final nameCtrl = TextEditingController(text: h['hospital_name']?.toString() ?? '');
    final specCtrl = TextEditingController(text: h['specialties']?.toString() ?? 'Multi-Specialty Emergency Care');
    final adminNameCtrl = TextEditingController(text: h['admin_name']?.toString() ?? h['full_name']?.toString() ?? '');
    final adminEmailCtrl = TextEditingController(text: h['admin_email']?.toString() ?? h['email']?.toString() ?? '');
    final adminPhoneCtrl = TextEditingController(text: h['admin_phone']?.toString() ?? h['phone']?.toString() ?? '');
    final staffCtrl = TextEditingController(text: '${h['staff_count'] ?? 25}');
    bool parkingVal = h['parking_available'] != false;
    final editIcuCtrl = TextEditingController(text: '${res['icu_beds_available'] ?? icu.text}');
    final editO2Ctrl = TextEditingController(text: '${res['oxygen_cylinders_available'] ?? o2Cylinders.text}');
    final editErCtrl = TextEditingController(text: '${res['emergency_beds_available'] ?? erBeds.text}');
    final editVentCtrl = TextEditingController(text: '${res['ventilators_available'] ?? vents.text}');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final screenWidth = MediaQuery.sizeOf(context).width;
          final isMobile = screenWidth < 620;

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.health_and_safety_rounded, color: LuxuryTheme.blue, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Hospital Facility Profile',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: isMobile ? 16 : 18),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: isMobile ? screenWidth * 0.92 : 600,
              child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F1E36), Color(0xFF1E3A8A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.verified_user_rounded, color: Color(0xFF38BDF8), size: 26),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('GSTIN: ${h['gst_number'] ?? 'Verified Facility Record'}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
                              const SizedBox(height: 2),
                              Text('Official Government Registered Facility in RescuPath Network',
                                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: .8))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('ORGANIZATIONAL PROFILE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: LuxuryTheme.muted, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Hospital Name', prefixIcon: Icon(Icons.local_hospital_outlined))),
                  const SizedBox(height: 8),
                  TextField(
                      controller: specCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Clinical Specialties',
                          hintText: 'e.g. Cardiac, Trauma, Neurology',
                          prefixIcon: Icon(Icons.medical_services_outlined))),
                  const SizedBox(height: 14),
                  const Text('ADMINISTRATOR CONTACT',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: LuxuryTheme.muted, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  if (isMobile) ...[
                    TextField(
                        controller: adminNameCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Administrator Name', prefixIcon: Icon(Icons.person_outline))),
                    const SizedBox(height: 8),
                    TextField(
                        controller: adminPhoneCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Emergency Phone', prefixIcon: Icon(Icons.phone_outlined))),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                            child: TextField(
                                controller: adminNameCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Administrator Name', prefixIcon: Icon(Icons.person_outline)))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: adminPhoneCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Emergency Phone', prefixIcon: Icon(Icons.phone_outlined)))),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                      controller: adminEmailCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Administrator Work Email (Official Record)', prefixIcon: Icon(Icons.email_outlined)),
                      readOnly: true),
                  const SizedBox(height: 14),
                  const Text('STAFF & AMBULANCE PARKING',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: LuxuryTheme.muted, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  if (isMobile) ...[
                    TextField(
                        controller: staffCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Medical Staff on Duty', prefixIcon: Icon(Icons.people_outline))),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: LuxuryTheme.bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: LuxuryTheme.line)),
                      child: Row(
                        children: [
                          const Icon(Icons.local_parking_rounded, color: LuxuryTheme.blue, size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                              child: Text('Ambulance Parking Bay',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                          Switch(
                              value: parkingVal,
                              activeThumbColor: LuxuryTheme.green,
                              onChanged: (v) => setDialogState(() => parkingVal = v)),
                        ],
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                            child: TextField(
                                controller: staffCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Medical Staff on Duty', prefixIcon: Icon(Icons.people_outline)))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: LuxuryTheme.bg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: LuxuryTheme.line)),
                            child: Row(
                              children: [
                                const Icon(Icons.local_parking_rounded, color: LuxuryTheme.blue, size: 20),
                                const SizedBox(width: 6),
                                const Expanded(
                                    child: Text('Ambulance Parking Bay',
                                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11))),
                                Switch(
                                    value: parkingVal,
                                    activeThumbColor: LuxuryTheme.green,
                                    onChanged: (v) => setDialogState(() => parkingVal = v)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text('LIVE EMERGENCY CAPACITY & INVENTORY',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: LuxuryTheme.muted, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  if (isMobile) ...[
                    Row(
                      children: [
                        Expanded(
                            child: TextField(
                                controller: editIcuCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'ICU Beds'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: editO2Ctrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'O₂ Cylinders'))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: TextField(
                                controller: editErCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'ER Beds'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: editVentCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Ventilators'))),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                            child: TextField(
                                controller: editIcuCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'ICU Beds'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: editO2Ctrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'O₂ Cylinders'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: editErCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'ER Beds'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: editVentCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Ventilators'))),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  // Additional sign-out button inside account view (with confirmation)
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _confirmSignOut();
                        },
                        icon: const Icon(Icons.logout_rounded, size: 16, color: LuxuryTheme.red),
                        label: const Text('Sign Out of Facility', style: TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w800, fontSize: 11)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _confirmSignOut();
              },
              icon: const Icon(Icons.logout_rounded, color: LuxuryTheme.red, size: 16),
              label: const Text('Sign Out', style: TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFECDD3)),
              ),
            ),
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      setState(() => saving = true);
                      try {
                        await api.put('/coordination/hospital/profile', {
                          'hospital_name': nameCtrl.text.trim(),
                          'specialties': specCtrl.text.trim(),
                          'admin_name': adminNameCtrl.text.trim(),
                          'admin_phone': adminPhoneCtrl.text.trim(),
                          'staff_count': int.tryParse(staffCtrl.text) ?? 25,
                          'parking_available': parkingVal,
                        });
                        await api.put('/coordination/hospital/availability', {
                          'emergency_available': emergencyAvailable,
                          'icu_beds_available': int.tryParse(editIcuCtrl.text) ?? 0,
                          'oxygen_cylinders_available': int.tryParse(editO2Ctrl.text) ?? 20,
                          'emergency_beds_available': int.tryParse(editErCtrl.text) ?? 0,
                          'ventilators_available': int.tryParse(editVentCtrl.text) ?? 0,
                          'oxygen_available': oxygenAvailable,
                          'trauma_capable': traumaCapable,
                          'cardiac_capable': cardiacCapable,
                        });
                        icu.text = editIcuCtrl.text;
                        o2Cylinders.text = editO2Ctrl.text;
                        erBeds.text = editErCtrl.text;
                        vents.text = editVentCtrl.text;
                        _toast('Hospital account details & inventory updated.', LuxuryTheme.green);
                        await _load();
                        if (mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        _toast(e.toString().replaceFirst('Exception: ', ''), LuxuryTheme.red);
                      } finally {
                        if (mounted) setState(() => saving = false);
                      }
                    },
              icon: const Icon(Icons.save_rounded),
              label: Text(saving ? 'Saving…' : 'Save Records'),
              style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.blue),
            ),
          ],
        );
      },
    ),
  );
}

  // Clickable Tab Card for Pending, Accepted, Declined, History
  Widget _filterCard({
    required String label,
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
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withValues(alpha: .88),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: .35),
            width: isSelected ? 2.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: .3), blurRadius: 12, offset: const Offset(0, 4))]
              : const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(count,
                            style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 18)),
                        if (isSelected) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                            child: const Text('VIEW',
                                style: TextStyle(color: Colors.white, fontSize: 7.5, fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isSelected ? LuxuryTheme.ink : LuxuryTheme.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Sorting & Time Filter Toolbar for Accepted, Declined, History
  Widget _buildSortAndFilterToolbar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: LuxuryTheme.line),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_list_rounded, size: 16, color: LuxuryTheme.blue),
                  const SizedBox(width: 5),
                  Text('Filter $activeFilter:',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: LuxuryTheme.ink)),
                ],
              ),
              _timeFilterChip('ALL', 'All Time'),
              _timeFilterChip('TODAY', 'Today'),
              _timeFilterChip('THIS_MONTH', 'This Month'),
              _timeFilterChip('THIS_YEAR', 'This Year'),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sort_rounded, size: 16, color: LuxuryTheme.muted),
              const SizedBox(width: 6),
              const Text('Sort:',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: LuxuryTheme.muted)),
              const SizedBox(width: 6),
              DropdownButton<String>(
                value: sortOrder,
                underline: const SizedBox(),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: LuxuryTheme.ink),
                items: const [
                  DropdownMenuItem(value: 'NEWEST', child: Text('Newest First')),
                  DropdownMenuItem(value: 'OLDEST', child: Text('Oldest First')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => sortOrder = v);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeFilterChip(String key, String label) {
    final isSel = timeFilter == key;
    return InkWell(
      onTap: () => setState(() => timeFilter = key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? LuxuryTheme.blue : LuxuryTheme.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSel ? LuxuryTheme.blue : LuxuryTheme.line),
        ),
        child: Text(label,
            style: TextStyle(
                color: isSel ? Colors.white : LuxuryTheme.ink, fontSize: 10, fontWeight: FontWeight.w800)),
      ),
    );
  }

  // Patient Clinical Dossier and Intake/Exit Card
  Widget _buildPatientClinicalCard(Map<String, dynamic> r) {
    final p = r['patient'] is Map ? Map<String, dynamic>.from(r['patient']) : null;
    final intakeAt = r['patient_intake_at']?.toString();
    final exitAt = r['patient_exit_at']?.toString();
    final exitNotes = r['patient_exit_notes']?.toString();
    final id = r['request_id']?.toString() ?? '';
    final isDismissed = r['is_dismissed'] == true;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: LuxuryTheme.green.withValues(alpha: .15), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.personal_injury_rounded, color: LuxuryTheme.green, size: 18),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('PATIENT CLINICAL DOSSIER',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        color: Color(0xFF14532D),
                        letterSpacing: 0.5)),
              ),
              if (p != null && (p['blood_group'] != null && p['blood_group'].toString().isNotEmpty))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: LuxuryTheme.red, borderRadius: BorderRadius.circular(6)),
                  child: Text('Blood: ${p['blood_group']}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (p != null) ...[
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _clinicalField('NAME', p['full_name'] ?? 'Unidentified Patient'),
                _clinicalField('AGE / SEX', '${p['age'] ?? '—'} yrs • ${p['sex'] ?? '—'}'),
                _clinicalField('CONDITION', r['condition'] ?? 'Emergency Case'),
                _clinicalField('SEVERITY', r['severity'] ?? 'HIGH'),
              ],
            ),
            if (p['medical_notes'] != null && p['medical_notes'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Paramedic Clinical / Triage Notes:',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10, color: Color(0xFF15803D))),
                    const SizedBox(height: 2),
                    Text('${p['medical_notes']}',
                        style: const TextStyle(fontSize: 11, color: LuxuryTheme.ink)),
                  ],
                ),
              ),
            ],
          ] else ...[
            Text('Triage info: ${r['condition'] ?? 'Emergency Case'} (${r['severity'] ?? 'HIGH'} priority)',
                style: const TextStyle(fontSize: 11, color: LuxuryTheme.ink)),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFBBF7D0)),
          const SizedBox(height: 8),
          // Intake and Exit Tracking
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('HOSPITAL ENTRY (INTAKE)',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 9, color: LuxuryTheme.muted)),
                    const SizedBox(height: 3),
                    if (intakeAt != null)
                      Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: LuxuryTheme.green, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(_formatIso(intakeAt),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800, fontSize: 10, color: LuxuryTheme.green))),
                        ],
                      )
                    else
                      const Text('Awaiting Intake',
                          style: TextStyle(color: LuxuryTheme.muted, fontSize: 10, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('HOSPITAL EXIT (DISCHARGE)',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 9, color: LuxuryTheme.muted)),
                    const SizedBox(height: 3),
                    if (exitAt != null)
                      Row(
                        children: [
                          const Icon(Icons.outbox_rounded, color: LuxuryTheme.blue, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(_formatIso(exitAt),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800, fontSize: 10, color: LuxuryTheme.blue))),
                        ],
                      )
                    else
                      const Text('In Treatment / Admitted',
                          style: TextStyle(color: LuxuryTheme.muted, fontSize: 10, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          if (exitNotes != null && exitNotes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Discharge Notes: $exitNotes',
                style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 10, color: LuxuryTheme.muted)),
          ],
          if (isDismissed && r['dismissed_at'] != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.archive_outlined, color: LuxuryTheme.muted, size: 13),
                const SizedBox(width: 4),
                Text('Archived to History: ${_formatIso(r['dismissed_at'])}',
                    style: const TextStyle(color: LuxuryTheme.muted, fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
          // Intake & Discharge action buttons (available if request accepted)
          if ((r['request_status'] == 'ACCEPTED' || _isCompletedRequest(r)) && !isDismissed) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (intakeAt == null)
                  FilledButton.icon(
                    onPressed: saving ? null : () => _recordIntake(id),
                    icon: const Icon(Icons.login_rounded, size: 15),
                    label: const Text('Record Patient Intake (Entry)', style: TextStyle(fontSize: 11)),
                    style: FilledButton.styleFrom(
                        backgroundColor: LuxuryTheme.green, visualDensity: VisualDensity.compact),
                  ),
                if (intakeAt != null && exitAt == null)
                  FilledButton.icon(
                    onPressed: saving ? null : () => _recordDischarge(id),
                    icon: const Icon(Icons.logout_rounded, size: 15),
                    label: const Text('Record Patient Exit (Discharge)', style: TextStyle(fontSize: 11)),
                    style: FilledButton.styleFrom(
                        backgroundColor: LuxuryTheme.blue, visualDensity: VisualDensity.compact),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _clinicalField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: LuxuryTheme.muted, fontSize: 9, fontWeight: FontWeight.w800)),
        const SizedBox(height: 1),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: LuxuryTheme.ink)),
      ],
    );
  }

  Widget _selectedRequestDetails(Map<String, dynamic> r) => CommandCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.emergency_rounded, color: LuxuryTheme.red),
            const SizedBox(width: 8),
            Expanded(
                child: Text('${r['ambulance_number'] ?? 'Ambulance'} • ${r['severity'] ?? 'HIGH'}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: LuxuryTheme.ink))),
            _status(r['request_status']?.toString() ?? 'REQUESTED'),
          ]),
          const SizedBox(height: 9),
          Text('${r['condition'] ?? 'Emergency'} • ${r['status'] ?? 'ACTIVE'}',
              style: const TextStyle(color: LuxuryTheme.muted, fontSize: 12)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _info('AMBULANCE ETA', _duration(r['eta_seconds']))),
            Expanded(
                child:
                    _info('LIVE GPS', '${_coord(r['ambulance_latitude'])}, ${_coord(r['ambulance_longitude'])}')),
          ]),
          if (r['response_note'] != null)
            Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Text(r['response_note'].toString(),
                    style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11))),
          _buildPatientClinicalCard(r),
          const SizedBox(height: 8),
          Row(children: [
            Icon(
                r['request_status'] == 'ACCEPTED'
                    ? Icons.check_circle_rounded
                    : r['request_status'] == 'DECLINED'
                        ? Icons.cancel_rounded
                        : Icons.hourglass_top_rounded,
                color: r['request_status'] == 'ACCEPTED'
                    ? LuxuryTheme.green
                    : r['request_status'] == 'DECLINED'
                        ? LuxuryTheme.red
                        : LuxuryTheme.amber,
                size: 18),
            const SizedBox(width: 7),
            Expanded(
                child: Text(
                    'Request: ${(r['request_status']?.toString() ?? 'REQUESTED').replaceAll('_', ' ')} • ETA ${_duration(r['eta_seconds'])}',
                    style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w800, fontSize: 11))),
          ]),
        ]),
      );

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
    final r = selected;
    final h = hospital ?? {};
    final center = r == null
        ? _point(h['latitude'], h['longitude'])
        : _point(r['ambulance_latitude'], r['ambulance_longitude'], fallback: _point(h['latitude'], h['longitude']));
    final pts = _routePoints();
    final markers = <Marker>[];
    if (r != null) {
      markers.add(Marker(
          point: _point(r['ambulance_latitude'], r['ambulance_longitude']),
          width: 48,
          height: 48,
          child: const _MapMarker(icon: Icons.emergency_rounded, color: LuxuryTheme.red)));
    }
    markers.add(Marker(
        point: _point(h['latitude'], h['longitude']),
        width: 44,
        height: 44,
        child: const _MapMarker(icon: Icons.local_hospital_rounded, color: LuxuryTheme.green)));

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
                      userAgentPackageName: 'com.rescupath.hospital'),
                  if (pts.length > 1)
                    PolylineLayer(polylines: [Polyline(points: pts, strokeWidth: 5, color: LuxuryTheme.blue)]),
                  if (pts.isEmpty && r != null)
                    PolylineLayer(polylines: [
                      Polyline(points: [center, _point(h['latitude'], h['longitude'])], strokeWidth: 3, color: LuxuryTheme.blue)
                    ]),
                  MarkerLayer(markers: markers),
                  RichAttributionWidget(attributions: const [TextSourceAttribution('OpenStreetMap contributors')]),
                ])));
  }

  // Executive Profile Button Widget at the right corner
  Widget _buildProfileButton() {
    return InkWell(
      onTap: _showHospitalAccountDialog,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: LuxuryTheme.blue.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: LuxuryTheme.blue.withValues(alpha: .25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.account_circle_rounded, color: LuxuryTheme.blue, size: 22),
            SizedBox(width: 6),
            Text(
              'Profile',
              style: TextStyle(
                color: LuxuryTheme.blue,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = hospital ?? {};
    final r = selected;
    final requestsToDisplay = displayedRequests;

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
                          // Header Bar (Responsive for Mobile & Desktop)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isMobile = constraints.maxWidth < 720;
                              if (isMobile) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: LuxuryTheme.blue,
                                            borderRadius: BorderRadius.circular(13),
                                          ),
                                          child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 22),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '$_greeting, ${h['hospital_name'] ?? 'Hospital Portal'}',
                                                style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 16),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                '${h['department'] ?? 'Emergency Department'} • Verified Facility Command',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Refresh',
                                          icon: const Icon(Icons.refresh_rounded, color: LuxuryTheme.ink, size: 22),
                                          onPressed: _load,
                                        ),
                                        // Profile function placed at the right corner
                                        _buildProfileButton(),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: LuxuryTheme.green.withValues(alpha: .10),
                                            borderRadius: BorderRadius.circular(99),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.circle, color: LuxuryTheme.green, size: 8),
                                              SizedBox(width: 5),
                                              Text(
                                                'Online',
                                                style: TextStyle(color: LuxuryTheme.green, fontWeight: FontWeight.w800, fontSize: 10),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (h['gst_number'] != null) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: LuxuryTheme.blue.withValues(alpha: .12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'GST: ${h['gst_number']}',
                                              style: const TextStyle(color: LuxuryTheme.blue, fontWeight: FontWeight.w800, fontSize: 10),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: LuxuryTheme.blue,
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 25),
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 8,
                                          children: [
                                            Text(
                                              '$_greeting, ${h['hospital_name'] ?? 'Hospital Portal'}',
                                              style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 16),
                                            ),
                                            if (h['gst_number'] != null)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: LuxuryTheme.blue.withValues(alpha: .12),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  'GST: ${h['gst_number']}',
                                                  style: const TextStyle(color: LuxuryTheme.blue, fontWeight: FontWeight.w800, fontSize: 10),
                                                ),
                                              ),
                                          ],
                                        ),
                                        Text(
                                          '${h['department'] ?? 'Emergency Department'} • Verified Facility Command',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: LuxuryTheme.green.withValues(alpha: .10),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.circle, color: LuxuryTheme.green, size: 8),
                                        SizedBox(width: 6),
                                        Text('Online', style: TextStyle(color: LuxuryTheme.green, fontWeight: FontWeight.w800, fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Refresh',
                                    onPressed: _load,
                                    icon: const Icon(Icons.refresh_rounded, color: LuxuryTheme.ink),
                                  ),
                                  const SizedBox(width: 4),
                                  // Profile function placed at the right corner
                                  _buildProfileButton(),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),

                          // Emergency Arrivals Filter Banner
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(26),
                              gradient: const LinearGradient(
                                  colors: [Color(0xFF1D70F5), Color(0xFF59A4FF)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight),
                              boxShadow: const [
                                BoxShadow(color: Color(0x222477FF), blurRadius: 22, offset: Offset(0, 8))
                              ],
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              LayoutBuilder(
                                builder: (context, heroBox) {
                                  final isMobile = heroBox.maxWidth < 650;
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$_greeting • Emergency Arrivals',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: isMobile ? 18 : 24,
                                            fontWeight: FontWeight.w900,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                        decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: .2),
                                            borderRadius: BorderRadius.circular(20)),
                                        child: Text('Viewing: $activeFilter',
                                            style: const TextStyle(
                                                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10.5)),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 3),
                              Text(
                                  '$pendingCount Pending Arrival Orders • $historyCount Records in History Archive • ${h['hospital_name'] ?? 'Your facility'}',
                                  style: TextStyle(color: Colors.white.withValues(alpha: .88), fontSize: 12)),
                              const SizedBox(height: 17),
                              LayoutBuilder(builder: (context, constraints) {
                                final wide = constraints.maxWidth >= 650;
                                final width = wide ? (constraints.maxWidth - 24) / 4 : (constraints.maxWidth - 8) / 2;
                                return Wrap(spacing: 8, runSpacing: 8, children: [
                                  SizedBox(
                                    width: width,
                                    child: _filterCard(
                                      label: 'Pending',
                                      count: '$pendingCount',
                                      icon: Icons.pending_actions_rounded,
                                      color: LuxuryTheme.red,
                                      isSelected: activeFilter == 'PENDING',
                                      onTap: () => setState(() => activeFilter = 'PENDING'),
                                    ),
                                  ),
                                  SizedBox(
                                    width: width,
                                    child: _filterCard(
                                      label: 'Accepted',
                                      count: '$acceptedCount',
                                      icon: Icons.check_circle_rounded,
                                      color: LuxuryTheme.green,
                                      isSelected: activeFilter == 'ACCEPTED',
                                      onTap: () => setState(() => activeFilter = 'ACCEPTED'),
                                    ),
                                  ),
                                  SizedBox(
                                    width: width,
                                    child: _filterCard(
                                      label: 'Declined',
                                      count: '$declinedCount',
                                      icon: Icons.cancel_rounded,
                                      color: LuxuryTheme.amber,
                                      isSelected: activeFilter == 'DECLINED',
                                      onTap: () => setState(() => activeFilter = 'DECLINED'),
                                    ),
                                  ),
                                  SizedBox(
                                    width: width,
                                    child: _filterCard(
                                      label: 'History',
                                      count: '$historyCount',
                                      icon: Icons.history_rounded,
                                      color: LuxuryTheme.blue,
                                      isSelected: activeFilter == 'HISTORY',
                                      onTap: () => setState(() => activeFilter = 'HISTORY'),
                                    ),
                                  ),
                                ]);
                              }),
                            ]),
                          ),
                          if (error != null) ...[const SizedBox(height: 12), _message(error!, LuxuryTheme.red)],
                          const SizedBox(height: 21),

                          // Requests Header
                          Row(children: [
                            Expanded(
                              child: Text(
                                activeFilter == 'HISTORY'
                                    ? 'Request History Archive (${requestsToDisplay.length})'
                                    : '$activeFilter Requests (${requestsToDisplay.length})',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: LuxuryTheme.ink),
                              ),
                            ),
                            TextButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: const Text('Refresh')),
                          ]),
                          const SizedBox(height: 8),

                          // Sorting & Date Filter Toolbar (for Accepted, Declined, History)
                          if (activeFilter != 'PENDING') _buildSortAndFilterToolbar(),

                          LayoutBuilder(builder: (context, constraints) {
                            final requestList = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              if (requestsToDisplay.isEmpty)
                                CommandCard(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 56,
                                        height: 56,
                                        decoration: BoxDecoration(
                                            color: LuxuryTheme.blue.withValues(alpha: .10), shape: BoxShape.circle),
                                        child: Icon(
                                          activeFilter == 'HISTORY'
                                              ? Icons.history_toggle_off_rounded
                                              : Icons.mark_email_read_outlined,
                                          color: LuxuryTheme.blue,
                                          size: 30,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        activeFilter == 'HISTORY'
                                            ? 'No requests in history'
                                            : 'No $activeFilter requests found',
                                        style: const TextStyle(
                                            color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 16),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        activeFilter == 'HISTORY'
                                            ? 'When ambulance arrivals are completed, accepted, declined, or archived, they will appear here.'
                                            : 'No requests currently match the "$activeFilter" filter.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: LuxuryTheme.muted, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                )
                              else ...[
                                if (requestsToDisplay.isNotEmpty) ...[
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
                                        Expanded(
                                          child: Text(
                                            _selectedHistoryIds.isEmpty
                                                ? '${requestsToDisplay.length} total • ${activeFilter == "HISTORY" ? "Archived History" : "Active Incoming"}'
                                                : '${_selectedHistoryIds.length} of ${requestsToDisplay.length} selected',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: LuxuryTheme.ink),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
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
                                              onPressed: _batchArchiveActiveRequests,
                                              icon: const Icon(Icons.archive_outlined, size: 15),
                                              label: Text('Archive (${_selectedHistoryIds.length})'),
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
                                            final listIds = requestsToDisplay
                                                .map((item) => item['request_id']?.toString() ?? '')
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
                                ...requestsToDisplay.map((item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _requestCard(item, selectedRequestId == item['request_id']))),
                              ],
                            ]);

                            if (!hasActiveRequests || activeFilter == 'HISTORY') {
                              // NO ACTIVE AMBULANCE REQUESTS (or in History view): DO NOT SHOW MAP!
                              return requestList;
                            }

                            // ACTIVE INCOMING REQUESTS: SHOW MAP PANEL!
                            final mapPanel = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Row(children: [
                                const Expanded(
                                    child: Text('Live ambulance map',
                                        style: TextStyle(
                                            fontSize: 17, fontWeight: FontWeight.w900, color: LuxuryTheme.ink))),
                                Text('5s refresh', style: const TextStyle(color: LuxuryTheme.muted, fontSize: 10))
                              ]),
                              const SizedBox(height: 9),
                              if (r == null)
                                CommandCard(
                                    child: Column(children: const [
                                  Icon(Icons.map_outlined, color: LuxuryTheme.muted, size: 38),
                                  SizedBox(height: 6),
                                  Text('Select a request to view live route',
                                      style: TextStyle(color: LuxuryTheme.muted, fontSize: 12))
                                ]))
                              else
                                _map(),
                              if (r != null) ...[const SizedBox(height: 10), _selectedRequestDetails(r)],
                            ]);

                            if (constraints.maxWidth >= 1080) {
                              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(flex: 7, child: requestList),
                                const SizedBox(width: 18),
                                Expanded(flex: 5, child: mapPanel),
                              ]);
                            }
                            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              requestList,
                              const SizedBox(height: 18),
                              mapPanel,
                            ]);
                          }),
                          const SizedBox(height: 15),
                          const Text(
                              'Live ETA is based on the latest route estimate sent by the paramedic. Bed and resource figures are maintained by your facility team.',
                              style: TextStyle(color: LuxuryTheme.muted, fontSize: 10, height: 1.4)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _requestCard(Map<String, dynamic> item, bool active) {
    final requestStatus = (item['request_status']?.toString() ?? 'REQUESTED').toUpperCase();
    final terminal = _isCompletedRequest(item);
    final isDismissed = item['is_dismissed'] == true;
    final inHistory = activeFilter == 'HISTORY' || isDismissed || terminal;
    final id = item['request_id']?.toString() ?? '';
    final isExpanded = _expandedRequestIds.contains(id);
    final ambId = item['ambulance_id']?.toString() ?? (id.length > 8 ? id.substring(0, 8) : id);
    final ambNumber = item['ambulance_number']?.toString() ?? 'Ambulance';

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
                selectedRequestId = id;
                routeData = null;
              });
              await _loadRoute();
              final lat = item['ambulance_latitude'];
              final lon = item['ambulance_longitude'];
              if (mounted && lat is num && lon is num) {
                _mapController.move(LatLng(lat.toDouble(), lon.toDouble()), 13);
              }
            },
      borderRadius: BorderRadius.circular(20),
      child: CommandCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
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
                    color: (active ? LuxuryTheme.blue : LuxuryTheme.cyan).withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.emergency_rounded, color: LuxuryTheme.red, size: 23)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                children: [
                  Text(ambNumber,
                      style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 14)),
                  if (isDismissed) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration:
                          BoxDecoration(color: LuxuryTheme.muted.withValues(alpha: .15), borderRadius: BorderRadius.circular(4)),
                      child: const Text('ARCHIVED',
                          style: TextStyle(color: LuxuryTheme.muted, fontSize: 8, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text('Ambulance ID: $ambId • ETA ${_duration(item['eta_seconds'])}',
                  style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11, fontWeight: FontWeight.w700)),
            ])),
            _status(requestStatus),
            if (activeFilter == 'HISTORY' || isDismissed || terminal)
              IconButton(
                tooltip: 'Permanently delete from database & cache',
                onPressed: () => _deleteRequestPermanently(item),
                icon: const Icon(Icons.delete_forever_rounded, color: LuxuryTheme.red),
              )
            else
              IconButton(
                tooltip: 'Archive to History',
                onPressed: () => _dismissRequest(item),
                icon: const Icon(Icons.archive_outlined, color: LuxuryTheme.muted),
              ),
          ]),

          // Expandable View Details: Patient details shown ONLY when pressed
          if (isExpanded) ...[
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.priority_high_rounded, color: LuxuryTheme.red, size: 16),
              const SizedBox(width: 4),
              Text('${item['severity'] ?? 'HIGH'} priority',
                  style: const TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w800, fontSize: 10)),
              const SizedBox(width: 12),
              const Icon(Icons.location_on_outlined, color: LuxuryTheme.muted, size: 15),
              const SizedBox(width: 3),
              Expanded(
                  child: Text('${_coord(item['ambulance_latitude'])}, ${_coord(item['ambulance_longitude'])}',
                      style: const TextStyle(color: LuxuryTheme.muted, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              if (item['request_created_at'] != null)
                Text(_formatIso(item['request_created_at']),
                    style: const TextStyle(color: LuxuryTheme.muted, fontSize: 9, fontWeight: FontWeight.w700)),
            ]),
            // Patient clinical card
            _buildPatientClinicalCard(item),
          ],

          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 460;
              final viewDetailsBtn = OutlinedButton.icon(
                onPressed: () async {
                  setState(() {
                    if (isExpanded) {
                      _expandedRequestIds.remove(id);
                    } else {
                      _expandedRequestIds.add(id);
                      selectedRequestId = id;
                      routeData = null;
                    }
                  });
                  if (!isExpanded) {
                    await _loadRoute();
                    final lat = item['ambulance_latitude'];
                    final lon = item['ambulance_longitude'];
                    if (mounted && lat is num && lon is num) {
                      _mapController.move(LatLng(lat.toDouble(), lon.toDouble()), 13);
                    }
                  }
                },
                icon: Icon(isExpanded ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 16),
                label: Text(
                  isExpanded ? 'Hide Patient Details' : 'View Details',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              );

              final hasIntakeActions = requestStatus == 'REQUESTED' && !terminal && !isDismissed;
              if (!hasIntakeActions) {
                return viewDetailsBtn;
              }

              final acceptBtn = FilledButton.icon(
                onPressed: saving ? null : () => _respond('ACCEPTED', request: item),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Accept'),
                style: FilledButton.styleFrom(
                  backgroundColor: LuxuryTheme.green,
                  minimumSize: const Size.fromHeight(44),
                ),
              );

              final declineBtn = FilledButton.icon(
                onPressed: saving ? null : () => _respond('DECLINED', request: item),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Decline'),
                style: FilledButton.styleFrom(
                  backgroundColor: LuxuryTheme.red,
                  minimumSize: const Size.fromHeight(44),
                ),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    viewDetailsBtn,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: acceptBtn),
                        const SizedBox(width: 8),
                        Expanded(child: declineBtn),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: viewDetailsBtn),
                  const SizedBox(width: 8),
                  Expanded(child: acceptBtn),
                  const SizedBox(width: 8),
                  Expanded(child: declineBtn),
                ],
              );
            },
          ),

          if (requestStatus == 'ACCEPTED') ...[
            const SizedBox(height: 6),
            const Row(children: [
              Icon(Icons.check_circle_rounded, color: LuxuryTheme.green, size: 16),
              SizedBox(width: 6),
              Expanded(
                  child: Text('Accepted — emergency intake ready, 1 ICU & 1 O₂ reserved',
                      style: TextStyle(color: LuxuryTheme.green, fontSize: 10, fontWeight: FontWeight.w800)))
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _info(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: LuxuryTheme.muted, fontSize: 9, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: LuxuryTheme.ink, fontSize: 12, fontWeight: FontWeight.w900))
      ]);

  Widget _status(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: (text == 'ACCEPTED'
                  ? LuxuryTheme.green
                  : text == 'DECLINED'
                      ? LuxuryTheme.red
                      : LuxuryTheme.amber)
              .withValues(alpha: .11),
          borderRadius: BorderRadius.circular(99)),
      child: Text(text.replaceAll('_', ' '),
          style: TextStyle(
              color: text == 'ACCEPTED'
                  ? LuxuryTheme.green
                  : text == 'DECLINED'
                      ? LuxuryTheme.red
                      : LuxuryTheme.amber,
              fontWeight: FontWeight.w900,
              fontSize: 9)));

  Widget _message(String message, Color color) =>
      CommandCard(child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.w700)));

  String _duration(dynamic raw) =>
      raw is num ? raw < 60 ? '${raw.round()} sec' : '${(raw / 60).ceil()} min' : 'Awaiting ETA';

  String _coord(dynamic raw) => raw is num ? raw.toStringAsFixed(5) : '—';

  String _formatIso(dynamic raw) {
    if (raw == null) return '—';
    final d = DateTime.tryParse(raw.toString())?.toLocal();
    if (d == null) return raw.toString();
    final hour = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}, $hour:$min';
  }

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
                            boxShadow: const [
                              BoxShadow(color: Color(0x330A1930), blurRadius: 20, offset: Offset(0, 8))
                            ]),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 9),
                          Expanded(
                              child: Text(text,
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, height: 1.3)))
                        ]),
                      ))),
            ));
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
    clockTimer?.cancel();
    _mapController.dispose();
    icu.dispose();
    erBeds.dispose();
    vents.dispose();
    o2Cylinders.dispose();
    _icuFocus.dispose();
    _erFocus.dispose();
    _ventsFocus.dispose();
    _o2Focus.dispose();
    super.dispose();
  }
}

class _MapMarker extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _MapMarker({required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x2A0A1930), blurRadius: 12)]),
      child: Icon(icon, color: Colors.white, size: 24));
}
