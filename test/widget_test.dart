import 'package:flutter_test/flutter_test.dart';

import 'package:dehiwala_zoo_app/main.dart';

void main() {
  testWidgets('visitors can open a zoo location from the map', (
    WidgetTester tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    await tester.pumpWidget(const ZooMapApp());
    await tester.pumpAndSettle();

    expect(find.text('Dehiwala Zoo Map'), findsOneWidget);
    expect(find.text('Locate Me'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Aquarium Entrance'));
    await tester.pumpAndSettle();

    expect(find.text('Aquarium Entrance'), findsOneWidget);
    expect(find.text('Category: facility'), findsOneWidget);
  });
}
