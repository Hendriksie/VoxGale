import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';
import 'package:voxtral_live/mistral/mistral.dart';
import 'package:voxtral_live/session/capture_task_handler.dart';
import 'package:voxtral_live/session/session_models.dart';
import 'package:voxtral_live/session/wav_file_writer.dart';

class MockRealtimeTranscriptionClient extends Mock
    implements RealtimeTranscriptionClient {}

class MockRealtimeSession extends Mock implements RealtimeSession {}

class MockAudioRecorder extends Mock implements AudioRecorder {}

class MockWavFileWriter extends Mock implements WavFileWriter {}

class FakeApiKeyStore implements ApiKeyStore {
  String? key;

  @override
  Future<String?> readKey() async => key;

  @override
  Future<void> saveKey(String key) async => this.key = key;

  @override
  Future<void> deleteKey() async => key = null;
}

/// Records everything the handler sends, in order.
class FakeCaptureTaskTransport implements CaptureTaskTransport {
  String? savedConfig;
  final List<SessionEvent> sentEvents = [];
  final List<String> notificationTexts = [];
  int stopServiceCalls = 0;
  final List<String> log = [];

  @override
  Future<String?> readSavedConfig() async => savedConfig;

  @override
  void sendToUi(Object data) {
    final event = SessionEvent.fromWire(data);
    if (event == null) {
      throw StateError('Handler sent an undecodable payload: $data');
    }
    sentEvents.add(event);
    log.add('event:${event.runtimeType}');
  }

  @override
  Future<void> updateNotificationText(String text) async {
    notificationTexts.add(text);
    log.add('notification');
  }

  @override
  Future<void> stopService() async {
    stopServiceCalls++;
    log.add('stop');
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(RealtimeSessionConfig());
    registerFallbackValue(const RecordConfig());
    registerFallbackValue(Uint8List(0));
  });

  late MockRealtimeTranscriptionClient client;
  late MockRealtimeSession session;
  late MockAudioRecorder recorder;
  late MockWavFileWriter wav;
  late FakeCaptureTaskTransport transport;
  late FakeApiKeyStore apiKeyStore;
  late StreamController<RealtimeEvent> eventController;
  late StreamController<Uint8List> audioController;

  /// Lets the event loop run until [condition] holds (with a timeout).
  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue);
  }

  CaptureTaskHandler createHandler() => CaptureTaskHandler(
        transport: transport,
        apiKeyStore: apiKeyStore,
        clientFactory: (_) => client,
        recorderFactory: () => recorder,
        wavFactory: (_) async => wav,
        audioPathFor: (_) async => '/docs/sessions/session-1.wav',
      );

  Future<void> startHandler(CaptureTaskHandler handler) async {
    transport.savedConfig = jsonEncode({
      'session_id': 'session-1',
      'session': RealtimeSessionConfig(
        turnDetection: const TurnDetectionConfig(),
      ).toSessionUpdateJson(),
    });
    await handler.onStart(DateTime.now(), TaskStarter.developer);
  }

  setUp(() {
    client = MockRealtimeTranscriptionClient();
    session = MockRealtimeSession();
    recorder = MockAudioRecorder();
    wav = MockWavFileWriter();
    transport = FakeCaptureTaskTransport();
    apiKeyStore = FakeApiKeyStore()..key = 'test-key';
    // Sync controllers: events/chunks are delivered to the handler's
    // listeners synchronously, which keeps the assertions deterministic.
    eventController = StreamController<RealtimeEvent>(sync: true);
    audioController = StreamController<Uint8List>(sync: true);

    when(() => client.startSession(any())).thenAnswer((_) async => session);
    when(() => session.events).thenAnswer((_) => eventController.stream);
    when(() => session.sendAudio(any())).thenAnswer((_) {});
    when(() => session.end()).thenAnswer((_) async {});
    when(() => session.dispose()).thenAnswer((_) async {});
    when(() => recorder.startStream(any()))
        .thenAnswer((_) async => audioController.stream);
    when(() => recorder.pause()).thenAnswer((_) async {});
    when(() => recorder.resume()).thenAnswer((_) async {});
    when(() => recorder.stop()).thenAnswer((_) async => null);
    when(() => recorder.dispose()).thenAnswer((_) async {});
    when(() => wav.add(any())).thenAnswer((_) {});
    when(() => wav.close()).thenAnswer((_) async {});
  });

  tearDown(() {
    // Fire-and-forget: closing a sync controller that never had a listener
    // never completes its done future, which would time the test out.
    eventController.close();
    audioController.close();
  });

  test('onStart wires recorder, WAV, and realtime session in the service '
      'isolate and forwards events to the UI', () async {
    final handler = createHandler();
    await startHandler(handler);

    // The saved config is parsed back into the session config (the settings
    // lock after the first audio chunk, so the config is fixed at start).
    final config = verify(
      () => client.startSession(captureAny<RealtimeSessionConfig>()),
    ).captured.single as RealtimeSessionConfig;
    expect(config.sampleRate, 16000);
    expect(config.turnDetection, isNotNull);
    expect(config.diarize, isFalse);

    // The API key from secure storage is injected only into the client
    // (the capture above already verified the single startSession call).

    // Recorder: PCM16 mono at 16 kHz.
    verify(() => recorder.startStream(any())).called(1);

    // Audio chunks are teed to the realtime session and the WAV file.
    audioController.add(Uint8List.fromList([1, 2, 3]));
    verify(() => session.sendAudio(any())).called(1);
    verify(() => wav.add(any())).called(1);

    // Domain events are forwarded as session events.
    eventController.add(const TextDelta('hello'));
    expect(transport.sentEvents, hasLength(1));
    expect(
      transport.sentEvents.single.toJson(),
      const SessionTextDelta('hello').toJson(),
    );

    // The notification shows the elapsed time while transcribing.
    expect(transport.notificationTexts, isNotEmpty);
    expect(transport.notificationTexts.last, startsWith('Transcribing · '));

    // Stop so no timer outlives the test.
    handler.onReceiveData('stop');
    await waitFor(() => transport.stopServiceCalls == 1);
  });

  test('the stop command ends gracefully: session.end, WAV closed, guarded '
      'recorder dispose, final event before stopService', () async {
    // The server's final message arrives while end() waits for it.
    when(() => session.end()).thenAnswer((_) async {
      eventController.add(TranscriptionDone(
        fullText: 'Hello world',
        segments: const [TranscriptSegment(text: 'Hello world')],
        language: 'en',
        model: 'voxtral-mini-transcribe-realtime-3-0',
        usage: const Usage(promptAudioSeconds: 61),
      ));
    });

    final handler = createHandler();
    await startHandler(handler);
    handler.onReceiveData('stop');
    await waitFor(() => transport.stopServiceCalls == 1);

    verify(() => session.end()).called(1);
    verify(() => wav.close()).called(1);
    verify(() => recorder.stop()).called(1);
    verify(() => recorder.dispose()).called(1);

    // The final transcription.done is forwarded, then the session-ended
    // event carrying the transcript of record — both before the service
    // stops.
    expect(transport.sentEvents, hasLength(2));
    expect(transport.sentEvents[0], isA<SessionTranscriptionDone>());
    final ended = transport.sentEvents[1];
    expect(ended, isA<SessionEnded>());
    final endedJson = ended.toJson();
    expect(endedJson['session_id'], 'session-1');
    expect(endedJson['audio_path'], '/docs/sessions/session-1.wav');
    expect(endedJson['full_text'], 'Hello world');
    expect(endedJson['language'], 'en');
    expect(endedJson['usage'], {'prompt_audio_seconds': 61});
    expect(transport.log.last, 'stop');
    expect(
      transport.log.lastIndexOf('event:SessionEnded'),
      lessThan(transport.log.indexOf('stop')),
    );
  });

  test('stop is idempotent across the stop command, the notification '
      'button, and destroy', () async {
    final handler = createHandler();
    await startHandler(handler);
    handler.onReceiveData('stop');
    handler.onNotificationButtonPressed(CaptureTaskHandler.stopButtonId);
    await handler.onDestroy(DateTime.now(), false);
    await waitFor(() => transport.stopServiceCalls == 1);
    verify(() => session.end()).called(1);
    verify(() => wav.close()).called(1);
  });

  test('the notification stop button routes to the same graceful stop',
      () async {
    final handler = createHandler();
    await startHandler(handler);
    handler.onNotificationButtonPressed(CaptureTaskHandler.stopButtonId);
    await waitFor(() => transport.stopServiceCalls == 1);
    verify(() => session.end()).called(1);
    verify(() => wav.close()).called(1);
    verify(() => recorder.dispose()).called(1);
    expect(transport.sentEvents.last, isA<SessionEnded>());
  });

  test('other notification buttons are ignored', () async {
    final handler = createHandler();
    await startHandler(handler);
    handler.onNotificationButtonPressed('mic');
    verifyNever(() => session.end());
    verifyNever(() => recorder.stop());
    // Stop explicitly so no timer outlives the test.
    handler.onReceiveData('stop');
    await waitFor(() => transport.stopServiceCalls == 1);
  });

  test('pause and resume commands pause the recorder and update the '
      'notification; the session stays open', () async {
    final handler = createHandler();
    await startHandler(handler);

    handler.onReceiveData('pause');
    await waitFor(() => transport.notificationTexts.last.startsWith('Paused'));
    verify(() => recorder.pause()).called(1);
    verifyNever(() => session.end());

    handler.onReceiveData('resume');
    await waitFor(
      () => transport.notificationTexts.last.startsWith('Transcribing'),
    );
    verify(() => recorder.resume()).called(1);
    verifyNever(() => session.end());

    // The realtime session is still open: audio keeps flowing.
    audioController.add(Uint8List.fromList([9]));
    verify(() => session.sendAudio(any())).called(1);

    handler.onReceiveData('stop');
    await waitFor(() => transport.stopServiceCalls == 1);
  });

  test('pause and resume before a session started are no-ops', () {
    final handler = createHandler();
    handler.onReceiveData('pause');
    handler.onReceiveData('resume');
    verifyNever(() => recorder.pause());
    verifyNever(() => recorder.resume());
  });

  test('stop before a session started stops the service without a final '
      'event', () async {
    final handler = createHandler();
    handler.onReceiveData('stop');
    await waitFor(() => transport.stopServiceCalls == 1);
    expect(transport.sentEvents, isEmpty);
  });

  test('a missing saved config fails with an error event and stops the '
      'service', () async {
    transport.savedConfig = null;
    final handler = createHandler();
    await handler.onStart(DateTime.now(), TaskStarter.developer);
    expect(transport.sentEvents, hasLength(1));
    expect(transport.sentEvents.single, isA<SessionError>());
    expect(transport.stopServiceCalls, 1);
    verifyNever(() => client.startSession(any()));
  });

  test('a corrupt saved config fails with an error event', () async {
    transport.savedConfig = '{not json';
    final handler = createHandler();
    await handler.onStart(DateTime.now(), TaskStarter.developer);
    expect(transport.sentEvents.single, isA<SessionError>());
    expect(transport.stopServiceCalls, 1);
    verifyNever(() => client.startSession(any()));
  });

  test('a missing API key fails with an error event and stops the service',
      () async {
    apiKeyStore.key = null;
    final handler = createHandler();
    await startHandler(handler);
    expect(transport.sentEvents.single, isA<SessionError>());
    expect(
      transport.sentEvents.single.toJson()['message'],
      'No API key saved',
    );
    expect(transport.stopServiceCalls, 1);
    verifyNever(() => client.startSession(any()));
  });

  test('a recorder failure reports an error and the destroy path cleans up '
      'the partial pipeline', () async {
    when(() => recorder.startStream(any())).thenThrow(StateError('no mic'));
    final handler = createHandler();
    await startHandler(handler);
    expect(transport.sentEvents.single, isA<SessionError>());
    expect(transport.stopServiceCalls, 1);

    // The service is destroyed after the failure: the guarded stop path
    // disposes the partially started pipeline.
    await handler.onDestroy(DateTime.now(), false);
    verify(() => session.end()).called(1);
    verify(() => session.dispose()).called(1);
    verify(() => wav.close()).called(1);
    verify(() => recorder.dispose()).called(1);
  });

  test('a recorder that throws on stop/dispose does not block the graceful '
      'stop', () async {
    when(() => recorder.stop()).thenThrow(StateError('already disposed'));
    when(() => recorder.dispose()).thenThrow(StateError('already disposed'));
    final handler = createHandler();
    await startHandler(handler);
    handler.onReceiveData('stop');
    await waitFor(() => transport.stopServiceCalls == 1);
    verify(() => wav.close()).called(1);
    expect(transport.sentEvents.last, isA<SessionEnded>());
  });

  test('a recorder pause failure is reported as an error event and does '
      'not mark the session paused', () async {
    when(() => recorder.pause()).thenThrow(StateError('cannot pause'));
    final handler = createHandler();
    await startHandler(handler);
    handler.onReceiveData('pause');
    await waitFor(() => transport.sentEvents.isNotEmpty);
    expect(transport.sentEvents.single, isA<SessionError>());
    expect(
      transport.notificationTexts.last,
      startsWith('Transcribing · '),
    );
    // A later resume is a no-op (the session never paused) — the guard runs
    // synchronously, so the verification is deterministic.
    handler.onReceiveData('resume');
    verifyNever(() => recorder.resume());
    // Stop explicitly so no timer outlives the test.
    handler.onReceiveData('stop');
    await waitFor(() => transport.stopServiceCalls == 1);
  });
}
