import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxgale/mistral/mistral.dart';
import 'package:voxgale/session/audio_focus_gateway.dart';
import 'package:voxgale/session/capture_service.dart';
import 'package:voxgale/session/live_session_controller.dart';
import 'package:voxgale/session/screen_wake_gateway.dart';
import 'package:voxgale/session/session_models.dart';
import 'package:voxgale/session/session_providers.dart';
import 'package:voxgale/storage/storage.dart';

class MockCaptureService extends Mock implements CaptureService {}

class MockForegroundTaskGateway extends Mock implements ForegroundTaskGateway {}

class MockSessionRepository extends Mock implements SessionRepository {}

class MockBatchTranscriptionClient extends Mock
    implements BatchTranscriptionClient {}

class FakeApiKeyStore implements ApiKeyStore {
  String? key;

  @override
  Future<String?> readKey() async => key;

  @override
  Future<void> saveKey(String newKey) async => key = newKey;

  @override
  Future<void> deleteKey() async => key = null;
}

class InMemoryPreferencesRepository implements PreferencesRepository {
  StoredPreferences stored = const StoredPreferences();

  @override
  Future<StoredPreferences> loadPreferences() async => stored;

  @override
  Future<void> savePreferences(StoredPreferences preferences) async {
    stored = preferences;
  }
}

/// Deterministic [SessionClock]: the test advances time and fires ticks.
class FakeSessionClock implements SessionClock {
  FakeSessionClock() : nowValue = DateTime(2026, 10, 23, 10, 0, 0);

  DateTime nowValue;
  // Sync: ticks are delivered to the controller's listener immediately.
  final StreamController<int> tickController =
      StreamController<int>.broadcast(sync: true);

  /// When true, [ticks] throws — simulates a start-path clock failure.
  bool throwOnTicks = false;

  @override
  DateTime now() => nowValue;

  @override
  Stream<int> ticks() {
    if (throwOnTicks) {
      throw StateError('clock failure (test)');
    }
    return tickController.stream;
  }

  void advance(Duration duration) => nowValue = nowValue.add(duration);

  void tick() => tickController.add(0);
}

/// A fake [AudioFocusGateway] (design P3-D2): records configuration and
/// release, and lets the test emit focus events.
class FakeAudioFocusGateway implements AudioFocusGateway {
  // Sync: focus events are delivered to the controller's listener
  // immediately.
  final StreamController<AudioFocusEvent> focusController =
      StreamController<AudioFocusEvent>.broadcast(sync: true);

  int configureCount = 0;
  int releaseCount = 0;

  @override
  Future<void> configureForRecord() async {
    configureCount++;
  }

  @override
  Stream<AudioFocusEvent> get focusEvents => focusController.stream;

  @override
  Future<void> release() async {
    releaseCount++;
  }

  void emit(AudioFocusEvent event) => focusController.add(event);

  Future<void> dispose() => focusController.close();
}

/// A fake [ScreenWakeGateway] (change
/// 2026-10-29-keep-screen-on-during-sessions): records the requested screen
/// wake lock states and can be told to throw, simulating a platform failure.
class FakeScreenWakeGateway implements ScreenWakeGateway {
  /// The requested states, in call order.
  final List<bool> calls = [];

  /// When true, [setScreenOn] throws — simulates a platform failure.
  bool throwOnSet = false;

  @override
  Future<void> setScreenOn(bool on) async {
    if (throwOnSet) {
      throw StateError('screen wake failure (test)');
    }
    calls.add(on);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(RealtimeSessionConfig());
    registerFallbackValue('');
    registerFallbackValue(
      StoredSession(
        id: 'fallback',
        startedAt: DateTime(2026, 1, 1),
        durationSeconds: 0,
        model: 'model',
        status: SessionStatus.provisional,
      ),
    );
    registerFallbackValue(<StoredSegment>[]);
    registerFallbackValue(0);
    registerFallbackValue(0.0);
    registerFallbackValue(
      BatchTranscriptionRequest(
        model: 'model',
        audioBytes: Uint8List(0),
        fileName: 'file.wav',
      ),
    );
  });

  late MockCaptureService captureService;
  late MockForegroundTaskGateway gateway;
  late MockSessionRepository repository;
  late MockBatchTranscriptionClient batchClient;
  late FakeApiKeyStore apiKeyStore;
  late FakeSessionClock clock;
  late FakeAudioFocusGateway audioFocus;
  late FakeScreenWakeGateway screenWake;
  late InMemoryPreferencesRepository preferences;
  late StreamController<SessionEvent> eventController;
  late ProviderContainer container;
  late Directory tempDir;

  /// Captured from the mocked capture service / repository.
  String? startedSessionId;
  RealtimeSessionConfig? startedConfig;
  StoredSession? savedSession;
  List<StoredSegment>? savedSegments;
  List<StoredSegment>? replacedSegments;
  int? replacedBilled;
  double? replacedCost;

  /// The mocked startSession's response — tests can replace it with a
  /// pending future to hold the session in the starting phase.
  Future<CaptureStartFailure?> Function() startSessionAnswer =
      () async => null;

  LiveSessionState state() => container.read(liveSessionControllerProvider);

  LiveSessionController controller() =>
      container.read(liveSessionControllerProvider.notifier);

  /// Lets the event loop run until [condition] holds (with a timeout).
  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue);
  }

  void stubServiceStart({bool batteryIgnored = true}) {
    when(() => captureService.events)
        .thenAnswer((_) => eventController.stream);
    when(() => captureService.isBatteryOptimizationIgnored())
        .thenAnswer((_) async => batteryIgnored);
    when(
      () => captureService.startSession(
        sessionId: any(named: 'sessionId'),
        config: any(named: 'config'),
      ),
    ).thenAnswer((invocation) async {
      startedSessionId = invocation.namedArguments[#sessionId] as String;
      startedConfig = invocation.namedArguments[#config] as RealtimeSessionConfig;
      return startSessionAnswer();
    });
    when(() => captureService.stop()).thenAnswer((_) async {});
    when(() => captureService.openBatteryOptimizationSettings())
        .thenAnswer((_) async => true);
  }

  void stubSaveSession() {
    when(() => repository.saveSession(any(), any())).thenAnswer(
      (invocation) async {
        savedSession = invocation.positionalArguments[0] as StoredSession;
        savedSegments =
            invocation.positionalArguments[1] as List<StoredSegment>;
      },
    );
  }

  void stubReplaceTranscript() {
    when(
      () => repository.replaceTranscript(
        any(),
        any(),
        billedAudioSeconds: any(named: 'billedAudioSeconds'),
        actualCost: any(named: 'actualCost'),
      ),
    ).thenAnswer((invocation) async {
      replacedSegments =
          invocation.positionalArguments[1] as List<StoredSegment>;
      replacedBilled = invocation.namedArguments[#billedAudioSeconds] as int;
      replacedCost = invocation.namedArguments[#actualCost] as double;
    });
  }

  /// Writes a session WAV with [dataBytes] of audio data and returns its path.
  Future<String> writeSessionAudio(int dataBytes) async {
    final file = File('${tempDir.path}/session-audio.wav');
    // The 44-byte header [WavFileWriter] writes, then zeroed audio data.
    await file.writeAsBytes(List<int>.filled(44 + dataBytes, 0));
    return file.path;
  }

  /// Starts a session and brings it to [LiveSessionPhase.active].
  Future<void> startActiveSession({bool batteryIgnored = true}) async {
    stubServiceStart(batteryIgnored: batteryIgnored);
    stubSaveSession();
    await controller().start();
    expect(state().phase, LiveSessionPhase.active);
  }

  /// Stops the active session, forwarding the final session-ended event for
  /// a 30 s recording, and waits until the pass is offered.
  Future<String> finalizeToPassOffered({
    List<TranscriptSegment> segments = const [
      TranscriptSegment(text: 'Hello world'),
    ],
    String fullText = 'Hello world',
    int billedAudioSeconds = 61,
    int elapsedSeconds = 65,
    int audioDataBytes = 32000 * 30,
  }) async {
    eventController.add(const SessionTextDelta('Hello world'));
    clock.advance(Duration(seconds: elapsedSeconds));
    final audioPath = await writeSessionAudio(audioDataBytes);
    final stopFuture = controller().stop();
    eventController.add(
      SessionEnded(
        sessionId: startedSessionId!,
        audioPath: audioPath,
        fullText: fullText,
        segments: segments,
        language: 'en',
        model: 'voxtral-mini-transcribe-realtime-3-0',
        usage: Usage(promptAudioSeconds: billedAudioSeconds),
      ),
    );
    await stopFuture;
    await waitFor(() => state().phase == LiveSessionPhase.passOffered);
    return audioPath;
  }

  void stubBatchSuccess() {
    when(() => batchClient.transcribe(any())).thenAnswer(
      (_) async => const BatchTranscriptionResult(
        text: 'Hello world',
        segments: [
          TranscriptSegment(
            text: 'Hello ',
            speakerId: 'speaker_1',
            start: 0,
            end: 1.5,
          ),
          TranscriptSegment(
            text: 'world',
            speakerId: 'speaker_2',
            start: 1.5,
            end: 2.5,
          ),
        ],
        language: 'en',
        model: 'voxtral-mini-transcribe-3-0',
        usage: Usage(promptAudioSeconds: 30),
      ),
    );
    stubReplaceTranscript();
  }

  setUp(() async {
    captureService = MockCaptureService();
    gateway = MockForegroundTaskGateway();
    repository = MockSessionRepository();
    batchClient = MockBatchTranscriptionClient();
    apiKeyStore = FakeApiKeyStore()..key = 'test-key';
    clock = FakeSessionClock();
    audioFocus = FakeAudioFocusGateway();
    screenWake = FakeScreenWakeGateway();
    preferences = InMemoryPreferencesRepository();
    startSessionAnswer = () async => null;
    // Sync: events are delivered to the controller's listener immediately.
    eventController = StreamController<SessionEvent>.broadcast(sync: true);
    tempDir = await Directory.systemTemp.createTemp('voxtral_controller_test');
    container = ProviderContainer(
      overrides: [
        captureServiceProvider.overrideWith((ref) => captureService),
        sessionRepositoryProvider.overrideWith((ref) => repository),
        // The diarization pass provider resolves the default batch model
        // through the preferences chain (design P2-D7) — keep it in memory.
        preferencesRepositoryProvider.overrideWith((ref) => preferences),
        mistralConfigProvider.overrideWith((ref) => MistralConfig.defaults),
        apiKeyStoreProvider.overrideWith((ref) => apiKeyStore),
        batchTranscriptionClientProvider.overrideWith((ref) async => batchClient),
        sessionClockProvider.overrideWith((ref) => clock),
        foregroundTaskGatewayProvider.overrideWith((ref) => gateway),
        audioFocusGatewayProvider.overrideWith((ref) => audioFocus),
        screenWakeGatewayProvider.overrideWith((ref) => screenWake),
        sessionFinalizeTimeoutProvider.overrideWith(
          (ref) => const Duration(milliseconds: 100),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await eventController.close();
    await audioFocus.dispose();
    await tempDir.delete(recursive: true);
  });

  group('LiveSessionState', () {
    test('has value equality', () {
      const a = LiveSessionState(
        phase: LiveSessionPhase.active,
        turns: [TranscriptTurn(text: 'hi')],
      );
      const b = LiveSessionState(
        phase: LiveSessionPhase.active,
        turns: [TranscriptTurn(text: 'hi')],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const LiveSessionState()));
    });
  });

  group('start (4.1)', () {
    test('fails with the no-key error state when no API key is saved',
        () async {
      apiKeyStore.key = null;
      stubServiceStart();

      await controller().start();

      expect(state().phase, LiveSessionPhase.error);
      expect(state().missingApiKey, isTrue);
      expect(state().hasError, isTrue);
      verifyNever(
        () => captureService.startSession(
          sessionId: any(named: 'sessionId'),
          config: any(named: 'config'),
        ),
      );
    });

    test('runs the state machine idle → starting → active, starts the '
        'service with turn detection, and carries the battery-prompt flag',
        () async {
      stubServiceStart(batteryIgnored: false);
      stubSaveSession();
      // A pending service start holds the session in the starting phase.
      final startCompleter = Completer<CaptureStartFailure?>();
      startSessionAnswer = () => startCompleter.future;

      final startFuture = controller().start();
      await waitFor(() => state().phase == LiveSessionPhase.starting);
      expect(state().batteryPromptNeeded, isTrue);
      expect(state().sessionId, isNotNull);

      startCompleter.complete(null);
      await startFuture;

      expect(state().phase, LiveSessionPhase.active);
      expect(state().sessionId, startedSessionId);
      // The v1 default: turn detection live, the post-session pass for
      // speaker attribution.
      expect(startedConfig, isNotNull);
      expect(startedConfig!.turnDetection, isNotNull);
      expect(startedConfig!.diarize, isFalse);
    });

    test('live diarization is a start option', () async {
      stubServiceStart();
      stubSaveSession();

      await controller().start(diarize: true, language: 'en');

      expect(startedConfig!.diarize, isTrue);
      expect(startedConfig!.turnDetection, isNull);
      expect(startedConfig!.language, 'en');
    });

    test('does not start while a session is in flight', () async {
      stubServiceStart();
      stubSaveSession();

      await controller().start();
      await controller().start();

      verify(
        () => captureService.startSession(
          sessionId: any(named: 'sessionId'),
          config: any(named: 'config'),
        ),
      ).called(1);
    });

    test('surfaces an unexpected start-path failure as an error state '
        '(regression: the session must not hang in starting)', () async {
      // A clock whose ticks() throws (as Stream.periodic without a
      // computation callback did on Dart 3.13) must surface as an error
      // state, not an unhandled exception with the spinner stuck.
      clock.throwOnTicks = true;
      stubServiceStart();

      await controller().start();

      expect(state().phase, LiveSessionPhase.error);
      expect(state().hasError, isTrue);
      verifyNever(
        () => captureService.startSession(
          sessionId: any(named: 'sessionId'),
          config: any(named: 'config'),
        ),
      );
    });

    test('fails when the capture service does not start', () async {
      stubServiceStart();
      startSessionAnswer = () async => const MicPermissionDenied();

      await controller().start();

      expect(state().phase, LiveSessionPhase.error);
      expect(state().error, contains('Microphone permission'));
    });

    test('a service error while starting fails the session', () async {
      stubServiceStart();
      final startCompleter = Completer<CaptureStartFailure?>();
      startSessionAnswer = () => startCompleter.future;

      final startFuture = controller().start();
      await waitFor(() => state().phase == LiveSessionPhase.starting);
      eventController.add(const SessionError('No API key saved'));
      await waitFor(() => state().phase == LiveSessionPhase.error);
      startCompleter.complete(null);
      await startFuture;

      expect(state().phase, LiveSessionPhase.error);
      expect(state().error, 'No API key saved');
    });

    test('ticks advance the elapsed time and the live cost estimate',
        () async {
      stubServiceStart();
      stubSaveSession();
      await controller().start();

      clock.advance(const Duration(seconds: 65));
      clock.tick();

      expect(state().elapsedSeconds, 65);
      // 65 s / 60 × 0.008 USD/min.
      expect(state().estimatedCost, closeTo(65 / 60 * 0.008, 1e-12));
    });

    test('openBatterySettings delegates to the capture service', () async {
      stubServiceStart(batteryIgnored: false);
      stubSaveSession();
      await controller().start();

      await controller().openBatterySettings();

      verify(() => captureService.openBatteryOptimizationSettings())
          .called(1);
    });

    test('requestMicPermission re-requests the record permission through '
        'the foreground-task gateway (Phase 3 group 2)', () async {
      when(() => gateway.requestRecordAudioPermission())
          .thenAnswer((_) async => true);

      expect(await controller().requestMicPermission(), isTrue);

      verify(() => gateway.requestRecordAudioPermission()).called(1);
    });
  });

  group('key presence tracking (v1.1: dogfood friction — stale message)', () {
    test('shows the missing-key state while no key is saved, without a '
        'start attempt', () async {
      apiKeyStore.key = null;
      controller();

      await waitFor(() =>
          state().phase == LiveSessionPhase.error && state().missingApiKey);

      expect(state().error, contains('No API key saved'));
    });

    test('dismisses the missing-key state as soon as a key is saved '
        '(no restart)', () async {
      apiKeyStore.key = null;
      controller();
      await waitFor(() => state().missingApiKey);

      // The settings controller invalidates apiKeyProvider after a save;
      // the presence provider re-computes and the listener dismisses.
      await apiKeyStore.saveKey('test-key');
      container.invalidate(apiKeyProvider);

      await waitFor(() =>
          state().phase == LiveSessionPhase.idle && !state().missingApiKey);
      expect(state().hasError, isFalse);
    });

    test('shows the missing-key state again when the key is removed '
        '(no restart)', () async {
      controller();
      await waitFor(() => state().phase == LiveSessionPhase.idle);

      await apiKeyStore.deleteKey();
      container.invalidate(apiKeyProvider);

      await waitFor(() => state().missingApiKey);
      expect(state().phase, LiveSessionPhase.error);
      expect(state().error, contains('No API key saved'));
    });

    test('ignores presence changes while a session runs', () async {
      await startActiveSession();

      await apiKeyStore.deleteKey();
      container.invalidate(apiKeyProvider);
      await waitFor(() => container.read(apiKeyPresentProvider).value == false);
      // Let the controller's listener run — it must ignore the change.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(state().phase, LiveSessionPhase.active);
      expect(state().missingApiKey, isFalse);
    });
  });

  group('battery exemption re-check (v1.1: dogfood friction — stale banner)',
      () {
    test('dismisses the prompt once the app is exempt', () async {
      stubServiceStart(batteryIgnored: false);
      stubSaveSession();
      await controller().start();
      expect(state().batteryPromptNeeded, isTrue);

      when(() => captureService.isBatteryOptimizationIgnored())
          .thenAnswer((_) async => true);

      await controller().recheckBatteryExemption();

      expect(state().batteryPromptNeeded, isFalse);
    });

    test('keeps the prompt while the app is not exempt (session context)',
        () async {
      stubServiceStart(batteryIgnored: false);
      stubSaveSession();
      await controller().start();
      expect(state().batteryPromptNeeded, isTrue);

      await controller().recheckBatteryExemption();

      expect(state().batteryPromptNeeded, isTrue);
    });

    test('does not query the platform without a session context', () async {
      controller();
      await waitFor(() => state().phase == LiveSessionPhase.idle);

      await controller().recheckBatteryExemption();

      verifyNever(() => captureService.isBatteryOptimizationIgnored());
      expect(state().batteryPromptNeeded, isFalse);
    });
  });

  group('turn grouping (4.1)', () {
    test('groups text deltas into turns and closes blocks on turn '
        'boundaries (turn-detection mode)', () async {
      await startActiveSession();

      eventController.add(const SessionTurnStarted(0));
      eventController.add(const SessionTextDelta('Hello '));
      eventController.add(const SessionTextDelta('world'));
      eventController.add(
        const SessionTurnEnded(timeS: 2, endReason: 'threshold'),
      );
      eventController.add(const SessionTurnStarted(3));
      eventController.add(const SessionTextDelta('Again'));

      expect(state().turns, [
        const TranscriptTurn(text: 'Hello world'),
        const TranscriptTurn(text: 'Again'),
      ]);
    });

    test('a speaker change starts a new block (diarize mode)', () async {
      await startActiveSession();

      eventController.add(
        const SessionSpeakerSegment(text: 'Hi ', speakerId: 'speaker_1'),
      );
      eventController.add(
        const SessionSpeakerSegment(text: 'there', speakerId: 'speaker_1'),
      );
      eventController.add(
        const SessionSpeakerSegment(text: 'Hey', speakerId: 'speaker_2'),
      );

      expect(state().turns, [
        const TranscriptTurn(speakerLabel: 'speaker_1', text: 'Hi there'),
        const TranscriptTurn(speakerLabel: 'speaker_2', text: 'Hey'),
      ]);
    });

    test('an empty trailing turn is dropped at a turn boundary', () async {
      await startActiveSession();

      eventController.add(const SessionTextDelta('Hello '));
      eventController.add(const SessionTurnStarted(1));
      // No text for this turn — the boundary drops it.
      eventController.add(
        const SessionTurnEnded(timeS: 2, endReason: 'timeout'),
      );

      expect(state().turns, [const TranscriptTurn(text: 'Hello ')]);
    });
  });

  group('connection status (4.1)', () {
    test('carries the last reconnect/replay/dropped info', () async {
      await startActiveSession();

      eventController.add(
        const SessionReconnected(dropReason: 'close code 1006'),
      );
      eventController.add(const SessionBufferedAudioReplayed(12));
      eventController.add(const SessionBufferedAudioDropped(5));

      expect(state().connection.reconnectCount, 1);
      expect(state().connection.lastDropReason, 'close code 1006');
      expect(state().connection.lastReplayedSeconds, 12);
      expect(state().connection.lastDroppedSeconds, 5);
      expect(state().connection.hadInterruption, isTrue);
    });

    test('a transient error while running is a warning; a reconnect clears '
        'it', () async {
      await startActiveSession();

      eventController.add(const SessionError('Connection lost'));
      await waitFor(() => state().hasError);
      expect(state().phase, LiveSessionPhase.active);
      expect(state().error, 'Connection lost');

      eventController.add(const SessionReconnected());
      expect(state().error, isEmpty);
      expect(state().connection.reconnectCount, 1);
    });

    test('the actual usage is carried from transcription.done', () async {
      await startActiveSession();

      eventController.add(
        const SessionTranscriptionDone(
          fullText: 'Hello world',
          segments: [TranscriptSegment(text: 'Hello world')],
          language: 'en',
          model: 'voxtral-mini-transcribe-realtime-3-0',
          usage: Usage(promptAudioSeconds: 61),
        ),
      );

      expect(state().realtimeBilledSeconds, 61);
      expect(state().realtimeActualCost, closeTo(61 / 60 * 0.008, 1e-12));
      expect(state().model, 'voxtral-mini-transcribe-realtime-3-0');
      expect(state().language, 'en');
    });
  });

  group('pause/resume (4.2)', () {
    test('pauses and resumes, and produces no transcript text while paused',
        () async {
      await startActiveSession();
      eventController.add(const SessionTextDelta('Hello '));

      await controller().pause();
      expect(state().phase, LiveSessionPhase.paused);
      verify(() => captureService.pause()).called(1);

      // While paused, no transcript text is produced — even if the service
      // were to forward a stray delta or segment.
      eventController.add(const SessionTextDelta('ignored'));
      eventController.add(
        const SessionSpeakerSegment(text: 'ignored', speakerId: 'speaker_1'),
      );
      expect(state().turns, [const TranscriptTurn(text: 'Hello ')]);

      // The pause is silence: it closes the current turn (a turn boundary).
      eventController.add(
        const SessionTurnEnded(timeS: 5, endReason: 'timeout'),
      );

      await controller().resume();
      expect(state().phase, LiveSessionPhase.active);
      verify(() => captureService.resume()).called(1);

      // The transcript continues in the same conversation (a new block).
      eventController.add(const SessionTextDelta('world'));
      expect(state().turns, [
        const TranscriptTurn(text: 'Hello '),
        const TranscriptTurn(text: 'world'),
      ]);
    });

    test('pause/resume are no-ops outside their phases', () async {
      await startActiveSession();

      await controller().resume(); // not paused — no-op
      verifyNever(() => captureService.resume());
      expect(state().phase, LiveSessionPhase.active);

      await controller().pause();
      await controller().pause(); // already paused — no-op
      verify(() => captureService.pause()).called(1);
    });
  });

  group('pause freezes the session clock (PS-D2)', () {
    test('the elapsed time and estimate freeze while paused and resume '
        'from the frozen value', () async {
      await startActiveSession();

      clock.advance(const Duration(seconds: 5));
      clock.tick();
      expect(state().elapsedSeconds, 5);
      final estimateAtPause = state().estimatedCost;
      expect(estimateAtPause, greaterThan(0));

      await controller().pause();
      clock.advance(const Duration(seconds: 10));
      clock.tick();
      // The clock does not advance while paused — and neither does the
      // estimate (nothing is sent or billed while paused).
      expect(state().elapsedSeconds, 5);
      expect(state().estimatedCost, estimateAtPause);

      await controller().resume();
      clock.advance(const Duration(seconds: 3));
      clock.tick();
      expect(state().elapsedSeconds, 8);
      expect(state().estimatedCost, greaterThan(estimateAtPause));
    });

    test('the finalized duration excludes the paused time', () async {
      await startActiveSession();

      clock.advance(const Duration(seconds: 5));
      clock.tick();
      await controller().pause();
      clock.advance(const Duration(seconds: 10));
      await controller().resume();
      clock.advance(const Duration(seconds: 3));
      clock.tick();

      // Stop: the final session-ended event finalizes the session with the
      // active capture time (5 s + 3 s; the 10 s pause is excluded).
      final audioPath = await writeSessionAudio(32000 * 8);
      final stopFuture = controller().stop();
      eventController.add(
        SessionEnded(
          sessionId: startedSessionId!,
          audioPath: audioPath,
          fullText: 'Hello',
          segments: const [TranscriptSegment(text: 'Hello')],
          language: 'en',
          model: 'voxtral-mini-transcribe-realtime-3-0',
          usage: const Usage(promptAudioSeconds: 8),
        ),
      );
      await stopFuture;
      await waitFor(() => state().phase == LiveSessionPhase.passOffered);
      expect(state().durationSeconds, 8);
    });
  });

  group('audio focus (3.2)', () {
    test('focus loss pauses the session through the existing pause path and '
        'keeps the session open; focus gain resumes into the same '
        'transcript', () async {
      await startActiveSession();
      eventController.add(const SessionTextDelta('Hello '));

      audioFocus.emit(AudioFocusEvent.lost);
      await waitFor(() => state().phase == LiveSessionPhase.paused);

      // The existing pause path: the capture service pauses, the phase
      // becomes paused, and the session (and its transcript) stays open.
      verify(() => captureService.pause()).called(1);
      expect(state().pausedByAudioFocus, isTrue);
      expect(state().sessionId, startedSessionId);
      expect(state().turns, [const TranscriptTurn(text: 'Hello ')]);

      audioFocus.emit(AudioFocusEvent.gained);
      await waitFor(() => state().phase == LiveSessionPhase.active);

      verify(() => captureService.resume()).called(1);
      expect(state().pausedByAudioFocus, isFalse);
      expect(state().sessionId, startedSessionId);

      // The transcript continues in the same session.
      eventController.add(const SessionTextDelta('world'));
      expect(state().turns, [const TranscriptTurn(text: 'Hello world')]);
    });

    test('a user-paused session stays paused across a focus loss and gain',
        () async {
      await startActiveSession();
      await controller().pause();

      // The focus loss does not pause again (the session is already
      // paused) and does not claim the pause.
      audioFocus.emit(AudioFocusEvent.lost);
      await Future<void>.delayed(Duration.zero);
      expect(state().phase, LiveSessionPhase.paused);
      expect(state().pausedByAudioFocus, isFalse);

      // The focus return does not resume a user pause.
      audioFocus.emit(AudioFocusEvent.gained);
      await Future<void>.delayed(Duration.zero);
      expect(state().phase, LiveSessionPhase.paused);

      // Exactly one pause command (the user's) and no resume command.
      verify(() => captureService.pause()).called(1);
      verifyNever(() => captureService.resume());
    });

    test('a manual resume while focus-paused clears the audio-focus flag, '
        'and the focus return is then a no-op', () async {
      await startActiveSession();
      audioFocus.emit(AudioFocusEvent.lost);
      await waitFor(() => state().phase == LiveSessionPhase.paused);
      expect(state().pausedByAudioFocus, isTrue);

      // The user resumes before focus returns.
      await controller().resume();
      expect(state().phase, LiveSessionPhase.active);
      expect(state().pausedByAudioFocus, isFalse);

      audioFocus.emit(AudioFocusEvent.gained);
      await Future<void>.delayed(Duration.zero);
      verify(() => captureService.resume()).called(1);
      expect(state().phase, LiveSessionPhase.active);
    });

    test('configures the audio session for record at start and releases it '
        'when the session ends', () async {
      await startActiveSession();
      expect(audioFocus.configureCount, 1);
      expect(audioFocus.releaseCount, 0);

      await finalizeToPassOffered();

      expect(audioFocus.releaseCount, 1);
    });

    test('no focus events means no pause/resume commands', () async {
      await startActiveSession();

      clock.tick();

      expect(state().phase, LiveSessionPhase.active);
      verifyNever(() => captureService.pause());
      verifyNever(() => captureService.resume());
    });

    test('focus events are ignored when no session is active', () async {
      audioFocus.emit(AudioFocusEvent.lost);
      audioFocus.emit(AudioFocusEvent.gained);
      await Future<void>.delayed(Duration.zero);

      expect(state().phase, LiveSessionPhase.idle);
      verifyNever(() => captureService.pause());
      verifyNever(() => captureService.resume());
    });

    test('disposing the controller cancels the focus subscription and '
        'releases the audio session', () async {
      await startActiveSession();
      expect(audioFocus.configureCount, 1);
      expect(audioFocus.releaseCount, 0);

      // Disposing the container disposes the controller (Riverpod's
      // dispose is a no-op on the second call in tearDown).
      container.dispose();

      expect(audioFocus.releaseCount, 1);
      // The subscription is cancelled: focus events no longer reach the
      // controller.
      audioFocus.emit(AudioFocusEvent.lost);
      await Future<void>.delayed(Duration.zero);
      verifyNever(() => captureService.pause());
    });
  });

  group('finalization (4.4)', () {
    test('a graceful stop saves the session + segments + audio path and '
        'offers the pass with its estimated cost', () async {
      await startActiveSession();
      final audioPath = await finalizeToPassOffered();

      // The saved record: text, labels, timestamps, duration, date, and the
      // billed usage (realtime segments carry no timestamps and, in turn
      // detection mode, no speaker labels — nulls where absent).
      expect(
        savedSession,
        StoredSession(
          id: startedSessionId!,
          startedAt: DateTime(2026, 10, 23, 10, 0, 0),
          durationSeconds: 65,
          model: 'voxtral-mini-transcribe-realtime-3-0',
          status: SessionStatus.provisional,
          billedAudioSeconds: 61,
          actualCost: 61 / 60 * 0.008,
          language: 'en',
          audioPath: audioPath,
        ),
      );
      expect(savedSegments, [
        StoredSegment(
          sessionId: startedSessionId!,
          order: 0,
          text: 'Hello world',
          speakerLabel: null,
          startSeconds: null,
          endSeconds: null,
        ),
      ]);
      // The offer: 30 s of audio × the batch Mini rate.
      expect(state().phase, LiveSessionPhase.passOffered);
      expect(state().passEstimatedCost, closeTo(30 / 60 * 0.0035, 1e-12));
      expect(state().durationSeconds, 65);
      expect(state().realtimeBilledSeconds, 61);
      expect(state().realtimeActualCost, closeTo(61 / 60 * 0.008, 1e-12));
      expect(state().model, 'voxtral-mini-transcribe-realtime-3-0');
      expect(state().language, 'en');
      // The provisional transcript is kept until the pass replaces it.
      expect(state().turns, [const TranscriptTurn(text: 'Hello world')]);
    });

    test('persists speaker labels from a diarize-mode session', () async {
      await startActiveSession();
      await finalizeToPassOffered(
        segments: const [
          TranscriptSegment(text: 'Hi ', speakerId: 'speaker_1'),
          TranscriptSegment(text: 'Hey', speakerId: 'speaker_2'),
        ],
      );

      expect(savedSegments, [
        StoredSegment(
          sessionId: startedSessionId!,
          order: 0,
          text: 'Hi ',
          speakerLabel: 'speaker_1',
          startSeconds: null,
          endSeconds: null,
        ),
        StoredSegment(
          sessionId: startedSessionId!,
          order: 1,
          text: 'Hey',
          speakerLabel: 'speaker_2',
          startSeconds: null,
          endSeconds: null,
        ),
      ]);
    });

    test('falls back to the full text when the API reported no segments',
        () async {
      await startActiveSession();
      await finalizeToPassOffered(segments: const []);

      expect(savedSegments, [
        StoredSegment(
          sessionId: startedSessionId!,
          order: 0,
          text: 'Hello world',
        ),
      ]);
    });

    test('fails the session when the service stops without the final event',
        () async {
      await startActiveSession();

      await controller().stop(); // no session-ended event arrives

      expect(state().phase, LiveSessionPhase.error);
      expect(state().hasError, isTrue);
      verifyNever(() => repository.saveSession(any(), any()));
    });

    test('finalizes when the notification stop button ends the session '
        'without the UI calling stop', () async {
      await startActiveSession();
      eventController.add(const SessionTextDelta('Hi'));
      final audioPath = await writeSessionAudio(32000 * 30);

      eventController.add(
        SessionEnded(
          sessionId: startedSessionId!,
          audioPath: audioPath,
          fullText: 'Hi',
          segments: const [TranscriptSegment(text: 'Hi')],
          language: 'en',
          model: 'voxtral-mini-transcribe-realtime-3-0',
          usage: const Usage(promptAudioSeconds: 30),
        ),
      );

      await waitFor(() => state().phase == LiveSessionPhase.passOffered);
      expect(savedSession, isNotNull);
      expect(savedSession!.audioPath, audioPath);
    });
  });

  group('diarization pass (4.3)', () {
    test('running the pass replaces the provisional transcript with the '
        'labelled segments, persists it, and deletes the audio', () async {
      await startActiveSession();
      final audioPath = await finalizeToPassOffered();
      stubBatchSuccess();

      await controller().runDiarizationPass();

      expect(state().phase, LiveSessionPhase.done);
      expect(state().turns, [
        const TranscriptTurn(
          speakerLabel: 'speaker_1',
          text: 'Hello ',
          isProvisional: false,
        ),
        const TranscriptTurn(
          speakerLabel: 'speaker_2',
          text: 'world',
          isProvisional: false,
        ),
      ]);
      expect(state().passBilledSeconds, 30);
      expect(state().passActualCost, closeTo(30 / 60 * 0.0035, 1e-12));
      expect(state().hasError, isFalse);
      // The transcript is persisted (the session marked final with the
      // pass's billed totals) and the audio is deleted.
      expect(replacedSegments, [
        StoredSegment(
          sessionId: startedSessionId!,
          order: 0,
          text: 'Hello ',
          speakerLabel: 'speaker_1',
          startSeconds: 0,
          endSeconds: 1.5,
        ),
        StoredSegment(
          sessionId: startedSessionId!,
          order: 1,
          text: 'world',
          speakerLabel: 'speaker_2',
          startSeconds: 1.5,
          endSeconds: 2.5,
        ),
      ]);
      expect(replacedBilled, 30);
      expect(replacedCost, closeTo(30 / 60 * 0.0035, 1e-12));
      expect(await File(audioPath).exists(), isFalse);
    });

    test('a failed pass preserves the provisional transcript with an error '
        'state, keeps the audio, and a retry succeeds', () async {
      await startActiveSession();
      final audioPath = await finalizeToPassOffered();
      when(() => batchClient.transcribe(any()))
          .thenThrow(MistralApiException('quota exceeded'));

      await controller().runDiarizationPass();

      expect(state().phase, LiveSessionPhase.passFailed);
      expect(state().error, 'quota exceeded');
      // The provisional transcript is preserved; the audio is kept.
      expect(state().turns, [const TranscriptTurn(text: 'Hello world')]);
      expect(await File(audioPath).exists(), isTrue);
      verifyNever(
        () => repository.replaceTranscript(
          any(),
          any(),
          billedAudioSeconds: any(named: 'billedAudioSeconds'),
          actualCost: any(named: 'actualCost'),
        ),
      );

      // The retry re-reads the saved audio and succeeds.
      stubBatchSuccess();
      await controller().runDiarizationPass();

      expect(state().phase, LiveSessionPhase.done);
      expect(state().turns, hasLength(2));
      expect(state().turns.every((turn) => !turn.isProvisional), isTrue);
      expect(await File(audioPath).exists(), isFalse);
    });

    test('skipping the pass keeps the provisional transcript and the audio, '
        'and sends no batch request', () async {
      await startActiveSession();
      final audioPath = await finalizeToPassOffered();

      await controller().skipDiarizationPass();

      expect(state().phase, LiveSessionPhase.done);
      verifyNever(() => batchClient.transcribe(any()));
      // The provisional transcript is the transcript of record; the audio is
      // kept so the pass can still be run later.
      expect(state().turns, [const TranscriptTurn(text: 'Hello world')]);
      expect(state().passBilledSeconds, isNull);
      expect(await File(audioPath).exists(), isTrue);
    });

    test('running the pass is a no-op unless it was offered or failed',
        () async {
      await startActiveSession();

      await controller().runDiarizationPass();

      expect(state().phase, LiveSessionPhase.active);
      verifyNever(() => batchClient.transcribe(any()));
    });

    test('a new session resets the state after a completed one', () async {
      await startActiveSession();
      final firstSessionId = startedSessionId;
      await finalizeToPassOffered();
      await controller().skipDiarizationPass();
      expect(state().phase, LiveSessionPhase.done);

      await controller().start();

      expect(state().phase, LiveSessionPhase.active);
      expect(state().turns, isEmpty);
      expect(state().error, isEmpty);
      expect(state().passEstimatedCost, isNull);
      expect(state().realtimeBilledSeconds, isNull);
      expect(state().sessionId, isNot(firstSessionId));
    });
  });

  group('history list invalidation (user report: stale empty history)', () {
    test('finalizing a session refreshes the history list provider', () async {
      // The list reflects the repository's saved sessions.
      final listed = <StoredSession>[];
      when(() => repository.listSessions(searchQuery: any(named: 'searchQuery')))
          .thenAnswer((_) async => List.of(listed));
      // The list provider is kept alive by a listener (as the history
      // screen would) and captures its data states.
      final states = <List<StoredSession>>[];
      final sub = container.listen(
        historyListProvider,
        (prev, next) => next.whenOrNull(data: (s) => states.add(s)),
      );
      addTearDown(sub.close);

      // Prime the list: the history is empty.
      await waitFor(() => states.isNotEmpty);
      expect(states.last, isEmpty);

      // A session runs and finalizes (saved to the repository).
      await startActiveSession();
      when(() => repository.saveSession(any(), any())).thenAnswer(
        (invocation) async {
          listed.add(invocation.positionalArguments[0] as StoredSession);
        },
      );
      await finalizeToPassOffered();

      // The save invalidated the provider: it re-ran and sees the session.
      await waitFor(() => states.any((s) => s.length == 1));
      expect(states.last.single.status, SessionStatus.provisional);
    });

    test('running the diarization pass refreshes the history list provider',
        () async {
      // The list reflects the repository's saved sessions.
      final listed = <StoredSession>[];
      when(() => repository.listSessions(searchQuery: any(named: 'searchQuery')))
          .thenAnswer((_) async => List.of(listed));
      // The list provider is kept alive by a listener (as the history
      // screen would) and captures its data states.
      final states = <List<StoredSession>>[];
      final sub = container.listen(
        historyListProvider,
        (prev, next) => next.whenOrNull(data: (s) => states.add(s)),
      );
      addTearDown(sub.close);
      await waitFor(() => states.isNotEmpty);

      await startActiveSession();
      when(() => repository.saveSession(any(), any())).thenAnswer(
        (invocation) async {
          listed.add(invocation.positionalArguments[0] as StoredSession);
        },
      );
      final audioPath = await finalizeToPassOffered();
      stubBatchSuccess();
      when(() => repository.replaceTranscript(
            any(),
            any(),
            billedAudioSeconds: any(named: 'billedAudioSeconds'),
            actualCost: any(named: 'actualCost'),
          )).thenAnswer((invocation) async {
        final session = listed.single;
        listed
          ..clear()
          ..add(StoredSession(
            id: session.id,
            startedAt: session.startedAt,
            durationSeconds: session.durationSeconds,
            model: session.model,
            status: SessionStatus.finalized,
            billedAudioSeconds:
                invocation.namedArguments[#billedAudioSeconds] as int,
            actualCost: invocation.namedArguments[#actualCost] as double,
            language: session.language,
            audioPath: session.audioPath,
            source: session.source,
            sourceFileName: session.sourceFileName,
          ));
      });

      await controller().runDiarizationPass();

      // The pass invalidated the provider: it re-ran and sees the final
      // session.
      await waitFor(
        () => states.any((s) => s.isNotEmpty && s.single.status == SessionStatus.finalized),
      );
      expect(states.last.single.status, SessionStatus.finalized);
      expect(await File(audioPath).exists(), isFalse);
    });
  });

  group('screen wake lock (2026-10-29-keep-screen-on-during-sessions)', () {
    test('is held while a session runs when the preference is on', () async {
      preferences.stored = const StoredPreferences(keepScreenOn: true);
      await startActiveSession();
      expect(screenWake.calls, [true]);
    });

    test('is not held when the preference is off (the default)', () async {
      await startActiveSession();
      expect(screenWake.calls, isEmpty);
    });

    test('is held through pause and resume', () async {
      preferences.stored = const StoredPreferences(keepScreenOn: true);
      await startActiveSession();
      await controller().pause();
      await controller().resume();
      expect(screenWake.calls, [true]);
    });

    test('is released when the session stops', () async {
      preferences.stored = const StoredPreferences(keepScreenOn: true);
      await startActiveSession();
      await finalizeToPassOffered();
      expect(screenWake.calls, [true, false]);
    });

    test('is not touched when the session fails to start', () async {
      preferences.stored = const StoredPreferences(keepScreenOn: true);
      startSessionAnswer = () async => MicPermissionDenied();
      stubServiceStart();
      await controller().start();
      expect(state().phase, LiveSessionPhase.error);
      expect(screenWake.calls, isEmpty);
    });

    test('a gateway failure never fails the session', () async {
      preferences.stored = const StoredPreferences(keepScreenOn: true);
      screenWake.throwOnSet = true;
      await startActiveSession();
      expect(state().phase, LiveSessionPhase.active);
      // The release in teardown is swallowed the same way.
      await finalizeToPassOffered();
      expect(state().phase, LiveSessionPhase.passOffered);
    });
  });
}
