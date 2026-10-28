class AnimalDiscovery {
  final String waypointId;
  final int xpAwarded;
  final DateTime discoveredAtUtc;

  const AnimalDiscovery({
    required this.waypointId,
    required this.xpAwarded,
    required this.discoveredAtUtc,
  });

  Map<String, Object> toJson() => {
    'waypointId': waypointId,
    'xpAwarded': xpAwarded,
    'discoveredAtUtc': discoveredAtUtc.toUtc().toIso8601String(),
  };

  factory AnimalDiscovery.fromJson(Map<String, dynamic> json) {
    return AnimalDiscovery(
      waypointId: json['waypointId'] as String,
      xpAwarded: (json['xpAwarded'] as num).toInt(),
      discoveredAtUtc: DateTime.parse(json['discoveredAtUtc'] as String)
          .toUtc(),
    );
  }
}
