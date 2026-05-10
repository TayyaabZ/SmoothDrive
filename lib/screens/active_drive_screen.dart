import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/road_hazard.dart';
import '../services/database_service.dart';
import '../services/drive_settings.dart';
import '../services/sync_service.dart';
import 'settings_screen.dart';

class ActiveDriveScreen extends StatefulWidget {
  const ActiveDriveScreen({super.key, this.initialLocation});

  final LatLng? initialLocation;

  @override
  State<ActiveDriveScreen> createState() => _ActiveDriveScreenState();
}

class _ActiveDriveScreenState extends State<ActiveDriveScreen> {
  final MapController mapController = MapController();
  late final ValueNotifier<LatLng?> _userLocNotifier = ValueNotifier(
    widget.initialLocation,
  );
  bool _autoFollow = true;
  late DateTime _driveStartTime;
  int _sessionHazardsCount = 0;
  int _pendingQueue = 0;
  final List<RoadHazard> _sessionHazardsList = [];
  List<RoadHazard> _globalHazards = [];
  RoadHazard? _warnHazard;
  bool _showWarn = false;
  DateTime? _lastWarnAt;
  double _warnDistance = 0.0;
  final ValueNotifier<bool> _isOnlineNotifier = ValueNotifier(true);
  final ValueNotifier<bool> _isGpsEnabled = ValueNotifier(true);
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  StreamSubscription<ServiceStatus>? _gpsSubscription;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  final List<RoadHazard> _hazards = [];
  final ValueNotifier<List<double>> _recentZNotifier = ValueNotifier([
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
  ]);
  double _speedKmh = 0.0;
  DateTime? _lastHazardAt;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  double _lastPitchRate = 0.0;

  @override
  void initState() {
    _driveStartTime = DateTime.now();
    super.initState();
    _loadHazards();
    _loadGlobalHazards();
    _refreshPendingQueue();
    _startLocationUpdates();
    _startAccelerometer();
    _startGyroscope();
    _initGpsStatus();
    _networkSubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final hasNet =
          results.isNotEmpty && results.first != ConnectivityResult.none;
      _isOnlineNotifier.value = hasNet;
    });
  }

  void _initGpsStatus() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    _isGpsEnabled.value = enabled;
    await _gpsSubscription?.cancel();
    _gpsSubscription = Geolocator.getServiceStatusStream().listen((status) {
      _isGpsEnabled.value = status == ServiceStatus.enabled;
    });
  }

  Future<void> _loadHazards() async {
    final items = await DatabaseService().getHazards();
    if (!mounted) {
      return;
    }
    setState(() {
      _hazards
        ..clear()
        ..addAll(items);
    });
  }

  Future<void> _loadGlobalHazards() async {
    final serverIp = context.read<DriveSettings>().serverIp;
    final items = await SyncService().fetchGlobalHazards(serverIp);
    if (!mounted) {
      return;
    }
    setState(() {
      _globalHazards = items;
    });
  }

  Future<void> _refreshPendingQueue() async {
    final items = await DatabaseService().getHazards();
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingQueue = items.length;
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
    await _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: isBatterySaver ? 15 : 5,
          ),
        ).listen((position) {
          final speed = position.speed.isFinite ? position.speed * 3.6 : 0.0;
          final loc = LatLng(position.latitude, position.longitude);
          if (_autoFollow) {
            mapController.move(loc, 16);
          }
          _userLocNotifier.value = loc;
          _speedKmh = speed < 0 ? 0.0 : speed;
          final now = DateTime.now();
          for (final item in _globalHazards) {
            final distance = Geolocator.distanceBetween(
              loc.latitude,
              loc.longitude,
              item.lat,
              item.lng,
            );
            final lastWarn = _lastWarnAt;
            if (distance < 50 &&
                (lastWarn == null ||
                    now.difference(lastWarn).inSeconds >= 30)) {
              setState(() {
                _warnHazard = item;
                _showWarn = true;
                _warnDistance = distance;
                _lastWarnAt = now;
              });
              HapticFeedback.vibrate();
              Future.delayed(const Duration(milliseconds: 100), () {
                HapticFeedback.vibrate();
              });
              Future.delayed(const Duration(seconds: 5), () {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _showWarn = false;
                });
              });
              break;
            }
          }
        });
  }

  void _startAccelerometer() {
    _accelerometerSubscription = userAccelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen(_handleAccelerometerEvent);
  }

  void _startGyroscope() {
    _gyroscopeSubscription =
        gyroscopeEventStream(
          samplingPeriod: const Duration(milliseconds: 20),
        ).listen((event) {
          _lastPitchRate = event.x.abs() + event.y.abs();
        });
  }

  void _handleAccelerometerEvent(UserAccelerometerEvent event) {
    final impact = event.z.abs();
    final newList = List<double>.from(_recentZNotifier.value);
    newList.removeAt(0);
    newList.add(impact);
    _recentZNotifier.value = newList;

    final sensitivity = context.read<DriveSettings>().sensitivity;
    final adjusted = sensitivity.clamp(0.0, 1.0).toDouble();
    final threshold = 12.0 - (adjusted * 6.5);
    final side = sqrt(pow(event.x, 2) + pow(event.y, 2));
    final now = DateTime.now();
    final last = _lastHazardAt;
    RoadHazard? hazard;

    if (_speedKmh >= 3.0 &&
        impact >= threshold &&
        side <= impact * 0.8 &&
        (last == null || now.difference(last).inMilliseconds >= 1500)) {
      final currentLoc = _userLocNotifier.value;
      final lat = currentLoc?.latitude ?? 0.0;
      final lng = currentLoc?.longitude ?? 0.0;
      debugPrint(
        '--- SHOCK DETECTED! Angular Velocity: $_lastPitchRate rad/s ---',
      );
      final type = _lastPitchRate > 0.8 ? 'speed_bump' : 'pothole';
      hazard = RoadHazard(
        lat: lat,
        lng: lng,
        timestamp: now,
        impactMagnitude: impact,
        hazardType: type,
      );
    }

    final validHazard = hazard;
    if (validHazard == null) {
      return;
    }

    DatabaseService().insertHazard(validHazard);
    if (!mounted) {
      return;
    }
    setState(() {
      _hazards.add(validHazard);
      _lastHazardAt = now;
      _sessionHazardsCount++;
      _pendingQueue++;
      _sessionHazardsList.add(validHazard);
    });
    if (validHazard.hazardType == 'speed_bump') {
      HapticFeedback.vibrate();
      Future.delayed(const Duration(milliseconds: 120), () {
        HapticFeedback.vibrate();
      });
    } else {
      HapticFeedback.vibrate();
    }
  }

  Future<void> _stopSessionAndShowSummary() async {
    await _positionSubscription?.cancel();
    await _accelerometerSubscription?.cancel();
    await _networkSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();
    var potholes = 0;
    var bumps = 0;
    for (final item in _sessionHazardsList) {
      if (item.hazardType == 'pothole') {
        potholes++;
      } else {
        bumps++;
      }
    }

    if (!mounted) return;

    final settings = context.read<DriveSettings>();
    final serverIp = settings.serverIp;
    final isWifiOnly = settings.wifiOnly;
    await SyncService().syncHazards(serverIp, isWifiOnly);
    final elapsed = DateTime.now().difference(_driveStartTime);
    final durationString = '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s';
    final pendingCount = (await DatabaseService().getHazards()).length;
    var minorCount = 0;
    var moderateCount = 0;
    var severeCount = 0;
    var maxImpact = 0.0;
    for (final item in _sessionHazardsList) {
      final magnitude = item.impactMagnitude;
      if (magnitude > maxImpact) {
        maxImpact = magnitude;
      }
      if (magnitude < 8.0) {
        minorCount++;
      } else if (magnitude <= 15.0) {
        moderateCount++;
      } else {
        severeCount++;
      }
    }
    final totalCount = _sessionHazardsList.length;
    final ratingText = severeCount > 0
        ? 'Rough Road Detected'
        : (moderateCount > 0
              ? 'Moderate Bumps Detected'
              : (minorCount > 0
                    ? 'Mostly Smooth Drive'
                    : 'Perfect Smooth Drive!'));
    final ratingColor = severeCount > 0
        ? const Color(0xFFFF5252)
        : (moderateCount > 0
              ? Colors.orange
              : (minorCount > 0 ? Colors.yellow : const Color(0xFF00E676)));
    var showDetails = false;
    final bars = <Widget>[];
    if (minorCount > 0) {
      bars.add(
        Expanded(
          flex: minorCount,
          child: Container(color: Colors.yellow),
        ),
      );
    }
    if (moderateCount > 0) {
      bars.add(
        Expanded(
          flex: moderateCount,
          child: Container(color: Colors.orange),
        ),
      );
    }
    if (severeCount > 0) {
      bars.add(
        Expanded(
          flex: severeCount,
          child: Container(color: Colors.red),
        ),
      );
    }
    if (!mounted) {
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ratingText,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: ratingColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Duration: $durationString',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hazards Detected: $_sessionHazardsCount',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Worst Impact: ${maxImpact.toStringAsFixed(1)}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFFF5252),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: totalCount == 0
                          ? Container(
                              height: 12,
                              color: const Color(0xFF00E676),
                            )
                          : SizedBox(height: 12, child: Row(children: bars)),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        setDialogState(() {
                          showDetails = !showDetails;
                        });
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                      child: Text(
                        showDetails
                            ? 'Hide Technical Details'
                            : 'Show Technical Details',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (showDetails)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF242424),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Minor: $minorCount | Moderate: $moderateCount | Severe: $severeCount',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Database Sync Queue: $pendingCount pending upload',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () async {
                          final sessionData = {
                            'start_time': _driveStartTime.toIso8601String(),
                            'duration': durationString,
                            'hazard_count': _sessionHazardsCount,
                            'max_impact': maxImpact,
                            'pothole_count': potholes,
                            'speed_bump_count': bumps,
                          };
                          await DatabaseService().insertSession(sessionData);

                          if (!context.mounted) return;

                          Navigator.pop(context);
                          Navigator.pop(context);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFFB300),
                        ),
                        child: Text(
                          'Done',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _networkSubscription?.cancel();
    _gpsSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displaySpeed = _speedKmh.isFinite ? _speedKmh : 0.0;
    final start = widget.initialLocation ?? const LatLng(0, 0);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: start,
              initialZoom: 16,
              minZoom: 4.0,
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
              ),
              MarkerLayer(
                markers: _hazards.map((item) {
                  final magnitude = item.impactMagnitude;
                  final markerColor = magnitude < 8.0
                      ? Colors.yellow
                      : (magnitude <= 15.0 ? Colors.orange : Colors.red);
                  return Marker(
                    point: LatLng(item.lat, item.lng),
                    width: 24,
                    height: 24,
                    child: Icon(Icons.warning, color: markerColor),
                  );
                }).toList(),
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
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            right: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: const Color(0xFF1E1E1E).withValues(alpha: 0.85),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Color(0xFFFFB300),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$_sessionHazardsCount Hazards',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Row(
                        children: [
                          const Icon(
                            Icons.cloud_off,
                            color: Colors.white54,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _pendingQueue.toString(),
                            style: GoogleFonts.inter(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF00E676),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${displaySpeed.toStringAsFixed(0)} km/h',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      ValueListenableBuilder<bool>(
                        valueListenable: _isOnlineNotifier,
                        builder: (context, isOnline, child) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isOnline
                                    ? Icons.cloud_done_rounded
                                    : Icons.wifi_off_rounded,
                                size: 16,
                                color: isOnline
                                    ? const Color(0xFF00E676)
                                    : const Color(0xFFFFB300),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isOnline ? 'Synced' : 'Offline',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isOnline
                                      ? const Color(0xFF00E676)
                                      : const Color(0xFFFFB300),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Container(width: 1, height: 16, color: Colors.white24),
                      IconButton(
                        icon: const Icon(
                          Icons.settings,
                          size: 18,
                          color: Colors.white70,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ).then((_) {
                            _loadHazards();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 80,
            left: 12,
            right: 12,
            child: _showWarn && _warnHazard != null
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _warnHazard!.impactMagnitude > 10.0
                            ? const Color(0xFFFF5252)
                            : Colors.orange,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFFFB300),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hazard Ahead!',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _warnHazard!.hazardType == 'speed_bump'
                                    ? 'Speed bump'
                                    : 'Pothole',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_warnDistance.round()} m ahead',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
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
                        'Live Accelerometer Data',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ValueListenableBuilder<List<double>>(
                        valueListenable: _recentZNotifier,
                        builder: (context, values, child) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: values.map((value) {
                              final height = (value * 4.0)
                                  .clamp(4.0, 48.0)
                                  .toDouble();
                              final color = height > 24.0
                                  ? const Color(0xFFFF5252)
                                  : const Color(0xFFFFB300);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 80),
                                  width: 4,
                                  height: height,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _stopSessionAndShowSummary,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5252),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 72),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(36),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.stop_rounded, size: 28),
                            const SizedBox(width: 10),
                            Text(
                              'STOP DRIVE & SAVE',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
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
          ValueListenableBuilder<bool>(
            valueListenable: _isGpsEnabled,
            builder: (context, isEnabled, child) {
              if (isEnabled) {
                return const SizedBox.shrink();
              }
              return Positioned.fill(
                child: Container(
                  color: const Color(0xFF121212).withValues(alpha: 0.95),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_off_rounded,
                          size: 48,
                          color: Color(0xFFFF5252),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'GPS Connection Lost',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please enable GPS to resume tracking.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
