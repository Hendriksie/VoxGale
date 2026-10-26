// Production foreground-service task handler for live sessions (design
// P1-D1, task 3.1): promoted from `SpikeTaskHandler`. The service isolate
// owns the recorder, the session WAV, and the realtime session for the whole
// session; the UI isolate never captures — it sends commands and renders the
// events forwarded over the plugin's data channel.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../mistral/mistral.dart';
import 'session_models.dart';
import 'wav_file_writer.dart';

/// Entry point for the foreground service isolate. Must be a top-level
/// function.
@pragma('vm:entry-point')
void captureBackgroundTaskHandler() {
  FlutterForegroundTask.setTaskHandler(CaptureTaskHandler());
}

/// The capture handler's side of the platform: the saved config, the event
/// channel to the UI isolate, the persistent notification, and the service
/// lifecycle. The production implementation delegates to the
/// flutter_foreground_task statics; unit tests substitute a fake.
abstract interface class CaptureTaskTransport {
  /// Reads the session config the UI saved before starting the service.
  Future<String?> readSavedConfig();

  /// Sends one JSON-encoded [SessionEvent] to the UI isolate.
  void sendToUi(Object data);

  /// Updates the persistent notification's text (elapsed time / paused).
  Future<void> updateNotificationText(String text);

  /// Stops the foreground service.
  Future<void> stopService();
}

/// [CaptureTaskTransport] over the flutter_foreground_task statics.
class ForegroundTaskTransport implements CaptureTaskTransport {
  @override
  Future<String?> readSavedConfig() =>
      FlutterForegroundTask.getData<String>(key: CaptureTaskHandler.configKey);

  @override
  void sendToUi(Object data) => FlutterForegroundTask.sendDataToMain(data);

  @override
  Future<void> updateNotificationText(String text) async {
    await FlutterForegroundTask.updateService(notificationText: text);
  }

  @override
  Future<void> stopService() => FlutterForegroundTask.stopService();
}

/// The production [TaskHandler] for live sessions (design P1-D1/D2).
///
/// Lifecycle: `onStart` reads the config the UI saved (session id + session
/// settings), starts the realtime session, opens the WAV at
/// `<documents>/sessions/<id>.wav`, and starts the recorder; audio chunks are
/// teed to the session and the WAV. `onReceiveData` handles the pause/resume/
/// stop commands; `onNotificationButtonPressed` routes the notification stop
/// button to the same stop path. There is exactly one stop path — the
/// graceful stop — reached from the stop command, the notification button,
/// and `onDestroy`.
class CaptureTaskHandler extends TaskHandler {
  /// SharedPreferences key the UI saves the session config under before
  /// starting the service (settings lock: the config is fixed at start).
  static const String configKey = 'voxtral_capture_config';

  /// Id of the notification stop button. A tap is delivered to
  /// [onNotificationButtonPressed] in this isolate — the plugin's Android
  /// service broadcasts the tap to the task (service) isolate, not to the
  /// UI — and is routed to the same graceful stop as the stop command.
  static const String stopButtonId = 'stop';

  CaptureTaskHandler({
    CaptureTaskTransport? transport,
    ApiKeyStore? apiKeyStore,
    RealtimeTranscriptionClient Function(String apiKey)? clientFactory,
    AudioRecorder Function()? recorderFactory,
    Future<WavFileWriter> Function(String path)? wavFactory,
    Future<String> Function(String sessionId)? audioPathFor,
    this.notificationInterval = const Duration(seconds: 1),
  })  : _transport = transport ?? ForegroundTaskTransport(),
        _apiKeyStore = apiKeyStore ?? SecureStorageApiKeyStore(),
        _clientFactory = clientFactory ?? _defaultClientFactory,
        _recorderFactory = recorderFactory ?? AudioRecorder.new,
        _wavFactory = wavFactory ?? WavFileWriter.create,
        _audioPathFor = audioPathFor ?? defaultAudioPath;

  /// How often the notification's elapsed time is refreshed while running.
  /// Every second: the notification is a live timer (the spec requires the
  /// elapsed session time to be displayed; the update cost is negligible
  /// next to the active mic + WebSocket).
  final Duration notificationInterval;

  static RealtimeTranscriptionClient _defaultClientFactory(String apiKey) =>
      WebSocketRealtimeClient(apiKey: apiKey, config: MistralConfig.defaults);

  /// `<documents>/sessions/<sessionId>.wav` (design P1-D4: session audio
  /// lives in app-private storage, not the spike's temp directory).
  static Future<String> defaultAudioPath(String sessionId) async {
    final dir = await getApplicationDocumentsDirectory();
    final sessionsDir = Directory('${dir.path}/sessions');
    if (!await sessionsDir.exists()) {
      await sessionsDir.create(recursive: true);
    }
    return '${sessionsDir.path}/$sessionId.wav';
  }

  final CaptureTaskTransport _transport;
  final ApiKeyStore _apiKeyStore;
  final RealtimeTranscriptionClient Function(String apiKey) _clientFactory;
  final AudioRecorder Function() _recorderFactory;
  final Future<WavFileWriter> Function(String path) _wavFactory;
  final Future<String> Function(String sessionId) _audioPathFor;

  RealtimeSession? _session;
  AudioRecorder? _recorder;
  WavFileWriter? _wav;
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription<RealtimeEvent>? _eventSub;
  Timer? _notificationTimer;
  String? _sessionId;
  String? _audioPath;
  DateTime? _startedAt;
  SessionTranscriptionDone? _done;
  bool _paused = false;
  bool _stopping = false;
  bool _captureActive = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final configJson = await _transport.readSavedConfig();
    if (configJson == null) {
      await _fail('No session config saved before the service started');
      return;
    }

    final Map<String, dynamic> saved;
    try {
      saved = jsonDecode(configJson) as Map<String, dynamic>;
    } on FormatException {
      await _fail('Corrupt session config saved before the service started');
      return;
    }
    final sessionId = saved['session_id'];
    final sessionJson = saved['session'];
    if (sessionId is! String || sessionId.isEmpty || sessionJson is! Map) {
      await _fail('Session config is missing the session id or settings');
      return;
    }

    // The key is read from secure storage here in the service isolate; it is
    // injected only into the lib/mistral/ client.
    final key = await _apiKeyStore.readKey();
    if (key == null || key.isEmpty) {
      await _fail('No API key saved');
      return;
    }

    try {
      final sessionConfig = _sessionConfigFromJson(
        sessionJson as Map<String, dynamic>,
      );
      final session = await _clientFactory(key).startSession(sessionConfig);
      _session = session;
      final audioPath = await _audioPathFor(sessionId);
      final wav = await _wavFactory(audioPath);
      _wav = wav;

      final recorder = _recorderFactory();
      _recorder = recorder;
      // Do NOT check record's hasPermission() here: it is activity-bound and
      // returns false in a service isolate (no Activity) even when the app
      // holds RECORD_AUDIO. The UI isolate checks permission before starting
      // the service, and the runtime permission is process-wide — recording
      // just works here. Any real failure surfaces from startStream below.
      final stream = await recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));

      _sessionId = sessionId;
      _audioPath = audioPath;
      _startedAt = DateTime.now();
      _eventSub = session.events.listen(_forward);
      // Audio tee: every chunk goes to the realtime session and to the WAV
      // saved for the post-session diarization pass.
      _audioSub = stream.listen((chunk) {
        session.sendAudio(chunk);
        wav.add(chunk);
      });
      _captureActive = true;
      _startNotificationTimer();
      await _updateNotification();
    } on MistralApiException catch (e) {
      await _fail(e.message);
    } catch (e) {
      // Any failure in the service isolate is reported to the UI instead of
      // silently killing the service.
      await _fail(
        'Capture session failed: ${MistralApiException.sanitize(e, key)}',
      );
    }
  }

  @override
  void onReceiveData(Object data) {
    switch (CaptureCommand.fromWire(data)) {
      case CaptureCommand.pause:
        _pause();
      case CaptureCommand.resume:
        _resume();
      case CaptureCommand.stop:
        _stop();
      case null:
        break; // unknown command — ignore
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    // The notification stop button is delivered here, in the service
    // isolate (the plugin's background channel), not to the UI — route it to
    // the same graceful stop as the UI's stop command.
    if (id == stopButtonId) {
      _stop();
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Notification updates run on the handler's own timer.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _stop();
  }

  /// Maps a domain event to the session event forwarded to the UI isolate.
  void _forward(RealtimeEvent event) {
    final sessionEvent = sessionEventFromRealtime(event);
    if (sessionEvent is SessionTranscriptionDone) {
      // Remembered so the final session-ended event can carry the transcript
      // of record even though it is sent after the event stream is closed.
      _done = sessionEvent;
    }
    if (sessionEvent != null) {
      _send(sessionEvent);
    }
  }

  void _send(SessionEvent event) {
    _transport.sendToUi(jsonEncode(event.toJson()));
  }

  Future<void> _pause() async {
    if (_paused || _stopping || !_captureActive) {
      return;
    }
    try {
      // record's pause() stops the stream's audio flow; the subscription, the
      // WAV, and the realtime session stay in place (design P1-D2) — the
      // client's keep-alive silence feed keeps the server session alive.
      await _recorder?.pause();
    } catch (e) {
      _send(SessionError('Could not pause capture: $e'));
      return;
    }
    _paused = true;
    await _updateNotification();
  }

  Future<void> _resume() async {
    if (!_paused || _stopping) {
      return;
    }
    try {
      await _recorder?.resume();
    } catch (e) {
      _send(SessionError('Could not resume capture: $e'));
      return;
    }
    _paused = false;
    await _updateNotification();
  }

  /// The single stop path (graceful stop): end the realtime session
  /// (`input_audio.end`, wait for `transcription.done`), close the WAV (patch
  /// the header), stop/dispose the recorder with guarded dispose, forward the
  /// final session-ended event to the UI BEFORE stopping the service, then
  /// stop the service.
  Future<void> _stop() async {
    if (_stopping) {
      return;
    }
    _stopping = true;
    _notificationTimer?.cancel();
    _notificationTimer = null;

    // Stop the audio flow first so nothing is sent after input_audio.end.
    await _audioSub?.cancel();
    _audioSub = null;

    final session = _session;
    _session = null;
    if (session != null) {
      try {
        await session.end();
      } catch (_) {}
      // The event subscription stays until end() resolved: transcription.done
      // arrives on it and is forwarded by _forward.
      await _eventSub?.cancel();
      _eventSub = null;
      try {
        await session.dispose();
      } catch (_) {}
    }

    final wav = _wav;
    _wav = null;
    try {
      await wav?.close();
    } catch (_) {}

    // record throws "Recorder has not yet been created or has already been
    // disposed" if stop/dispose is called on a recorder that never started or
    // was already disposed — swallow it so the service can still stop.
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) {
      try {
        await recorder.stop();
      } catch (_) {}
      try {
        await recorder.dispose();
      } catch (_) {}
    }

    // Forward the final event BEFORE stopping the service: once the service
    // is stopped the UI may no longer receive data from this isolate.
    if (_captureActive) {
      final done = _done;
      _send(SessionEnded(
        sessionId: _sessionId ?? '',
        audioPath: _audioPath ?? '',
        fullText: done?.fullText ?? '',
        segments: done?.segments ?? const [],
        language: done?.language,
        model: done?.model ?? '',
        usage: done?.usage ?? const Usage(),
      ));
    }
    await _transport.stopService();
  }

  Future<void> _fail(String message) async {
    _send(SessionError(message));
    await _transport.stopService();
  }

  void _startNotificationTimer() {
    _notificationTimer?.cancel();
    _notificationTimer = Timer.periodic(notificationInterval, (_) {
      _updateNotification();
    });
  }

  /// "Transcribing · MM:SS" (or "Paused · MM:SS" while paused) — the elapsed
  /// session time in the persistent notification.
  Future<void> _updateNotification() async {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return;
    }
    final elapsed = DateTime.now().difference(startedAt);
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final label = _paused ? 'Paused' : 'Transcribing';
    await _transport.updateNotificationText('$label · $mm:$ss');
  }

  /// Rebuilds the [RealtimeSessionConfig] from the `session` object of the
  /// `session.update` JSON the UI saved before starting the service (the
  /// settings lock after the first audio chunk, so the config is fixed at
  /// start — the same round-trip as the spike harness).
  static RealtimeSessionConfig _sessionConfigFromJson(
    Map<String, dynamic> json,
  ) {
    final audioFormat = json['audio_format'];
    final sampleRate = audioFormat is Map
        ? audioFormat['sample_rate'] as int? ?? 16000
        : 16000;
    final contextBias = json['context_bias'];
    final references = json['speaker_references'];
    return RealtimeSessionConfig(
      sampleRate: sampleRate,
      targetStreamingDelayMs:
          json['target_streaming_delay_ms'] as int? ?? 480,
      language: json['language'] as String?,
      contextBias:
          contextBias is List ? contextBias.cast<String>() : const [],
      diarize: json['diarize'] == true,
      turnDetection:
          json['turn_detection'] != null ? const TurnDetectionConfig() : null,
      speakerReferences: references is Map
          ? {
              for (final entry in references.entries)
                entry.key as String: base64Decode(entry.value as String),
            }
          : const {},
    );
  }
}
