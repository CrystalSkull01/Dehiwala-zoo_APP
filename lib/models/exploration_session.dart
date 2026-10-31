class ExplorationSession {
  final DateTime startedAtUtc;
  final Map<String, int> discoveries;

  ExplorationSession._({
    required this.startedAtUtc,
    required Map<String, int> discoveries,
  }) : discoveries = Map.unmodifiable(discoveries);

  factory ExplorationSession.start(DateTime startedAt) => ExplorationSession._(
    startedAtUtc: startedAt.toUtc(),
    discoveries: const {},
  );

  int get discoveryCount => discoveries.length;

  int get xpEarned => discoveries.values.fold<int>(0, (sum, xp) => sum + xp);

  ExplorationSession recordDiscovery(String waypointId, int xpAwarded) {
    if (discoveries.containsKey(waypointId)) return this;
    return ExplorationSession._(
      startedAtUtc: startedAtUtc,
      discoveries: {...discoveries, waypointId: xpAwarded},
    );
  }
}
