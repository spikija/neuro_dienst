import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/main.dart';
import 'package:neuro_admin/supabase_config.dart';

void main() {
  testWidgets(
    'shell resizes with a two-to-one split and missing-config notice',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in [const Size(1280, 720), const Size(800, 500)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          const NeuroAdminApp(
            config: SupabaseConfig(url: '', publishableKey: ''),
          ),
        );
        await tester.pump();
        expect(find.text('NeuroDienst Admin'), findsOneWidget);
        expect(find.text('Roster calendar'), findsOneWidget);
        expect(find.text('Physicians / workload'), findsOneWidget);
        expect(find.text('Desktop administrator client'), findsOneWidget);
        expect(
          find.text('Supabase configuration not provided'),
          findsOneWidget,
        );
        final panes = find.byType(Card);
        final left = tester.getRect(panes.at(0));
        final right = tester.getRect(panes.at(1));
        expect(left.width / right.width, closeTo(2, 0.01));
        expect(right.left, greaterThan(left.right));
        expect(left.top, right.top);
        expect(left.height, right.height);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('provided configuration does not claim an active connection', (
    tester,
  ) async {
    await tester.pumpWidget(
      const NeuroAdminApp(
        config: SupabaseConfig(
          url: 'https://example.invalid',
          publishableKey: 'test-public-key',
        ),
      ),
    );
    expect(find.textContaining('Supabase is not initialized.'), findsOneWidget);
    expect(find.textContaining('test-public-key'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('both configuration fields must be present', () {
    expect(
      const SupabaseConfig(url: ' ', publishableKey: 'key').isConfigured,
      isFalse,
    );
    expect(
      const SupabaseConfig(
        url: 'https://example.invalid',
        publishableKey: '',
      ).isConfigured,
      isFalse,
    );
  });
}
