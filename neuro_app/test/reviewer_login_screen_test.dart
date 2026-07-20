import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_app/screens/login_screen.dart';

void main() {
  testWidgets('reviewer login uses email and password fields', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Email / E-Mail'), findsOneWidget);
    expect(find.text('Password / Passwort'), findsOneWidget);
    expect(find.text('Sign in / Anmelden'), findsOneWidget);

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields, hasLength(2));
    expect(fields.first.keyboardType, TextInputType.emailAddress);
    expect(fields.last.obscureText, isTrue);
  });
}
