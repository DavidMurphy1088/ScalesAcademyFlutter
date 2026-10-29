import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scales_academy_flutter/main.dart';

void main() {
  testWidgets('Home lists the test screens, and Listen opens with Start listening', (WidgetTester tester) async {
    await tester.pumpWidget(const ScalesAcademyFlutterApp());
    await tester.pumpAndSettle();
    expect(find.text('Listen'), findsOneWidget);
    expect(find.text('Sound'), findsOneWidget);

    // Widget tests run as Android by default, so the listening screen uses the YIN detector
    await tester.tap(find.text('Listen'));
    await tester.pumpAndSettle();
    expect(find.text('Start listening'), findsOneWidget);
    expect(find.text('Detector: YIN'), findsOneWidget);
    expect(find.byType(Slider), findsWidgets);
  });
}
