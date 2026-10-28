// The live-flow integration test (design P3-D4, task 4.4 — test-coverage
// spec): drives [LiveSessionController] end to end over fakes — a fake
// capture service (no platform channels, no foreground service, no Mistral
// client), a mocktail-mocked batch client that is never called, the real
// [DriftSessionRepository] over the in-memory Drift database, a fake clock,
// and a fake audio-focus gateway. Start → the fake service emits realtime
// text deltas → stop → the finalized session, carrying the streamed
// transcript, appears in history. A second case fails the stream mid-session
// and asserts the text received so far is preserved with an error state.
//
// Plain test() on purpose: the session audio is real file IO (written into a
// system temp directory), and testWidgets + real dart:io deadlocks (KB
// gotcha). No network, no live API, no platform channels — the batch client
// is a mock and is verified never to be called.

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
import 'package:voxgale/session/session_models.dart';
import 'package:voxgale/session/session_providers.dart';
import 'package:voxgale/session/wav_file_writer.dart';
import 'package:voxgale/storage/storage.dart';

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

/// Deterministic [SessionClock]: the test advances time; ticks are delivered
/// immediately (sync broadcast).
class FakeSessionClock implements SessionClock {
  FakeSessionClock() : nowValue = DateTime(2026, 10, 23, 10, 0, 0);

  DateTime nowValue;
  final StreamController<int> _ticks = StreamController<int>.broadcast(sync: true);

  @override
  DateTime now() => nowValue;

  @override
  Stream<int> ticks() => _ticks.stream;

  void advance(Duration duration) => nowValue = nowValue.add(duration);

  void tick() => _ticks.add(0);

  Future<void> dispose() => _ticks.close();
}

/// A no-op [AudioFocusGateway]: no focus events, records configuration.
class FakeAudioFocusGateway implements AudioFocusGateway {
  final StreamController<AudioFocusEvent> _focus =
      StreamController<AudioFocusEvent>.broadcast(sync: true);

  int configureCount = 0;
  int releaseCount = 0;

  @override
  Future<void> configureForRecord() async {
    configureCount++;
  }

  @override
  Stream<AudioFocusEvent> get focusEvents => _focus.stream;

  @override
  Future<void> release() async {
    releaseCount++;
  }

  Future<void> dispose() => _focus.close();
}

/// A fake [CaptureService]: no platform channels, no foreground service, no
/// Mistral client. The test drives the session events through it, and the
/// fake plays the service isolate's role end to end — it accumulates the
/// streamed transcript, "records" the session audio as a real WAV (via the
/// production [WavFileWriter]) in a temp directory, and on stop forwards the
/// final session-ended event carrying what the stream produced.
class FakeCaptureService implements CaptureService {
  FakeCaptureService({
    required this.clock,
    required this.audioDirectory,
  });

  /// The session clock (the fake records the session's audio length from it).
  final SessionClock clock;

  /// The directory the session audio WAV is written to (a temp directory).
  final Directory audioDirectory;

  final StreamController<SessionEvent> _events =
      StreamController<SessionEvent>.broadcast(sync: true);

  /// The commands the UI isolate sent (pause/resume/stop), in order.
  final List<String> commands = [];

  String? startedSessionId;
  RealtimeSessionConfig? startedConfig;
  DateTime? _startedAt;

  /// The transcript accumulated from the text deltas the stream delivered.
  final StringBuffer _streamedText = StringBuffer();

  /// The path of the session audio WAV "recorded" for the session.
  String? audioPath;

  @override
  Stream<SessionEvent> get events => _events.stream;

  @override
  Duration get forceStopDelay => const Duration(seconds: 2);

  @override
  Future<bool> isRunning() async => true;

  @override
  Future<bool> isBatteryOptimizationIgnored() async => true;

  @override
  Future<bool> requestIgnoreBatteryOptimization() async => true;

  @override
  Future<bool> openBatteryOptimizationSettings() async => true;

  @override
  Future<CaptureStartFailure?> startSession({
    required String sessionId,
    required RealtimeSessionConfig config,
  }) async {
    startedSessionId = sessionId;
    startedConfig = config;
    _startedAt = clock.now();
    return null;
  }

  @override
  void pause() => commands.add('pause');

  @override
  void resume() => commands.add('resume');

  /// Feeds one realtime text delta into the session event stream (what the
  /// service isolate forwards from the WebSocket) and accumulates it into
  /// the session's transcript of record.
  void emitTextDelta(String text) {
    _streamedText.write(text);
    _events.add(SessionTextDelta(text));
  }

  /// Feeds any other session event (turn boundaries, stream errors).
  void emit(SessionEvent event) => _events.add(event);

  @override
  Future<void> stop() async {
    commands.add('stop');
    // The graceful stop: the service ends the realtime session, closes the
    // WAV (its length matches the session's duration), and forwards the
    // final session-ended event with the transcript the stream produced.
    final sessionId = startedSessionId!;
    final path = '${audioDirectory.path}/$sessionId.wav';
    final startedAt = _startedAt ?? clock.now();
    // PCM16 mono at 16 kHz = 32,000 bytes per second of audio.
    final dataBytes = clock.now().difference(startedAt).inSeconds * 32000;
    final writer = await WavFileWriter.create(path);
    writer.add(Uint8List(dataBytes));
    await writer.close();
    audioPath = path;
    final fullText = _streamedText.toString();
    _events.add(SessionEnded(
      sessionId: sessionId,
      audioPath: path,
      fullText: fullText,
      segments: [
        if (fullText.isNotEmpty) TranscriptSegment(text: fullText),
      ],
      language: 'en',
      model: 'voxtral-mini-transcribe-realtime-3-0',
      usage: Usage(promptAudioSeconds: dataBytes ~/ 32000),
    ));
  }

  @override
  void dispose() => _events.close();
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      BatchTranscriptionRequest(
        model: 'model',
        audioBytes: Uint8List(0),
        fileName: 'file.wav',
      ),
    );
  });

  late FakeCaptureService capture;
  late MockBatchTranscriptionClient batchClient;
  late FakeApiKeyStore apiKeyStore;
  late FakeSessionClock clock;
  late FakeAudioFocusGateway audioFocus;
  late AppDatabase db;
  late ProviderContainer container;
  late Directory tempDir;

  /// The history list's data states, captured while it is kept alive (as the
  /// history screen would keep it).
  late List<List<StoredSession>> historyStates;
  late ProviderSubscription<AsyncValue<List<StoredSession>>> historySub;

  LiveSessionState state() => container.read(liveSessionControllerProvider);

  LiveSessionController controller() =>
      container.read(liveSessionControllerProvider.notifier);

  SessionRepository repository() =>
      container.read(sessionRepositoryProvider);

  /// Lets the event loop run until [condition] holds (with a timeout).
  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue);
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('voxgale_flow_test');
    clock = FakeSessionClock();
    audioFocus = FakeAudioFocusGateway();
    apiKeyStore = FakeApiKeyStore()..key = 'test-key';
    capture = FakeCaptureService(clock: clock, audioDirectory: tempDir);
    batchClient = MockBatchTranscriptionClient();
    db = AppDatabase.memory();
    container = ProviderContainer(
      overrides: [
        captureServiceProvider.overrideWith((ref) => capture),
        // The real repository over the in-memory Drift database: the
        // finalized session must land in actual storage, not a mock.
        appDatabaseProvider.overrideWith((ref) => db),
        preferencesRepositoryProvider.overrideWith(
            (ref) => InMemoryPreferencesRepository()),
        apiKeyStoreProvider.overrideWith((ref) => apiKeyStore),
        batchTranscriptionClientProvider.overrideWith(
            (ref) async => batchClient),
        sessionClockProvider.overrideWith((ref) => clock),
        audioFocusGatewayProvider.overrideWith((ref) => audioFocus),
        sessionFinalizeTimeoutProvider.overrideWith(
          (ref) => const Duration(milliseconds: 100),
        ),
      ],
    );
    // Keep the history list alive (as the history screen would) and capture
    // its data states.
    historyStates = [];
    historySub = container.listen(
      historyListProvider,
      (prev, next) =>
          next.whenOrNull(data: (sessions) => historyStates.add(sessions)),
    );
  });

  tearDown(() async {
    historySub.close();
    container.dispose();
    capture.dispose();
    await audioFocus.dispose();
    await clock.dispose();
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('the live flow end to end: start, streamed text deltas, stop — the '
      'finalized session with the streamed transcript appears in history',
      () async {
    // The history is empty before the session.
    await waitFor(() => historyStates.isNotEmpty);
    expect(historyStates.last, isEmpty);

    // Start: the capture service starts with the v1 default config.
    await controller().start();
    expect(state().phase, LiveSessionPhase.active);
    expect(capture.startedConfig, isNotNull);
    expect(capture.startedConfig!.turnDetection, isNotNull);
    expect(capture.startedConfig!.diarize, isFalse);

    // The realtime stream delivers text deltas mid-session.
    capture.emit(const SessionTurnStarted(0));
    capture.emitTextDelta('Hello ');
    capture.emitTextDelta('world');
    capture.emit(const SessionTurnEnded(timeS: 2, endReason: 'threshold'));

    // The streamed transcript is grouped into turns live.
    expect(state().turns, [const TranscriptTurn(text: 'Hello world')]);

    // Stop: the service ends the session and forwards the final event.
    clock.advance(const Duration(seconds: 65));
    await controller().stop();
    await waitFor(() => state().phase == LiveSessionPhase.passOffered);
    expect(capture.commands, ['stop']);

    // The finalized session appears in history over the in-memory Drift
    // database, carrying the streamed transcript text.
    final sessionId = capture.startedSessionId!;
    await waitFor(() =>
        historyStates.isNotEmpty &&
        historyStates.last.any((s) => s.id == sessionId));
    final listed = historyStates.last.singleWhere((s) => s.id == sessionId);
    expect(
      listed,
      StoredSession(
        id: sessionId,
        startedAt: DateTime(2026, 10, 23, 10, 0, 0),
        durationSeconds: 65,
        model: 'voxtral-mini-transcribe-realtime-3-0',
        status: SessionStatus.provisional,
        billedAudioSeconds: 65,
        actualCost: 65 / 60 * 0.008,
        language: 'en',
        audioPath: capture.audioPath,
      ),
    );
    expect(await File(listed.audioPath!).exists(), isTrue);

    // The transcript of record in storage is the streamed text.
    final record = await repository().loadSession(sessionId);
    expect(record, isNotNull);
    expect(record!.segments, [
      StoredSegment(sessionId: sessionId, order: 0, text: 'Hello world'),
    ]);

    // The provisional transcript is kept until the pass replaces it, and the
    // pass is offered with its estimated cost (65 s of audio × the Mini rate).
    expect(state().turns, [const TranscriptTurn(text: 'Hello world')]);
    expect(state().realtimeBilledSeconds, 65);
    expect(state().passEstimatedCost, closeTo(65 / 60 * 0.0035, 1e-12));

    // No network: the batch client was never called.
    verifyNever(() => batchClient.transcribe(any()));
  });

  test('a stream failure mid-session: the text received so far is preserved '
      'and an error state is surfaced', () async {
    await controller().start();
    expect(state().phase, LiveSessionPhase.active);

    // Text streams in, then the realtime stream fails mid-session (a
    // RealtimeError forwarded by the service).
    capture.emitTextDelta('Hello ');
    capture.emit(const SessionError('Connection lost'));
    await waitFor(() => state().hasError);

    // The error is surfaced as a warning — the session stays open and the
    // text received so far is preserved.
    expect(state().phase, LiveSessionPhase.active);
    expect(state().error, 'Connection lost');
    expect(state().turns, [const TranscriptTurn(text: 'Hello ')]);

    // The session still ends gracefully: the partial transcript is what gets
    // saved, and the error state stays surfaced alongside it.
    clock.advance(const Duration(seconds: 12));
    await controller().stop();
    await waitFor(() => state().phase == LiveSessionPhase.passOffered);

    expect(state().error, 'Connection lost');
    expect(state().turns, [const TranscriptTurn(text: 'Hello ')]);

    // The finalized session is in history with the text received so far.
    final sessionId = capture.startedSessionId!;
    await waitFor(() =>
        historyStates.isNotEmpty &&
        historyStates.last.any((s) => s.id == sessionId));
    final record = await repository().loadSession(sessionId);
    expect(record, isNotNull);
    expect(record!.segments, [
      StoredSegment(sessionId: sessionId, order: 0, text: 'Hello '),
    ]);

    // No network: the batch client was never called.
    verifyNever(() => batchClient.transcribe(any()));
  });
}
