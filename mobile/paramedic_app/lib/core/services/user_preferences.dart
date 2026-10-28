import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UserPreferences {
  static const _storage = FlutterSecureStorage();

  static Future<bool> _readBool(String key, {required bool fallback}) async {
    final value = await _storage.read(key: key);
    if (value == null) return fallback;
    return value == 'true';
  }

  static Future<void> _writeBool(String key, bool value) =>
      _storage.write(key: key, value: value.toString());

  static Future<bool> get dutyMode =>
      _readBool('pref_duty_mode', fallback: true);

  static Future<bool> get notificationsEnabled =>
      _readBool('pref_notifications', fallback: true);

  static Future<bool> get highAccuracyGps =>
      _readBool('pref_high_accuracy_gps', fallback: true);

  static Future<bool> get autoRouteRefresh =>
      _readBool('pref_auto_route_refresh', fallback: true);

  static Future<void> setDutyMode(bool value) =>
      _writeBool('pref_duty_mode', value);

  static Future<void> setNotificationsEnabled(bool value) =>
      _writeBool('pref_notifications', value);

  static Future<void> setHighAccuracyGps(bool value) =>
      _writeBool('pref_high_accuracy_gps', value);

  static Future<void> setAutoRouteRefresh(bool value) =>
      _writeBool('pref_auto_route_refresh', value);
}
