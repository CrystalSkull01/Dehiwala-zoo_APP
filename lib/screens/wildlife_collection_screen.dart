import 'package:flutter/material.dart';

import '../models/gamification_profile.dart';
import '../models/zoo_waypoint.dart';
import '../widgets/animal_illustration.dart';

enum _CollectionFilter { all, discovered, undiscovered }

class WildlifeCollectionScreen extends StatefulWidget {
  final List<ZooWaypoint> animals;
  final GamificationProfile profile;
  final ValueChanged<ZooWaypoint> onOpenAnimal;
  final ValueChanged<ZooWaypoint> onShowOnMap;

  const WildlifeCollectionScreen({
    super.key,
    required this.animals,
    required this.profile,
    required this.onOpenAnimal,
    required this.onShowOnMap,
  });

  @override
  State<WildlifeCollectionScreen> createState() =>
      _WildlifeCollectionScreenState();
}

class _WildlifeCollectionScreenState extends State<WildlifeCollectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  _CollectionFilter _filter = _CollectionFilter.all;

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
    final animals = widget.animals.where((animal) {
      final discovered = widget.profile.hasDiscovered(animal.id);
      final matchesFilter = switch (_filter) {
        _CollectionFilter.all => true,
        _CollectionFilter.discovered => discovered,
        _CollectionFilter.undiscovered => !discovered,
      };
      return matchesFilter &&
          (query.isEmpty || animal.name.toLowerCase().contains(query));
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wildlife Collection'),
        leading: const Icon(Icons.auto_awesome_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colors.primaryContainer,
                        colors.tertiaryContainer,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.explore_rounded, color: colors.primary),
                          const SizedBox(width: 8),
                          Text(
                            '$discoveredCount of ${widget.animals.length} explored',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          Text(
                            '${widget.profile.totalXp} XP',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LinearProgressIndicator(
                          value: widget.animals.isEmpty
                              ? 0
                              : discoveredCount / widget.animals.length,
                          minHeight: 9,
                          backgroundColor: colors.surface.withValues(
                            alpha: 0.7,
                          ),
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search your collection',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
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
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 7,
                  children: [
                    for (final entry in [
                      (_CollectionFilter.all, 'All'),
                      (_CollectionFilter.discovered, 'Discovered'),
                      (_CollectionFilter.undiscovered, 'Undiscovered'),
                    ])
                      FilterChip(
                        label: Text(entry.$2),
                        selected: _filter == entry.$1,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _filter = entry.$1),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: animals.isEmpty
                ? Center(
                    child: Text(
                      'No animals match this search.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: animals.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (context, index) {
                      final animal = animals[index];
                      final discovered = widget.profile.hasDiscovered(
                        animal.id,
                      );
                      final note = animal.reviewNote?.trim();
                      final metadata = <String>[
                        'Animal',
                        discovered ? 'Discovered' : 'Not discovered',
                        if (!animal.nameVerified) 'Name not verified',
                        if (animal.needsReview) 'Details need review',
                        if (note != null && note.isNotEmpty) note,
                      ].join(' • ');
                      return Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        clipBehavior: Clip.antiAlias,
                        color: colors.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(19),
                          side: BorderSide(
                            color: discovered
                                ? const Color(0xFFD7A83D).withValues(alpha: .65)
                                : colors.outlineVariant.withValues(alpha: .5),
                          ),
                        ),
                        child: Column(
                          children: [
                            InkWell(
                              onTap: () => widget.onOpenAnimal(animal),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 94,
                                    height: 94,
                                    child: AnimalIllustration(
                                      animalName: animal.name,
                                      width: 94,
                                      height: 94,
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        13,
                                        10,
                                        8,
                                        10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  animal.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              if (discovered)
                                                const Icon(
                                                  Icons.check_circle_rounded,
                                                  size: 18,
                                                  color: Color(0xFFB98216),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            metadata,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            discovered
                                                ? 'Open journal card'
                                                : 'Explore this animal',
                                            style: TextStyle(
                                              color: colors.primary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(height: 1, color: colors.outlineVariant),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => widget.onShowOnMap(animal),
                                icon: const Icon(Icons.map_outlined, size: 17),
                                label: const Text('Show on map'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
