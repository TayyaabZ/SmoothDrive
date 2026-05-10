import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/road_hazard.dart';
import 'database_service.dart';

class SyncService {
  Future<void> syncHazards(String serverIp, bool isWifiOnly) async {
    final results = await Connectivity().checkConnectivity();
    if (results.contains(ConnectivityResult.none)) {
      return;
    }
    if (isWifiOnly && !results.contains(ConnectivityResult.wifi)) {
      return;
    }

    final items = await DatabaseService().getHazards();
    if (items.isEmpty) {
      return;
    }

    final data = items.map((item) => item.toJson()).toList();
    final url = 'http://$serverIp:3000/api/sync';

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        await DatabaseService().clearHazards();
        debugPrint('Synced ${items.length} hazards');
      }
    } catch (_) {
      return;
    }
  }

  Future<List<RoadHazard>> fetchGlobalHazards(String serverIp) async {
    final url = 'http://$serverIp:3000/api/hazards';
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        return [];
      }
      final raw = jsonDecode(response.body);
      if (raw is! List) {
        return [];
      }
      return raw
          .map(
            (item) {
              if (item is! Map) {
                return null;
              }
              final map = Map<String, dynamic>.from(item);
              final lat = map['lat'];
              final lng = map['lng'];
              final timestamp = map['timestamp'];
              final impact = map['impact'];
              if (lat is! num ||
                  lng is! num ||
                  timestamp is! String ||
                  impact is! num) {
                return null;
              }
              return RoadHazard.fromJson(map);
            },
          )
          .whereType<RoadHazard>()
          .toList();
    } catch (_) {
      return [];
    }
  }
}
