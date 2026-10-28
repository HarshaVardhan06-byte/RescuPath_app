import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  final api = ApiClient();
  bool loading = false;
  String? error;

  Future<void> _register() async {
    if (name.text.trim().length < 2 || email.text.trim().isEmpty || password.text.length < 8) {
      setState(() => error = 'Use a name, email, and password of at least 8 characters.');
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      final r = await api.post('/auth/register', {'full_name': name.text.trim(), 'email': email.text.trim(), 'phone': phone.text.trim().isEmpty ? null : phone.text.trim(), 'password': password.text});
      await api.saveToken(r['access_token'].toString());
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SurfaceCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Brand(), const SizedBox(height: 24),
                  const Text('Create your account', style: TextStyle(color: AppTheme.ink, fontSize: 29, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text('Your assigned ambulance and response profile will be created automatically.', style: TextStyle(color: AppTheme.muted)),
                  const SizedBox(height: 22),
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline))),
                  const SizedBox(height: 12),
                  TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Work email', prefixIcon: Icon(Icons.email_outlined))),
                  const SizedBox(height: 12),
                  TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined))),
                  const SizedBox(height: 12),
                  TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline))),
                  if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: AppTheme.red))),
                  const SizedBox(height: 20),
                  PrimaryButton(label: loading ? 'Creating…' : 'Create account', icon: Icons.rocket_launch_outlined, onPressed: loading ? null : _register, background: AppTheme.red),
                  const SizedBox(height: 10),
                  Center(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Already registered? Sign in'))),
                ]),
              ),
            ),
          ),
        ),
      );

  @override
  void dispose() { name.dispose(); email.dispose(); phone.dispose(); password.dispose(); super.dispose(); }
}
