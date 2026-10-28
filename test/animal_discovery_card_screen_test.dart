import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dehiwala_zoo_app/models/animal_discovery.dart';
import 'package:dehiwala_zoo_app/models/animal_profile.dart';
import 'package:dehiwala_zoo_app/models/zoo_waypoint.dart';
import 'package:dehiwala_zoo_app/screens/animal_discovery_card_screen.dart';
import 'package:dehiwala_zoo_app/services/animal_information_service.dart';

void main() {
  const unverifiedAnimal = ZooWaypoint(
    id: 'WP002',
    name: 'Ostrich',
    latitude: 6.856792,
    longitude: 79.872837,
    category: 'animal',
    nameVerified: false,
    reviewNote: 'Name retained from the source map.',
  );

  testWidgets('card handles missing facts without inventing information', (
    WidgetTester tester,
  ) async {
    var mapTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AnimalDiscoveryCardScreen(
          animal: unverifiedAnimal,
          discovery: AnimalDiscovery(
            waypointId: unverifiedAnimal.id,
            xpAwarded: 100,
            discoveredAtUtc: DateTime.utc(2026, 10, 25),
          ),
          informationService: AnimalInformationService(),
          onShowOnMap: () => mapTapped = true,
          showReward: true,
        ),
      ),
    );

    expect(find.text('DISCOVERED'), findsOneWidget);
    expect(find.text('+100 XP'), findsOneWidget);
    expect(
      find.text(
        'Name not verified. This is the name recorded for the map location.',
      ),
      findsOneWidget,
    );
    expect(find.text('Name retained from the source map.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Field notes are being prepared'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Field notes are being prepared'), findsOneWidget);
    expect(find.text('Scientific name'), findsNothing);
    expect(find.text('Asian Elephant'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Find this habitat on the map'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Find this habitat on the map'));
    await tester.pumpAndSettle();
    expect(mapTapped, isTrue);
  });

  testWidgets('verified sourced profile facts are displayed when available', (
    WidgetTester tester,
  ) async {
    const verifiedWaypoint = ZooWaypoint(
      id: 'WP900',
      name: 'Test animal',
      latitude: 6.8,
      longitude: 79.8,
      category: 'animal',
      nameVerified: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AnimalDiscoveryCardScreen(
          animal: verifiedWaypoint,
          discovery: null,
          informationService: AnimalInformationService(
            profiles: [
              AnimalProfile(
                waypointId: verifiedWaypoint.id,
                scientificName: 'Example species',
                classification: 'Mammal',
                habitat: 'Woodland',
                diet: 'Herbivore',
                nativeRange: 'Example region',
                conservationStatus: 'Least Concern',
                interestingFact: 'A short sourced fact.',
                status: AnimalInformationStatus.verified,
                sources: [
                  AnimalInformationSource(
                    name: 'Example authority',
                    uri: Uri.parse('https://example.org'),
                  ),
                ],
              ),
            ],
          ),
          onShowOnMap: () {},
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Woodland'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Example species'), findsOneWidget);
    expect(find.text('Woodland'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('A short sourced fact.'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('A short sourced fact.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Example authority'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Example authority'), findsOneWidget);
    expect(
      find.text(
        'Name not verified. This is the name recorded for the map location.',
      ),
      findsNothing,
    );
  });

  testWidgets('sourced facts stay hidden while waypoint name is unverified', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AnimalDiscoveryCardScreen(
          animal: unverifiedAnimal,
          discovery: null,
          informationService: AnimalInformationService(
            profiles: [
              AnimalProfile(
                waypointId: 'WP002',
                scientificName: 'Example species',
                sources: [
                  AnimalInformationSource(
                    name: 'Reference',
                    uri: Uri.parse('https://example.org'),
                  ),
                ],
              ),
            ],
          ),
          onShowOnMap: () {},
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -560));
    await tester.pumpAndSettle();
    expect(find.text('Example species'), findsNothing);
    expect(find.text('Reference'), findsNothing);
  });
}
