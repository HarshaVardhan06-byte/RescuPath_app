import 'package:flutter/material.dart';
import '../core/app_api.dart';
import '../core/luxury_theme.dart';

class PoliceLoginPage extends StatefulWidget {
  final VoidCallback onSignedIn;
  const PoliceLoginPage({super.key, required this.onSignedIn});
  @override State<PoliceLoginPage> createState() => _PoliceLoginPageState();
}

class _PoliceLoginPageState extends State<PoliceLoginPage> {
  final api = AppApi();
  final name = TextEditingController(); final email = TextEditingController(); final password = TextEditingController();
  final phone = TextEditingController(); final badge = TextEditingController(); final station = TextEditingController(); final junction = TextEditingController();
  bool registering = false; bool busy = false; bool obscure = true; String? error;

  Future<void> submit() async {
    if (email.text.trim().isEmpty || password.text.isEmpty || (registering && [name, badge, station, junction].any((c) => c.text.trim().isEmpty))) {
      setState(() => error = registering ? 'Complete name, work email, password, badge, station and junction.' : 'Enter your work email and password.'); return;
    }
    setState(() { busy = true; error = null; });
    try {
      final response = registering
        ? await api.post('/coordination/police/register', {'full_name': name.text.trim(), 'email': email.text.trim(), 'password': password.text, 'phone': phone.text.trim().isEmpty ? null : phone.text.trim(), 'badge_number': badge.text.trim(), 'station_name': station.text.trim(), 'junction_name': junction.text.trim()})
        : await api.post('/auth/login', {'email': email.text.trim(), 'password': password.text});
      await api.saveToken(response['access_token'].toString());
      await api.get('/coordination/police/board');
      widget.onSignedIn();
    } catch (e) {
      await api.logout();
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const BrandHeader(title: 'RescuPath Police', subtitle: 'Traffic coordination • Emergency response network', icon: Icons.local_police_rounded),
        const SizedBox(height: 22),
        CommandCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(registering ? 'Officer enrolment' : 'Officer sign in', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: LuxuryTheme.ink)),
          const SizedBox(height: 6), Text(registering ? 'Create your officer profile and assigned junction.' : 'Access active ambulance alerts for your duty junction.', style: const TextStyle(color: LuxuryTheme.muted)),
          const SizedBox(height: 18),
          if (registering) ...[
            TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Officer full name', prefixIcon: Icon(Icons.person_outline))), const SizedBox(height: 10),
            TextField(controller: badge, decoration: const InputDecoration(labelText: 'Badge / service number', prefixIcon: Icon(Icons.badge_outlined))), const SizedBox(height: 10),
            TextField(controller: station, decoration: const InputDecoration(labelText: 'Police station / unit', prefixIcon: Icon(Icons.account_balance_outlined))), const SizedBox(height: 10),
            TextField(controller: junction, decoration: const InputDecoration(labelText: 'Assigned traffic junction', prefixIcon: Icon(Icons.traffic_outlined))), const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact number (optional)', prefixIcon: Icon(Icons.phone_outlined))), const SizedBox(height: 10),
          ],
          TextField(controller: email, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: const InputDecoration(labelText: 'Work email', prefixIcon: Icon(Icons.alternate_email))), const SizedBox(height: 10),
          TextField(controller: password, obscureText: obscure, decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
          if (error != null) ...[const SizedBox(height: 12), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: LuxuryTheme.red.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)), child: Text(error!, style: const TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w700)))],
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: busy ? null : submit, icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.arrow_forward_rounded), label: Text(busy ? 'Please wait…' : registering ? 'Create police account' : 'Sign in'), style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.blue, minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
          const SizedBox(height: 8), TextButton(onPressed: busy ? null : () => setState(() { registering = !registering; error = null; }), child: Text(registering ? 'Already enrolled? Sign in' : 'First time? Create officer profile')),
        ])),
        const SizedBox(height: 12), const Text('Live alerts refresh automatically. Allow location access while on duty.', textAlign: TextAlign.center, style: TextStyle(color: LuxuryTheme.muted, fontSize: 12)),
      ]),
    )))),
  );

  @override void dispose() { name.dispose(); email.dispose(); password.dispose(); phone.dispose(); badge.dispose(); station.dispose(); junction.dispose(); super.dispose(); }
}
