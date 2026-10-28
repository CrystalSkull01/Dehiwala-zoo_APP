import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dehiwala_zoo_app/models/zoo_waypoint.dart';
import 'package:dehiwala_zoo_app/screens/animal_discovery_card_screen.dart';
import 'package:dehiwala_zoo_app/services/animal_information_service.dart';
import 'package:dehiwala_zoo_app/widgets/animal_illustration.dart';

void main() {
  const cases = <({String name, String asset, Alignment alignment})>[
    (
      name: 'Ostrich',
      asset: 'assets/images/animals/cartoon_animals_1.png',
      alignment: Alignment(-1, -1),
    ),
    (
      name: 'Crowned Crane',
      asset: 'assets/images/animals/cartoon_animals_1.png',
      alignment: Alignment(-1 / 3, -1),
    ),
    (
      name: 'Black Swan',
      asset: 'assets/images/animals/cartoon_animals_1.png',
      alignment: Alignment(1, -1),
    ),
    (
      name: 'Blue-and-yellow macaw / scarlet macaw',
      asset: 'assets/images/animals/cartoon_animals_1.png',
      alignment: Alignment(-1 / 3, -1 / 3),
    ),
    (
      name: 'Bengal Tiger',
      asset: 'assets/images/animals/cartoon_animals_1.png',
      alignment: Alignment(1 / 3, 1 / 3),
    ),
    (
      name: 'Elephant',
      asset: 'assets/images/animals/cartoon_animals_2.png',
      alignment: Alignment(-1, -1 / 3),
    ),
    (
      name: 'White-bellied Sea Eagle',
      asset: 'assets/images/animals/cartoon_animals_3.png',
      alignment: Alignment(-1, -1),
    ),
  ];

  testWidgets(
    'bird and mammal sprite frames keep the correct atlas crop and fit',
    (tester) async {
      for (final testCase in cases) {
        for (final constraints in const [
          (width: 320.0, height: 150.0),
          (width: 390.0, height: 224.0),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: AnimalIllustration(
                    animalName: testCase.name,
                    width: constraints.width,
                    height: constraints.height,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final image = tester.widget<Image>(find.byType(Image));
          final atlas = image.image as AssetImage;
          final crop = tester.widget<OverflowBox>(find.byType(OverflowBox));
          final alignment = crop.alignment.resolve(TextDirection.ltr);
          expect(atlas.assetName, testCase.asset, reason: testCase.name);
          expect(image.fit, BoxFit.contain, reason: testCase.name);
          expect(image.width, image.height, reason: testCase.name);
          expect(
            alignment.x,
            closeTo(testCase.alignment.x, 1e-9),
            reason: testCase.name,
          );
          expect(
            alignment.y,
            closeTo(testCase.alignment.y, 1e-9),
            reason: testCase.name,
          );
          expect(tester.takeException(), isNull, reason: testCase.name);
        }
      }
    },
  );

  testWidgets('animal detail card fits a small phone screen', (tester) async {
    const smallPhone = Size(320, 640);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const animal = ZooWaypoint(
      id: 'small-phone-animal',
      name: 'Black Swan',
      latitude: 6.856,
      longitude: 79.872,
      category: 'animal',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AnimalDiscoveryCardScreen(
          animal: animal,
          discovery: null,
          informationService: AnimalInformationService(),
          onShowOnMap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.view.physicalSize, smallPhone);
    expect(tester.takeException(), isNull);
    expect(find.text('NOT YET DISCOVERED'), findsOneWidget);
    expect(find.text('Field notes'), findsOneWidget);
  });
}
