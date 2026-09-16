import 'package:flutter_test/flutter_test.dart';

import 'package:ble_attendance_poc/main.dart';

void main() {
  testWidgets('role select screen shows Teacher and Student options', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ClassLinkApp());

    expect(find.text("I'm the Teacher"), findsOneWidget);
    expect(find.text("I'm a Student"), findsOneWidget);
  });
}
