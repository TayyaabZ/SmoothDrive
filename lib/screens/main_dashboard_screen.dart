import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'active_drive_screen.dart';
import 'drive_history_screen.dart';
import 'route_preview_screen.dart';
import 'settings_screen.dart';
import '../services/drive_settings.dart';
import '../services/sync_service.dart';
import '../models/road_hazard.dart';

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  final MapController mapController = MapController();
  final ValueNotifier<LatLng?> _userLocNotifier = ValueNotifier(null);
  bool _autoFollow = true;
  StreamSubscription<Position>? positionSub;
  List<RoadHazard> _globalHazards = [];
  bool _isLoading = false;
  RoadHazard? _selectedHazard;
  final Set<String> _expandedCoords = {};

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
    _loadGlobalHazards();
  }

  Future<void> _loadGlobalHazards() async {
    setState(() {
      _isLoading = true;
    });
    final serverIp = context.read<DriveSettings>().serverIp;
    final items = await SyncService().fetchGlobalHazards(serverIp);
    if (!mounted) {
      return;
    }
    setState(() {
      _globalHazards = items;
      _isLoading = false;
    });
  }

  Future<void> _startLocationUpdates() async {
    final isBatterySaver = context.read<DriveSettings>().batterySaver;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    await positionSub?.cancel();
    positionSub =
        Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: isBatterySaver ? 15 : 5,
          ),
        ).listen((position) {
          final loc = LatLng(position.latitude, position.longitude);
          _userLocNotifier.value = loc;
          if (_autoFollow) {
            mapController.move(loc, 15);
          }
        });
  }

  @override
  void dispose() {
    positionSub?.cancel();
    super.dispose();
  }

  String _coordKey(RoadHazard item) {
    final lat = item.lat.toStringAsFixed(5);
    final lng = item.lng.toStringAsFixed(5);
    return '$lat,$lng';
  }

  Marker buildSingleMarker(RoadHazard item) {
    final magnitude = item.impactMagnitude;
    final isPothole = item.hazardType == 'pothole';
    final markerColor = isPothole
        ? (magnitude < 8.0
            ? Colors.yellow
            : (magnitude <= 15.0 ? Colors.orange : Colors.red))
        : Colors.cyan;
    final markerIcon = isPothole ? Icons.warning : Icons.waves;
    final badgeTextColor = isPothole
        ? (magnitude > 15.0 ? Colors.white : Colors.black)
        : Colors.black;
    final level = isPothole
        ? (magnitude < 8.0
            ? 'Minor Pothole'
            : (magnitude <= 15.0 ? 'Moderate Pothole' : 'Severe Pothole'))
        : 'Speed Bump';
    final iso = item.timestamp.toIso8601String();
    final datePart = iso.substring(0, 10);
    final timePart = iso.substring(11, 16);
    final dateBits = datePart.split('-');
    final dateText = '${dateBits[2]}/${dateBits[1]}/${dateBits[0]}';
    return Marker(
      point: LatLng(item.lat, item.lng),
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onTap: () => setState(() => _selectedHazard = item),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(markerIcon, color: markerColor),
                if (item.hitCount > 1)
                  Positioned(
                    top: -5,
                    right: -5,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: markerColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          item.hitCount.toString(),
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: badgeTextColor,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_selectedHazard == item)
            Positioned(
              bottom: 35,
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: markerColor,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            level,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: markerColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Impact: ${magnitude.toStringAsFixed(1)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Hits: ${item.hitCount}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$dateText $timePart',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Marker buildClusterMarker(RoadHazard item, int totalHits, String key) {
    final magnitude = item.impactMagnitude;
    final isPothole = item.hazardType == 'pothole';
    final markerColor = isPothole
        ? (magnitude < 8.0
            ? Colors.yellow
            : (magnitude <= 15.0 ? Colors.orange : Colors.red))
        : Colors.cyan;
    final badgeTextColor = isPothole
        ? (magnitude > 15.0 ? Colors.white : Colors.black)
        : Colors.black;
    return Marker(
      point: LatLng(item.lat, item.lng),
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () => setState(() => _expandedCoords.add(key)),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(Icons.layers, color: markerColor),
            Positioned(
              top: -5,
              right: -5,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: markerColor,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    totalHits.toString(),
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: badgeTextColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker buildOffsetMarker(RoadHazard item, int index, int total, String key) {
    final magnitude = item.impactMagnitude;
    final isPothole = item.hazardType == 'pothole';
    final markerColor = isPothole
        ? (magnitude < 8.0
            ? Colors.yellow
            : (magnitude <= 15.0 ? Colors.orange : Colors.red))
        : Colors.cyan;
    final markerIcon = isPothole ? Icons.warning : Icons.waves;
    final badgeTextColor = isPothole
        ? (magnitude > 15.0 ? Colors.white : Colors.black)
        : Colors.black;
    final level = isPothole
        ? (magnitude < 8.0
            ? 'Minor Pothole'
            : (magnitude <= 15.0 ? 'Moderate Pothole' : 'Severe Pothole'))
        : 'Speed Bump';
    final iso = item.timestamp.toIso8601String();
    final datePart = iso.substring(0, 10);
    final timePart = iso.substring(11, 16);
    final dateBits = datePart.split('-');
    final dateText = '${dateBits[2]}/${dateBits[1]}/${dateBits[0]}';
    final offsetFactor = (index - (total - 1) / 2) * 0.00018;
    return Marker(
      point: LatLng(item.lat, item.lng + offsetFactor),
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onTap: () => setState(() => _selectedHazard = item),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(markerIcon, color: markerColor),
                if (item.hitCount > 1)
                  Positioned(
                    top: -5,
                    right: -5,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: markerColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          item.hitCount.toString(),
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: badgeTextColor,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_selectedHazard == item)
            Positioned(
              bottom: 35,
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: markerColor,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            level,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: markerColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Impact: ${magnitude.toStringAsFixed(1)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Hits: ${item.hitCount}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$dateText $timePart',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: const LatLng(33.6844, 73.0479),
              initialZoom: 15,
              minZoom: 4.0,
              onTap: (tapPosition, latLng) => setState(() {
                _selectedHazard = null;
                _expandedCoords.clear();
              }),
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  _autoFollow = false;
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'dev.tayyaab.smoothdrive',
                tileDisplay: const TileDisplay.instantaneous(),
              ),
              MarkerLayer(
                markers: () {
                  final grouped = <String, List<RoadHazard>>{};
                  for (final item in _globalHazards) {
                    final key = _coordKey(item);
                    final list = grouped[key];
                    if (list == null) {
                      grouped[key] = [item];
                    } else {
                      list.add(item);
                    }
                  }
                  final markers = <Marker>[];
                  for (final entry in grouped.entries) {
                    final key = entry.key;
                    final items = entry.value;
                    if (items.length == 1) {
                      markers.add(buildSingleMarker(items.first));
                    } else if (!_expandedCoords.contains(key)) {
                      final totalHits = items.fold<int>(
                        0,
                        (sum, item) => sum + item.hitCount,
                      );
                      markers.add(buildClusterMarker(items.first, totalHits, key));
                    } else {
                      final total = items.length;
                      for (var i = 0; i < total; i++) {
                        markers.add(buildOffsetMarker(items[i], i, total, key));
                      }
                    }
                  }
                  return markers;
                }(),
              ),
              ValueListenableBuilder<LatLng?>(
                valueListenable: _userLocNotifier,
                builder: (context, value, child) {
                  if (value == null) {
                    return const MarkerLayer(markers: []);
                  }
                  return MarkerLayer(
                    markers: [
                      Marker(
                        point: value,
                        width: 20,
                        height: 20,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blueAccent,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blueAccent.withValues(alpha: 0.5),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Colors.transparent,
                    const Color(0xFF121212).withValues(alpha: 0.8),
                  ],
                  stops: [0.4, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.route_outlined, color: Colors.white),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RoutePreviewScreen(),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 64,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.history, color: Colors.white),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DriveHistoryScreen(),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(32),
                topRight: Radius.circular(32),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E).withValues(alpha: 0.75),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ready to Drive?',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ActiveDriveScreen(
                                initialLocation: _userLocNotifier.value,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 72),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(36),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.play_arrow, size: 28),
                            const SizedBox(width: 10),
                            Text(
                              'START TRACKING',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                                letterSpacing: 1.2,
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
          Positioned(
            bottom: 140,
            right: 16,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.my_location, color: Colors.white),
                onPressed: () {
                  _autoFollow = true;
                  final loc = _userLocNotifier.value;
                  if (loc != null) {
                    mapController.move(loc, 15);
                  }
                },
              ),
            ),
          ),
          Positioned(
            bottom: 200,
            right: 16,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFFFB300),
                          ),
                        ),
                      )
                    : const Icon(Icons.refresh, color: Colors.white),
                onPressed: _isLoading ? null : _loadGlobalHazards,
              ),
            ),
          ),
        ],
      ),
    );
  }
}