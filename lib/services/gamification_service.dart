import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:geolocator/geolocator.dart';

import '../models/animal_discovery.dart';
import '../models/gamification_profile.dart';
import '../models/zoo_waypoint.dart';
import 'gamification_storage_service.dart';

enum DiscoveryStatus {
  discovered,
  alreadyDiscovered,
  notEligible,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  timedOut,
  locationUnavailable,
  poorAccuracy,
  tooFar,
  storageError,
  debugOnlyUnavailable,
}

enum LocationReadStatus {
  available,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  timedOut,
  unavailable,
}

class DiscoveryLocation {
  final LocationReadStatus status;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;

  const DiscoveryLocation({
    required this.status,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
  });
}

abstract interface class DiscoveryLocationProvider {
  Future<DiscoveryLocation> getCurrentLocation();
}

class GeolocatorDiscoveryLocationProvider implements DiscoveryLocationProvider {
  const GeolocatorDiscoveryLocationProvider();

  @override
  Future<DiscoveryLocation> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const DiscoveryLocation(
          status: LocationReadStatus.serviceDisabled,
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const DiscoveryLocation(
          status: LocationReadStatus.permissionDenied,
        );
      }
      if (permission == LocationPermission.deniedForever) {
        return const DiscoveryLocation(
          status: LocationReadStatus.permissionDeniedForever,
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return DiscoveryLocation(
        status: LocationReadStatus.available,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
    } on TimeoutException {
      return const DiscoveryLocation(status: LocationReadStatus.timedOut);
    } on PermissionDeniedException {
      return const DiscoveryLocation(
        status: LocationReadStatus.permissionDenied,
      );
    } on LocationServiceDisabledException {
      return const DiscoveryLocation(
        status: LocationReadStatus.serviceDisabled,
      );
    } catch (_) {
      return const DiscoveryLocation(status: LocationReadStatus.unavailable);
    }
  }
}

class DiscoveryRules {
  final double proximityRadiusMeters;
  final double maximumAccuracyMeters;
  final int xpPerDiscovery;
  final bool requireVerifiedName;
  final bool excludeNeedsReview;

  const DiscoveryRules({
    this.proximityRadiusMeters = 40,
    this.maximumAccuracyMeters = 25,
    this.xpPerDiscovery = 100,
    this.requireVerifiedName = false,
    this.excludeNeedsReview = false,
  });

  bool isEligible(ZooWaypoint waypoint) {
    if (waypoint.category.trim().toLowerCase() != 'animal') return false;
    if (requireVerifiedName && !waypoint.nameVerified) return false;
    if (excludeNeedsReview && waypoint.needsReview) return false;
    return true;
  }
}

class DiscoveryResult {
  final DiscoveryStatus status;
  final double? distanceMeters;
  final int xpAwarded;
  final GamificationProfile profile;

  const DiscoveryResult({
    required this.status,
    required this.profile,
    this.distanceMeters,
    this.xpAwarded = 0,
  });

  bool get wasDiscovered => status == DiscoveryStatus.discovered;
}

class GamificationService {
  final GamificationStorageService storage;
  final DiscoveryLocationProvider locationProvider;
  final DiscoveryRules rules;

  GamificationProfile _profile = GamificationProfile.empty();
  Future<void> _transactionQueue = Future<void>.value();
  bool _isLoaded = false;

  GamificationService({
    required this.storage,
    required this.locationProvider,
    this.rules = const DiscoveryRules(),
  });

  GamificationProfile get profile => _profile;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    _profile = await storage.loadProfile();
    _isLoaded = true;
  }

  Future<DiscoveryResult> discoverAnimal(ZooWaypoint waypoint) {
    return _queueTransaction(() async {
      if (!_isLoaded || !rules.isEligible(waypoint)) {
        return _result(DiscoveryStatus.notEligible);
      }
      if (_profile.hasDiscovered(waypoint.id)) {
        return _result(DiscoveryStatus.alreadyDiscovered);
      }

      final location = await locationProvider.getCurrentLocation();
      return _handleLocation(waypoint, location);
    });
  }

  /// A clearly labelled debug helper. The app exposes it only in debug builds.
  Future<DiscoveryResult> debugDiscoverNearby(ZooWaypoint waypoint) {
    if (!kDebugMode) {
      return Future.value(_result(DiscoveryStatus.debugOnlyUnavailable));
    }
    return _queueTransaction(() async {
      if (!_isLoaded || !rules.isEligible(waypoint)) {
        return _result(DiscoveryStatus.notEligible);
      }
      if (_profile.hasDiscovered(waypoint.id)) {
        return _result(DiscoveryStatus.alreadyDiscovered);
      }
      return _handleLocation(
        waypoint,
        DiscoveryLocation(
          status: LocationReadStatus.available,
          latitude: waypoint.latitude,
          longitude: waypoint.longitude,
          accuracyMeters: 1,
        ),
      );
    });
  }

  Future<DiscoveryResult> _queueTransaction(
    Future<DiscoveryResult> Function() action,
  ) {
    final completer = Completer<DiscoveryResult>();
    _transactionQueue = _transactionQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (_) {
        completer.complete(_result(DiscoveryStatus.locationUnavailable));
      }
    });
    return completer.future;
  }

  Future<DiscoveryResult> _handleLocation(
    ZooWaypoint waypoint,
    DiscoveryLocation location,
  ) async {
    final status = switch (location.status) {
      LocationReadStatus.available => null,
      LocationReadStatus.serviceDisabled => DiscoveryStatus.serviceDisabled,
      LocationReadStatus.permissionDenied => DiscoveryStatus.permissionDenied,
      LocationReadStatus.permissionDeniedForever =>
        DiscoveryStatus.permissionDeniedForever,
      LocationReadStatus.timedOut => DiscoveryStatus.timedOut,
      LocationReadStatus.unavailable => DiscoveryStatus.locationUnavailable,
    };
    if (status != null) return _result(status);

    final latitude = location.latitude;
    final longitude = location.longitude;
    final accuracy = location.accuracyMeters;
    if (latitude == null ||
        longitude == null ||
        accuracy == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        !accuracy.isFinite) {
      return _result(DiscoveryStatus.locationUnavailable);
    }
    if (accuracy < 0 || accuracy > rules.maximumAccuracyMeters) {
      return _result(DiscoveryStatus.poorAccuracy);
    }

    final distance = distanceBetweenMeters(
      latitude,
      longitude,
      waypoint.latitude,
      waypoint.longitude,
    );
    if (distance - accuracy > rules.proximityRadiusMeters) {
      return _result(DiscoveryStatus.tooFar, distance: distance);
    }
    if (distance + accuracy > rules.proximityRadiusMeters) {
      return _result(DiscoveryStatus.poorAccuracy, distance: distance);
    }

    final discovery = AnimalDiscovery(
      waypointId: waypoint.id,
      xpAwarded: rules.xpPerDiscovery,
      discoveredAtUtc: DateTime.now().toUtc(),
    );
    final updatedProfile = _profile.record(discovery);
    try {
      await storage.saveProfile(updatedProfile);
    } catch (_) {
      return _result(DiscoveryStatus.storageError, distance: distance);
    }
    _profile = updatedProfile;
    return _result(
      DiscoveryStatus.discovered,
      distance: distance,
      xp: rules.xpPerDiscovery,
    );
  }

  DiscoveryResult _result(
    DiscoveryStatus status, {
    double? distance,
    int xp = 0,
  }) => DiscoveryResult(
    status: status,
    profile: _profile,
    distanceMeters: distance,
    xpAwarded: xp,
  );
}

double distanceBetweenMeters(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  const earthRadiusMeters = 6371000.0;
  final latA = latitudeA * math.pi / 180;
  final latB = latitudeB * math.pi / 180;
  final deltaLat = (latitudeB - latitudeA) * math.pi / 180;
  final deltaLon = (longitudeB - longitudeA) * math.pi / 180;
  final haversine =
      math.pow(math.sin(deltaLat / 2), 2) +
      math.cos(latA) * math.cos(latB) * math.pow(math.sin(deltaLon / 2), 2);
  return earthRadiusMeters * 2 * math.asin(math.sqrt(haversine));
}
