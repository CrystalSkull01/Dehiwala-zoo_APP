import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dehiwala_zoo_app/models/animal_discovery.dart';
import 'package:dehiwala_zoo_app/models/gamification_profile.dart';
import 'package:dehiwala_zoo_app/models/zoo_waypoint.dart';
import 'package:dehiwala_zoo_app/services/gamification_service.dart';
import 'package:dehiwala_zoo_app/services/gamification_storage_service.dart';

class _MemoryGamificationStorage implements GamificationStorageService {
  GamificationProfile savedProfile = GamificationProfile.empty();
  int saveCount = 0;

  @override
  Future<GamificationProfile> loadProfile() async => savedProfile;

  @override
  Future<void> saveProfile(GamificationProfile profile) async {
    savedProfile = profile;
    saveCount++;
  }
}

class _FakeLocationProvider implements DiscoveryLocationProvider {
  DiscoveryLocation nextLocation;
  int requestCount = 0;

  _FakeLocationProvider(this.nextLocation);

  @override
  Future<DiscoveryLocation> getCurrentLocation() async {
    requestCount++;
    return nextLocation;
  }
}

void main() {
  const animal = ZooWaypoint(
    id: 'WP-animal',
    name: 'Ostrich',
    latitude: 6.85,
    longitude: 79.87,
    category: 'animal',
  );

  DiscoveryLocation atAnimal({double accuracy = 5}) => DiscoveryLocation(
    status: LocationReadStatus.available,
    latitude: animal.latitude,
    longitude: animal.longitude,
    accuracyMeters: accuracy,
  );

  group('GamificationService discovery', () {
    late _MemoryGamificationStorage storage;
    late _FakeLocationProvider location;
    late GamificationService service;

    setUp(() async {
      storage = _MemoryGamificationStorage();
      location = _FakeLocationProvider(atAnimal());
      service = GamificationService(
        storage: storage,
        locationProvider: location,
      );
      await service.load();
    });

    test('awards 100 XP for a nearby eligible animal', () async {
      final result = await service.discoverAnimal(animal);

      expect(result.status, DiscoveryStatus.discovered);
      expect(result.xpAwarded, 100);
      expect(result.profile.totalXp, 100);
      expect(result.profile.hasDiscovered(animal.id), isTrue);
      expect(storage.saveCount, 1);
    });

    test('does not reward facilities or landmarks', () async {
      for (final category in ['facility', 'landmark']) {
        final waypoint = ZooWaypoint(
          id: 'WP-$category',
          name: category,
          latitude: animal.latitude,
          longitude: animal.longitude,
          category: category,
        );
        final result = await service.discoverAnimal(waypoint);
        expect(result.status, DiscoveryStatus.notEligible);
      }
      expect(location.requestCount, 0);
      expect(storage.saveCount, 0);
    });

    test('refuses a location beyond the configured radius', () async {
      location.nextLocation = DiscoveryLocation(
        status: LocationReadStatus.available,
        latitude: animal.latitude + 0.001,
        longitude: animal.longitude,
        accuracyMeters: 5,
      );

      final result = await service.discoverAnimal(animal);

      expect(result.status, DiscoveryStatus.tooFar);
      expect(result.distanceMeters, greaterThan(40));
      expect(result.profile.totalXp, 0);
      expect(storage.saveCount, 0);
    });

    test(
      'does not award when GPS uncertainty overlaps the radius edge',
      () async {
        final longitudeOffset = 0.00031; // About 34 m at the zoo latitude.
        location.nextLocation = DiscoveryLocation(
          status: LocationReadStatus.available,
          latitude: animal.latitude,
          longitude: animal.longitude + longitudeOffset,
          accuracyMeters: 10,
        );

        final result = await service.discoverAnimal(animal);

        expect(result.status, DiscoveryStatus.poorAccuracy);
        expect(result.profile.totalXp, 0);
        expect(storage.saveCount, 0);
      },
    );

    test(
      'retries low accuracy, denied permission, and GPS timeout safely',
      () async {
        location.nextLocation = atAnimal(accuracy: 70);
        expect(
          (await service.discoverAnimal(animal)).status,
          DiscoveryStatus.poorAccuracy,
        );

        location.nextLocation = const DiscoveryLocation(
          status: LocationReadStatus.permissionDenied,
        );
        expect(
          (await service.discoverAnimal(animal)).status,
          DiscoveryStatus.permissionDenied,
        );

        location.nextLocation = const DiscoveryLocation(
          status: LocationReadStatus.timedOut,
        );
        expect(
          (await service.discoverAnimal(animal)).status,
          DiscoveryStatus.timedOut,
        );
        expect(storage.saveCount, 0);
      },
    );

    test('prevents duplicate XP and avoids another GPS request', () async {
      await service.discoverAnimal(animal);
      location.nextLocation = const DiscoveryLocation(
        status: LocationReadStatus.permissionDenied,
      );

      final duplicate = await service.discoverAnimal(animal);

      expect(duplicate.status, DiscoveryStatus.alreadyDiscovered);
      expect(location.requestCount, 1);
      expect(storage.saveCount, 1);
      expect(duplicate.profile.totalXp, 100);
    });

    test(
      'discovery rules can require verified names for a later release',
      () async {
        final restricted = GamificationService(
          storage: storage,
          locationProvider: location,
          rules: const DiscoveryRules(requireVerifiedName: true),
        );
        await restricted.load();

        final result = await restricted.discoverAnimal(animal);

        expect(result.status, DiscoveryStatus.notEligible);
        expect(location.requestCount, 0);
      },
    );

    test(
      'debug simulation is explicit and does not call the GPS provider',
      () async {
        location.nextLocation = const DiscoveryLocation(
          status: LocationReadStatus.permissionDenied,
        );

        final result = await service.debugDiscoverNearby(animal);

        expect(result.status, DiscoveryStatus.discovered);
        expect(result.profile.totalXp, 100);
        expect(location.requestCount, 0);
      },
    );
  });

  test(
    'file storage restores discovery IDs, XP and history after restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'zoo-gamification-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final storage = FileGamificationStorageService(rootDirectory: directory);
      final profile = GamificationProfile.empty().record(
        AnimalDiscovery(
          waypointId: animal.id,
          xpAwarded: 100,
          discoveredAtUtc: DateTime.utc(2026, 10, 25),
        ),
      );

      await storage.saveProfile(profile);
      final updatedProfile = profile.record(
        AnimalDiscovery(
          waypointId: 'WP-animal-two',
          xpAwarded: 100,
          discoveredAtUtc: DateTime.utc(2026, 10, 26),
        ),
      );
      await storage.saveProfile(updatedProfile);
      final restored = await FileGamificationStorageService(
        rootDirectory: directory,
      ).loadProfile();

      expect(restored.totalXp, 200);
      expect(restored.discoveredCount, 2);
      expect(restored.hasDiscovered(animal.id), isTrue);
      expect(
        restored.discoveries[animal.id]?.discoveredAtUtc,
        DateTime.utc(2026, 10, 25),
      );
    },
  );
}
