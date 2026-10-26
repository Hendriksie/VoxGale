import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxtral_live/mistral/mistral.dart';
import 'package:voxtral_live/session/file_transcription_controller.dart';
import 'package:voxtral_live/session/live_session_controller.dart';
import 'package:voxtral_live/session/session_providers.dart';
import 'package:voxtral_live/storage/storage.dart';

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

/// A [AudioFilePicker] test double: [result] is returned from [pick].
class FakeAudioFilePicker implements AudioFilePicker {
  PickedAudioFile? result;
  int calls = 0;

  @override
  Future<PickedAudioFile?> pick() async {
    calls++;
    return result;
  }
}

/// An [AudioDurationProber] test double: [duration] is returned from [probe].
class FakeAudioDurationProber implements AudioDurationProber {
  Duration? duration;
  int calls = 0;

  @override
  Future<Duration?> probe(String path) async {
    calls++;
    return duration;
  }
}

/// Deterministic [SessionClock]: the test advances time and fires ticks.
class FakeSessionClock implements SessionClock {
  FakeSessionClock() : nowValue = DateTime(2026, 10, 26, 12, 0, 0);

  DateTime nowValue;
  final StreamController<int> tickController =
      StreamController<int>.broadcast(sync: true);

  @override
  DateTime now() => nowValue;

  @override
  Stream<int> ticks() => tickController.stream;

  void tick() => tickController.add(0);
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
  });

  late MockSessionRepository repository;
  late MockBatchTranscriptionClient batchClient;
  late FakeApiKeyStore apiKeyStore;
  late InMemoryPreferencesRepository preferences;
  late FakeAudioFilePicker picker;
  late FakeAudioDurationProber prober;
  late FakeSessionClock clock;
  late ProviderContainer container;

  const config = MistralConfig.defaults;

  FileTranscriptionState state() =>
      container.read(fileTranscriptionControllerProvider);

  FileTranscriptionController controller() =>
      container.read(fileTranscriptionControllerProvider.notifier);

  /// Lets the event loop run until [condition] holds (with a timeout).
  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue);
  }

  PickedAudioFile pickedFile({
    String name = 'interview.mp3',
    int bytes = 1024,
  }) =>
      PickedAudioFile(
        name: name,
        path: '/tmp/$name',
        bytes: Uint8List(bytes),
      );

  /// Captured from the mocked repository.
  StoredSession? savedSession;
  List<StoredSegment>? savedSegments;

  void stubSaveSession() {
    when(() => repository.saveSession(any(), any())).thenAnswer(
      (invocation) async {
        savedSession = invocation.positionalArguments[0] as StoredSession;
        savedSegments =
            invocation.positionalArguments[1] as List<StoredSegment>;
      },
    );
  }

  BatchTranscriptionResult transcriptionResult({
    int billedSeconds = 30,
    String language = 'en',
  }) =>
      BatchTranscriptionResult(
        text: 'Hello world',
        segments: const [
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
        language: language,
        model: config.batchMiniModel,
        usage: Usage(promptAudioSeconds: billedSeconds),
      );

  setUp(() {
    repository = MockSessionRepository();
    batchClient = MockBatchTranscriptionClient();
    apiKeyStore = FakeApiKeyStore()..key = 'test-key';
    preferences = InMemoryPreferencesRepository();
    picker = FakeAudioFilePicker();
    prober = FakeAudioDurationProber();
    clock = FakeSessionClock();
    savedSession = null;
    savedSegments = null;
    container = ProviderContainer(
      overrides: [
        apiKeyStoreProvider.overrideWith((ref) => apiKeyStore),
        audioFilePickerProvider.overrideWith((ref) => picker),
        audioDurationProberProvider.overrideWith((ref) => prober),
        sessionRepositoryProvider.overrideWith((ref) => repository),
        batchTranscriptionClientProvider.overrideWith((ref) async => batchClient),
        preferencesRepositoryProvider.overrideWith((ref) => preferences),
        mistralConfigProvider.overrideWith((ref) => config),
        sessionClockProvider.overrideWith((ref) => clock),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('initial load', () {
    test('loads the key presence (never the key itself)', () async {
      controller();
      await waitFor(() => !state().missingApiKey && state().error.isEmpty);

      expect(state().missingApiKey, isFalse);
      expect(state().toString(), isNot(contains('test-key')));
    });

    test('flags a missing key', () async {
      apiKeyStore.key = null;
      controller();
      await waitFor(() => state().missingApiKey);

      expect(state().missingApiKey, isTrue);
    });
  });

  group('pick (file-transcription spec: import an audio file)', () {
    test('a cancelled picker keeps the idle phase', () async {
      picker.result = null;
      controller();

      await controller().pick();

      expect(picker.calls, 1);
      expect(state().phase, FileTranscriptionPhase.idle);
    });

    test('without an API key the pick fails with a missing-key state and '
        'never opens the picker', () async {
      apiKeyStore.key = null;
      controller();
      await waitFor(() => state().missingApiKey);

      await controller().pick();

      expect(picker.calls, 0);
      expect(state().phase, FileTranscriptionPhase.error);
      expect(state().missingApiKey, isTrue);
      expect(state().error, contains('No API key saved'));
    });

    test('a picked file moves to picked with its duration, the default '
        'model, and the duration-based estimate', () async {
      picker.result = pickedFile();
      prober.duration = const Duration(seconds: 60);
      controller();

      await controller().pick();

      expect(state().phase, FileTranscriptionPhase.picked);
      expect(state().fileName, 'interview.mp3');
      expect(state().durationSeconds, 60);
      expect(state().durationKnown, isTrue);
      // The default preference is the pinned Mini model.
      expect(state().selectedModel, config.batchMiniModel);
      // 60 s / 60 × the Mini rate.
      expect(state().estimatedCost, closeTo(config.batchMiniRatePerMinute, 1e-12));
    });

    test('the settings preference sets the default model and its rate',
        () async {
      preferences.stored = const StoredPreferences(
        defaultBatchModel: 'voxtral-small-transcribe-3-0',
      );
      picker.result = pickedFile();
      prober.duration = const Duration(seconds: 60);
      controller();

      await controller().pick();

      expect(state().selectedModel, config.batchSmallModel);
      expect(state().estimatedCost,
          closeTo(config.batchSmallRatePerMinute, 1e-12));
    });

    test('an unprobeable duration leaves the estimate empty', () async {
      picker.result = pickedFile();
      prober.duration = null;
      controller();

      await controller().pick();

      expect(state().phase, FileTranscriptionPhase.picked);
      expect(state().durationKnown, isFalse);
      expect(state().estimatedCost, 0);
    });
  });

  group('setModel (file-transcription spec: per-file model choice)', () {
    test('recomputes the estimate with the selected model rate', () async {
      picker.result = pickedFile();
      prober.duration = const Duration(seconds: 60);
      controller();
      await controller().pick();

      controller().setModel(config.batchSmallModel);

      expect(state().selectedModel, config.batchSmallModel);
      expect(state().estimatedCost,
          closeTo(config.batchSmallRatePerMinute, 1e-12));
    });

    test('is a no-op outside the picked phase', () async {
      controller();

      controller().setModel(config.batchSmallModel);

      expect(state().selectedModel, isNull);
    });
  });

  group('transcribe (file-transcription spec: diarized result saved to '
      'history)', () {
    test('transcribes with diarization on the selected model and saves the '
        'result with its source, model, and billed usage', () async {
      picker.result = pickedFile();
      prober.duration = const Duration(seconds: 30);
      controller();
      await controller().pick();
      stubSaveSession();
      BatchTranscriptionRequest? request;
      when(() => batchClient.transcribe(any())).thenAnswer(
        (invocation) async {
          request =
              invocation.positionalArguments[0] as BatchTranscriptionRequest;
          return transcriptionResult();
        },
      );

      await controller().transcribe();

      // The request: the picked bytes, the selected model, diarization on,
      // the audio duration (so a stalled call is bounded).
      expect(request, isNotNull);
      expect(request!.model, config.batchMiniModel);
      expect(request!.diarize, isTrue);
      expect(request!.fileName, 'interview.mp3');
      expect(request!.audioBytes, picker.result!.bytes);
      expect(request!.audioDuration, const Duration(seconds: 30));
      // The saved session: a file source with the file name, the model, the
      // billed usage, finalized.
      expect(savedSession, isNotNull);
      expect(savedSession!.source, StoredSession.sourceFile);
      expect(savedSession!.sourceFileName, 'interview.mp3');
      expect(savedSession!.model, config.batchMiniModel);
      expect(savedSession!.status, SessionStatus.finalized);
      expect(savedSession!.billedAudioSeconds, 30);
      expect(savedSession!.actualCost,
          closeTo(30 / 60 * config.batchMiniRatePerMinute, 1e-12));
      expect(savedSession!.durationSeconds, 30);
      expect(savedSegments, hasLength(2));
      expect(savedSegments!.first.speakerLabel, 'speaker_1');
      // The state: done, with the labelled turns and the actual usage.
      expect(state().phase, FileTranscriptionPhase.done);
      expect(state().turns, hasLength(2));
      expect(state().turns.first.speakerLabel, 'speaker_1');
      expect(state().turns.first.isProvisional, isFalse);
      expect(state().billedAudioSeconds, 30);
      expect(state().actualCost,
          closeTo(30 / 60 * config.batchMiniRatePerMinute, 1e-12));
      expect(state().language, 'en');
    });

    test('applies the pinned language hint', () async {
      preferences.stored = const StoredPreferences(languageHint: 'de');
      picker.result = pickedFile();
      prober.duration = const Duration(seconds: 10);
      controller();
      await controller().pick();
      stubSaveSession();
      BatchTranscriptionRequest? request;
      when(() => batchClient.transcribe(any())).thenAnswer(
        (invocation) async {
          request =
              invocation.positionalArguments[0] as BatchTranscriptionRequest;
          return transcriptionResult();
        },
      );

      await controller().transcribe();

      expect(request!.language, 'de');
    });

    test('an API error keeps the picked file and shows the error; a retry '
        'from the error phase succeeds', () async {
      picker.result = pickedFile();
      prober.duration = const Duration(seconds: 10);
      controller();
      await controller().pick();
      when(() => batchClient.transcribe(any()))
          .thenThrow(MistralApiException('quota exceeded'));

      await controller().transcribe();

      expect(state().phase, FileTranscriptionPhase.error);
      expect(state().error, 'quota exceeded');
      // The picked file is kept (the spec: errors without losing the file).
      expect(state().fileName, 'interview.mp3');
      verifyNever(() => repository.saveSession(any(), any()));

      // A retry re-runs the same file.
      stubSaveSession();
      when(() => batchClient.transcribe(any()))
          .thenAnswer((_) async => transcriptionResult());
      await controller().transcribe();

      expect(state().phase, FileTranscriptionPhase.done);
      expect(savedSession, isNotNull);
    });

    test('an unprobeable duration saves the billed duration and sends no '
        'audio duration', () async {
      picker.result = pickedFile();
      prober.duration = null;
      controller();
      await controller().pick();
      stubSaveSession();
      BatchTranscriptionRequest? request;
      when(() => batchClient.transcribe(any())).thenAnswer(
        (invocation) async {
          request =
              invocation.positionalArguments[0] as BatchTranscriptionRequest;
          return transcriptionResult(billedSeconds: 42);
        },
      );

      await controller().transcribe();

      expect(request!.audioDuration, isNull);
      expect(savedSession!.durationSeconds, 42);
    });

    test('is a no-op outside the picked and error phases', () async {
      controller();

      await controller().transcribe();

      verifyNever(() => batchClient.transcribe(any()));
      expect(state().phase, FileTranscriptionPhase.idle);
    });
  });

  group('the running estimate (cost-indicator spec)', () {
    test('accrues with the elapsed time while the transcription runs',
        () async {
      picker.result = pickedFile();
      prober.duration = const Duration(seconds: 600);
      controller();
      await controller().pick();
      stubSaveSession();
      final completer = Completer<BatchTranscriptionResult>();
      when(() => batchClient.transcribe(any()))
          .thenAnswer((_) => completer.future);

      final running = controller().transcribe();
      await waitFor(() => state().phase == FileTranscriptionPhase.running);

      clock.tick();
      expect(state().elapsedSeconds, 1);
      expect(state().estimatedCost,
          closeTo(1 / 60 * config.batchMiniRatePerMinute, 1e-12));
      clock.tick();
      expect(state().elapsedSeconds, 2);
      expect(state().estimatedCost,
          closeTo(2 / 60 * config.batchMiniRatePerMinute, 1e-12));

      completer.complete(transcriptionResult());
      await running;
      expect(state().phase, FileTranscriptionPhase.done);
    });
  });
}
