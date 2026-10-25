import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dehiwala_zoo_app/main.dart';

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.text('Search the zoo'));
  await _pumpUi(tester);
}

Future<void> _selectSearchResult(WidgetTester tester, String name) async {
  await tester.enterText(find.byType(TextField), name);
  await _pumpUi(tester);
  await tester.tap(
    find.ancestor(of: find.text(name).last, matching: find.byType(ListTile)),
  );
  await _pumpUi(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path,
      );

  testWidgets(
    'map search opens facilities and landmarks and shows quality notes',
    (WidgetTester tester) async {
      await tester.pumpWidget(const ZooMapApp(startIn3dMode: false));
      await _pumpUi(tester);

      expect(find.text('Locate Me'), findsOneWidget);
      expect(find.text('Search the zoo'), findsOneWidget);

      await _openSearch(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'Facilities'));
      await _pumpUi(tester);
      await _selectSearchResult(tester, 'Aquarium Entrance');
      expect(find.text('Facility'), findsOneWidget);
      expect(find.text('Name not verified'), findsOneWidget);
      await tester.tap(find.text('Center map here'));
      await _pumpUi(tester);

      await _openSearch(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'Landmarks'));
      await _pumpUi(tester);
      await _selectSearchResult(tester, 'Viewpoint');
      expect(find.text('Landmark'), findsOneWidget);
      expect(find.text('Name not verified'), findsOneWidget);
      await tester.tap(find.text('Center map here'));
      await _pumpUi(tester);

      await _openSearch(tester);
      final landmarksChip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Landmarks'),
      );
      expect(landmarksChip.selected, isTrue);
      await tester.enterText(find.byType(TextField), 'Viewpoint');
      await _pumpUi(tester);
      expect(
        find.ancestor(
          of: find.text('Viewpoint').last,
          matching: find.byType(ListTile),
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilterChip, 'Animals'));
      await _pumpUi(tester);
      await tester.enterText(find.byType(TextField), 'Crowned Crane');
      await _pumpUi(tester);
      await tester.tap(
        find.ancestor(
          of: find.text('Crowned Crane').last,
          matching: find.byType(ListTile),
        ),
      );
      await _pumpUi(tester);
      expect(
        find.text(
          'Original label was "African crown crane". Confirm the exact '
          'crowned-crane species from the sign or staff.',
        ),
        findsOneWidget,
      );
      expect(find.text('Name not verified'), findsOneWidget);
    },
  );
}
