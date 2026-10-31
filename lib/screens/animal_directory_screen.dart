import 'package:flutter/material.dart';

import '../models/gamification_profile.dart';
import '../models/zoo_waypoint.dart';
import '../widgets/animal_illustration.dart';

enum _AnimalGroupFilter { all, mammals, birds }

class AnimalDirectoryScreen extends StatefulWidget {
  final List<ZooWaypoint> animals;
  final GamificationProfile profile;
  final String Function(String name) groupForName;
  final ValueChanged<ZooWaypoint> onOpenAnimal;
  final ValueChanged<ZooWaypoint> onShowOnMap;
  final VoidCallback onToggleTheme;
  final bool isDarkMode;

  const AnimalDirectoryScreen({
    super.key,
    required this.animals,
    required this.profile,
    required this.groupForName,
    required this.onOpenAnimal,
    required this.onShowOnMap,
    required this.onToggleTheme,
    required this.isDarkMode,
  });

  @override
  State<AnimalDirectoryScreen> createState() => _AnimalDirectoryScreenState();
}

class _AnimalDirectoryScreenState extends State<AnimalDirectoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  _AnimalGroupFilter _filter = _AnimalGroupFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final query = _searchController.text.trim().toLowerCase();
    final discoveredCount = widget.animals
        .where((animal) => widget.profile.hasDiscovered(animal.id))
        .length;
    final filteredAnimals = widget.animals.where((animal) {
      final group = widget.groupForName(animal.name);
      final matchesGroup = switch (_filter) {
        _AnimalGroupFilter.all => true,
        _AnimalGroupFilter.mammals => group == 'Mammals',
        _AnimalGroupFilter.birds => group == 'Birds',
      };
      return matchesGroup &&
          (query.isEmpty || animal.name.toLowerCase().contains(query));
    }).toList();

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Animals'),
        actions: [
          IconButton.filledTonal(
            tooltip: widget.isDarkMode ? 'Use light theme' : 'Use dark theme',
            onPressed: widget.onToggleTheme,
            icon: Icon(
              widget.isDarkMode
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 13),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colors.primaryContainer,
                        colors.tertiaryContainer,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(23),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.pets_rounded, color: colors.primary),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'Meet the animal friends',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          Text(
                            '${widget.profile.totalXp} XP',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$discoveredCount of ${widget.animals.length} discovered',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 9),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: LinearProgressIndicator(
                          value: widget.animals.isEmpty
                              ? 0
                              : discoveredCount / widget.animals.length,
                          minHeight: 7,
                          backgroundColor: colors.surface.withValues(
                            alpha: .65,
                          ),
                          color: const Color(0xFFE5AD3A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search animals',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: colors.primary,
                    ),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: colors.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('All', _AnimalGroupFilter.all),
                      const SizedBox(width: 8),
                      _filterChip('Mammals', _AnimalGroupFilter.mammals),
                      const SizedBox(width: 8),
                      _filterChip('Birds', _AnimalGroupFilter.birds),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: filteredAnimals.isEmpty
                ? Center(
                    child: Text(
                      'No animals match this search.',
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
                    itemCount: filteredAnimals.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 9),
                    itemBuilder: (context, index) => _AnimalListCard(
                      animal: filteredAnimals[index],
                      group: widget.groupForName(filteredAnimals[index].name),
                      isDiscovered: widget.profile.hasDiscovered(
                        filteredAnimals[index].id,
                      ),
                      onOpen: () => widget.onOpenAnimal(filteredAnimals[index]),
                      onShowOnMap: () =>
                          widget.onShowOnMap(filteredAnimals[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _AnimalGroupFilter filter) {
    final colors = Theme.of(context).colorScheme;
    final selected = _filter == filter;
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      backgroundColor: colors.surfaceContainerLow,
      selectedColor: colors.primaryContainer,
      side: BorderSide(
        color: selected
            ? colors.primary.withValues(alpha: .35)
            : colors.outlineVariant.withValues(alpha: .5),
      ),
      labelStyle: TextStyle(
        color: selected ? colors.onPrimaryContainer : colors.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
      onSelected: (_) => setState(() => _filter = filter),
    );
  }
}

class _AnimalListCard extends StatelessWidget {
  final ZooWaypoint animal;
  final String group;
  final bool isDiscovered;
  final VoidCallback onOpen;
  final VoidCallback onShowOnMap;

  const _AnimalListCard({
    required this.animal,
    required this.group,
    required this.isDiscovered,
    required this.onOpen,
    required this.onShowOnMap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reviewNote = animal.reviewNote?.trim();
    final quality = <String>[
      if (!animal.nameVerified) 'Name not verified',
      if (animal.needsReview) 'Details need review',
      if (reviewNote != null && reviewNote.isNotEmpty) reviewNote,
    ];

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(21),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: AnimalIllustration(
                    animalName: animal.name,
                    width: 84,
                    height: 84,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        animal.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            group == 'Birds'
                                ? Icons.emoji_nature_rounded
                                : Icons.pets_rounded,
                            size: 14,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            group,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                          if (isDiscovered) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 15,
                              color: Color(0xFF27814F),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Discovered',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: const Color(0xFF27814F),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ],
                      ),
                      if (quality.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          quality.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontSize: 10,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Show on zoo map',
                onPressed: onShowOnMap,
                icon: Icon(Icons.map_outlined, color: colors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
