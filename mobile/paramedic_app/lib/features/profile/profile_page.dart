import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final api = ApiClient();
  Map<String, dynamic>? user; bool loading = true;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final r = await api.get('/auth/me'); if (mounted) setState(() => user = Map<String, dynamic>.from(r)); } catch (_) {} finally { if (mounted) setState(() => loading = false); } }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Sign out?'), content: const Text('Your active emergency data stays on the server. This only signs this device out.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out'))]));
    if (confirm != true) return;
    await api.logout();
    try { await GoogleSignIn().signOut(); } catch (_) {}
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 30), children: [
        PageHeader(eyebrow: 'Account', title: 'Profile', subtitle: 'Your identity, duty controls and support tools.'),
        const SizedBox(height: 16),
        SurfaceCard(gradient: const [Color(0xFF0D2342), Color(0xFF163A67)], child: Row(children: [Container(width: 72, height: 72, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .12), border: Border.all(color: Colors.white24, width: 2)), child: const Icon(Icons.person_rounded, color: Colors.white, size: 38)), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('PARAMEDIC', style: TextStyle(color: Color(0x99FFFFFF), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)), const SizedBox(height: 4), Text(user?['full_name']?.toString() ?? 'Paramedic', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 21)), Text(user?['email']?.toString() ?? '', style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11))]))]),
        ),
        const SizedBox(height: 14),
        if (loading) const LinearProgressIndicator(minHeight: 3),
        if (!loading) SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(user?['full_name']?.toString() ?? 'Paramedic', style: const TextStyle(color: AppTheme.ink, fontSize: 21, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(user?['email']?.toString() ?? '—', style: const TextStyle(color: AppTheme.muted)), if (user?['phone'] != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(user!['phone'].toString(), style: const TextStyle(color: AppTheme.muted, fontSize: 12))), const SizedBox(height: 11), Row(children: [StatusChip(user?['is_active'] == true ? 'ACCOUNT ACTIVE' : 'ACCOUNT DISABLED', color: user?['is_active'] == true ? AppTheme.green : AppTheme.red), const SizedBox(width: 7), const StatusChip('PARAMEDIC', color: AppTheme.blue)])])),
        const SizedBox(height: 14),
        _profileItem(Icons.person_outline_rounded, 'Personal information', 'Edit your name and phone', AppTheme.blue, () => Navigator.pushNamed(context, '/profile/personal').then((_) => _load())),
        _profileItem(Icons.tune_rounded, 'Settings', 'Duty mode, GPS and alerts', AppTheme.purple, () => Navigator.pushNamed(context, '/profile/settings')),
        _profileItem(Icons.help_outline_rounded, 'Help & support', 'FAQs, contact and emergency help', AppTheme.green, () => Navigator.pushNamed(context, '/profile/help')),
        _profileItem(Icons.notifications_none_rounded, 'Notifications', 'Response and system alerts', AppTheme.amber, () => Navigator.pushNamed(context, '/notifications')),
        const SizedBox(height: 10),
        PrimaryButton(label: 'Sign out', icon: Icons.logout_rounded, background: AppTheme.red, onPressed: _logout),
        const SizedBox(height: 18),
        const Center(child: Text('RescuPath • Emergency coordination made simple', style: TextStyle(color: AppTheme.muted, fontSize: 10))),
      ]);

  Widget _profileItem(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) => Padding(padding: const EdgeInsets.only(bottom: 10), child: SurfaceCard(onTap: onTap, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), child: Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: color)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w800)), Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 10))])), const Icon(Icons.chevron_right_rounded, color: AppTheme.ink)])));
}
