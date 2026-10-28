import 'package:flutter/material.dart';

class XpProgressCard extends StatelessWidget {
  final int totalXp;
  final int discoveredCount;
  final int eligibleAnimalCount;
  final VoidCallback onOpenCollection;

  const XpProgressCard({
    super.key,
    required this.totalXp,
    required this.discoveredCount,
    required this.eligibleAnimalCount,
    required this.onOpenCollection,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress = eligibleAnimalCount == 0
        ? 0.0
        : (discoveredCount / eligibleAnimalCount).clamp(0.0, 1.0);
    return Material(
      color: colors.surface.withValues(alpha: 0.97),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onOpenCollection,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 202,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.stars_rounded, color: colors.tertiary, size: 19),
                    const SizedBox(width: 5),
                    Text(
                      '$totalXp XP',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.collections_bookmark_rounded,
                      color: colors.primary,
                      size: 17,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '$discoveredCount of $eligibleAnimalCount locations explored',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: colors.surfaceContainerHighest,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
