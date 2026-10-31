import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dehiwala_zoo_app/widgets/exploration_session_panel.dart';

void main() {
  testWidgets('start button begins an exploration callback', (tester) async {
    var starts = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExplorationSessionPanel(
            isActive: false,
            isFindingLocation: false,
            totalXp: 200,
            discoveredCount: 2,
            eligibleAnimalCount: 10,
            sessionDiscoveryCount: 0,
            sessionXp: 0,
            destinationName: null,
            distanceMeters: null,
            destinationNameVerified: false,
            hasRecordedTrace: false,
            onStart: () => starts++,
            onFinish: () {},
            onOpenCollection: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Start Exploring'));
    expect(starts, 1);
    expect(find.text('Zoo adventure'), findsOneWidget);
  });

  testWidgets('active session shows destination, GPS trace note and finish', (
    tester,
  ) async {
    var finishes = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ExplorationSessionPanel(
              isActive: true,
              isFindingLocation: false,
              totalXp: 300,
              discoveredCount: 3,
              eligibleAnimalCount: 10,
              sessionDiscoveryCount: 1,
              sessionXp: 100,
              destinationName: 'Bengal Tiger',
              distanceMeters: 125,
              destinationNameVerified: false,
              hasRecordedTrace: true,
              onStart: () {},
              onFinish: () => finishes++,
              onOpenCollection: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Bengal Tiger'), findsOneWidget);
    expect(find.textContaining('125 m straight-line estimate'), findsOneWidget);
    expect(find.text('Recorded name, not yet verified'), findsOneWidget);
    expect(
      find.textContaining('not an official walking route'),
      findsOneWidget,
    );
    await tester.tap(find.text('Finish exploration'));
    expect(finishes, 1);
  });
}
