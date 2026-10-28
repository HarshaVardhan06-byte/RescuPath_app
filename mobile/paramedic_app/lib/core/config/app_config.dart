import 'package:flutter/foundation.dart';

class AppConfig {
  static String get apiBaseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;
    if (kIsWeb) return 'http://127.0.0.1:8000';
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  static String get mapTileUrl {
    const override = String.fromEnvironment('MAP_TILE_URL');
    return override.isNotEmpty
        ? override
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  static String get googleWebClientId =>
      const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static String get appleServiceId =>
      const String.fromEnvironment('APPLE_SERVICE_ID');

  static String get supportEmail =>
      const String.fromEnvironment('SUPPORT_EMAIL', defaultValue: '');

  static String get supportPhone =>
      const String.fromEnvironment('SUPPORT_PHONE', defaultValue: '');
}
