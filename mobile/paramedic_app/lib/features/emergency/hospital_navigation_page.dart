import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/audio_buzzer.dart';
import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/services/location_service.dart';
import '../../core/services/user_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../hospitals/hospital_selection_page.dart';

class HospitalNavigationPage extends StatefulWidget {
  final String emergencyId;
  final Map<String, dynamic> hospital;
  final Map<String, dynamic>? assignedEmergency;
  final String initialSeverity;
  const HospitalNavigationPage({super.key, required this.emergencyId, required this.hospital, this.assignedEmergency, this.initialSeverity = 'HIGH'});
  @override State<HospitalNavigationPage> createState() => _HospitalNavigationPageState();
}

class _HospitalNavigationPageState extends State<HospitalNavigationPage> {
  final api = ApiClient();
  final location = LocationService();
  final map = MapController();
  StreamSubscription<dynamic>? locationSubscription;
  Timer? routeTimer;
  Timer? statusTimer;
  Timer? hospitalResponseTimer;
  List<Map<String, dynamic>> hospitalResponses = [];
  Map<String, dynamic>? policeCoordination;
  LatLng? current; LatLng? destination;
  Map<String, dynamic>? route; Map<String, dynamic>? emergency;
  bool loading = true; bool refreshing = false; bool informingHospital = false; bool informingPolice = false;
  bool showDirections = true;
  String status = 'HOSPITAL_ASSIGNED'; DateTime? lastGpsUpdate; String? error;
  OverlayEntry? _toastEntry;
  Timer? _toastTimer;
  double currentSpeedMps = 0;
  bool _isFirstHospitalResponseFetch = true;
  bool _isFirstPoliceFetch = true;

  String get hospitalName => widget.hospital['hospital_name']?.toString() ?? 'Selected Hospital';
  String? get hospitalPhone => widget.hospital['phone']?.toString();
  String get condition => (widget.hospital['condition']?.toString() ?? emergency?['condition']?.toString() ?? 'OTHER').toUpperCase();
  String get _safeEmergencyId {
    final wid = widget.emergencyId.trim();
    if (wid.isNotEmpty && wid != 'null') return wid;
    final emId = emergency?['id']?.toString().trim();
    if (emId != null && emId.isNotEmpty && emId != 'null') return emId;
    return 'active';
  }

  void _handleBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HospitalSelectionPage(
            emergencyId: _safeEmergencyId,
            initialSeverity: widget.initialSeverity,
          ),
        ),
      );
    }
  }


  @override void initState() { super.initState(); emergency = widget.assignedEmergency; status = widget.assignedEmergency?['status']?.toString() ?? 'HOSPITAL_ASSIGNED'; _setDestination(widget.assignedEmergency); _initialize(); }

  Future<void> _initialize() async {
    try {
      final e = await api.get('/emergencies/$_safeEmergencyId');
      if (mounted) setState(() { emergency = Map<String, dynamic>.from(e); status = e['status']?.toString() ?? status; _setDestination(e); });
      final highAccuracy = await UserPreferences.highAccuracyGps;
      try { final p = await location.currentPosition(highAccuracy: highAccuracy); await _handleLocation(p.latitude, p.longitude, p.accuracy, p.speed, p.heading); } catch (_) {}
      await _refreshRoute();
      await _setEnRoute();
      _startTracking(highAccuracy);
      if (await UserPreferences.autoRouteRefresh) { routeTimer = Timer.periodic(const Duration(seconds: 12), (_) => _refreshRoute()); }
      statusTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshEmergency());

      // Automatically send alert requests to both Hospital and Police immediately
      await _autoDispatchHospitalAndPolice();

      hospitalResponseTimer = Timer.periodic(const Duration(seconds: 5), (_) { _refreshHospitalResponses(); _refreshPoliceStatus(); });
      await _refreshHospitalResponses();
      await _refreshPoliceStatus();
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> _autoDispatchHospitalAndPolice() async {
    try {
      final id = widget.hospital['hospital_id']?.toString() ?? widget.hospital['id']?.toString();
      final gst = widget.hospital['gst_number']?.toString();
      final raw = route?['duration_seconds'];
      final body = <String, dynamic>{
        'eta_seconds': raw is num ? raw.round() : null,
        'phone': hospitalPhone,
        'note': 'Ambulance is en route to $hospitalName. Bed availability requested.',
      };
      if (id != null && id.isNotEmpty) body['hospital_id'] = id;
      if (gst != null && gst.isNotEmpty) body['gst_number'] = gst;

      await Future.wait([
        api.post('/emergencies/$_safeEmergencyId/notify-hospital', body).catchError((_) => null),
        api.post('/emergencies/$_safeEmergencyId/notify-police', {'eta_seconds': raw is num ? raw.round() : null}).catchError((_) => null),
      ]);
      if (mounted) {
        setState(() => status = 'HOSPITAL_ALERTED');
      }
    } catch (_) {}
  }

  void _setDestination(Map<String, dynamic>? e) {
    final lat = e?['destination_latitude'] ?? widget.hospital['latitude']; final lng = e?['destination_longitude'] ?? widget.hospital['longitude'];
    if (lat is num && lng is num) destination = LatLng(lat.toDouble(), lng.toDouble());
  }

  Future<void> _refreshEmergency() async { try { final e = await api.get('/emergencies/$_safeEmergencyId'); if (!mounted) return; setState(() { emergency = Map<String, dynamic>.from(e); status = e['status']?.toString() ?? status; _setDestination(e); }); } catch (_) {} }

  Future<void> _refreshHospitalResponses() async {
    try {
      final raw = await api.get('/coordination/emergencies/$_safeEmergencyId/hospital-availability');
      if (!mounted || raw is! List) return;
      final rows = raw.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
      final isFirst = _isFirstHospitalResponseFetch;
      _isFirstHospitalResponseFetch = false;

      final previousStatuses = <String, String>{
        for (final row in hospitalResponses)
          if (row['request_id'] != null)
            row['request_id'].toString(): row['status']?.toString() ?? 'REQUESTED',
      };
      final newlyResponded = rows.where((row) {
        final id = row['request_id']?.toString();
        final statusNow = row['status']?.toString() ?? 'REQUESTED';
        final hasTerminalResponse =
            statusNow == 'ACCEPTED' || statusNow == 'DECLINED';
        final changedFromPending =
            id != null &&
            previousStatuses.containsKey(id) &&
            previousStatuses[id] == 'REQUESTED';
        return id != null &&
            hasTerminalResponse &&
            !isFirst &&
            changedFromPending &&
            row['hospital_id']?.toString() ==
                widget.hospital['hospital_id']?.toString();
      }).toList();
      setState(() => hospitalResponses = rows);
      if (newlyResponded.isNotEmpty && mounted) {
        final response = newlyResponded.first;
        final accepted = response['status']?.toString() == 'ACCEPTED';
        final responseHospitalName = response['hospital_name']?.toString() ?? hospitalName;
        final responseNote = response['response_note']?.toString();
        final responseMessage = '$responseHospitalName ${accepted ? "accepted" : "declined"} the emergency arrival request${responseNote == null || responseNote.isEmpty ? "" : ": $responseNote"}';
        if (accepted) {
          unawaited(AudioBuzzer.playAcknowledgeReceived());
        }
        _toast(responseMessage, accepted ? AppTheme.green : AppTheme.red);
      }
    } catch (_) {}
  }

  Future<void> _refreshPoliceStatus() async {
    try {
      final raw = await api.get(
        '/coordination/emergencies/$_safeEmergencyId/police-status',
      );
      if (!mounted || raw is! Map) return;

      final next = Map<String, dynamic>.from(raw);
      final isFirst = _isFirstPoliceFetch;
      _isFirstPoliceFetch = false;

      final wasAcknowledged = policeCoordination?['acknowledged'] == true;
      final isAcknowledged = next['acknowledged'] == true;
      final wasCleared = policeCoordination?['traffic_cleared'] == true;
      final isCleared = next['traffic_cleared'] == true;

      setState(() => policeCoordination = next);

      if (!isFirst) {
        if (!wasAcknowledged && isAcknowledged) {
          unawaited(AudioBuzzer.playAcknowledgeReceived());
          _toast(
            'Police acknowledged the ambulance alert.',
            AppTheme.green,
          );
        }
        if (!wasCleared && isCleared) {
          unawaited(AudioBuzzer.playAcknowledgeReceived());
          _toast(
            'Police reported traffic cleared along the route.',
            AppTheme.green,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _setEnRoute() async {
    if (status == 'EN_ROUTE' || status == 'HOSPITAL_ALERTED') return;
    try { final result = await api.post('/emergencies/$_safeEmergencyId/status', {'status': 'EN_ROUTE'}); if (mounted) setState(() => status = result['status']?.toString() ?? 'EN_ROUTE'); } catch (_) {}
  }

  Future<void> _refreshRoute() async {
    if (refreshing || !mounted) return;
    setState(() => refreshing = true);
    try { final result = await api.get('/emergencies/$_safeEmergencyId/route'); if (!mounted) return; setState(() { route = Map<String, dynamic>.from(result as Map); _setDestination(route); }); }
    catch (e) { if (mounted && route == null) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => refreshing = false); }
  }

  void _startTracking(bool highAccuracy) {
    locationSubscription?.cancel();
    locationSubscription = location.stream(highAccuracy: highAccuracy).listen((p) => _handleLocation(p.latitude, p.longitude, p.accuracy, p.speed, p.heading));
  }

  Future<void> _handleLocation(double latitude, double longitude, double accuracy, double speed, double heading) async {
    final point = LatLng(latitude, longitude);
    if (!mounted) return;
    setState(() { current = point; currentSpeedMps = speed; lastGpsUpdate = DateTime.now(); });
    try { await api.post('/emergencies/$_safeEmergencyId/location', {'latitude': latitude, 'longitude': longitude, 'accuracy_meters': accuracy, 'speed_mps': speed, 'heading_degrees': heading, 'eta_seconds': route?['duration_seconds'] is num ? (route!['duration_seconds'] as num).round() : null}); } catch (_) {}
    if (mounted) map.move(point, map.camera.zoom < 13 ? 15 : map.camera.zoom);
  }

  Future<void> _informHospital({bool forceSend = false}) async {
    final alreadyAlerted = status == 'HOSPITAL_ALERTED' || hospitalResponses.isNotEmpty;
    if (alreadyAlerted && !forceSend) {
      _showCoordinationSheet(focusHospital: true);
      return;
    }
    if (informingHospital) return;
    setState(() => informingHospital = true);
    try {
      final id = widget.hospital['hospital_id']?.toString() ?? widget.hospital['id']?.toString();
      final gst = widget.hospital['gst_number']?.toString();
      final raw = route?['duration_seconds'];
      final body = <String, dynamic>{
        'eta_seconds': raw is num ? raw.round() : null,
        'phone': hospitalPhone,
        'note': 'Ambulance is en route to $hospitalName. Please confirm emergency department availability.',
      };
      if (id != null && id.isNotEmpty) body['hospital_id'] = id;
      if (gst != null && gst.isNotEmpty) body['gst_number'] = gst;

      await api.post('/emergencies/$_safeEmergencyId/notify-hospital', body);
      if (mounted) {
        setState(() => status = 'HOSPITAL_ALERTED');
        _toast('Hospital informed • ETA ${_etaText()}. Waiting for their response.', AppTheme.green);
        await _refreshHospitalResponses();
        _showCoordinationSheet(focusHospital: true);
      }
    } catch (e) {
      if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''), AppTheme.red);
    } finally {
      if (mounted) setState(() => informingHospital = false);
    }
  }

  Future<void> _callHospital() async {
    final phone = hospitalPhone;
    if (phone == null || phone.trim().isEmpty) { _toast('No public phone is available in the live hospital data. Use Open Map to view the hospital listing.', AppTheme.amber); await _openGoogleMaps(); return; }
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    await launchUrl(Uri(scheme: 'tel', path: cleaned), mode: LaunchMode.externalApplication);
  }

  Future<void> _informPolice({bool forceSend = false}) async {
    final alreadyAlerted = policeCoordination != null;
    if (alreadyAlerted && !forceSend) {
      _showCoordinationSheet(focusPolice: true);
      return;
    }
    if (informingPolice) return;
    setState(() => informingPolice = true);
    try {
      final routeEta = route?['duration_seconds'];
      final res = await api.post('/emergencies/$_safeEmergencyId/notify-police', {'eta_seconds': routeEta is num ? routeEta.round() : null});
      await _refreshPoliceStatus();
      await _refreshHospitalResponses();
      if (mounted) {
        _toast('Police alerted for traffic clearance.', AppTheme.green);
        _showCoordinationSheet(
          policeNotifyResult: res is Map ? Map<String, dynamic>.from(res) : null,
          focusPolice: true,
        );
      }
    }
    catch (e) { if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''), AppTheme.red); }
    finally { if (mounted) setState(() => informingPolice = false); }
  }

  void _showCoordinationSheet({Map<String, dynamic>? policeNotifyResult, bool focusPolice = false, bool focusHospital = false}) {
    final remainingIcu = policeNotifyResult?['remaining_icu_beds'] ??
        policeCoordination?['remaining_icu_beds'] ??
        (hospitalResponses.isNotEmpty ? hospitalResponses.first['remaining_icu_beds'] : null) ??
        widget.hospital['icu_beds_available'] ??
        18;
    final remainingO2 = policeNotifyResult?['remaining_oxygen_cylinders'] ??
        policeCoordination?['remaining_oxygen_cylinders'] ??
        (hospitalResponses.isNotEmpty ? hospitalResponses.first['remaining_oxygen_cylinders'] : null) ??
        widget.hospital['oxygen_cylinders_available'] ??
        30;
    final hName = policeNotifyResult?['hospital_name'] ?? policeCoordination?['hospital_name'] ?? hospitalName;
    final isPoliceAck = policeCoordination?['acknowledged'] == true;
    final isTrafficCleared = policeCoordination?['traffic_cleared'] == true;
    final isPoliceAlerted = policeCoordination != null || policeNotifyResult != null;

    final isHospitalAccepted = hospitalResponses.any((r) => r['status'] == 'ACCEPTED');
    final isHospitalDeclined = hospitalResponses.any((r) => r['status'] == 'DECLINED');
    final isHospitalAlerted = status == 'HOSPITAL_ALERTED' || hospitalResponses.isNotEmpty;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [BoxShadow(color: Color(0x330A1930), blurRadius: 24, offset: Offset(0, -6))],
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (isHospitalAccepted ? AppTheme.green : isHospitalAlerted ? const Color(0xFFFF991F) : AppTheme.blue).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    isHospitalAccepted ? Icons.verified_rounded : isHospitalAlerted ? Icons.hourglass_top_rounded : Icons.local_hospital_rounded,
                    color: isHospitalAccepted ? AppTheme.green : isHospitalAlerted ? const Color(0xFFFF991F) : AppTheme.blue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isHospitalAccepted
                            ? 'Hospital Acknowledged & Accepted'
                            : isHospitalDeclined
                                ? 'Hospital Intake Declined'
                                : isHospitalAlerted
                                    ? 'Hospital Alert Sent (Pending)'
                                    : 'Hospital Status: Not Alerted',
                        style: const TextStyle(color: AppTheme.ink, fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      Text(hName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                StatusChip(
                  isHospitalAccepted
                      ? 'ACCEPTED'
                      : isHospitalDeclined
                          ? 'DECLINED'
                          : isHospitalAlerted
                              ? 'SENT • PENDING'
                              : 'NOT SENT',
                  color: isHospitalAccepted
                      ? AppTheme.green
                      : isHospitalDeclined
                          ? AppTheme.red
                          : isHospitalAlerted
                              ? const Color(0xFFFF991F)
                              : AppTheme.muted,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Hospital Inventory & Readiness Card
            SurfaceCard(
              gradient: const [Color(0xFFEFF7FF), Color(0xFFFFFFFF)],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.inventory_2_rounded, size: 18, color: AppTheme.blue),
                      SizedBox(width: 8),
                      Text('Hospital Live Inventory Remaining', style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.ink, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Remaining ICU Beds', style: TextStyle(color: AppTheme.muted, fontSize: 10, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text('$remainingIcu Available', style: const TextStyle(color: AppTheme.ink, fontSize: 17, fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Remaining O₂ Cylinders', style: TextStyle(color: AppTheme.muted, fontSize: 10, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text('$remainingO2 Available', style: const TextStyle(color: Color(0xFF00897B), fontSize: 17, fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Icon(
                        isHospitalAccepted ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                        color: isHospitalAccepted ? AppTheme.green : AppTheme.muted,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isHospitalAccepted
                              ? '1 Dedicated ICU Bed and 1 O₂ Cylinder allocated for incoming patient.'
                              : 'Hospital notification sent. Reservation will be confirmed upon facility acceptance.',
                          style: TextStyle(
                            color: isHospitalAccepted ? AppTheme.green : AppTheme.ink,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _callHospital();
                          },
                          icon: const Icon(Icons.phone_in_talk_rounded, size: 16),
                          label: const Text('Call Desk', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _informHospital(forceSend: true);
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: Text(
                            isHospitalAlerted ? 'Re-send Alert' : 'Alert Hospital',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Police Green Corridor Status Card
            SurfaceCard(
              gradient: isTrafficCleared
                  ? const [Color(0xFFF0FDF4), Color(0xFFFFFFFF)]
                  : isPoliceAck
                      ? const [Color(0xFFEFF6FF), Color(0xFFFFFFFF)]
                      : const [Color(0xFFFFFBEB), Color(0xFFFFFFFF)],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: (isTrafficCleared
                                  ? AppTheme.green
                                  : isPoliceAck
                                      ? AppTheme.blue
                                      : const Color(0xFFFF991F))
                              .withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isTrafficCleared
                              ? Icons.verified_rounded
                              : isPoliceAck
                                  ? Icons.local_police_rounded
                                  : Icons.hourglass_top_rounded,
                          color: isTrafficCleared
                              ? AppTheme.green
                              : isPoliceAck
                                  ? AppTheme.blue
                                  : const Color(0xFFFF991F),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isTrafficCleared
                                  ? 'Police: Route Cleared (Green Corridor)'
                                  : isPoliceAck
                                      ? 'Police: Acknowledged & Escorting'
                                      : isPoliceAlerted
                                          ? 'Police: Alert Dispatched (Pending)'
                                          : 'Police: Not Dispatched',
                              style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isTrafficCleared
                                  ? 'Traffic signals and intermediate junctions cleared by police units.'
                                  : isPoliceAck
                                      ? 'Duty officer acknowledged alert. Patrol units clearing route junctions.'
                                      : isPoliceAlerted
                                          ? 'Traffic clearance alert dispatched to police control. Waiting for acknowledgment.'
                                          : 'Tap Inform Police to dispatch green corridor alert.',
                              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      StatusChip(
                        isTrafficCleared
                            ? 'CLEARED'
                            : isPoliceAck
                                ? 'ESCORT'
                                : isPoliceAlerted
                                    ? 'SENT'
                                    : 'NOT SENT',
                        color: isTrafficCleared
                            ? AppTheme.green
                            : isPoliceAck
                                ? AppTheme.blue
                                : const Color(0xFFFF991F),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _call112();
                          },
                          icon: const Icon(Icons.phone_in_talk_rounded, size: 16),
                          label: const Text('Call 112 Desk', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _informPolice(forceSend: true);
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: Text(
                            isPoliceAlerted ? 'Re-send Police Alert' : 'Alert Police Now',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF991F),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Resume Navigation View',
              icon: Icons.navigation_rounded,
              background: AppTheme.blue,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _call112() async { await launchUrl(Uri(scheme: 'tel', path: '112'), mode: LaunchMode.externalApplication); }

  Future<void> _openGoogleMaps() async {
    final lat = widget.hospital['latitude']; final lng = widget.hospital['longitude']; if (lat is! num || lng is! num) return;
    final origin = current == null ? null : '${current!.latitude},${current!.longitude}';
    final query = <String, String>{'api': '1', 'destination': '${lat.toDouble()},${lng.toDouble()}', 'travelmode': 'driving', 'dir_action': 'navigate'};
    if (origin != null) query['origin'] = origin;
    final uri = Uri.https('www.google.com', '/maps/dir/', query);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _markArrived() async {
    try {
      final result = await api.post('/emergencies/$_safeEmergencyId/status', {'status': 'ARRIVED'});
      if (mounted) {
        setState(() => status = result['status']?.toString() ?? 'ARRIVED');
        _toast('Arrival recorded. Ambulance marked available.', AppTheme.green);
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
          }
        });
      }
    }
    catch (e) { if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''), AppTheme.red); }
  }

  List<LatLng> _routePoints() {
    final raw = route?['polyline_points']; if (raw is! List) return const [];
    return raw.whereType<List>().where((p) => p.length >= 2).map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble())).toList();
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const r = 6371000.0; final dLat = (b.latitude - a.latitude) * math.pi / 180; final dLng = (b.longitude - a.longitude) * math.pi / 180; final lat1 = a.latitude * math.pi / 180; final lat2 = b.latitude * math.pi / 180; final h = math.pow(math.sin(dLat / 2), 2) + math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2); return 2 * r * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  Map<String, dynamic>? _nextStep() {
    final raw = route?['steps']; if (raw is! List || raw.isEmpty) return null; if (current == null) return Map<String, dynamic>.from(raw.first as Map);
    Map<String, dynamic>? closest; double best = double.infinity;
    for (final item in raw.whereType<Map>()) { final lat = item['latitude']; final lng = item['longitude']; if (lat is! num || lng is! num) continue; final d = _distanceMeters(current!, LatLng(lat.toDouble(), lng.toDouble())); if (d >= 35 && d < best) { best = d; closest = Map<String, dynamic>.from(item); } }
    return closest ?? Map<String, dynamic>.from(raw.first as Map);
  }

  String _etaText() { final raw = route?['duration_seconds']; return raw is num ? '${(raw / 60).ceil()} min' : '—'; }
  String _distanceText() { final raw = route?['distance_meters']; return raw is num ? raw >= 1000 ? '${(raw / 1000).toStringAsFixed(1)} km' : '${raw.round()} m' : '—'; }
  void _toast(String text, Color color) {
    if (!mounted) return;

    _toastTimer?.cancel();
    _toastEntry?.remove();
    _toastEntry = null;

    final overlay = Overlay.of(context, rootOverlay: true);
    final media = MediaQuery.of(context);
    final toastWidth =
        media.size.width < 500 ? media.size.width - 28.0 : 370.0;

    _toastEntry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: media.padding.top + 12,
        right: 14,
        width: toastWidth.clamp(220.0, 370.0).toDouble(),
        child: IgnorePointer(
          ignoring: true,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 13,
              ),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(17),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 20,
                    offset: Offset(0, 7),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.notifications_active_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_toastEntry!);
    _toastTimer = Timer(const Duration(seconds: 5), () {
      _toastEntry?.remove();
      _toastEntry = null;
      _toastTimer = null;
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _toastEntry?.remove();
    routeTimer?.cancel();
    statusTimer?.cancel();
    hospitalResponseTimer?.cancel();
    locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = _routePoints();
    final step = _nextStep();

    String turnPrefix = 'Turn left onto';
    String streetName = hospitalName;
    String turnDist = '350 m';
    bool isRightTurn = false;

    if (step != null) {
      final instr = step['instruction']?.toString() ?? '';
      if (instr.toLowerCase().contains('right')) {
        turnPrefix = 'Turn right onto';
        isRightTurn = true;
      } else if (instr.toLowerCase().contains('left')) {
        turnPrefix = 'Turn left onto';
        isRightTurn = false;
      } else {
        turnPrefix = 'Continue onto';
      }

      final name = step['name']?.toString() ?? step['street']?.toString();
      if (name != null && name.trim().isNotEmpty) {
        streetName = name;
      } else if (instr.isNotEmpty) {
        streetName = instr;
      }

      final dist = step['distance'];
      if (dist is num) {
        turnDist = dist >= 1000 ? '${(dist / 1000).toStringAsFixed(1)} km' : '${dist.round()} m';
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2563EB)),
            )
          : Stack(
              children: [
                // 1. Full-screen map surface
                Positioned.fill(
                  child: FlutterMap(
                    mapController: map,
                    options: MapOptions(
                      initialCenter: current ?? destination ?? const LatLng(12.9716, 77.5946),
                      initialZoom: 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: AppConfig.mapTileUrl,
                        userAgentPackageName: 'com.rescupath.paramedic_app',
                      ),
                      if (points.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: points,
                              strokeWidth: 6,
                              color: const Color(0xFF2563EB),
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (current != null)
                            Marker(
                              point: current!,
                              width: 48,
                              height: 48,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(
                                    color: const Color(0xFF2563EB),
                                    width: 3.5,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x442563EB),
                                      blurRadius: 14,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.navigation_rounded,
                                  color: Color(0xFF2563EB),
                                  size: 24,
                                ),
                              ),
                            ),
                          if (destination != null)
                            Marker(
                              point: destination!,
                              width: 46,
                              height: 46,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFDC2626),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2.5,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x55DC2626),
                                      blurRadius: 14,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Text(
                                    'H',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 2. Clean Top Navigation Header
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x120F172A),
                            blurRadius: 16,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: _handleBack,
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: Color(0xFF0F172A),
                              size: 24,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  hospitalName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                const Text(
                                  'Live Navigation',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Red Square 'H' Badge
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Center(
                              child: Text(
                                'H',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Floating Turn-by-Turn Maneuver Card
                if (showDirections)
                  Positioned(
                    top: 86,
                    left: 14,
                    right: 14,
                    child: SafeArea(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A2540),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x330A2540),
                              blurRadius: 18,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E3A8A),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isRightTurn ? Icons.turn_right_rounded : Icons.turn_left_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    turnPrefix,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    streetName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              turnDist,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 4. Layers / Re-center map tool on right
                Positioned(
                  bottom: 215,
                  right: 14,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.layers_outlined, color: Color(0xFF0F172A), size: 22),
                      tooltip: 'Re-center map',
                      onPressed: () {
                        if (current != null) {
                          map.move(current!, 16);
                        } else if (destination != null) {
                          map.move(destination!, 15);
                        }
                      },
                    ),
                  ),
                ),

                // 5. Lower Telematics, Status Pills & Action Panel
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x180F172A),
                            blurRadius: 20,
                            offset: Offset(0, -6),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 3-Column Metrics Card (Live GPS, 5 min ETA, 3.2 km Distance)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                // Col 1: Live GPS
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.signal_cellular_alt_rounded,
                                        color: Color(0xFF22C55E),
                                        size: 22,
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Text(
                                            'Live',
                                            style: TextStyle(
                                              color: Color(0xFF0F172A),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            'GPS',
                                            style: TextStyle(
                                              color: Color(0xFF64748B),
                                              fontWeight: FontWeight.w500,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(width: 1, height: 28, color: const Color(0xFFE2E8F0)),
                                // Col 2: ETA
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.access_time_rounded,
                                        color: Color(0xFF64748B),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _etaText(),
                                            style: const TextStyle(
                                              color: Color(0xFF0F172A),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const Text(
                                            'ETA',
                                            style: TextStyle(
                                              color: Color(0xFF64748B),
                                              fontWeight: FontWeight.w500,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(width: 1, height: 28, color: const Color(0xFFE2E8F0)),
                                // Col 3: Distance
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.alt_route_rounded,
                                        color: Color(0xFF64748B),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _distanceText(),
                                            style: const TextStyle(
                                              color: Color(0xFF0F172A),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const Text(
                                            'Distance',
                                            style: TextStyle(
                                              color: Color(0xFF64748B),
                                              fontWeight: FontWeight.w500,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Status Pills: Hospital Acknowledged & Police Acknowledged
                          Builder(builder: (context) {
                            final isHospitalAccepted = hospitalResponses.any((r) => r['status'] == 'ACCEPTED');
                            final isTrafficCleared = policeCoordination?['traffic_cleared'] == true;
                            final isPoliceAck = policeCoordination?['acknowledged'] == true;

                            return Row(
                              children: [
                                // Hospital Pill
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _showCoordinationSheet(focusHospital: true),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isHospitalAccepted
                                            ? const Color(0xFFDCFCE7)
                                            : const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            isHospitalAccepted
                                                ? Icons.check_circle_rounded
                                                : Icons.hourglass_top_rounded,
                                            color: isHospitalAccepted
                                                ? const Color(0xFF22C55E)
                                                : const Color(0xFFD97706),
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              isHospitalAccepted ? 'Hospital Acknowledged' : 'Hospital: Sent',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isHospitalAccepted
                                                    ? const Color(0xFF15803D)
                                                    : const Color(0xFFB45309),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Police Pill
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _showCoordinationSheet(focusPolice: true),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: (isTrafficCleared || isPoliceAck)
                                            ? const Color(0xFFDCFCE7)
                                            : const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            (isTrafficCleared || isPoliceAck)
                                                ? Icons.check_circle_rounded
                                                : Icons.hourglass_top_rounded,
                                            color: (isTrafficCleared || isPoliceAck)
                                                ? const Color(0xFF22C55E)
                                                : const Color(0xFFD97706),
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              isTrafficCleared
                                                  ? 'Traffic Cleared'
                                                  : isPoliceAck
                                                      ? 'Police Acknowledged'
                                                      : 'Police: Sent',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: (isTrafficCleared || isPoliceAck)
                                                    ? const Color(0xFF15803D)
                                                    : const Color(0xFFB45309),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }),
                          const SizedBox(height: 10),

                          // Action Buttons: Mark Arrived & Green Call Button
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: FilledButton.icon(
                                    onPressed: _markArrived,
                                    icon: const Icon(
                                      Icons.flag_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    label: const Text(
                                      'Mark Arrived',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFFDC2626),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 52,
                                height: 52,
                                child: FilledButton(
                                  onPressed: _callHospital,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF16A34A),
                                    elevation: 0,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.call_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
