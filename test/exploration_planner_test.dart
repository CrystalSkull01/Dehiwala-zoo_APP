import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:dehiwala_zoo_app/models/animal_discovery.dart';
import 'package:dehiwala_zoo_app/models/exploration_session.dart';
import 'package:dehiwala_zoo_app/models/gamification_profile.dart';
import 'package:dehiwala_zoo_app/models/zoo_waypoint.dart';
import 'package:dehiwala_zoo_app/services/exploration_planner.dart';
import 'package:dehiwala_zoo_app/services/gamification_service.dart';

void main() {
  const nearAnimal = ZooWaypoint(
    id: 'near',
    name: 'Ostrich',
    latitude: 6.8561,
    longitude: 79.8721,
    category: 'animal',
    nameVerified: false,
  );
  const farAnimal = ZooWaypoint(
    id: 'far',
    name: 'Tiger',
    latitude: 6.859,
    longitude: 79.875,
    category: 'animal',
  );
  const facility = ZooWaypoint(
    id: 'facility',
    name: 'Entrance',
    latitude: 6.856,
    longitude: 79.872,
    category: 'facility',
  );

  test('planner selects the nearest eligible animal, not input order', () {
    final destination = ExplorationPlanner.nextEligibleAnimal(
      waypoints: const [facility, farAnimal, nearAnimal],
      profile: GamificationProfile.empty(),
      rules: const DiscoveryRules(),
      currentLocation: const LatLng(6.8562, 79.8722),
    );

    expect(destination?.waypoint.id, nearAnimal.id);
    expect(destination?.distanceMeters, greaterThan(0));
  });

  test('planner skips discovered animals and non-animal locations', () {
    final profile = GamificationProfile.empty().record(
      AnimalDiscovery(
        waypointId: nearAnimal.id,
        xpAwarded: 100,
        discoveredAtUtc: DateTime.utc(2026),
      ),
    );

    final destination = ExplorationPlanner.nextEligibleAnimal(
      waypoints: const [facility, nearAnimal, farAnimal],
      profile: profile,
      rules: const DiscoveryRules(),
      currentLocation: const LatLng(6.8562, 79.8722),
    );

    expect(destination?.waypoint.id, farAnimal.id);
    expect(destination?.distanceMeters, greaterThan(0));
  });

  test('planner selects a recorded destination without a GPS fix', () {
    final destination = ExplorationPlanner.nextEligibleAnimal(
      waypoints: const [facility, nearAnimal, farAnimal],
      profile: GamificationProfile.empty(),
      rules: const DiscoveryRules(),
      currentLocation: null,
    );

    expect(destination?.waypoint.id, nearAnimal.id);
    expect(destination?.distanceMeters, isNull);
  });

  test(
    'planner returns no destination when all eligible animals are found',
    () {
      final profile = GamificationProfile.empty()
          .record(
            AnimalDiscovery(
              waypointId: nearAnimal.id,
              xpAwarded: 100,
              discoveredAtUtc: DateTime.utc(2026),
            ),
          )
          .record(
            AnimalDiscovery(
              waypointId: farAnimal.id,
              xpAwarded: 100,
              discoveredAtUtc: DateTime.utc(2026),
            ),
          );

      expect(
        ExplorationPlanner.nextEligibleAnimal(
          waypoints: const [nearAnimal, farAnimal],
          profile: profile,
          rules: const DiscoveryRules(),
          currentLocation: const LatLng(6.856, 79.872),
        ),
        isNull,
      );
    },
  );

  test('session records XP once per newly discovered waypoint', () {
    final startedAt = DateTime.utc(2026, 10, 28);
    final session = ExplorationSession.start(startedAt)
        .recordDiscovery('near', 100)
        .recordDiscovery('near', 100)
        .recordDiscovery('far', 100);

    expect(session.startedAtUtc, startedAt);
    expect(session.discoveryCount, 2);
    expect(session.xpEarned, 200);
  });
}
