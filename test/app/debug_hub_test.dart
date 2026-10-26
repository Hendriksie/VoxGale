// Widget tests for the home replacement (task 5.5, design P1-D6): the live
// session screen is home; the spike links live behind the debug-only route
// opened from the live screen's app bar (the debug action is a `kDebugMode`
// const — true in tests, folded out of release builds). The debug-only API
// key entry was removed in Phase 2 — the production settings screen replaced
// it. The controller is a test double — never real services.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxtral_live/app/debug_hub_screen.dart';
import 'package:voxtral_live/app/live_session_screen.dart';

import 'fakes.dart';

void main() {
  testWidgets('home is the live session screen, without spike links',
      (tester) async {
    await tester.pumpWidget(appWithStore(
      FakeApiKeyStore(),
      sessionController: FakeLiveSessionController(),
    ));
    await tester.pump();

    expect(find.byType(LiveSessionScreen), findsOneWidget);
    expect(find.text('Voxtral Live'), findsOneWidget);
    expect(find.text('Start a session to see the live transcript.'),
        findsOneWidget);
    // The spike harness is not on the home screen.
    expect(find.textContaining('Spike A'), findsNothing);
    expect(find.textContaining('Spike B'), findsNothing);
    expect(find.textContaining('Spike C'), findsNothing);
    expect(find.text('API key (debug)'), findsNothing);
  });

  testWidgets('the debug action opens the debug hub with the spike links '
      '(debug-route gating; kDebugMode is true in tests)', (tester) async {
    await tester.pumpWidget(appWithStore(
      FakeApiKeyStore(),
      sessionController: FakeLiveSessionController(),
    ));
    await tester.pump();

    // The debug action is present on the live screen's app bar.
    await tester.tap(find.byIcon(Icons.bug_report_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(DebugHubScreen), findsOneWidget);
    expect(find.text('Spike A — live transcription'), findsOneWidget);
    expect(find.text('Spike B — background capture'), findsOneWidget);
    expect(find.text('Spike C — batch transcription'), findsOneWidget);
    // The debug-only API key entry is gone — the settings screen (Phase 2)
    // replaced it.
    expect(find.text('API key (debug)'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
}
