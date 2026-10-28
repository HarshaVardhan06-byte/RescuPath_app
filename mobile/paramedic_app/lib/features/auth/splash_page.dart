import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final api = ApiClient();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    final token = await api.token();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    try {
      await api.get('/auth/me');
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (_) {
      await api.logout();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF7FAFF), Color(0xFFEAF3FF)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Brand(),
                const SizedBox(height: 18),
                const Text('Emergency coordination, simplified.', style: TextStyle(color: AppTheme.muted)),
                const SizedBox(height: 48),
                SizedBox(
                  width: 110,
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(99),
                    backgroundColor: Colors.white,
                    color: AppTheme.red,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
