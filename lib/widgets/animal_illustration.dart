import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Reuses the project's existing cartoon sprite sheets with a soft habitat
/// backdrop. This is illustrative artwork, not a verified species photograph.
class AnimalIllustration extends StatelessWidget {
  final String animalName;
  final double width;
  final double height;

  const AnimalIllustration({
    super.key,
    required this.animalName,
    required this.width,
    required this.height,
  });

  static const _frames = <String, int>{
    'ostrich': 0,
    'crowned crane': 1,
    'cassowary': 2,
    'black swan': 3,
    'oryx / gaur': 4,
    'blue-and-yellow macaw / scarlet macaw': 5,
    'camel': 7,
    'brown bear': 8,
    'fox': 9,
    'bengal tiger': 10,
    'eurasian otter': 11,
    'meerkat': 12,
    'jungle cat': 13,
    'ring-tailed lemur': 14,
    'purple-faced langur': 15,
    'grey langur': 16,
    'white toque monkey': 17,
    'hippopotamus': 18,
    'capybara': 19,
    'elephant': 20,
    'deer': 21,
    'nilgai / hog deer / muntjac': 22,
    'hamadryas baboon': 25,
    'lion': 26,
    'african lion': 27,
    'chimpanzee': 28,
    'mule': 29,
    'brahminy kite / mountain hawk-eagle': 30,
    'white-bellied sea eagle': 32,
    'emu': 33,
    "bennett's wallaby": 34,
    'wild boar': 35,
    'lechwe': 36,
    'scimitar-horned oryx': 37,
    'rhinoceros': 38,
    'sheep': 39,
    'greater kudu': 40,
    'wild horse': 41,
    'horse': 42,
    'donkey': 43,
    'swan': 44,
    'sloth bear': 45,
    'black jaguar / jaguar': 46,
    'llama': 47,
  };

  @override
  Widget build(BuildContext context) {
    final key = animalName
        .replaceFirst(RegExp(r'\s+\d+$'), '')
        .trim()
        .toLowerCase();
    final frame = _frames[key] ?? 0;
    final localFrame = frame % 16;
    // Keep a square viewport for one sprite cell while the containing card can
    // be any shape. The transparent animal artwork then keeps its own ratio.
    final availableWidth = width.isFinite ? width : height;
    final availableHeight = height.isFinite ? height : width;
    final size = math.min(availableWidth, availableHeight);
    final asset =
        'assets/images/animals/cartoon_animals_${frame ~/ 16 + 1}.png';

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFCDE8D0),
                  Color(0xFF9CCB9B),
                  Color(0xFFF2DFA7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            left: -size * .12,
            bottom: -size * .54,
            child: Container(
              width: size * 1.25,
              height: size * .85,
              decoration: BoxDecoration(
                color: const Color(0xFF5F9E68).withValues(alpha: .45),
                borderRadius: BorderRadius.circular(size),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 19,
              color: Colors.white.withValues(alpha: .9),
            ),
          ),
          Center(
            child: ClipRect(
              child: SizedBox(
                width: size,
                height: size,
                child: OverflowBox(
                  minWidth: size * 4,
                  maxWidth: size * 4,
                  minHeight: size * 4,
                  maxHeight: size * 4,
                  alignment: Alignment(
                    -1 + (localFrame % 4) * (2 / 3),
                    -1 + (localFrame ~/ 4) * (2 / 3),
                  ),
                  child: Image.asset(
                    asset,
                    width: size * 4,
                    height: size * 4,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.pets_rounded,
                      size: 48,
                      color: Color(0xFF39734B),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
