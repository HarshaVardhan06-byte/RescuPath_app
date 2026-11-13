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
  final otp = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  final api = ApiClient();

  int step = 1; // 1 = Enter Email, 2 = Enter OTP and New Password
  String? message;
  String? error;
  bool loading = false;
  bool obscurePassword = true;

  Future<void> sendOtp() async {
    final emailText = email.text.trim();
    if (emailText.isEmpty || !emailText.contains('@')) {
      setState(() => error = 'Please enter a valid Gmail or work email address.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
      message = null;
    });
    try {
      await api.post('/auth/forgot-password', {'email': emailText});
      if (mounted) {
        setState(() {
          step = 2;
          message = 'A 6-digit verification code has been dispatched directly to $emailText. Please check your Gmail inbox (and Spam folder), then enter the code below to set your new password.';
          otp.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resetPassword() async {
    final otpText = otp.text.trim();
    final pwd = newPassword.text;
    final confirm = confirmPassword.text;

    if (otpText.length < 4) {
      setState(() => error = 'Please enter the verification OTP code.');
      return;
    }
    if (pwd.length < 6) {
      setState(() => error = 'Password must be at least 6 characters.');
      return;
    }
    if (pwd != confirm) {
      setState(() => error = 'Passwords do not match.');
      return;
    }

    setState(() {
      loading = true;
      error = null;
      message = null;
    });
    try {
      final r = await api.post('/auth/reset-password', {
        'email': email.text.trim(),
        'otp': otpText,
        'new_password': pwd,
      });
      if (mounted) {
        setState(() {
          message = r['message']?.toString() ?? 'Password updated successfully! Redirecting…';
        });
        await Future.delayed(const Duration(milliseconds: 1400));
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Password Assistance', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Brand(),
                    const SizedBox(height: 24),
                    Text(
                      step == 1 ? 'Reset your password' : 'Enter verification code',
                      style: const TextStyle(color: AppTheme.ink, fontSize: 26, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      step == 1
                          ? 'Enter your registered Gmail or work email. An automated verification OTP will be sent to your inbox.'
                          : 'Enter the 6-digit verification code sent to ${email.text.trim()} along with your new password.',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 22),
                    if (step == 1) ...[
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Registered Gmail / Work email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: loading ? 'Sending OTP…' : 'Send Reset Code to Gmail',
                        icon: Icons.mark_email_read_outlined,
                        background: AppTheme.blue,
                        onPressed: loading ? null : sendOtp,
                      ),
                    ] else ...[
                      TextField(
                        controller: otp,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: '6-digit OTP code',
                          prefixIcon: Icon(Icons.pin_outlined),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: newPassword,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => obscurePassword = !obscurePassword),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmPassword,
                        obscureText: obscurePassword,
                        decoration: const InputDecoration(
                          labelText: 'Confirm new password',
                          prefixIcon: Icon(Icons.lock_reset_outlined),
                        ),
                      ),
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: loading ? 'Updating…' : 'Confirm & Reset Password',
                        icon: Icons.check_circle_outline_rounded,
                        background: AppTheme.green,
                        onPressed: loading ? null : resetPassword,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: loading ? null : sendOtp,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Resend code', style: TextStyle(fontSize: 12)),
                          ),
                          TextButton(
                            onPressed: loading
                                ? null
                                : () => setState(() {
                                      step = 1;
                                      error = null;
                                      message = null;
                                    }),
                            child: const Text('Change email', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                    if (message != null)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.green.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.green.withValues(alpha: .3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppTheme.green, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                message!,
                                style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (error != null)
                      Container(
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.red.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.red.withValues(alpha: .3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppTheme.red, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                error!,
                                style: const TextStyle(color: AppTheme.red, fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  @override
  void dispose() {
    email.dispose();
    otp.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }
}
