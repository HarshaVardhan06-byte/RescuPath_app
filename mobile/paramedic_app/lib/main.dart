import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/ambulance/ambulance_page.dart';
import 'features/auth/forgot_password_page.dart';
import 'features/auth/login_page.dart';
import 'features/auth/register_page.dart';
import 'features/auth/splash_page.dart';
import 'features/emergency/active_emergency_page.dart';
import 'features/emergency/create_emergency_page.dart';
import 'features/home/home_page.dart';
import 'features/hospitals/nearby_hospitals_page.dart';
import 'features/map/live_location_page.dart';
import 'features/notifications/notifications_page.dart';
import 'features/profile/help_support_page.dart';
import 'features/profile/personal_info_page.dart';
import 'features/profile/profile_page.dart';
import 'features/profile/settings_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RescuPathApp());
}

class RescuPathApp extends StatelessWidget {
  const RescuPathApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RescuPath',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        initialRoute: '/',
        routes: {
          '/': (_) => const SplashPage(),
          '/login': (_) => const LoginPage(),
          '/register': (_) => const RegisterPage(),
          '/forgot': (_) => const ForgotPasswordPage(),
          '/home': (_) => const HomePage(),
          '/emergency': (_) => const CreateEmergencyPage(),
          '/active': (_) => const ActiveEmergencyPage(),
          '/location': (_) => const LiveLocationPage(),
          '/ambulance': (_) => const AmbulancePage(),
          '/hospitals': (_) => const NearbyHospitalsPage(),
          '/profile': (_) => const ProfilePage(),
          '/profile/personal': (_) => const PersonalInfoPage(),
          '/profile/settings': (_) => const SettingsPage(),
          '/profile/help': (_) => const HelpSupportPage(),
          '/notifications': (_) => const NotificationsPage(),
        },
      );
}
