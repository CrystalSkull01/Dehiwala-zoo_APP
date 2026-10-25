import 'package:flutter_test/flutter_test.dart';

import 'package:dehiwala_zoo_app/main.dart';

void main() {
  group('ZooWaypoint data quality fields', () {
    test('loads explicit verification and review metadata', () {
      final waypoint = ZooWaypoint.fromJson({
        'id': 'WP-test',
        'name': 'Test landmark',
        'latitude': 6.85,
        'longitude': 79.87,
        'category': 'landmark',
        'nameVerified': true,
        'needsReview': true,
        'reviewNote': 'Check this location label.',
      });

      expect(waypoint.nameVerified, isTrue);
      expect(waypoint.needsReview, isTrue);
      expect(waypoint.reviewNote, 'Check this location label.');
    });

    test('uses safe defaults when optional quality fields are absent', () {
      final waypoint = ZooWaypoint.fromJson({
        'id': 'WP-test',
        'name': 'Unverified location',
        'latitude': 6.85,
        'longitude': 79.87,
        'category': 'landmark',
      });

      expect(waypoint.nameVerified, isFalse);
      expect(waypoint.needsReview, isFalse);
      expect(waypoint.reviewNote, isNull);
    });
  });

  group('waypoint categories', () {
    final waypoints = [
      const ZooWaypoint(
        id: 'animal',
        name: 'Ostrich',
        latitude: 6.85,
        longitude: 79.87,
        category: 'animal',
      ),
      const ZooWaypoint(
        id: 'facility',
        name: 'Aquarium Entrance',
        latitude: 6.85,
        longitude: 79.87,
        category: 'facility',
      ),
      const ZooWaypoint(
        id: 'landmark',
        name: 'Viewpoint',
        latitude: 6.85,
        longitude: 79.87,
        category: 'landmark',
      ),
    ];

    test('filters landmarks by category and search text', () {
      final landmarks = filterZooWaypoints(
        waypoints,
        category: 'Landmarks',
        query: 'view',
      );

      expect(landmarks.map((waypoint) => waypoint.name), ['Viewpoint']);
    });

    test('maps a selected landmark back to the Landmarks filter', () {
      expect(mapCategoryForWaypoint('landmark'), 'Landmarks');
      expect(mapCategoryForWaypoint('animal'), 'Animals');
      expect(mapCategoryForWaypoint('facility'), 'Facilities');
    });
  });
}
