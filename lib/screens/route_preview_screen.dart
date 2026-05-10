import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/road_hazard.dart';
import '../services/drive_settings.dart';
import '../services/sync_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model for a single autocomplete suggestion
// ─────────────────────────────────────────────────────────────────────────────
class _Suggestion {
  const _Suggestion({
    required this.displayName,
    required this.shortName,
    required this.latLng,
  });

  final String displayName; // full Nominatim name (kept for subtitle)
  final String shortName;   // first 2 parts — shown as the title
  final LatLng latLng;
}

// ─────────────────────────────────────────────────────────────────────────────
// Status kind
// ─────────────────────────────────────────────────────────────────────────────
enum _StatusKind { info, success, warning, error }

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class RoutePreviewScreen extends StatefulWidget {
  const RoutePreviewScreen({super.key});

  @override
  State<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends State<RoutePreviewScreen> {
  // Controllers
  final TextEditingController _searchCtrl = TextEditingController();
  final MapController _mapCtrl = MapController();
  final FocusNode _searchFocus = FocusNode();

  // Route state
  LatLng? _pinPoint;
  List<LatLng> _routePoints = [];
  List<RoadHazard> _routeHazards = [];

  // UI state
  bool _loading = false;
  bool _reversing = false;
  String _statusMsg = '';
  _StatusKind _statusKind = _StatusKind.info;

  // Autocomplete state
  List<_Suggestion> _suggestions = [];
  bool _fetchingSuggestions = false;
  Timer? _debounce;

  // ── Constants ──────────────────────────────────────────────────────────────
  static const _amber   = Color(0xFFFFB300);
  static const _surface = Color(0xFF1E1E1E);
  static const _bg      = Color(0xFF121212);
  static const _card    = Color(0xFF252525);
  static const _defaultCenter = LatLng(33.6844, 73.0479);

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onTextChanged);
    // Hide suggestions when the field loses focus
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus) _hideSuggestions();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onTextChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  // ── Text change handler ────────────────────────────────────────────────────
  void _onTextChanged() {
    if (!mounted) return;
    setState(() {}); // refresh suffix icon
    _scheduleSuggestionFetch();
  }

  void _scheduleSuggestionFetch() {
    _debounce?.cancel();
    final text = _searchCtrl.text.trim();

    // Need at least 3 chars to be worth calling the API
    if (text.length < 3) {
      if (_suggestions.isNotEmpty || _fetchingSuggestions) {
        setState(() {
          _suggestions = [];
          _fetchingSuggestions = false;
        });
      }
      return;
    }

    // 450 ms debounce — fires after user stops typing
    _debounce = Timer(const Duration(milliseconds: 450), () => _fetchSuggestions(text));
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    setState(() => _fetchingSuggestions = true);

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}&format=json&limit=5&addressdetails=0',
      );
      final res = await http
          .get(url, headers: {'User-Agent': 'SmoothDrive/1.0'})
          .timeout(const Duration(seconds: 6));

      if (!mounted) return;

      if (res.statusCode == 200) {
        final list = json.decode(res.body) as List<dynamic>;
        final results = <_Suggestion>[];
        for (final raw in list) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final lat = double.tryParse(item['lat'].toString());
          final lon = double.tryParse(item['lon'].toString());
          final name = item['display_name'] as String? ?? '';
          if (lat == null || lon == null || name.isEmpty) continue;
          final parts = name.split(',');
          results.add(_Suggestion(
            displayName: name,
            shortName: parts.take(2).join(',').trim(),
            latLng: LatLng(lat, lon),
          ));
        }
        setState(() {
          _suggestions = results;
          _fetchingSuggestions = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted) setState(() => _fetchingSuggestions = false);
  }

  void _selectSuggestion(_Suggestion s) {
    setState(() {
      _searchCtrl.text = s.shortName;
      _pinPoint = s.latLng;
      _routePoints = [];
      _routeHazards = [];
      _suggestions = [];
      _fetchingSuggestions = false;
      _statusMsg = '';
    });
    _searchFocus.unfocus();
    _mapCtrl.move(s.latLng, 14);
  }

  void _hideSuggestions() {
    if (_suggestions.isNotEmpty || _fetchingSuggestions) {
      setState(() {
        _suggestions = [];
        _fetchingSuggestions = false;
      });
    }
  }

  // ── Status helpers ─────────────────────────────────────────────────────────
  void _setStatus(String msg, {_StatusKind kind = _StatusKind.info}) {
    if (!mounted) return;
    setState(() {
      _statusMsg = msg;
      _statusKind = kind;
    });
  }

  // ── GPS ────────────────────────────────────────────────────────────────────
  Future<LatLng?> _getCurrentLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  // ── Reverse geocode ────────────────────────────────────────────────────────
  Future<void> _reverseGeocode(LatLng point) async {
    if (!mounted) return;
    setState(() => _reversing = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${point.latitude}&lon=${point.longitude}&format=json',
      );
      final res = await http
          .get(url, headers: {'User-Agent': 'SmoothDrive/1.0'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final display = data['display_name'];
        if (display is String && display.isNotEmpty) {
          final short = display.split(',').take(3).join(',').trim();
          if (mounted) {
            setState(() {
              _searchCtrl.text = short;
              _reversing = false;
            });
          }
          return;
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _searchCtrl.text =
            '${point.latitude.toStringAsFixed(5)}, '
            '${point.longitude.toStringAsFixed(5)}';
        _reversing = false;
      });
    }
  }

  // ── Forward geocode ────────────────────────────────────────────────────────
  Future<LatLng?> _geocodeText(String text) async {
    final coordRx =
        RegExp(r'^\s*([-+]?\d+(?:\.\d+)?),\s*([-+]?\d+(?:\.\d+)?)\s*$');
    final m = coordRx.firstMatch(text);
    if (m != null) {
      final lat = double.tryParse(m.group(1) ?? '');
      final lng = double.tryParse(m.group(2) ?? '');
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(text)}&format=json&limit=1',
      );
      final res = await http
          .get(url, headers: {'User-Agent': 'SmoothDrive/1.0'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final list = json.decode(res.body) as List<dynamic>;
        if (list.isNotEmpty) {
          final item = list.first as Map<String, dynamic>;
          final lat = double.tryParse(item['lat'].toString());
          final lon = double.tryParse(item['lon'].toString());
          if (lat != null && lon != null) return LatLng(lat, lon);
        }
      }
    } catch (_) {}
    return null;
  }

  // ── Route calculation ──────────────────────────────────────────────────────
  Future<void> _runRoute() async {
    _searchFocus.unfocus();
    _hideSuggestions();

    // 1. Resolve destination
    LatLng? dest = _pinPoint;
    if (dest == null) {
      final text = _searchCtrl.text.trim();
      if (text.isEmpty) {
        _setStatus('Type a destination or tap the map first',
            kind: _StatusKind.error);
        return;
      }
      _setStatus('Looking up "$text"…');
      dest = await _geocodeText(text);
      if (!mounted) return;
      if (dest == null) {
        _setStatus('Destination not found — try a different query',
            kind: _StatusKind.error);
        return;
      }
      setState(() {
        _pinPoint = dest;
        _routePoints = [];
        _routeHazards = [];
      });
      _mapCtrl.move(dest, 14);
    }

    // 2. Get current position
    if (!mounted) return;
    setState(() {
      _loading = true;
      _statusMsg = 'Getting your location…';
      _statusKind = _StatusKind.info;
      _routePoints = [];
      _routeHazards = [];
    });

    final start = await _getCurrentLocation();
    if (!mounted) return;
    if (start == null) {
      setState(() => _loading = false);
      _setStatus('Location permission denied', kind: _StatusKind.error);
      return;
    }

    // 3. OSRM route
    _setStatus('Calculating route…');
    try {
      final url = Uri.parse(
        'http://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${dest.longitude},${dest.latitude}'
        '?overview=full&geometries=geojson',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final geom = routes.first['geometry'] as Map<String, dynamic>?;
          final coords = geom?['coordinates'] as List<dynamic>?;
          if (coords != null) {
            setState(() {
              _routePoints = coords
                  .map<LatLng>((e) => LatLng(
                        (e[1] as num).toDouble(),
                        (e[0] as num).toDouble(),
                      ))
                  .toList();
            });
          }
        }
      }
    } catch (_) {}

    if (!mounted) return;
    if (_routePoints.isEmpty) {
      setState(() => _loading = false);
      _setStatus('Could not calculate a route', kind: _StatusKind.error);
      return;
    }

    // 4. Hazards along route
    _setStatus('Scanning for hazards…');
    try {
      if (!mounted) return;
      final ip = context.read<DriveSettings>().serverIp;
      final all = await SyncService().fetchGlobalHazards(ip);
      if (!mounted) return;
      final nearby = <RoadHazard>[];
      for (final h in all) {
        for (final p in _routePoints) {
          final d = Geolocator.distanceBetween(
              p.latitude, p.longitude, h.lat, h.lng);
          if (d <= 30) {
            nearby.add(h);
            break;
          }
        }
      }
      setState(() => _routeHazards = nearby);
    } catch (_) {}

    // 5. Finish
    if (!mounted) return;
    setState(() => _loading = false);
    if (_routeHazards.isEmpty) {
      _setStatus('Route clear — no hazards detected ✓', kind: _StatusKind.success);
    } else {
      _setStatus(
        '${_routeHazards.length} '
        'hazard${_routeHazards.length == 1 ? '' : 's'} along this route',
        kind: _StatusKind.warning,
      );
    }

    _mapCtrl.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(_routePoints),
        padding: const EdgeInsets.all(52),
      ),
    );
  }

  void _clearAll() {
    _debounce?.cancel();
    setState(() {
      _searchCtrl.clear();
      _pinPoint = null;
      _routePoints = [];
      _routeHazards = [];
      _reversing = false;
      _loading = false;
      _statusMsg = '';
      _suggestions = [];
      _fetchingSuggestions = false;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          _buildTopBar(context),
          _buildSearchBar(),
          // ── Autocomplete dropdown ──────────────────────────────────────────
          // Rendered as a Column child so it sits between the search bar and
          // the map. No Stack/Overlay needed — no z-index headaches.
          if (_fetchingSuggestions && _suggestions.isEmpty)
            _buildSuggestionsLoader(),
          if (_suggestions.isNotEmpty)
            _buildSuggestionsList(),
          // ── Status + progress ──────────────────────────────────────────────
          if (_statusMsg.isNotEmpty && _suggestions.isEmpty)
            _buildStatusBanner(),
          if (_loading)
            const LinearProgressIndicator(
              color: _amber,
              backgroundColor: Colors.white10,
              minHeight: 2,
            ),
          // ── Map (fills remaining space) ────────────────────────────────────
          Expanded(child: _buildMap()),
        ],
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      color: _surface,
      padding: EdgeInsets.only(top: topPad),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _amber),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Text(
              'Route Preview',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontSize: 18,
              ),
            ),
            const Spacer(),
            if (_pinPoint != null || _routePoints.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear_rounded, color: Colors.white54),
                tooltip: 'Clear route',
                onPressed: _clearAll,
              ),
          ],
        ),
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    Widget? suffix;
    if (_reversing || _fetchingSuggestions) {
      suffix = const Padding(
        padding: EdgeInsets.all(10),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: _amber),
        ),
      );
    } else if (_searchCtrl.text.isNotEmpty) {
      suffix = IconButton(
        icon: const Icon(Icons.cancel_rounded, color: Colors.white38, size: 20),
        onPressed: _clearAll,
        splashRadius: 18,
      );
    }

    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search destination or tap the map…',
                hintStyle:
                    GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF2C2C2C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _amber, width: 1.5),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Colors.white38,
                  size: 20,
                ),
                suffixIcon: suffix,
              ),
              onSubmitted: (_) => _runRoute(),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _loading ? null : _runRoute,
              style: ElevatedButton.styleFrom(
                backgroundColor: _amber,
                foregroundColor: Colors.black,
                disabledBackgroundColor: _amber.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.black45),
                      ),
                    )
                  : Text(
                      'Go',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Suggestions: loading shimmer ───────────────────────────────────────────
  Widget _buildSuggestionsLoader() {
    return Container(
      color: _card,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: _amber),
          ),
          const SizedBox(width: 12),
          Text(
            'Searching…',
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Suggestions: results list ──────────────────────────────────────────────
  Widget _buildSuggestionsList() {
    return Container(
      // Cap height so the map is still partially visible on short screens
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: _card,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        itemCount: _suggestions.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          thickness: 1,
          color: Colors.white.withValues(alpha: 0.06),
          indent: 48,
        ),
        itemBuilder: (context, i) {
          final s = _suggestions[i];
          // Split display_name into title + subtitle parts
          final parts = s.displayName.split(',');
          final title = parts.take(2).join(',').trim();
          final subtitle =
              parts.length > 2 ? parts.skip(2).take(3).join(',').trim() : '';

          return InkWell(
            onTap: () => _selectSuggestion(s),
            splashColor: _amber.withValues(alpha: 0.08),
            highlightColor: _amber.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: _amber,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: GoogleFonts.inter(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Tap to go arrow hint
                  const Icon(Icons.north_west_rounded,
                      color: Colors.white24, size: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Status banner ──────────────────────────────────────────────────────────
  Widget _buildStatusBanner() {
    final (color, icon) = switch (_statusKind) {
      _StatusKind.error   => (Colors.redAccent, Icons.error_outline_rounded),
      _StatusKind.success => (const Color(0xFF66BB6A), Icons.check_circle_outline_rounded),
      _StatusKind.warning => (_amber, Icons.warning_amber_rounded),
      _StatusKind.info    => (Colors.white60, Icons.info_outline_rounded),
    };

    return Container(
      width: double.infinity,
      color: _surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMsg,
              style: GoogleFonts.inter(color: color, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  // ── Map ────────────────────────────────────────────────────────────────────
  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: _defaultCenter,
        initialZoom: 13,
        onTap: (_, latlng) {
          if (_loading) return;
          _hideSuggestions();
          setState(() {
            _pinPoint = latlng;
            _routePoints = [];
            _routeHazards = [];
            _statusMsg = '';
            _searchCtrl.clear();
          });
          _reverseGeocode(latlng);
        },
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.example.smooth_drive',
        ),
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                color: _amber,
                strokeWidth: 4.5,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (_pinPoint != null)
              Marker(
                point: _pinPoint!,
                width: 48,
                height: 48,
                child: const Icon(
                  Icons.location_pin,
                  color: _amber,
                  size: 48,
                ),
              ),
            for (final h in _routeHazards)
              Marker(
                point: LatLng(h.lat, h.lng),
                width: 34,
                height: 34,
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                  size: 34,
                ),
              ),
          ],
        ),
      ],
    );
  }
}