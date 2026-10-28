import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  LocationSettings _settings({bool highAccuracy = true}) {
    final accuracy = highAccuracy ? LocationAccuracy.high : LocationAccuracy.medium;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: 8,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'RescuPath live navigation',
          notificationText: 'Emergency location tracking is active.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: accuracy,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 8,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }
    return LocationSettings(accuracy: accuracy, distanceFilter: 8);
  }

  Future<Position> currentPosition({bool highAccuracy = true}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are disabled.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Location permission was not granted.');
    }
    return Geolocator.getCurrentPosition(locationSettings: _settings(highAccuracy: highAccuracy));
  }

  Stream<Position> stream({bool highAccuracy = true}) =>
      Geolocator.getPositionStream(locationSettings: _settings(highAccuracy: highAccuracy));
}
