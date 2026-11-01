// Widget tests for the live session screen (tasks 5.1, 5.2, 5.4, Phase 3
// group 2): the turn-grouped transcript (provisional vs finalized styling,
// speaker chips, the gap marker), the status row (elapsed, estimated cost,
// actual usage, the connection-status indicator, the audio-focus pause
// wording), the state-driven control enablement, the error states (the
// shared taxonomy's full-screen state and transient banner — the API key is
// never displayed), the shared idle empty-transcript state, and the
// battery-restriction prompt. The controller is a test double — never real
// services.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/app/error_states.dart';
import 'package:voxgale/app/history_detail_screen.dart';
import 'package:voxgale/app/live_session_screen.dart';
import 'package:voxgale/app/transcript_widgets.dart';
import 'package:voxgale/mistral/mistral.dart';
import 'package:voxgale/session/live_session_controller.dart';
import 'package:voxgale/session/session_models.dart';
import 'package:voxgale/storage/storage.dart';

import 'fakes.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    LiveSessionState state, {
    ThemeMode? themeMode,
  }) async {
    await tester.pumpWidget(appWithStore(
      FakeApiKeyStore(),
      themeMode: themeMode,
      sessionController: FakeLiveSessionController(state),
    ));
    await tester.pump();
  }

  LiveSessionState activeState({
    List<TranscriptTurn> turns = const [],
    List<TranscriptGap> gapMarkers = const [],
    ConnectionStatus connection = const ConnectionStatus(),
    int elapsedSeconds = 0,
    double estimatedCost = 0,
    bool batteryPromptNeeded = false,
    String error = '',
  }) =>
      LiveSessionState(
        phase: LiveSessionPhase.active,
        turns: turns,
        gapMarkers: gapMarkers,
        connection: connection,
        elapsedSeconds: elapsedSeconds,
        estimatedCost: estimatedCost,
        batteryPromptNeeded: batteryPromptNeeded,
        error: error,
      );

  group('transcript (5.1)', () {
    testWidgets('renders turn-grouped blocks with speaker chips', (tester) async {
      await pumpScreen(tester, activeState(turns: [
        const TranscriptTurn(speakerLabel: 'speaker_1', text: 'Hello there'),
        const TranscriptTurn(speakerLabel: 'speaker_2', text: 'Hi'),
      ]));

      expect(find.byType(TranscriptTurnBlock), findsNWidgets(2));
      expect(find.text('Hello there'), findsOneWidget);
      expect(find.text('Hi'), findsOneWidget);
      expect(find.text('speaker_1'), findsOneWidget);
      expect(find.text('speaker_2'), findsOneWidget);
    });

    testWidgets('provisional turns render lighter/italic, finalized turns '
        'solid', (tester) async {
      await pumpScreen(tester, activeState(turns: const [
        TranscriptTurn(text: 'provisional text'),
        TranscriptTurn(text: 'final text', isProvisional: false),
      ]));

      final context = tester.element(find.byType(LiveSessionScreen));
      final scheme = Theme.of(context).colorScheme;
      final provisionalStyle =
          tester.widget<Text>(find.text('provisional text')).style;
      final finalStyle = tester.widget<Text>(find.text('final text')).style;

      expect(provisionalStyle?.fontStyle, FontStyle.italic);
      expect(provisionalStyle?.color, scheme.onSurfaceVariant);
      expect(finalStyle?.fontStyle, FontStyle.normal);
      expect(finalStyle?.color, scheme.onSurface);
    });

    testWidgets('renders a gap marker at the drop position, dimmed and '
        'italic', (tester) async {
      await pumpScreen(tester, activeState(
        turns: const [
          TranscriptTurn(text: 'Before the gap'),
          TranscriptTurn(text: 'After the gap'),
        ],
        gapMarkers: const [
          TranscriptGap(afterTurnIndex: 0, droppedSeconds: 5),
        ],
      ));

      const markerText = '— 5.0 s of audio could not be recovered —';
      expect(find.text(markerText), findsOneWidget);

      // The marker renders between the turns around the drop.
      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(TranscriptView),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .toList();
      expect(texts.indexOf(markerText),
          greaterThan(texts.indexOf('Before the gap')));
      expect(texts.indexOf(markerText),
          lessThan(texts.indexOf('After the gap')));

      // Dimmed, italic marker styling.
      final context = tester.element(find.byType(LiveSessionScreen));
      final scheme = Theme.of(context).colorScheme;
      final style = tester.widget<Text>(find.text(markerText)).style;
      expect(style?.fontStyle, FontStyle.italic);
      expect(style?.color, scheme.outline);
    });

    testWidgets('shows an empty state when there is no transcript', (tester) async {
      await pumpScreen(tester, const LiveSessionState());

      expect(find.byType(EmptyStateView), findsOneWidget);
      expect(
        find.text('Start a session to see the live transcript.'),
        findsOneWidget,
      );
    });
  });

  group('status row (5.1)', () {
    testWidgets('shows elapsed time and estimated cost while running',
        (tester) async {
      await pumpScreen(tester, activeState(elapsedSeconds: 65, estimatedCost: 0.009));

      expect(find.text('1:05'), findsOneWidget);
      expect(find.text('est. \$0.009'), findsOneWidget);
    });

    testWidgets('shows the actual usage after the stop, with the pass actuals '
        'alongside', (tester) async {
      await pumpScreen(tester, const LiveSessionState(
        phase: LiveSessionPhase.done,
        durationSeconds: 65,
        realtimeBilledSeconds: 61,
        realtimeActualCost: 0.011,
        passBilledSeconds: 30,
        passActualCost: 0.005,
      ));

      expect(find.text('61 s billed · \$0.011 · pass 30 s · \$0.005'),
          findsOneWidget);
    });

    testWidgets('indicates connection interruptions outside the transcript '
        '(no spike debug markers)', (tester) async {
      await pumpScreen(tester, activeState(
        turns: const [TranscriptTurn(text: 'Seamless text')],
        connection: const ConnectionStatus(
          reconnectCount: 1,
          lastDropReason: 'close code 1006',
          lastReplayedSeconds: 3.2,
          lastDroppedSeconds: 5,
        ),
      ));

      expect(find.text('Reconnected · Replayed 3.2 s · Dropped 5.0 s'),
          findsOneWidget);
      // The transcript text itself is unchanged, and no spike-style debug
      // markers leak into the production UI.
      expect(find.text('Seamless text'), findsOneWidget);
      expect(find.textContaining('[reconnected]'), findsNothing);
      expect(find.textContaining('[replayed]'), findsNothing);
      expect(find.textContaining('[dropped]'), findsNothing);
    });

    testWidgets('shows no connection status when the stream was seamless',
        (tester) async {
      await pumpScreen(tester, activeState());

      expect(find.byIcon(Icons.cloud_sync), findsNothing);
      expect(find.byIcon(Icons.cloud_off), findsNothing);
    });
  });

  group('recording indicator (5.1)', () {
    testWidgets('pulses orange while recording', (tester) async {
      await pumpScreen(tester, activeState());

      double dotAlpha() {
        final container = tester.widget<Container>(
          find.byKey(const ValueKey('recording-dot')),
        );
        return (container.decoration! as BoxDecoration).color!.a;
      }

      final alphaBefore = dotAlpha();
      await tester.pump(const Duration(milliseconds: 500));
      final alphaAfter = dotAlpha();

      expect(alphaBefore, isNot(alphaAfter));
    });

    testWidgets('is a static paused icon while paused (no pulse)',
        (tester) async {
      await pumpScreen(
        tester,
        const LiveSessionState(phase: LiveSessionPhase.paused),
      );
      // pumpAndSettle settles: no pulse animation is running.
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
      expect(find.byKey(const ValueKey('recording-dot')), findsNothing);
    });
  });

  group('controls (5.2)', () {
    Future<bool> isEnabled(WidgetTester tester, Finder finder) async {
      final widget = tester.widget(finder);
      if (widget is FilledButton) {
        return widget.onPressed != null;
      }
      if (widget is IconButton) {
        return widget.onPressed != null;
      }
      throw StateError('Unexpected widget: ${widget.runtimeType}');
    }

    Finder startButton() => find.ancestor(
          of: find.text('Start'),
          matching: find.byType(FilledButton),
        );
    Finder stopButton() => find.ancestor(
          of: find.text('Stop'),
          matching: find.byType(FilledButton),
        );
    Finder pauseButton() => find.ancestor(
          of: find.byIcon(Icons.pause),
          matching: find.byType(IconButton),
        );
    Finder resumeButton() => find.ancestor(
          of: find.byIcon(Icons.play_arrow),
          matching: find.byType(IconButton),
        );

    testWidgets('idle: Start enabled, no stop/pause/resume', (tester) async {
      await pumpScreen(tester, const LiveSessionState());

      expect(await isEnabled(tester, startButton()), isTrue);
      expect(find.text('Stop'), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('active: Stop and Pause enabled, no Start', (tester) async {
      await pumpScreen(tester, activeState());

      expect(await isEnabled(tester, stopButton()), isTrue);
      expect(await isEnabled(tester, pauseButton()), isTrue);
      expect(find.text('Start'), findsNothing);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('paused: Stop and Resume enabled, no Start/Pause',
        (tester) async {
      await pumpScreen(
        tester,
        const LiveSessionState(phase: LiveSessionPhase.paused),
      );

      expect(await isEnabled(tester, stopButton()), isTrue);
      expect(await isEnabled(tester, resumeButton()), isTrue);
      expect(find.text('Start'), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
    });

    testWidgets('starting: a progress indicator instead of controls',
        (tester) async {
      await pumpScreen(
        tester,
        const LiveSessionState(phase: LiveSessionPhase.starting),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Start'), findsNothing);
      expect(find.text('Stop'), findsNothing);
    });

    testWidgets('done: Start enabled again', (tester) async {
      await pumpScreen(
        tester,
        const LiveSessionState(phase: LiveSessionPhase.done),
      );

      expect(await isEnabled(tester, startButton()), isTrue);
      expect(find.text('Stop'), findsNothing);
    });

    testWidgets('the controls drive the controller actions', (tester) async {
      final controller = FakeLiveSessionController(activeState());
      await tester.pumpWidget(appWithStore(
        FakeApiKeyStore(),
        sessionController: controller,
      ));
      await tester.pump();

      await tester.tap(pauseButton());
      await tester.pump();
      await tester.tap(stopButton());
      await tester.pump();

      expect(controller.calls, ['pause', 'stop']);
    });
  });

  group('error states (5.1)', () {
    testWidgets('no API key: the error explains it and the key is never '
        'displayed', (tester) async {
      await pumpScreen(tester, const LiveSessionState(
        phase: LiveSessionPhase.error,
        error: 'No API key saved. Add your Mistral API key to start a session.',
        missingApiKey: true,
      ));

      // The shared full-screen error state (blocking failure).
      expect(find.byType(ErrorStateView), findsOneWidget);
      expect(find.textContaining('No API key saved'), findsOneWidget);
      // Phase 2: the missing-key state offers the settings screen (the
      // debug-only key entry is gone).
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.textContaining('debug menu'), findsNothing);
      // The key value itself is never rendered.
      expect(find.textContaining('sk-'), findsNothing);
    });

    testWidgets('permission and API errors render from the state',
        (tester) async {
      await pumpScreen(tester, const LiveSessionState(
        phase: LiveSessionPhase.error,
        error: 'Microphone permission denied. Grant it to record a session.',
      ));
      expect(find.textContaining('Microphone permission denied'),
          findsOneWidget);
      // Start is offered again after a fatal error.
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('a transient error while running is a slim banner row',
        (tester) async {
      await pumpScreen(tester, activeState(error: 'Connection lost'));

      // The shared inline banner: the failure kind's icon (no network) and
      // the state's message.
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.text('Connection lost'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      // The session controls stay available.
      expect(find.text('Stop'), findsOneWidget);
    });
  });

  group('shared empty/error states (Phase 3 group 2)', () {
    testWidgets('the idle empty-transcript state invites starting a session',
        (tester) async {
      await pumpScreen(tester, const LiveSessionState());

      expect(find.byType(EmptyStateView), findsOneWidget);
      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(
        find.text('Start a session to see the live transcript.'),
        findsOneWidget,
      );
      // The Start control is right below the empty state.
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('the empty-transcript state during a session is not an '
        'invitation to start one', (tester) async {
      await pumpScreen(tester, const LiveSessionState(
        phase: LiveSessionPhase.active,
      ));

      expect(find.byType(EmptyStateView), findsOneWidget);
      expect(find.text('No transcript yet.'), findsOneWidget);
      expect(
        find.text('Start a session to see the live transcript.'),
        findsNothing,
      );
    });

    testWidgets('the mic-permission-denied state re-requests the permission '
        'from its remedy action', (tester) async {
      final controller = FakeLiveSessionController(const LiveSessionState(
        phase: LiveSessionPhase.error,
        error: 'Microphone permission denied. Grant it to record a session.',
      ));
      await tester.pumpWidget(appWithStore(
        FakeApiKeyStore(),
        sessionController: controller,
      ));
      await tester.pump();

      expect(find.byType(ErrorStateView), findsOneWidget);
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
      expect(find.textContaining('Microphone permission denied'),
          findsOneWidget);

      await tester.tap(find.text('Grant microphone access'));
      await tester.pump();

      expect(controller.calls, ['requestMicPermission']);
    });

    testWidgets('the no-network state offers a retry that starts again',
        (tester) async {
      final controller = FakeLiveSessionController(const LiveSessionState(
        phase: LiveSessionPhase.error,
        error: 'Could not reach the Mistral API (connectionError).',
      ));
      await tester.pumpWidget(appWithStore(
        FakeApiKeyStore(),
        sessionController: controller,
      ));
      await tester.pump();

      expect(find.byType(ErrorStateView), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(
        find.text('Could not reach the Mistral API (connectionError).'),
        findsOneWidget,
      );

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(controller.calls, ['start']);
    });

    testWidgets('a fatal error carrying key-like material renders only the '
        'sanitized text', (tester) async {
      await pumpScreen(tester, const LiveSessionState(
        phase: LiveSessionPhase.error,
        error: 'Unauthorized: Bearer sk-abc123def456ghi',
      ));

      expect(find.textContaining('sk-abc123def456ghi'), findsNothing);
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    });

    testWidgets('the transient banner distinguishes auth, quota, and generic '
        'failures via the taxonomy', (tester) async {
      // Auth: the rejected-key wording maps to the auth kind's icon.
      await pumpScreen(
        tester,
        activeState(error: 'The API key was rejected. Check the key and try '
            'again.'),
      );
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(
        find.text('The API key was rejected. Check the key and try again.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Quota: the quota wording maps to the quota kind's icon.
      await pumpScreen(
        tester,
        activeState(error: 'Your API quota is exhausted.'),
      );
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.byIcon(Icons.account_balance_wallet_outlined),
          findsOneWidget);
      expect(find.text('Your API quota is exhausted.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Generic: anything else maps to the generic kind's icon.
      await pumpScreen(
        tester,
        activeState(error: 'The capture service stopped unexpectedly.'),
      );
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('the fatal error state renders in both themes', (tester) async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await pumpScreen(
          tester,
          const LiveSessionState(
            phase: LiveSessionPhase.error,
            error: 'No API key saved. Add your Mistral API key to start a '
                'session.',
            missingApiKey: true,
          ),
          themeMode: mode,
        );

        expect(find.byType(ErrorStateView), findsOneWidget);
        expect(find.text('Open settings'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });

  group('audio-focus pause (Phase 3 group 3)', () {
    testWidgets('an audio-focus pause is worded distinctly from a user pause',
        (tester) async {
      // Another app took audio focus: the pause says so.
      await pumpScreen(tester, const LiveSessionState(
        phase: LiveSessionPhase.paused,
        pausedByAudioFocus: true,
      ));

      expect(find.text('Paused — another app is using audio'), findsOneWidget);
      expect(find.text('Paused'), findsNothing);
      // The recording indicator still shows the paused state.
      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // A user pause keeps the plain wording.
      await pumpScreen(tester, const LiveSessionState(
        phase: LiveSessionPhase.paused,
      ));

      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Paused — another app is using audio'), findsNothing);
    });
  });

  group('battery prompt (5.4)', () {
    testWidgets('shown when the app is not exempt, deep-linking to the '
        'system settings', (tester) async {
      final controller = FakeLiveSessionController(
        activeState(batteryPromptNeeded: true),
      );
      await tester.pumpWidget(appWithStore(
        FakeApiKeyStore(),
        sessionController: controller,
      ));
      await tester.pump();

      expect(find.text('Allow unrestricted battery use'), findsOneWidget);
      expect(find.textContaining('battery restrictions'), findsOneWidget);

      await tester.tap(find.text('Open battery settings'));
      await tester.pump();
      expect(controller.calls, ['openBatterySettings']);
    });

    testWidgets('dismissible', (tester) async {
      await pumpScreen(
        tester,
        activeState(batteryPromptNeeded: true),
      );

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();

      expect(find.text('Allow unrestricted battery use'), findsNothing);
    });

    testWidgets('not shown when the app is exempt', (tester) async {
      await pumpScreen(tester, activeState(batteryPromptNeeded: false));

      expect(find.text('Allow unrestricted battery use'), findsNothing);
      expect(find.byIcon(Icons.battery_alert_outlined), findsNothing);
    });
  });

  group('home chrome (Phase 4 group 3)', () {
    testWidgets('the app bar carries only the production actions — no debug '
        'menu, no spike links', (tester) async {
      await pumpScreen(tester, const LiveSessionState());

      // The three production actions, and nothing else.
      expect(find.byTooltip('Transcribe a file'), findsOneWidget);
      expect(find.byTooltip('History'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(find.byType(IconButton), findsNWidgets(3));

      // The Phase-0 debug route and spike harness are gone for good (the
      // assertions moved here from the deleted debug_hub_test.dart).
      expect(find.byTooltip('Debug menu'), findsNothing);
      expect(find.byIcon(Icons.bug_report_outlined), findsNothing);
      expect(find.textContaining('Spike A'), findsNothing);
      expect(find.textContaining('Spike B'), findsNothing);
      expect(find.textContaining('Spike C'), findsNothing);
      expect(find.text('API key (debug)'), findsNothing);
    });
  });

  group('lifecycle (v1.1: battery re-check on resume)', () {
    testWidgets('re-checks the battery exemption when the app resumes',
        (tester) async {
      final controller = FakeLiveSessionController();
      await tester.pumpWidget(appWithStore(
        FakeApiKeyStore(),
        sessionController: controller,
      ));
      await tester.pump();

      // The binding dispatches lifecycle changes to observers synchronously.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      expect(controller.calls, contains('recheckBatteryExemption'));
    });
  });

  testWidgets('renders in both themes', (tester) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await pumpScreen(
        tester,
        activeState(turns: const [
          TranscriptTurn(speakerLabel: 'speaker_1', text: 'Hello'),
        ]),
        themeMode: mode,
      );

      expect(find.text('VoxGale'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  group('post-session card (change 2026-11-01-post-session-actions)', () {
    /// The export action test double: records its calls.
    final exportCalls = <({StoredSessionRecord record, bool markdown})>[];

    /// The saved record the Share action loads for session-1 (with a stored
    /// agent reply, so the history detail view shows the reply card).
    final savedRecord = StoredSessionRecord(
      session: StoredSession(
        id: 'session-1',
        startedAt: DateTime(2026, 11, 1, 10, 0),
        durationSeconds: 65,
        model: MistralConfig.defaults.realtimeModel,
        status: SessionStatus.provisional,
        agentReply: 'Three action items.',
        agentReplyAtMs: DateTime(2026, 11, 1, 10, 5).millisecondsSinceEpoch,
        agentReplyTotalTokens: 1285,
      ),
      segments: const [
        StoredSegment(sessionId: 'session-1', order: 0, text: 'Hello world'),
      ],
    );

    LiveSessionState doneState({bool agentSending = false, String agentError = ''}) =>
        LiveSessionState(
          phase: LiveSessionPhase.done,
          sessionId: 'session-1',
          durationSeconds: 65,
          realtimeBilledSeconds: 61,
          realtimeActualCost: 0.011,
          turns: const [TranscriptTurn(text: 'Hello world', isProvisional: false)],
          agentSending: agentSending,
          agentError: agentError,
        );

    LiveSessionState passOfferedState() => LiveSessionState(
          phase: LiveSessionPhase.passOffered,
          sessionId: 'session-1',
          durationSeconds: 65,
          realtimeBilledSeconds: 61,
          realtimeActualCost: 0.011,
          passEstimatedCost: 0.012,
          turns: const [TranscriptTurn(text: 'Hello world')],
        );

    /// Pumps the home screen in a post-session phase, with the in-memory
    /// repository holding the saved record and the selected agent configured.
    Future<FakeLiveSessionController> pumpCard(
      WidgetTester tester,
      LiveSessionState state, {
      String? agentId = 'ag_1',
      FakeLiveSessionController? controller,
    }) async {
      exportCalls.clear();
      final repository = InMemorySessionRepository()..add(savedRecord.session, savedRecord.segments);
      final preferences = InMemoryPreferencesRepository()
        ..stored = StoredPreferences(agentId: agentId);
      final sessionController = controller ?? FakeLiveSessionController(state);
      await tester.pumpWidget(appWithStore(
        FakeApiKeyStore(),
        sessionController: sessionController,
        sessionRepository: repository,
        preferencesRepository: preferences,
        transcriptExport: (record, _, {required markdown}) async {
          exportCalls.add((record: record, markdown: markdown));
        },
      ));
      await tester.pump();
      await tester.pump();
      return sessionController;
    }

    testWidgets('done: the card shows Session saved with Share and Send to '
        'agent, Send primary when an agent is selected', (tester) async {
      await pumpCard(tester, doneState());

      expect(find.text('Session saved'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Send to agent'), findsOneWidget);
      // Send to agent is the filled primary action; Share is secondary.
      expect(
        find.ancestor(of: find.text('Send to agent'), matching: find.byType(FilledButton)),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: find.text('Share'), matching: find.byType(TextButton)),
        findsOneWidget,
      );
      // No pass offer remains in done.
      expect(find.text('Add speaker labels'), findsNothing);
    });

    testWidgets('done without a selected agent: Share is primary and Send is '
        'secondary', (tester) async {
      await pumpCard(tester, doneState(), agentId: null);

      expect(
        find.ancestor(of: find.text('Share'), matching: find.byType(FilledButton)),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: find.text('Send to agent'), matching: find.byType(TextButton)),
        findsOneWidget,
      );
    });

    testWidgets('passOffered: the pass offer stays primary (Run/Skip) with '
        'Share and Send to agent as secondary text buttons', (tester) async {
      await pumpCard(tester, passOfferedState());

      expect(find.text('Add speaker labels'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('Run'), matching: find.byType(FilledButton)),
        findsOneWidget,
      );
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Send to agent'), findsOneWidget);
      // Both actions are secondary text buttons.
      expect(
        find.ancestor(of: find.text('Share'), matching: find.byType(TextButton)),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: find.text('Send to agent'), matching: find.byType(TextButton)),
        findsOneWidget,
      );
    });

    testWidgets('absent while a session is active or paused', (tester) async {
      await pumpCard(tester, activeState());

      expect(find.text('Session saved'), findsNothing);
      expect(find.text('Share'), findsNothing);
      expect(find.text('Send to agent'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await pumpCard(tester, const LiveSessionState(phase: LiveSessionPhase.paused));

      expect(find.text('Session saved'), findsNothing);
      expect(find.text('Share'), findsNothing);
      expect(find.text('Send to agent'), findsNothing);
    });

    testWidgets('send asks for confirmation and calls the controller',
        (tester) async {
      final controller = await pumpCard(tester, doneState());

      await tester.tap(find.text('Send to agent'));
      await tester.pumpAndSettle();
      expect(find.text('Send to agent?'), findsOneWidget);

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(controller.calls, ['sendToAgent']);
    });

    testWidgets('send with no agent selected shows the Settings snackbar and '
        'does not send', (tester) async {
      final controller = await pumpCard(tester, doneState(), agentId: null);

      await tester.tap(find.text('Send to agent'));
      await tester.pumpAndSettle();

      expect(find.text('Select an agent in Settings first.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.calls, isEmpty);
    });

    testWidgets('share opens the shared export sheet for the saved record',
        (tester) async {
      await pumpCard(tester, doneState());

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(find.text('Plain text'), findsOneWidget);
      expect(find.text('Markdown'), findsOneWidget);

      await tester.tap(find.text('Markdown'));
      await tester.pumpAndSettle();

      expect(exportCalls, hasLength(1));
      expect(exportCalls.single.markdown, isTrue);
      expect(exportCalls.single.record.session.id, 'session-1');
    });

    testWidgets('a send in flight shows a spinner and disables the send '
        'action', (tester) async {
      await pumpCard(tester, doneState(agentSending: true));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final sendButton =
          tester.widget<FilledButton>(find.byKey(const Key('sendToAgentAction')));
      expect(sendButton.onPressed, isNull);
    });

    testWidgets('an agent failure shows the shared error banner whose retry '
        're-sends', (tester) async {
      final controller = await pumpCard(
        tester,
        doneState(agentError: 'quota exceeded'),
      );

      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.text('quota exceeded'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(controller.calls, ['sendToAgent']);
    });

    testWidgets('a successful send opens the saved transcript in History '
        'with the reply visible', (tester) async {
      final controller = await pumpCard(tester, doneState());

      await tester.tap(find.text('Send to agent'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(controller.calls, ['sendToAgent']);
      // The app navigated to the saved transcript's history detail view,
      // where the persisted reply card is shown.
      expect(find.byType(HistoryDetailScreen), findsOneWidget);
      expect(find.text('Agent reply'), findsOneWidget);
      expect(find.text('Three action items.'), findsOneWidget);
    });

    testWidgets('a failed send stays on the live screen with the error '
        'banner', (tester) async {
      final controller = FakeLiveSessionController(
        doneState(agentError: 'quota exceeded'),
      )..sendSucceeds = false;
      await pumpCard(
        tester,
        doneState(agentError: 'quota exceeded'),
        controller: controller,
      );

      await tester.tap(find.text('Send to agent'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(controller.calls, ['sendToAgent']);
      expect(find.byType(HistoryDetailScreen), findsNothing);
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.text('quota exceeded'), findsOneWidget);
    });
  });
}
