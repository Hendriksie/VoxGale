// Widget tests for the post-session pass offer UI (task 5.3): the offer with
// its estimated cost and the run/skip actions, the running progress, the
// failure error with a retry, and the pass's actual usage in the done phase.
// The controller is a test double — never real services.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/session/live_session_controller.dart';
import 'package:voxgale/session/session_models.dart';

import 'fakes.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    LiveSessionState state, {
    FakeLiveSessionController? controller,
  }) async {
    await tester.pumpWidget(appWithStore(
      FakeApiKeyStore(),
      sessionController: controller ?? FakeLiveSessionController(state),
    ));
    await tester.pump();
  }

  /// A finalized session with the pass offered (the state after a graceful
  // stop): the provisional transcript is saved, the actuals are known.
  LiveSessionState passOfferedState({
    double passEstimatedCost = 0.012,
    List<TranscriptTurn> turns = const [
      TranscriptTurn(text: 'Hello world'),
    ],
  }) =>
      LiveSessionState(
        phase: LiveSessionPhase.passOffered,
        turns: turns,
        sessionId: 'session-1',
        durationSeconds: 65,
        realtimeBilledSeconds: 61,
        realtimeActualCost: 0.011,
        passEstimatedCost: passEstimatedCost,
      );

  testWidgets('the offer shows the estimated cost with run/skip actions',
      (tester) async {
    await pumpScreen(tester, passOfferedState());

    expect(find.text('Add speaker labels'), findsOneWidget);
    expect(find.text('Post-session pass · est. \$0.012'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    // The saved provisional transcript stays visible under the offer.
    expect(find.text('Hello world'), findsOneWidget);
    // The session's actual usage shows in the status row.
    expect(find.text('61 s billed · \$0.011'), findsOneWidget);
  });

  testWidgets('Run and Skip drive the controller', (tester) async {
    final controller = FakeLiveSessionController(passOfferedState());
    await pumpScreen(tester, passOfferedState(), controller: controller);

    await tester.tap(find.text('Run'));
    await tester.pump();
    expect(controller.calls, ['runDiarizationPass']);

    controller.calls.clear();
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(controller.calls, ['skipDiarizationPass']);
  });

  testWidgets('the running pass shows progress and no actions',
      (tester) async {
    await pumpScreen(tester, passOfferedState().copyWith(
      phase: LiveSessionPhase.passRunning,
    ));

    expect(find.text('Adding speaker labels…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('Run'), findsNothing);
    expect(find.text('Skip'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a failed pass shows the error with a retry, keeping the '
      'provisional transcript', (tester) async {
    final controller = FakeLiveSessionController(
      passOfferedState().copyWith(
        phase: LiveSessionPhase.passFailed,
        error: 'quota exceeded',
      ),
    );
    await pumpScreen(
      tester,
      passOfferedState().copyWith(
        phase: LiveSessionPhase.passFailed,
        error: 'quota exceeded',
      ),
      controller: controller,
    );

    expect(
      find.text('The speaker-attribution pass failed: quota exceeded'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    // The provisional transcript is preserved.
    expect(find.text('Hello world'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(controller.calls, ['runDiarizationPass']);
  });

  testWidgets('the done phase shows the pass actual usage next to the '
      'realtime actuals', (tester) async {
    await pumpScreen(tester, const LiveSessionState(
      phase: LiveSessionPhase.done,
      turns: [
        TranscriptTurn(
          speakerLabel: 'speaker_1',
          text: 'Hello ',
          isProvisional: false,
        ),
        TranscriptTurn(
          speakerLabel: 'speaker_2',
          text: 'world',
          isProvisional: false,
        ),
      ],
      durationSeconds: 65,
      realtimeBilledSeconds: 61,
      realtimeActualCost: 0.011,
      passBilledSeconds: 30,
      passActualCost: 0.005,
    ));

    // The finalized, speaker-labelled transcript replaced the provisional one.
    expect(find.text('speaker_1'), findsOneWidget);
    expect(find.text('speaker_2'), findsOneWidget);
    expect(find.text('61 s billed · \$0.011 · pass 30 s · \$0.005'),
        findsOneWidget);
    // No pass offer remains.
    expect(find.text('Add speaker labels'), findsNothing);
    // Start is available for the next session.
    expect(find.text('Start'), findsOneWidget);
  });
}
