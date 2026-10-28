class ZooWaypoint {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String category;
  final bool nameVerified;
  final bool needsReview;
  final String? reviewNote;

  const ZooWaypoint({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.category,
    this.nameVerified = false,
    this.needsReview = false,
    this.reviewNote,
  });

  factory ZooWaypoint.fromJson(Map<String, dynamic> json) {
    return ZooWaypoint(
      id: json['id'] as String? ?? 'unknown',
      name: json['name'] as String? ?? 'Unnamed location',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      category: json['category'] as String? ?? 'other',
      nameVerified: json['nameVerified'] as bool? ?? false,
      needsReview: json['needsReview'] as bool? ?? false,
      reviewNote: json['reviewNote'] as String?,
    );
  }
}

String mapCategoryForWaypoint(String category) =>
    switch (category.trim().toLowerCase()) {
      'animal' => 'Animals',
      'facility' => 'Facilities',
      'landmark' => 'Landmarks',
      _ => 'All',
    };

List<ZooWaypoint> filterZooWaypoints(
  List<ZooWaypoint> waypoints, {
  required String category,
  String query = '',
}) {
  final normalizedQuery = query.trim().toLowerCase();
  return waypoints.where((waypoint) {
    final wantedCategory = mapCategoryForWaypoint(waypoint.category);
    final categoryMatches = category == 'All' || category == wantedCategory;
    return categoryMatches &&
        (normalizedQuery.isEmpty ||
            waypoint.name.toLowerCase().contains(normalizedQuery));
  }).toList();
}
