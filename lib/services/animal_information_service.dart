import '../models/animal_profile.dart';

/// Supplies independently curated facts without mixing them into waypoint data.
///
/// The current zoo waypoint dataset contains no sourced wildlife facts and all
/// animal names are unverified, so the default catalogue is intentionally empty.
class AnimalInformationService {
  final Map<String, AnimalProfile> _profiles;

  AnimalInformationService({Iterable<AnimalProfile> profiles = const []})
    : _profiles = {for (final profile in profiles) profile.waypointId: profile};

  AnimalProfile? profileFor(String waypointId) => _profiles[waypointId];
}
