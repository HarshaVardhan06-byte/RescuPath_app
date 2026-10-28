import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final email = TextEditingController();
  final api = ApiClient();
  String? message;
  String? error;
  String? devToken;
  bool loading = false;

  Future<void> submit() async {
    if (email.text.trim().isEmpty) {
      setState(() => error = 'Enter your email address.');
      return;
    }
    setState(() { loading = true; error = null; message = null; devToken = null; });
    try {
      final r = await api.post('/auth/forgot-password', {'email': email.text.trim()});
      if (mounted) {
        setState(() {
          message = r['message']?.toString();
          devToken = r['development_token']?.toString();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Brand(),
                    const SizedBox(height: 28),
                    const Text('Reset password', style: TextStyle(color: AppTheme.ink, fontSize: 29, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    const Text('We will request a secure reset token for your account.', style: TextStyle(color: AppTheme.muted)),
                    const SizedBox(height: 22),
                    TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Work email', prefixIcon: Icon(Icons.email_outlined))),
                    const SizedBox(height: 18),
                    PrimaryButton(label: loading ? 'Sending…' : 'Send reset instructions', icon: Icons.mark_email_read_outlined, background: AppTheme.blue, onPressed: loading ? null : submit),
                    if (message != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(message!, style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.w700))),
                    if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: AppTheme.red, fontWeight: FontWeight.w700))),
                    if (devToken != null) Padding(padding: const EdgeInsets.only(top: 12), child: SelectableText('Development reset token:\n$devToken', style: const TextStyle(color: AppTheme.amber, fontSize: 11))),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  @override
  void dispose() { email.dispose(); super.dispose(); }
}
