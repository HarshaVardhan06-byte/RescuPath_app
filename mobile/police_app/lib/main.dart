import 'package:flutter/material.dart';
import 'core/app_api.dart';
import 'core/luxury_theme.dart';
import 'features/dashboard_page.dart';
import 'features/login_page.dart';

void main() => runApp(const RescuPathPoliceApp());

class RescuPathPoliceApp extends StatelessWidget {
  const RescuPathPoliceApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RescuPath Police Command',
    debugShowCheckedModeBanner: false,
    theme: LuxuryTheme.build(),
    home: const _PoliceRoot(),
  );
}

class _PoliceRoot extends StatefulWidget {
  const _PoliceRoot();
  @override State<_PoliceRoot> createState() => _PoliceRootState();
}

class _PoliceRootState extends State<_PoliceRoot> {
  final api = AppApi();
  bool checking = true;
  bool signedIn = false;
  @override
  void initState() { super.initState(); _check(); }
  Future<void> _check() async {
    try {
      final token = await api.token();
      if (token != null && token.isNotEmpty) {
        await api.get('/coordination/police/board');
        signedIn = true;
      }
    } catch (_) { await api.logout(); }
    if (mounted) setState(() => checking = false);
  }
  @override
  Widget build(BuildContext context) {
    if (checking) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return signedIn
      ? PoliceDashboardPage(onLogout: () async { await api.logout(); if (mounted) setState(() => signedIn = false); })
      : PoliceLoginPage(onSignedIn: () { if (mounted) setState(() => signedIn = true); });
  }
}
