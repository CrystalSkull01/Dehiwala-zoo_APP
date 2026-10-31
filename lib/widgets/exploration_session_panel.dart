import 'package:flutter/material.dart';

class ExplorationSessionPanel extends StatelessWidget {
  final bool isActive;
  final bool isMinimized;
  final bool isFindingLocation;
  final int totalXp;
  final int discoveredCount;
  final int eligibleAnimalCount;
  final int sessionDiscoveryCount;
  final int sessionXp;
  final String? destinationName;
  final double? distanceMeters;
  final bool destinationNameVerified;
  final bool hasRecordedTrace;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback? onToggleMinimized;
  final VoidCallback onOpenCollection;

  const ExplorationSessionPanel({
    super.key,
    required this.isActive,
    this.isMinimized = false,
    required this.isFindingLocation,
    required this.totalXp,
    required this.discoveredCount,
    required this.eligibleAnimalCount,
    required this.sessionDiscoveryCount,
    required this.sessionXp,
    required this.destinationName,
    required this.distanceMeters,
    required this.destinationNameVerified,
    required this.hasRecordedTrace,
    required this.onStart,
    required this.onFinish,
    this.onToggleMinimized,
    required this.onOpenCollection,
  });

  String _formatDistance(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress = eligibleAnimalCount == 0
        ? 0.0
        : (discoveredCount / eligibleAnimalCount).clamp(0.0, 1.0);

    return Material(
      color: colors.surface,
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: isMinimized
          ? _buildMinimized(context, colors, progress)
          : SizedBox(
              width: 252,
              child: Stack(
                children: [
                  Positioned(
                    right: -15,
                    top: -20,
                    child: Icon(
                      Icons.forest_rounded,
                      size: 86,
                      color: colors.primary.withValues(alpha: 0.07),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(13),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isActive
                                    ? Icons.explore_rounded
                                    : Icons.hiking_rounded,
                                color: colors.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                isActive ? 'Exploring' : 'Zoo adventure',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Minimize exploration panel',
                              onPressed: onToggleMinimized,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.keyboard_arrow_up_rounded,
                                size: 21,
                                color: colors.primary,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Open wildlife collection',
                              onPressed: onOpenCollection,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.collections_bookmark_rounded,
                                size: 19,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Icon(
                              Icons.stars_rounded,
                              size: 17,
                              color: colors.tertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$totalXp XP',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$discoveredCount / $eligibleAnimalCount explored',
                                maxLines: 1,
                                textAlign: TextAlign.end,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: colors.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 7,
                            backgroundColor: colors.surfaceContainerHighest,
                            color: const Color(0xFFE5AD3A),
                          ),
                        ),
                        if (!isActive) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Follow the zoo map, find animal friends, and earn XP.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  height: 1.2,
                                ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: onStart,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Start Exploring'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2F8055),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(42),
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.flag_rounded,
                                size: 18,
                                color: const Color(0xFFD69B24),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  destinationName ??
                                      'All eligible locations found!',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                          if (destinationName != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              isFindingLocation
                                  ? 'Finding your location…'
                                  : distanceMeters == null
                                  ? 'Allow location to estimate distance'
                                  : '${_formatDistance(distanceMeters!)} straight-line estimate',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                            if (!destinationNameVerified)
                              Text(
                                'Recorded name, not yet verified',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                          ],
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 15,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '$sessionDiscoveryCount found this trip  ·  +$sessionXp XP',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          if (hasRecordedTrace) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Gold line: recorded GPS trace, not an official walking route.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 10,
                                    height: 1.15,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 9),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: onFinish,
                              icon: const Icon(Icons.flag_outlined, size: 18),
                              label: const Text('Finish exploration'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colors.primary,
                                minimumSize: const Size.fromHeight(39),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMinimized(
    BuildContext context,
    ColorScheme colors,
    double progress,
  ) {
    final title = isActive
        ? destinationName ?? 'Adventure in progress'
        : 'Zoo adventure';
    final subtitle = isActive
        ? isFindingLocation
              ? 'Finding your location'
              : distanceMeters == null
              ? '$sessionDiscoveryCount found · +$sessionXp XP'
              : '${_formatDistance(distanceMeters!)} away · '
                    '$sessionDiscoveryCount found · +$sessionXp XP'
        : '$discoveredCount/$eligibleAnimalCount discovered · $totalXp XP';

    return SizedBox(
      width: 240,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 7, 7, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    isActive ? Icons.explore_rounded : Icons.hiking_rounded,
                    color: colors.primary,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Expand exploration panel',
                  onPressed: onToggleMinimized,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: colors.surfaceContainerHighest,
                color: const Color(0xFFE5AD3A),
              ),
            ),
            if (!isActive) ...[
              const SizedBox(height: 7),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Start Exploring'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2F8055),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
