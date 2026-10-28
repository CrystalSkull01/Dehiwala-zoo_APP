import 'package:flutter/material.dart';

import '../models/animal_discovery.dart';
import '../models/animal_profile.dart';
import '../models/zoo_waypoint.dart';
import '../services/animal_information_service.dart';
import '../widgets/animal_illustration.dart';

class AnimalDiscoveryCardScreen extends StatelessWidget {
  final ZooWaypoint animal;
  final AnimalDiscovery? discovery;
  final AnimalProfile? profile;
  final AnimalInformationService informationService;
  final VoidCallback onShowOnMap;
  final bool showReward;

  const AnimalDiscoveryCardScreen({
    super.key,
    required this.animal,
    required this.discovery,
    required this.informationService,
    required this.onShowOnMap,
    this.profile,
    this.showReward = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final candidateFacts = profile ?? informationService.profileFor(animal.id);
    final facts = animal.nameVerified && (candidateFacts?.isVerified ?? false)
        ? candidateFacts
        : null;
    final isDiscovered = discovery != null;
    final date = discovery?.discoveredAtUtc.toLocal();
    final fields = <(IconData, String, String?)>[
      (Icons.category_outlined, 'Animal group', facts?.classification),
      (Icons.forest_outlined, 'Natural habitat', facts?.habitat),
      (Icons.restaurant_outlined, 'Diet', facts?.diet),
      (Icons.public_outlined, 'Native range', facts?.nativeRange),
      (
        Icons.health_and_safety_outlined,
        'Conservation status',
        facts?.conservationStatus,
      ),
      (
        Icons.lightbulb_outline_rounded,
        'Wildlife fact',
        facts?.interestingFact,
      ),
    ];
    final availableFields = fields
        .where((field) => field.$3?.trim().isNotEmpty ?? false)
        .toList();

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Wildlife journal'),
        actions: [
          IconButton(
            tooltip: 'Close animal card',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _AnimalDiscoveryHero(
              animal: animal,
              scientificName: facts?.scientificName,
              isDiscovered: isDiscovered,
              xpAwarded: discovery?.xpAwarded,
              showReward: showReward,
            ),
            if (!animal.nameVerified) ...[
              const SizedBox(height: 12),
              const _Notice(
                icon: Icons.info_outline_rounded,
                text: 'Name not verified. This is the name recorded for the map location.',
              ),
            ],
            if (animal.needsReview) ...[
              const SizedBox(height: 8),
              const _Notice(
                icon: Icons.fact_check_outlined,
                text: 'This location record needs review.',
              ),
            ],
            if (animal.reviewNote?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              _Notice(
                icon: Icons.notes_rounded,
                text: animal.reviewNote!.trim(),
              ),
            ],
            if (showReward) ...[
              const SizedBox(height: 8),
              const _Notice(
                icon: Icons.celebration_rounded,
                text: 'New discovery saved to your wildlife journal.',
                emphasized: true,
              ),
            ],
            const SizedBox(height: 22),
            _sectionHeading(context, 'Field notes'),
            const SizedBox(height: 9),
            if (availableFields.isEmpty)
              const _EmptyFactsCard()
            else
              for (final (icon, title, value) in availableFields)
                _InformationRow(
                  icon: icon,
                  title: title,
                  value: value!.trim(),
                  isAvailable: true,
                ),
            if (facts?.sources.isNotEmpty ?? false) ...[
              const SizedBox(height: 14),
              _sectionHeading(context, 'Information sources'),
              const SizedBox(height: 7),
              for (final source in facts!.sources)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link_rounded),
                  title: Text(source.name),
                  subtitle: Text(source.uri.toString()),
                ),
            ],
            const SizedBox(height: 18),
            _sectionHeading(context, 'Your visit'),
            const SizedBox(height: 8),
            _InformationRow(
              icon: Icons.place_rounded,
              title: 'Map location',
              value: animal.name,
              isAvailable: true,
            ),
            _InformationRow(
              icon: Icons.bookmark_added_outlined,
              title: 'Discovery status',
              value: isDiscovered ? 'Discovered' : 'Not discovered yet',
              isAvailable: true,
            ),
            if (date != null)
              _InformationRow(
                icon: Icons.calendar_month_outlined,
                title: 'Discovery date',
                value: '${date.day}/${date.month}/${date.year}',
                isAvailable: true,
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                onShowOnMap();
                Navigator.of(context).maybePop();
              },
              icon: const Icon(Icons.map_rounded),
              label: const Text('Find this habitat on the map'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: const Color(0xFF205B43),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeading(BuildContext context, String label) => Text(
    label,
    style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w800),
  );
}

class _AnimalDiscoveryHero extends StatelessWidget {
  final ZooWaypoint animal;
  final String? scientificName;
  final bool isDiscovered;
  final int? xpAwarded;
  final bool showReward;

  const _AnimalDiscoveryHero({
    required this.animal,
    required this.scientificName,
    required this.isDiscovered,
    required this.xpAwarded,
    required this.showReward,
  });

  @override
  Widget build(BuildContext context) {
    final imageSize = (MediaQuery.sizeOf(context).width * .48)
        .clamp(144.0, 184.0)
        .toDouble();
    final reward = xpAwarded ?? 100;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF163F35), Color(0xFF236651), Color(0xFF287881)],
        ),
        borderRadius: BorderRadius.circular(29),
        border: Border.all(
          color: isDiscovered
              ? const Color(0xFFE7BB55)
              : const Color(0xFF4E8B70),
          width: isDiscovered ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF153F35).withValues(alpha: .22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(child: _HeroNaturePattern()),
          Positioned(
            right: -42,
            top: 48,
            child: _SoftOrb(size: 132, opacity: .07),
          ),
          Positioned(
            left: -50,
            bottom: 16,
            child: _SoftOrb(size: 126, opacity: .06),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.explore_rounded,
                      size: 17,
                      color: Color(0xFFB8E3C6),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'WILDLIFE FIELD GUIDE',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFFC6E6CE),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.05,
                        ),
                      ),
                    ),
                    if (isDiscovered || showReward)
                      _XpBadge(amount: reward, isNew: showReward),
                  ],
                ),
                const SizedBox(height: 13),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _HeroStatusBadge(isDiscovered: isDiscovered),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Container(
                    width: imageSize,
                    height: imageSize,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7DF),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: const Color(0xFFF4D487),
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x4420332D),
                          blurRadius: 15,
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: AnimalIllustration(
                        animalName: animal.name,
                        width: imageSize,
                        height: imageSize,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  animal.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    shadows: const [
                      Shadow(color: Color(0x55304737), blurRadius: 5),
                    ],
                  ),
                ),
                if (scientificName?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 5),
                  Text(
                    scientificName!.trim(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFD4E9DB),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStatusBadge extends StatelessWidget {
  final bool isDiscovered;

  const _HeroStatusBadge({required this.isDiscovered});

  @override
  Widget build(BuildContext context) {
    final color = isDiscovered
        ? const Color(0xFFFFD36E)
        : const Color(0xFFB8E3C6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: .42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDiscovered
                ? Icons.verified_rounded
                : Icons.travel_explore_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            isDiscovered ? 'DISCOVERED' : 'NOT YET DISCOVERED',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .7,
            ),
          ),
        ],
      ),
    );
  }
}

class _XpBadge extends StatelessWidget {
  final int amount;
  final bool isNew;

  const _XpBadge({required this.amount, required this.isNew});

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD36E),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x333A301A),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.stars_rounded, size: 16, color: Color(0xFF714B08)),
          const SizedBox(width: 4),
          Text(
            isNew ? '+$amount XP' : '$amount XP EARNED',
            style: const TextStyle(
              color: Color(0xFF714B08),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );

    if (!isNew) return badge;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .65, end: 1),
      duration: const Duration(milliseconds: 430),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: Alignment.centerRight,
        child: child,
      ),
      child: badge,
    );
  }
}

class _HeroNaturePattern extends StatelessWidget {
  const _HeroNaturePattern();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _HeroNaturePatternPainter());
}

class _HeroNaturePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final leafPaint = Paint()
      ..color = const Color(0xFFD3F0DB).withValues(alpha: .09);
    for (final center in [
      Offset(size.width * .08, size.height * .35),
      Offset(size.width * .91, size.height * .34),
      Offset(size.width * .14, size.height * .83),
      Offset(size.width * .84, size.height * .81),
    ]) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-.6);
      for (var leaf = 0; leaf < 3; leaf++) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(leaf * 7.0, leaf * -6.0),
            width: 16,
            height: 7,
          ),
          leafPaint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _HeroNaturePatternPainter oldDelegate) => false;
}

class _SoftOrb extends StatelessWidget {
  final double size;
  final double opacity;

  const _SoftOrb({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: opacity),
    ),
  );
}

class _EmptyFactsCard extends StatelessWidget {
  const _EmptyFactsCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.secondary.withValues(alpha: .18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Icon(Icons.menu_book_rounded, color: colors.secondary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Field notes are being prepared',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sourced animal details will appear here when reliable information is available.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool emphasized;

  const _Notice({
    required this.icon,
    required this.text,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: emphasized
            ? const Color(0xFFFFF1C9)
            : colors.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: emphasized ? const Color(0xFF96680D) : colors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _InformationRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool isAvailable;

  const _InformationRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.isAvailable,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isAvailable
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                    fontStyle: isAvailable ? null : FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
