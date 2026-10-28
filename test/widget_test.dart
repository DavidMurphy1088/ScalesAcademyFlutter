import 'package:flutter_test/flutter_test.dart';

import 'package:scales_academy_flutter/main.dart';

void main() {
  testWidgets('Shows the Start listening button', (WidgetTester tester) async {
    // Widget tests run as Android by default, so the listening screen is shown with the YIN detector
    await tester.pumpWidget(const ScalesAcademyFlutterApp());
    await tester.pumpAndSettle();
    expect(find.text('Start listening'), findsOneWidget);
    expect(find.text('Detector: YIN'), findsOneWidget);
  });
}
