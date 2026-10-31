import 'package:flutter_test/flutter_test.dart';

import 'package:pet_tracker_mobile/main.dart';

void main() {
  testWidgets('App shows the map screen title', (WidgetTester tester) async {
    await tester.pumpWidget(const PetTrackerApp());

    expect(find.text('Position de mon animal'), findsOneWidget);
  });
}
