import 'animal_discovery.dart';

class GamificationProfile {
  final Map<String, AnimalDiscovery> discoveries;

  GamificationProfile({Map<String, AnimalDiscovery> discoveries = const {}})
    : discoveries = Map.unmodifiable(discoveries);

  factory GamificationProfile.empty() => GamificationProfile();

  int get totalXp => discoveries.values.fold<int>(
    0,
    (total, discovery) => total + discovery.xpAwarded,
  );

  int get discoveredCount => discoveries.length;

  bool hasDiscovered(String waypointId) => discoveries.containsKey(waypointId);

  GamificationProfile record(AnimalDiscovery discovery) {
    if (hasDiscovered(discovery.waypointId)) return this;
    return GamificationProfile(
      discoveries: {...discoveries, discovery.waypointId: discovery},
    );
  }

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'discoveries': discoveries.values.map((entry) => entry.toJson()).toList(),
  };

  factory GamificationProfile.fromJson(Map<String, dynamic> json) {
    final entries = json['discoveries'] as List<dynamic>? ?? const [];
    final discoveries = <String, AnimalDiscovery>{};
    for (final entry in entries) {
      final discovery = AnimalDiscovery.fromJson(
        Map<String, dynamic>.from(entry as Map),
      );
      // If a previous file contains duplicate IDs, count the first reward once.
      discoveries.putIfAbsent(discovery.waypointId, () => discovery);
    }
    return GamificationProfile(discoveries: discoveries);
  }
}
