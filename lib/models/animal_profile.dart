/// Optional wildlife facts kept separate from map coordinates and progress.
///
/// A fact should only be populated from a reliable source. When the zoo has
/// not confirmed an animal's identity, callers should not attach a profile.
enum AnimalInformationStatus { unverified, verified }

class AnimalProfile {
  final String waypointId;
  final String? scientificName;
  final String? classification;
  final String? habitat;
  final String? diet;
  final String? nativeRange;
  final String? conservationStatus;
  final String? interestingFact;
  final List<AnimalInformationSource> sources;
  final AnimalInformationStatus status;

  const AnimalProfile({
    required this.waypointId,
    this.scientificName,
    this.classification,
    this.habitat,
    this.diet,
    this.nativeRange,
    this.conservationStatus,
    this.interestingFact,
    this.sources = const [],
    this.status = AnimalInformationStatus.unverified,
  });

  bool get isVerified => status == AnimalInformationStatus.verified;

  bool get hasFacts => [
    scientificName,
    classification,
    habitat,
    diet,
    nativeRange,
    conservationStatus,
    interestingFact,
  ].any((fact) => fact?.trim().isNotEmpty ?? false);
}

class AnimalInformationSource {
  final String name;
  final Uri uri;

  const AnimalInformationSource({required this.name, required this.uri});
}
