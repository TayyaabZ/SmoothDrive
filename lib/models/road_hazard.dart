class RoadHazard {
  const RoadHazard({
    required this.lat,
    required this.lng,
    required this.timestamp,
    required this.impactMagnitude,
    this.hitCount = 1,
    this.hazardType = 'pothole',
  });

  final double lat;
  final double lng;
  final DateTime timestamp;
  final double impactMagnitude;
  final int hitCount;
  final String hazardType;

  Map<String, dynamic> toMap() {
    return {
      'lat': lat,
      'lng': lng,
      'timestamp': timestamp.toIso8601String(),
      'impactMagnitude': impactMagnitude,
      'hazard_type': hazardType,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lng': lng,
      'timestamp': timestamp.toIso8601String(),
      'impact': impactMagnitude,
      'hit_count': hitCount,
      'hazard_type': hazardType,
    };
  }

  factory RoadHazard.fromJson(Map<String, dynamic> map) {
    final hit = map['hit_count'];
    final type = map['hazard_type'];
    return RoadHazard(
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      timestamp: DateTime.parse(map['timestamp'] as String),
      impactMagnitude: (map['impact'] as num).toDouble(),
      hitCount: hit is num ? hit.toInt() : 1,
      hazardType: type is String ? type : 'pothole',
    );
  }

  RoadHazard.fromMap(Map<String, dynamic> map)
      : lat = (map['lat'] as num).toDouble(),
        lng = (map['lng'] as num).toDouble(),
        timestamp = DateTime.parse(map['timestamp'] as String),
        impactMagnitude = (map['impactMagnitude'] as num).toDouble(),
        hitCount = (map['hit_count'] as num?)?.toInt() ?? 1,
        hazardType = (map['hazard_type'] as String?) ?? 'pothole';
}
