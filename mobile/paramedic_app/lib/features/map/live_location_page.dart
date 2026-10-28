import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/services/location_service.dart';
import '../../core/services/user_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

class LiveLocationPage extends StatefulWidget {
  const LiveLocationPage({super.key});

  @override
  State<LiveLocationPage> createState() => _LiveLocationPageState();
}

class _LiveLocationPageState extends State<LiveLocationPage> {
  final LocationService location = LocationService();
  final MapController map = MapController();

  StreamSubscription? sub;
  LatLng? current;
  bool tracking = false;
  bool starting = false;
  String status = 'GPS ready';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (starting || tracking) return;

    setState(() {
      starting = true;
      status = 'Getting GPS location…';
    });

    try {
      final high = await UserPreferences.highAccuracyGps;
      final position = await location.currentPosition(highAccuracy: high);

      if (!mounted) return;

      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        current = point;
        status = 'Accuracy ${position.accuracy.toStringAsFixed(0)} m';
      });

      // The map controller may not be attached yet during the first build.
      // The location marker will still be shown; the map can be recentered later.
      try {
        map.move(point, 15);
      } catch (_) {
        // MapController is not attached yet.
      }

      _listen(high);
    } catch (error) {
      if (mounted) {
        setState(() {
          status = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => starting = false);
      }
    }
  }

  void _listen(bool high) {
    sub?.cancel();

    if (mounted) {
      setState(() => tracking = true);
    }

    sub = location.stream(highAccuracy: high).listen(
      (position) {
        if (!mounted) return;

        final point = LatLng(position.latitude, position.longitude);
        setState(() {
          current = point;
          status = 'Accuracy ${position.accuracy.toStringAsFixed(0)} m';
        });

        try {
          map.move(point, map.camera.zoom);
        } catch (_) {
          // MapController is not attached yet.
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          tracking = false;
          status = 'GPS stream error: $error';
        });
      },
    );
  }

  void _stop() {
    sub?.cancel();
    sub = null;

    if (mounted) {
      setState(() {
        tracking = false;
        status = 'GPS paused';
      });
    }
  }

  Future<void> _openMap() async {
    final point = current;
    if (point == null) return;

    final uri = Uri.https(
      'www.google.com',
      '/maps/search/',
      {
        'api': '1',
        'query': '${point.latitude},${point.longitude}',
      },
    );

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    sub?.cancel();
    map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF091323),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: map,
              options: MapOptions(
                initialCenter: current ?? const LatLng(12.9716, 77.5946),
                initialZoom: 13,
              ),
              children: [
                TileLayer(
                  urlTemplate: AppConfig.mapTileUrl,
                  userAgentPackageName: 'com.rescupath.paramedic_app',
                ),
                if (current != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: current!,
                        width: 58,
                        height: 58,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(
                              color: AppTheme.blue,
                              width: 4,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x660A63FF),
                                blurRadius: 24,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.navigation_rounded,
                            color: AppTheme.blue,
                            size: 30,
                          ),
                        ),
                      ),
                    ],
                  ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xDD0A1930),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xDD0A1930),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: const Text(
                          'Live GPS Command Map',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.red,
                        borderRadius: BorderRadius.circular(17),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x44000000),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: TextButton.icon(
                        onPressed: _openMap,
                        icon: const Icon(
                          Icons.map_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                        label: const Text(
                          'Open Map',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 10,
                          ),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 100,
            left: 14,
            right: 14,
            child: SurfaceCard(
              color: Colors.white,
              radius: 20,
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tracking ? AppTheme.green : AppTheme.red,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          starting
                              ? 'Starting GPS…'
                              : tracking
                                  ? 'GPS live and updating'
                                  : 'GPS paused',
                          style: const TextStyle(
                            color: AppTheme.ink,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          status,
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: starting
                        ? null
                        : tracking
                            ? _stop
                            : _start,
                    icon: Icon(
                      tracking
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: AppTheme.blue,
                      size: 31,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  color: Colors.white,
                  radius: 22,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _coord(
                              'Latitude',
                              current?.latitude.toStringAsFixed(6) ?? '—',
                            ),
                          ),
                          Expanded(
                            child: _coord(
                              'Longitude',
                              current?.longitude.toStringAsFixed(6) ?? '—',
                            ),
                          ),
                          Expanded(
                            child: _coord('Tracking', tracking ? 'ON' : 'OFF'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: PrimaryButton(
                              label: 'Recenter',
                              icon: Icons.my_location_rounded,
                              outlined: true,
                              background: AppTheme.blue,
                              onPressed: current == null
                                  ? null
                                  : () {
                                      try {
                                        map.move(current!, 16);
                                      } catch (_) {
                                        // MapController is not attached yet.
                                      }
                                    },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PrimaryButton(
                              label: 'Open Map',
                              icon: Icons.map_rounded,
                              background: AppTheme.red,
                              onPressed: _openMap,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coord(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.ink,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}
