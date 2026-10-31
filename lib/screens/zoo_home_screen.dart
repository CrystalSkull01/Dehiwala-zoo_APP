import 'package:flutter/material.dart';

import '../models/gamification_profile.dart';
import '../models/zoo_waypoint.dart';
import '../widgets/animal_illustration.dart';

class ZooHomeScreen extends StatelessWidget {
  final List<ZooWaypoint> animals;
  final GamificationProfile profile;
  final String Function(String name) animalGroupForName;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenMapSearch;
  final VoidCallback onOpenAnimals;
  final VoidCallback onOpenFacilities;
  final VoidCallback onOpenLandmarks;
  final VoidCallback onOpenCollection;
  final ValueChanged<ZooWaypoint> onOpenAnimal;
  final VoidCallback onToggleTheme;
  final bool isDarkMode;

  const ZooHomeScreen({
    super.key,
    required this.animals,
    required this.profile,
    required this.animalGroupForName,
    required this.onOpenMap,
    required this.onOpenMapSearch,
    required this.onOpenAnimals,
    required this.onOpenFacilities,
    required this.onOpenLandmarks,
    required this.onOpenCollection,
    required this.onOpenAnimal,
    required this.onToggleTheme,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final discoveredCount = animals
        .where((animal) => profile.hasDiscovered(animal.id))
        .length;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 16, 14),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Icon(
                        Icons.forest_rounded,
                        color: colors.primary,
                        size: 27,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dehiwala Zoo',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                          ),
                          Text(
                            'A little wild, a lot to discover',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Open wildlife collection',
                      onPressed: onOpenCollection,
                      icon: const Icon(Icons.bookmarks_rounded),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: isDarkMode
                          ? 'Use light theme'
                          : 'Use dark theme',
                      onPressed: onToggleTheme,
                      icon: Icon(
                        isDarkMode
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Material(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: onOpenMapSearch,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, color: colors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Search the zoo',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                          Icon(
                            Icons.tune_rounded,
                            color: colors.onSurfaceVariant,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: _WildlifeFeatureCard(
                  animal: animals.isEmpty ? null : animals.first,
                  onExplore: onOpenMap,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: .7),
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.explore_rounded, color: colors.primary),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '$discoveredCount of ${animals.length} animals discovered',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '${profile.totalXp} XP',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 11),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Explore the zoo',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onOpenMap,
                      icon: const Icon(Icons.map_outlined, size: 17),
                      label: const Text('Open map'),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 100,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  children: [
                    _ExploreShortcut(
                      icon: Icons.map_rounded,
                      label: 'Zoo map',
                      tint: const Color(0xFFDFF0E2),
                      onTap: onOpenMap,
                    ),
                    _ExploreShortcut(
                      icon: Icons.pets_rounded,
                      label: 'Animals',
                      tint: const Color(0xFFFFE9D7),
                      onTap: onOpenAnimals,
                    ),
                    _ExploreShortcut(
                      icon: Icons.place_rounded,
                      label: 'Facilities',
                      tint: const Color(0xFFE2EEF9),
                      onTap: onOpenFacilities,
                    ),
                    _ExploreShortcut(
                      icon: Icons.landscape_rounded,
                      label: 'Landmarks',
                      tint: const Color(0xFFF5E9CB),
                      onTap: onOpenLandmarks,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 23, 16, 11),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Animal friends',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    TextButton(
                      onPressed: onOpenAnimals,
                      child: const Text('See all'),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 184,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: animals.length.clamp(0, 8).toInt(),
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final animal = animals[index];
                    return _AnimalPreviewCard(
                      animal: animal,
                      group: animalGroupForName(animal.name),
                      isDiscovered: profile.hasDiscovered(animal.id),
                      onTap: () => onOpenAnimal(animal),
                    );
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _WildlifeFeatureCard extends StatelessWidget {
  final ZooWaypoint? animal;
  final VoidCallback onExplore;

  const _WildlifeFeatureCard({required this.animal, required this.onExplore});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF174E3A),
      elevation: 3,
      shadowColor: const Color(0x33174434),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 202,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (animal != null)
              Positioned(
                right: -8,
                bottom: -13,
                width: 198,
                height: 190,
                child: AnimalIllustration(
                  animalName: animal!.name,
                  width: 198,
                  height: 190,
                ),
              ),
            Positioned(
              right: -23,
              top: -38,
              child: Icon(
                Icons.eco_rounded,
                size: 150,
                color: Colors.white.withValues(alpha: .06),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF174E3A),
                    const Color(0xFF174E3A).withValues(alpha: .92),
                    const Color(0xFF174E3A).withValues(alpha: .02),
                  ],
                  stops: const [0, .48, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 18, 18),
              child: SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                          color: Color(0xFFFFD36E),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'YOUR WILDLIFE ADVENTURE',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: const Color(0xFFD8E9D8),
                                fontWeight: FontWeight.w900,
                                letterSpacing: .7,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Text(
                      'Discover\nthe wild',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            height: 1.02,
                            letterSpacing: -.7,
                          ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: onExplore,
                      icon: const Icon(Icons.explore_rounded, size: 18),
                      label: const Text('Explore now'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD36E),
                        foregroundColor: const Color(0xFF28452F),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreShortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  const _ExploreShortcut({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 84,
      child: InkWell(
        borderRadius: BorderRadius.circular(19),
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 55,
              height: 55,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(19),
              ),
              child: Icon(icon, color: colors.primary, size: 25),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimalPreviewCard extends StatelessWidget {
  final ZooWaypoint animal;
  final String group;
  final bool isDiscovered;
  final VoidCallback onTap;

  const _AnimalPreviewCard({
    required this.animal,
    required this.group,
    required this.isDiscovered,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 146,
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(21),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimalIllustration(
                      animalName: animal.name,
                      width: 146,
                      height: 116,
                    ),
                    if (isDiscovered)
                      const Positioned(
                        right: 7,
                        top: 7,
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF27814F),
                          shadows: [Shadow(color: Colors.white, blurRadius: 5)],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      animal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      group,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
