import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_app/demo/demo_roster.dart';
import 'package:neuro_app/main.dart';

void main() {
  testWidgets('app starts', (WidgetTester tester) async {
    final roster = DemoRoster.createJune2026();
    final doctor = DemoRoster.createCurrentDoctor();
    final doctors = DemoRoster.createDoctors();

    await tester.pumpWidget(
      NeuroDienstApp(roster: roster, currentDoctor: doctor, doctors: doctors),
    );

    expect(find.text('6/2026'), findsOneWidget);
  });
}
