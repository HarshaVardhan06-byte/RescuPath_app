import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final api = ApiClient();
  bool loading = false;
  bool obscure = true;
  String? error;

  Future<void> _login() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your email and password.');
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      final r = await api.post('/auth/login', {'email': email.text.trim(), 'password': password.text});
      await api.saveToken(r['access_token'].toString());
      if (mounted) Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _google() async {
    try {
      final google = GoogleSignIn(serverClientId: AppConfig.googleWebClientId.isEmpty ? null : AppConfig.googleWebClientId);
      final account = await google.signIn();
      if (account == null) return;
      final auth = await account.authentication;
      if (auth.idToken == null) throw Exception('Google did not return an identity token.');
      final r = await api.post('/auth/oauth/google', {'id_token': auth.idToken});
      await api.saveToken(r['access_token'].toString());
      if (mounted) Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _apple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName]);
      final r = await api.post('/auth/oauth/apple', {'id_token': credential.identityToken, 'full_name': [credential.givenName, credential.familyName].whereType<String>().join(' ')});
      await api.saveToken(r['access_token'].toString());
      if (mounted) Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SurfaceCard(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Brand(),
                      const SizedBox(height: 30),
                      const Text('Welcome back', style: TextStyle(color: AppTheme.ink, fontSize: 30, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      const Text('Continue your response shift with RescuPath.', style: TextStyle(color: AppTheme.muted)),
                      const SizedBox(height: 24),
                      TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Work email', prefixIcon: Icon(Icons.alternate_email_rounded))),
                      const SizedBox(height: 12),
                      TextField(controller: password, obscureText: obscure, decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
                      Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pushNamed(context, '/forgot'), child: const Text('Forgot password?'))),
                      if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error!, style: const TextStyle(color: AppTheme.red, fontWeight: FontWeight.w700))),
                      PrimaryButton(label: loading ? 'Signing in…' : 'Sign in', icon: Icons.arrow_forward_rounded, onPressed: loading ? null : _login, background: AppTheme.blue),
                      const SizedBox(height: 14),
                      Row(children: const [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('OR', style: TextStyle(color: AppTheme.muted, fontSize: 10, fontWeight: FontWeight.w800))), Expanded(child: Divider())]),
                      const SizedBox(height: 14),
                      PrimaryButton(label: 'Continue with Google', icon: Icons.g_mobiledata, onPressed: _google, outlined: true, background: AppTheme.ink),
                      const SizedBox(height: 10),
                      PrimaryButton(label: 'Continue with Apple', icon: Icons.apple, onPressed: _apple, outlined: true, background: AppTheme.ink),
                      const SizedBox(height: 14),
                      TextButton(onPressed: () => Navigator.pushNamed(context, '/register'), child: const Text('Create a paramedic account')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }
}
