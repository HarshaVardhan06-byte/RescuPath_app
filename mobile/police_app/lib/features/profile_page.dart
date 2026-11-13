import 'package:flutter/material.dart';
import '../core/app_api.dart';
import '../core/luxury_theme.dart';

class PoliceProfilePage extends StatefulWidget {
  final Map<String, dynamic> officer;
  final bool onDuty;
  final ValueChanged<bool> onToggleDuty;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLogout;

  const PoliceProfilePage({
    super.key,
    required this.officer,
    required this.onDuty,
    required this.onToggleDuty,
    required this.onRefresh,
    required this.onLogout,
  });

  @override
  State<PoliceProfilePage> createState() => _PoliceProfilePageState();
}

class _PoliceProfilePageState extends State<PoliceProfilePage> {
  final api = AppApi();
  late bool currentDuty;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    currentDuty = widget.onDuty;
  }

  Future<void> _handleDutyToggle(bool val) async {
    if (!val && currentDuty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Go Off-Duty / Offline?'),
          content: const Text(
            'While offline, live emergency dispatches, junction arrival ETAs, and active ambulance routes will not be displayed on your dashboard.',
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
      await api.put('/coordination/police/duty', {'on_duty': val});
      setState(() => currentDuty = val);
      widget.onToggleDuty(val);
      await widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: LuxuryTheme.red,
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final off = widget.officer;
    final name = off['full_name']?.toString() ?? off['officer_name']?.toString() ?? 'Traffic Police Officer';
    final badge = off['badge_number']?.toString() ?? '—';
    final station = off['station_name']?.toString() ?? 'Police Command Center';
    final junction = off['junction_name']?.toString() ?? 'Junction not assigned';
    final email = off['email']?.toString() ?? '—';
    final phone = off['phone']?.toString() ?? '—';

    return Scaffold(
      backgroundColor: LuxuryTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: LuxuryTheme.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Officer Profile',
          style: TextStyle(color: LuxuryTheme.ink, fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final isMobile = box.maxWidth < 450;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Officer Hero Card
                        Container(
                          padding: EdgeInsets.all(isMobile ? 16 : 22),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [LuxuryTheme.navy, Color(0xFF1A3B69)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [
                              BoxShadow(color: Color(0x220A1930), blurRadius: 20, offset: Offset(0, 8)),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: isMobile ? 50 : 64,
                                height: isMobile ? 50 : 64,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .15),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withValues(alpha: .3), width: 2),
                                ),
                                child: Icon(Icons.shield_rounded, color: Colors.white, size: isMobile ? 26 : 34),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: isMobile ? 17 : 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Badge #$badge • $station',
                                      style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 11.5),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: (currentDuty ? LuxuryTheme.green : LuxuryTheme.amber).withValues(alpha: .25),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        currentDuty ? 'ON DUTY • ACTIVE' : 'OFF DUTY • OFFLINE',
                                        style: TextStyle(
                                          color: currentDuty ? Colors.lightGreenAccent : Colors.orangeAccent,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                  const SizedBox(height: 20),

                  // Duty Status Toggle Card
                  CommandCard(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: (currentDuty ? LuxuryTheme.green : LuxuryTheme.amber).withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            currentDuty ? Icons.radar_rounded : Icons.power_settings_new_rounded,
                            color: currentDuty ? LuxuryTheme.green : LuxuryTheme.amber,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentDuty ? 'Duty Mode Active' : 'Offline Mode',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: LuxuryTheme.ink),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                currentDuty
                                    ? 'Receiving traffic alerts and ambulance corridors'
                                    : 'Alerts paused while offline',
                                style: const TextStyle(color: LuxuryTheme.muted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: currentDuty,
                          onChanged: busy ? null : _handleDutyToggle,
                          activeThumbColor: LuxuryTheme.green,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Assignment Details Card
                  CommandCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Command & Assignment Details',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: LuxuryTheme.ink),
                        ),
                        const SizedBox(height: 16),
                        _profileRow(Icons.traffic_rounded, 'Assigned Junction', junction, LuxuryTheme.blue),
                        const Divider(height: 24),
                        _profileRow(Icons.local_police_rounded, 'Police Station', station, LuxuryTheme.navy),
                        const Divider(height: 24),
                        _profileRow(Icons.badge_rounded, 'Officer Badge', badge, LuxuryTheme.cyan),
                        const Divider(height: 24),
                        _profileRow(Icons.alternate_email_rounded, 'Email', email, LuxuryTheme.muted),
                        const Divider(height: 24),
                        _profileRow(Icons.phone_rounded, 'Phone', phone, LuxuryTheme.muted),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Sign Out
                  OutlinedButton.icon(
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout_rounded, color: LuxuryTheme.red),
                    label: const Text('Sign Out of Police Command', style: TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w800)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: LuxuryTheme.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ],
  ),
),
);
}

  Widget _profileRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: LuxuryTheme.muted, fontSize: 10, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: LuxuryTheme.ink, fontSize: 13, fontWeight: FontWeight.w800), softWrap: true),
            ],
          ),
        ),
      ],
    );
  }
}
