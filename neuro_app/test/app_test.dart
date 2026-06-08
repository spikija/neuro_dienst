import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_app/main.dart';

void main() {
  testWidgets(
    'app starts',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const NeuroDienstApp(),
      );

      expect(
        find.text('NeuroDienst'),
        findsOneWidget,
      );
    },
  );
}