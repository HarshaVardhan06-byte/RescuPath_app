import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
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
      if (mounted) {
        final err = e.toString().replaceFirst('Exception: ', '');
        if (err.contains('People API') || err.contains('people.googleapis.com')) {
          setState(() => error = 'Google People API must be enabled for project 1084797807505. Visit: console.developers.google.com/apis/api/people.googleapis.com/overview?project=1084797807505');
        } else {
          setState(() => error = err);
        }
      }
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _google() async {
    setState(() { busy = true; error = null; });
    try {
      final google = GoogleSignIn(
        clientId: AppApi.googleWebClientId,
        serverClientId: kIsWeb ? null : AppApi.googleWebClientId,
        scopes: const ['email', 'profile'],
      );
      final account = await google.signIn();
      if (account == null) {
        setState(() => busy = false);
        return;
      }
      final auth = await account.authentication;
      final token = (auth.idToken != null && auth.idToken!.isNotEmpty)
          ? auth.idToken!
          : (auth.accessToken ?? '');
      if (token.isEmpty) {
        throw Exception('Google did not return an identity or access token.');
      }
      final response = await api.post('/auth/oauth/google', {
        'id_token': token,
        'full_name': account.displayName,
        'role': 'POLICE',
      });
      await api.saveToken(response['access_token'].toString());
      await api.get('/coordination/police/board');
      widget.onSignedIn();
    } catch (e) {
      await api.logout();
      if (mounted) {
        final err = e.toString().replaceFirst('Exception: ', '');
        if (err.contains('People API') || err.contains('people.googleapis.com')) {
          setState(() => error = 'Google People API must be enabled for project 1084797807505. Visit: console.developers.google.com/apis/api/people.googleapis.com/overview?project=1084797807505');
        } else {
          setState(() => error = err);
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _apple() async {
    setState(() { busy = true; error = null; });
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      if (credential.identityToken == null || credential.identityToken!.isEmpty) {
        throw Exception('Apple did not return an identity token.');
      }
      final fullName = [credential.givenName, credential.familyName].whereType<String>().join(' ');
      final response = await api.post('/auth/oauth/apple', {
        'id_token': credential.identityToken,
        'full_name': fullName.isEmpty ? 'Traffic Police Officer' : fullName,
        'role': 'POLICE',
      });
      await api.saveToken(response['access_token'].toString());
      await api.get('/coordination/police/board');
      widget.onSignedIn();
    } catch (e) {
      await api.logout();
      if (mounted) {
        final err = e.toString().replaceFirst('Exception: ', '');
        if (err.contains('People API') || err.contains('people.googleapis.com')) {
          setState(() => error = 'Google People API must be enabled for project 1084797807505. Visit: console.developers.google.com/apis/api/people.googleapis.com/overview?project=1084797807505');
        } else {
          setState(() => error = err);
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
          if (!registering)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : _openForgotPassword,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Forgot password?', style: TextStyle(color: LuxuryTheme.blue, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          if (error != null) ...[const SizedBox(height: 12), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: LuxuryTheme.red.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)), child: Text(error!, style: const TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w700)))],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : submit,
            icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.arrow_forward_rounded),
            label: Text(busy ? 'Please wait…' : registering ? 'Create police account' : 'Sign in'),
            style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.blue, minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('OR CONTINUE WITH', style: TextStyle(color: LuxuryTheme.muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: busy ? null : _google,
            icon: const Icon(Icons.g_mobiledata, size: 24, color: LuxuryTheme.ink),
            label: const Text('Continue with Google', style: TextStyle(fontWeight: FontWeight.w800, color: LuxuryTheme.ink)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              side: const BorderSide(color: LuxuryTheme.line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : _apple,
            icon: const Icon(Icons.apple, size: 22, color: LuxuryTheme.ink),
            label: const Text('Continue with Apple', style: TextStyle(fontWeight: FontWeight.w800, color: LuxuryTheme.ink)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              side: const BorderSide(color: LuxuryTheme.line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: busy ? null : () => setState(() { registering = !registering; error = null; }), child: Text(registering ? 'Already enrolled? Sign in' : 'First time? Create officer profile')),
        ])),
        const SizedBox(height: 12), const Text('Live alerts refresh automatically. Allow location access while on duty.', textAlign: TextAlign.center, style: TextStyle(color: LuxuryTheme.muted, fontSize: 12)),
      ]),
    )))),
  );

  void _openForgotPassword() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _PoliceForgotSheet(
        api: api,
        initialEmail: email.text.trim(),
        onSuccess: (newPwd, userEmail) {
          setState(() {
            email.text = userEmail;
            password.text = newPwd;
            error = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password updated! You can now sign in with your new password.'),
              backgroundColor: LuxuryTheme.green,
            ),
          );
        },
      ),
    );
  }

  @override void dispose() { name.dispose(); email.dispose(); password.dispose(); phone.dispose(); badge.dispose(); station.dispose(); junction.dispose(); super.dispose(); }
}

class _PoliceForgotSheet extends StatefulWidget {
  final AppApi api;
  final String initialEmail;
  final void Function(String newPassword, String userEmail) onSuccess;

  const _PoliceForgotSheet({
    required this.api,
    required this.initialEmail,
    required this.onSuccess,
  });

  @override
  State<_PoliceForgotSheet> createState() => _PoliceForgotSheetState();
}

class _PoliceForgotSheetState extends State<_PoliceForgotSheet> {
  final emailCtrl = TextEditingController();
  final otpCtrl = TextEditingController();
  final newPwdCtrl = TextEditingController();
  final confirmPwdCtrl = TextEditingController();

  int step = 1; // 1 = Request OTP, 2 = Verify & Set Password
  bool loading = false;
  String? modalError;
  String? modalSuccess;
  bool obscure = true;

  @override
  void initState() {
    super.initState();
    emailCtrl.text = widget.initialEmail;
  }

  Future<void> _sendOtp() async {
    final mail = emailCtrl.text.trim();
    if (mail.isEmpty || !mail.contains('@')) {
      setState(() => modalError = 'Enter a valid officer work email or Gmail.');
      return;
    }
    setState(() {
      loading = true;
      modalError = null;
      modalSuccess = null;
    });
    try {
      await widget.api.post('/auth/forgot-password', {'email': mail});
      if (mounted) {
        setState(() {
          step = 2;
          modalSuccess = 'A 6-digit verification code has been dispatched directly to $mail. Please check your Gmail inbox (and Spam folder), then enter the code below to set your new password.';
          otpCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => modalError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final mail = emailCtrl.text.trim();
    final otp = otpCtrl.text.trim();
    final pwd = newPwdCtrl.text;
    final confirm = confirmPwdCtrl.text;

    if (otp.length < 4) {
      setState(() => modalError = 'Enter the 6-digit verification code.');
      return;
    }
    if (pwd.length < 6) {
      setState(() => modalError = 'Password must be at least 6 characters.');
      return;
    }
    if (pwd != confirm) {
      setState(() => modalError = 'Passwords do not match.');
      return;
    }

    setState(() {
      loading = true;
      modalError = null;
      modalSuccess = null;
    });
    try {
      await widget.api.post('/auth/reset-password', {
        'email': mail,
        'otp': otp,
        'new_password': pwd,
      });
      if (mounted) {
        widget.onSuccess(pwd, mail);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => modalError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.lock_reset_rounded, color: LuxuryTheme.blue, size: 24),
                const SizedBox(width: 8),
                Text(
                  step == 1 ? 'Reset Police Password' : 'Enter Verification OTP',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: LuxuryTheme.ink),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              step == 1
                  ? 'Enter your registered Gmail or police work email to receive an automated verification code.'
                  : 'Enter the 6-digit verification code sent to ${emailCtrl.text.trim()} and your new password.',
              style: const TextStyle(fontSize: 12, color: LuxuryTheme.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (step == 1) ...[
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Officer work email / Gmail',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: loading ? null : _sendOtp,
                icon: loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.mark_email_read_outlined),
                label: Text(loading ? 'Sending OTP…' : 'Send Verification OTP'),
                style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.blue, minimumSize: const Size.fromHeight(48)),
              ),
            ] else ...[
              TextField(
                controller: otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: '6-digit OTP code',
                  prefixIcon: Icon(Icons.pin_outlined),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newPwdCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'New password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmPwdCtrl,
                obscureText: obscure,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: Icon(Icons.lock_reset_outlined),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: loading ? null : _resetPassword,
                icon: loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_rounded),
                label: Text(loading ? 'Updating…' : 'Confirm & Reset Password'),
                style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.green, minimumSize: const Size.fromHeight(48)),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: loading ? null : _sendOtp,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Resend code', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: loading ? null : () => setState(() { step = 1; modalError = null; modalSuccess = null; }),
                    child: const Text('Change email', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
            if (modalSuccess != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: LuxuryTheme.green.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)),
                child: Text(modalSuccess!, style: const TextStyle(color: LuxuryTheme.green, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
            if (modalError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: LuxuryTheme.red.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)),
                child: Text(modalError!, style: const TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    otpCtrl.dispose();
    newPwdCtrl.dispose();
    confirmPwdCtrl.dispose();
    super.dispose();
  }
}
