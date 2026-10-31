import 'package:latlong2/latlong.dart';

import '../models/gamification_profile.dart';
import '../models/zoo_waypoint.dart';
import 'gamification_service.dart';

class ExplorationDestination {
  final ZooWaypoint waypoint;
  final double? distanceMeters;

  const ExplorationDestination({
    required this.waypoint,
    required this.distanceMeters,
  });
}

class ExplorationPlanner {
  const ExplorationPlanner._();

  static ExplorationDestination? nextEligibleAnimal({
    required Iterable<ZooWaypoint> waypoints,
    required GamificationProfile profile,
    required DiscoveryRules rules,
    required LatLng? currentLocation,
  }) {
    ZooWaypoint? nextWaypoint;
    double? shortestDistance;

    for (final waypoint in waypoints) {
      if (!rules.isEligible(waypoint) || profile.hasDiscovered(waypoint.id)) {
        continue;
      }

      final location = currentLocation;
      if (location == null) {
        return ExplorationDestination(waypoint: waypoint, distanceMeters: null);
      }

      final distance = distanceBetweenMeters(
        location.latitude,
        location.longitude,
        waypoint.latitude,
        waypoint.longitude,
      );
      if (shortestDistance == null || distance < shortestDistance) {
        nextWaypoint = waypoint;
        shortestDistance = distance;
      }
    }

    if (nextWaypoint == null) return null;
    return ExplorationDestination(
      waypoint: nextWaypoint,
      distanceMeters: shortestDistance,
    );
  }
}
