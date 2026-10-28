import 'package:flutter/material.dart';
import 'core/app_api.dart';
import 'core/luxury_theme.dart';
import 'features/dashboard_page.dart';
import 'features/login_page.dart';

void main() => runApp(const RescuPathHospitalApp());

class RescuPathHospitalApp extends StatelessWidget {
  const RescuPathHospitalApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(title: 'RescuPath Hospital Command', debugShowCheckedModeBanner: false, theme: LuxuryTheme.build(), home: const _HospitalRoot());
}

class _HospitalRoot extends StatefulWidget { const _HospitalRoot(); @override State<_HospitalRoot> createState() => _HospitalRootState(); }
class _HospitalRootState extends State<_HospitalRoot> {
  final api = AppApi(); bool checking = true; bool signedIn = false;
  @override void initState() { super.initState(); _check(); }
  Future<void> _check() async { try { final token = await api.token(); if (token != null && token.isNotEmpty) { await api.get('/coordination/hospital/board'); signedIn = true; } } catch (_) { await api.logout(); } if (mounted) setState(() => checking = false); }
  @override Widget build(BuildContext context) { if (checking) return const Scaffold(body: Center(child: CircularProgressIndicator())); return signedIn ? HospitalDashboardPage(onLogout: () async { await api.logout(); if (mounted) setState(() => signedIn = false); }) : HospitalLoginPage(onSignedIn: () { if (mounted) setState(() => signedIn = true); }); }
}
