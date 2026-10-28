// import 'package:flutter/material.dart';

// import '../../core/network/api_client.dart';
// import '../../core/theme/app_theme.dart';
// import '../../core/widgets/app_widgets.dart';
// import '../ambulance/ambulance_page.dart';
// import '../emergency/create_emergency_page.dart';
// import '../emergency/active_emergency_page.dart';
// import '../hospitals/nearby_hospitals_page.dart';
// import '../map/live_location_page.dart';
// import '../profile/profile_page.dart';

// class HomePage extends StatefulWidget {
//   const HomePage({super.key});
//   @override
//   State<HomePage> createState() => _HomePageState();
// }

// class _HomePageState extends State<HomePage> {
//   int tab = 0;
//   final api = ApiClient();
//   Map<String, dynamic> summary = {};

//   Future<void> load() async {
//     try {
//       final r = await api.get('/dashboard/summary');
//       if (mounted) setState(() => summary = Map<String, dynamic>.from(r));
//     } catch (_) {}
//   }

//   @override
//   void initState() { super.initState(); load(); }

//   @override
//   Widget build(BuildContext context) {
//     final pages = [
//       _home(),
//       const LiveLocationPage(),
//       const _EmergencyList(),
//       const ProfilePage(),
//     ];
//     return Scaffold(
//       body: SafeArea(child: IndexedStack(index: tab, children: pages)),
//       bottomNavigationBar: BottomNav(index: tab, onTap: (i) => setState(() => tab = i)),
//     );
//   }

//   Widget _home() => RefreshIndicator(
//         onRefresh: load,
//         child: ListView(
//           padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
//           physics: const AlwaysScrollableScrollPhysics(),
//           children: [
//             Row(children: [
//               Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('READY FOR RESPONSE', style: TextStyle(color: AppTheme.blue, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.3)), const SizedBox(height: 4), Text('Good morning, ${summary['user_name'] ?? 'Paramedic'}', style: const TextStyle(color: AppTheme.ink, fontSize: 25, fontWeight: FontWeight.w900))])),
//               AppIconButton(icon: Icons.notifications_none_rounded, tooltip: 'Notifications', onTap: () => Navigator.pushNamed(context, '/notifications')),
//             ]),
//             const SizedBox(height: 14),
//             SurfaceCard(
//               padding: EdgeInsets.zero,
//               radius: 28,
//               gradient: const [AppTheme.navy, AppTheme.navy2],
//               child: ClipRRect(
//                 borderRadius: BorderRadius.circular(28),
//                 child: Stack(children: [
//                   Positioned(right: -25, bottom: -5, child: Opacity(opacity: .96, child: SizedBox(width: 250, height: 180, child: Image.asset('assets/ambulance_hero.png', fit: BoxFit.cover)))),
//                   Padding(padding: const EdgeInsets.fromLTRB(20, 20, 185, 22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//                     const StatusChip('ON DUTY', color: AppTheme.green),
//                     const SizedBox(height: 16),
//                     const Text('Move faster.\nCoordinate smarter.', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, height: 1.03)),
//                     const SizedBox(height: 8),
//                     const Text('Live GPS, hospital matching and emergency communications in one place.', style: TextStyle(color: Color(0xD9FFFFFF), fontSize: 11, height: 1.35)),
//                   ])),
//                 ]),
//               ),
//             ),
//             const SizedBox(height: 14),
//             SurfaceCard(
//               padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
//               gradient: const [Color(0xFFFFEEF0), Color(0xFFFFF7F8)],
//               onTap: () => setState(() => tab = 2),
//               child: Row(children: [
//                 Container(width: 48, height: 48, decoration: BoxDecoration(color: AppTheme.red.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.emergency_rounded, color: AppTheme.red, size: 26)),
//                 const SizedBox(width: 13),
//                 const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Active emergencies', style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900, fontSize: 16)), SizedBox(height: 3), Text('Tap to manage the current response list', style: TextStyle(color: AppTheme.muted, fontSize: 11))])),
//                 const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppTheme.ink),
//               ]),
//             ),
//             const SizedBox(height: 18),
//             const Text('QUICK ACTIONS', style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 12)),
//             const SizedBox(height: 10),
//             GridView.count(
//               crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
//               crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.35,
//               children: [
//                 ActionTile(icon: Icons.emergency_rounded, title: 'New Emergency', subtitle: 'Report an incident', color: AppTheme.red, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateEmergencyPage()))),
//                 ActionTile(icon: Icons.local_shipping_rounded, title: 'My Ambulance', subtitle: 'Vehicle status', color: AppTheme.blue, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AmbulancePage()))),
//                 ActionTile(icon: Icons.location_on_rounded, title: 'Live GPS', subtitle: 'Track the unit', color: AppTheme.green, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveLocationPage()))),
//                 ActionTile(icon: Icons.local_hospital_rounded, title: 'Hospitals', subtitle: 'Find & navigate', color: AppTheme.purple, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NearbyHospitalsPage()))),
//               ],
//             ),
//             const SizedBox(height: 18),
//             SurfaceCard(
//               child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//                 const Row(children: [Text('Today at a glance', style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900, fontSize: 16)), Spacer(), Icon(Icons.insights_rounded, color: AppTheme.blue)]),
//                 const SizedBox(height: 14),
//                 Row(children: [MetricCard(icon: Icons.bolt_rounded, value: '${summary['total_responses'] ?? 0}', label: 'Responses', color: AppTheme.blue), const SizedBox(width: 8), MetricCard(icon: Icons.emergency_rounded, value: '${summary['active_emergencies'] ?? 0}', label: 'Active', color: AppTheme.red), const SizedBox(width: 8), MetricCard(icon: Icons.pending_actions_rounded, value: '${summary['pending'] ?? 0}', label: 'Pending', color: AppTheme.amber)]),
//               ]),
//             ),
//             const SizedBox(height: 18),
//             const Text('RESPONSE TOOLS', style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 12)),
//             const SizedBox(height: 10),
//             SurfaceCard(child: Column(children: [
//               _row(Icons.map_rounded, 'Command map', 'See live GPS and current route', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveLocationPage())), AppTheme.blue),
//               const Divider(height: 20),
//               _row(Icons.local_hospital_rounded, 'Hospital network', 'Search real nearby hospitals', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NearbyHospitalsPage())), AppTheme.purple),
//               const Divider(height: 20),
//               _row(Icons.settings_rounded, 'App settings', 'Duty, GPS and notification controls', () => Navigator.pushNamed(context, '/profile/settings'), AppTheme.ink),
//             ])),
//           ],
//         ),
//       );

//   Widget _row(IconData icon, String title, String subtitle, VoidCallback onTap, Color color) => ListTile(
//         contentPadding: EdgeInsets.zero,
//         onTap: onTap,
//         leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: color)),
//         title: Text(title, style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w800)),
//         subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
//         trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.ink),
//       );
// }

// class _EmergencyList extends StatefulWidget {
//   const _EmergencyList();
//   @override State<_EmergencyList> createState() => _EmergencyListState();
// }

// class _EmergencyListState extends State<_EmergencyList> {
//   final api = ApiClient();
//   List<dynamic> items = [];
//   bool loading = true;
//   String? error;

//   Future<void> load() async {
//     setState(() { loading = true; error = null; });
//     try {
//       final r = await api.get('/dashboard/emergencies');
//       if (mounted) setState(() => items = r is List ? r : []);
//     } catch (e) {
//       if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
//     } finally { if (mounted) setState(() => loading = false); }
//   }

//   @override void initState() { super.initState(); load(); }

//   @override
//   Widget build(BuildContext context) => ListView(
//         padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
//         children: [
//           PageHeader(eyebrow: 'Response center', title: 'Emergencies', subtitle: 'Monitor active responses and open the live workflow.'),
//           const SizedBox(height: 16),
//           PrimaryButton(label: 'Create new emergency', icon: Icons.add_alert_rounded, background: AppTheme.red, onPressed: () => Navigator.pushNamed(context, '/emergency')),
//           const SizedBox(height: 16),
//           if (loading) const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
//           else if (error != null) SurfaceCard(child: Column(children: [const Icon(Icons.cloud_off_rounded, color: AppTheme.red, size: 36), const SizedBox(height: 10), Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)), const SizedBox(height: 12), TextButton.icon(onPressed: load, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again'))]))
//           else if (items.isEmpty) const SurfaceCard(child: Row(children: [Icon(Icons.check_circle_outline_rounded, color: AppTheme.green), SizedBox(width: 10), Expanded(child: Text('No emergency records yet.', style: TextStyle(color: AppTheme.muted))) ]))
//           else ...items.map((e) {
//             final map = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
//             final id = map['id']?.toString() ?? 'unknown';
//             return Padding(padding: const EdgeInsets.only(bottom: 10), child: SurfaceCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveEmergencyPage(emergencyId: id, initialSeverity: map['severity']?.toString() ?? 'HIGH'))), child: Row(children: [
//               Container(width: 48, height: 48, decoration: BoxDecoration(color: AppTheme.red.withValues(alpha: .10), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.emergency_rounded, color: AppTheme.red)),
//               const SizedBox(width: 12),
//               Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Emergency #${id.length > 8 ? id.substring(0, 8) : id}', style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('${map['severity'] ?? 'HIGH'} • ${map['status'] ?? 'DISPATCHED'}', style: const TextStyle(color: AppTheme.muted, fontSize: 11))])),
//               const Icon(Icons.chevron_right_rounded, color: AppTheme.ink),
//             ])));
//           }),
//         ],
//       );
// }
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../ambulance/ambulance_page.dart';
import '../emergency/create_emergency_page.dart';
import '../emergency/active_emergency_page.dart';
import '../hospitals/nearby_hospitals_page.dart';
import '../map/live_location_page.dart';
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

  Future<void> load() async {
    try {
      final r = await api.get('/dashboard/summary');
      if (mounted) setState(() => summary = Map<String, dynamic>.from(r));
    } catch (_) {}
  }

  @override
  void initState() { super.initState(); load(); }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _home(),
      const LiveLocationPage(),
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
            final narrow = constraints.maxWidth < 700;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 18),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                    const SizedBox(height: 5),
                                    Text(
                                      'Good morning, ${summary['user_name'] ?? 'Paramedic'}',
                                      style: const TextStyle(
                                        color: AppTheme.ink,
                                        fontSize: 27,
                                        fontWeight: FontWeight.w900,
                                        height: 1.1,
                                      ),
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
                          const SizedBox(height: 18),

                          // Premium dark hero banner.
                          SurfaceCard(
                            padding: EdgeInsets.zero,
                            radius: 28,
                            gradient: const [AppTheme.navy, AppTheme.navy2],
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Stack(
                                children: [
                                  Positioned(
                                    right: -5,
                                    bottom: 0,
                                    child: IgnorePointer(
                                      child: Opacity(
                                        opacity: .96,
                                        child: SizedBox(
                                          width: narrow ? 145 : 310,
                                          height: narrow ? 132 : 192,
                                          child: Image.asset(
                                            'assets/ambulance_hero.png',
                                            fit: BoxFit.cover,
                                            alignment: Alignment.centerRight,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      22,
                                      22,
                                      narrow ? 130 : 270,
                                      24,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const StatusChip(
                                          'ON DUTY',
                                          color: AppTheme.green,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Move faster.\nCoordinate smarter.',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: narrow ? 22 : 29,
                                            fontWeight: FontWeight.w900,
                                            height: 1.03,
                                          ),
                                        ),
                                        const SizedBox(height: 9),
                                        const Text(
                                          'Live GPS, hospital matching and emergency communications in one place.',
                                          style: TextStyle(
                                            color: Color(0xD9FFFFFF),
                                            fontSize: 12,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // One clear entry point to the active response list.
                          SurfaceCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 15,
                            ),
                            radius: 24,
                            gradient: const [
                              Color(0xFFFFEEF0),
                              Color(0xFFFFF7F8),
                            ],
                            onTap: () => setState(() => tab = 2),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color:
                                        AppTheme.red.withValues(alpha: .12),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.emergency_rounded,
                                    color: AppTheme.red,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Active emergencies',
                                        style: TextStyle(
                                          color: AppTheme.ink,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${summary['active_emergencies'] ?? 0} active • Tap to manage response',
                                        style: const TextStyle(
                                          color: AppTheme.muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 21,
                                  color: AppTheme.ink,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'QUICK ACTIONS',
                            style: TextStyle(
                              color: AppTheme.ink,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 11),

                          // Compact cards avoid the tall, empty tiles on desktop.
                          LayoutBuilder(
                            builder: (context, gridConstraints) {
                              final columns =
                                  gridConstraints.maxWidth >= 620 ? 2 : 1;
                              return GridView(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio:
                                      columns == 2 ? 3.15 : 4.4,
                                ),
                                children: [
                                  _quickAction(
                                    icon: Icons.emergency_rounded,
                                    title: 'New emergency',
                                    subtitle: 'Report an incident',
                                    color: AppTheme.red,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const CreateEmergencyPage(),
                                      ),
                                    ),
                                  ),
                                  _quickAction(
                                    icon: Icons.local_shipping_rounded,
                                    title: 'My ambulance',
                                    subtitle: 'Vehicle and duty status',
                                    color: AppTheme.blue,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const AmbulancePage(),
                                      ),
                                    ),
                                  ),
                                  _quickAction(
                                    icon: Icons.navigation_rounded,
                                    title: 'Live GPS',
                                    subtitle: 'Track the current unit',
                                    color: AppTheme.green,
                                    onTap: () => setState(() => tab = 1),
                                  ),
                                  _quickAction(
                                    icon: Icons.local_hospital_rounded,
                                    title: 'Find hospitals',
                                    subtitle: 'Nearby facilities and routes',
                                    color: AppTheme.purple,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const NearbyHospitalsPage(),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 20),

                          // Live summary metrics remain connected to the dashboard API.
                          SurfaceCard(
                            radius: 24,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Today at a glance',
                                        style: TextStyle(
                                          color: AppTheme.ink,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.insights_rounded,
                                      color: AppTheme.blue,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: MetricCard(
                                        icon: Icons.bolt_rounded,
                                        value:
                                            '${summary['total_responses'] ?? 0}',
                                        label: 'Responses',
                                        color: AppTheme.blue,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: MetricCard(
                                        icon: Icons.emergency_rounded,
                                        value:
                                            '${summary['active_emergencies'] ?? 0}',
                                        label: 'Active',
                                        color: AppTheme.red,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: MetricCard(
                                        icon: Icons.pending_actions_rounded,
                                        value: '${summary['pending'] ?? 0}',
                                        label: 'Pending',
                                        color: AppTheme.amber,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
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

  Widget _quickAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SurfaceCard(
      radius: 22,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: AppTheme.muted,
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String title, String subtitle, VoidCallback onTap, Color color) => ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onTap,
        leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.ink),
      );
}

class _EmergencyList extends StatefulWidget {
  const _EmergencyList();
  @override State<_EmergencyList> createState() => _EmergencyListState();
}

class _EmergencyListState extends State<_EmergencyList> {
  final api = ApiClient();
  List<dynamic> items = [];
  bool loading = true;
  String? error;

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final r = await api.get('/dashboard/emergencies');
      if (mounted) setState(() => items = r is List ? r : []);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => loading = false); }
  }

  @override void initState() { super.initState(); load(); }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          PageHeader(eyebrow: 'Response center', title: 'Emergencies', subtitle: 'Monitor active responses and open the live workflow.'),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Create new emergency', icon: Icons.add_alert_rounded, background: AppTheme.red, onPressed: () => Navigator.pushNamed(context, '/emergency')),
          const SizedBox(height: 16),
          if (loading) const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          else if (error != null) SurfaceCard(child: Column(children: [const Icon(Icons.cloud_off_rounded, color: AppTheme.red, size: 36), const SizedBox(height: 10), Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)), const SizedBox(height: 12), TextButton.icon(onPressed: load, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again'))]))
          else if (items.isEmpty) const SurfaceCard(child: Row(children: [Icon(Icons.check_circle_outline_rounded, color: AppTheme.green), SizedBox(width: 10), Expanded(child: Text('No emergency records yet.', style: TextStyle(color: AppTheme.muted))) ]))
          else ...items.map((e) {
            final map = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
            final id = map['id']?.toString() ?? 'unknown';
            return Padding(padding: const EdgeInsets.only(bottom: 10), child: SurfaceCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveEmergencyPage(emergencyId: id, initialSeverity: map['severity']?.toString() ?? 'HIGH'))), child: Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: AppTheme.red.withValues(alpha: .10), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.emergency_rounded, color: AppTheme.red)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Emergency #${id.length > 8 ? id.substring(0, 8) : id}', style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('${map['severity'] ?? 'HIGH'} • ${map['status'] ?? 'DISPATCHED'}', style: const TextStyle(color: AppTheme.muted, fontSize: 11))])),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.ink),
            ])));
          }),
        ],
      );
}
