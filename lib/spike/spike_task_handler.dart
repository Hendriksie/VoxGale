// ignore_for_file: avoid_print — spike diagnostics need unthrottled console
// output; debugPrint throttles and drops messages under a reconnect flood.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:record/record.dart';

import '../mistral/mistral.dart';

/// Entry point for the foreground service isolate (Spike B, tasks 4.1–4.2).
///
/// Must be a top-level function. Runs the whole live pipeline — recorder +
/// realtime session — inside the service isolate (design decision D4) and
/// forwards normalized events to the UI isolate.
@pragma('vm:entry-point')
void spikeBackgroundTaskHandler() {
  FlutterForegroundTask.setTaskHandler(SpikeTaskHandler());
}

class SpikeTaskHandler extends TaskHandler {
  /// SharedPreferences key the UI saves the session config under before
  /// starting the service (settings lock: the config is fixed at start).
  static const String configKey = 'spike_session_config';

  /// Command sent from the UI isolate to stop the session.
  static const String stopCommand = 'stop';

  RealtimeSession? _session;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription<RealtimeEvent>? _eventSub;
  bool _stopping = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final configJson =
        await FlutterForegroundTask.getData<String>(key: configKey);
    if (configJson == null) {
      await _fail('No session config saved before the service started');
      return;
    }

    // The key is read from secure storage here in the service isolate; it is
    // injected only into the lib/mistral/ client.
    final key = await SecureStorageApiKeyStore().readKey();
    if (key == null || key.isEmpty) {
      await _fail('No API key saved');
      return;
    }

    final sessionConfig = _sessionConfigFromJson(
      jsonDecode(configJson) as Map<String, dynamic>,
    );

    try {
      final client = WebSocketRealtimeClient(
        apiKey: key,
        config: MistralConfig.defaults,
        debugLog: (message) => print('[spike-bg] $message'),
      );
      final session = await client.startSession(sessionConfig);

      final recorder = AudioRecorder();
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

      _session = session;
      _recorder = recorder;
      _eventSub = session.events.listen(_forward);
      _audioSub = stream.listen((chunk) => session.sendAudio(chunk));
      FlutterForegroundTask.sendDataToMain(jsonEncode({
        'type': 'status',
        'message': 'Background session started',
      }));
    } on MistralApiException catch (e) {
      await _fail(e.message);
    } catch (e) {
      // Any failure in the service isolate is reported to the UI instead of
      // silently killing the service.
      await _fail(
        'Background session failed: ${MistralApiException.sanitize(e, key)}',
      );
    }
  }

  /// Maps a domain event to a small transport map for the UI isolate. The
  /// domain events stay clean; this is spike plumbing.
  void _forward(RealtimeEvent event) {
    Map<String, dynamic>? map;
    switch (event) {
      case TextDelta(:final text):
        map = {'type': 'text', 'text': text};
      case SpeakerSegment(:final text, :final speakerId):
        map = {'type': 'segment', 'text': text, 'speaker': speakerId};
      case TurnStarted():
        map = null; // one marker per completed turn is enough for the log
      case TurnEnded():
        map = {'type': 'turn'};
      case TurnEagerEnd() || TurnResumed():
        map = null; // provisional turn signals carry no display text
      case Reconnected(:final dropReason):
        // print, not debugPrint: debugPrint throttles and drops messages
        // under a reconnect flood.
        final reason = dropReason == null ? '' : ' — $dropReason';
        print('[spike-bg] reconnected$reason');
        map = {'type': 'status', 'message': 'Reconnected$reason'};
      case BufferedAudioReplayed(:final seconds):
        print('[spike-bg] replayed ${seconds.toStringAsFixed(1)}s '
            'of buffered audio');
        map = {
          'type': 'status',
          'message': 'replayed ${seconds.toStringAsFixed(1)}s of buffered audio',
        };
      case TranscriptionDone(:final usage, :final fullText):
        map = {
          'type': 'done',
          'text': fullText,
          'audioSeconds': usage.promptAudioSeconds,
        };
      case RealtimeError(:final message):
        print('[spike-bg] error: $message');
        map = {'type': 'error', 'message': message};
      case SessionStarted():
        map = null;
    }
    if (map != null) {
      FlutterForegroundTask.sendDataToMain(jsonEncode(map));
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data == stopCommand) {
      _stop();
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  Future<void> _stop() async {
    if (_stopping) {
      return;
    }
    _stopping = true;
    await _audioSub?.cancel();
    await _eventSub?.cancel();
    final session = _session;
    if (session != null) {
      try {
        await session.end();
      } catch (_) {}
      try {
        await session.dispose();
      } catch (_) {}
    }
    // record throws "Recorder has not yet been created or has already been
    // disposed" if stop/dispose is called on a recorder that never started or
    // was already disposed — swallow it so the service can still stop.
    try {
      await _recorder?.stop();
    } catch (_) {}
    try {
      await _recorder?.dispose();
    } catch (_) {}
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _stop();
  }

  Future<void> _fail(String message) async {
    FlutterForegroundTask.sendDataToMain(jsonEncode({
      'type': 'error',
      'message': message,
    }));
    await FlutterForegroundTask.stopService();
  }

  static RealtimeSessionConfig _sessionConfigFromJson(
    Map<String, dynamic> json,
  ) {
    final session = (json['session'] as Map<String, dynamic>?) ?? json;
    final audioFormat = session['audio_format'];
    final sampleRate = audioFormat is Map
        ? audioFormat['sample_rate'] as int? ?? 16000
        : 16000;
    final contextBias = session['context_bias'];
    return RealtimeSessionConfig(
      sampleRate: sampleRate,
      targetStreamingDelayMs:
          session['target_streaming_delay_ms'] as int? ?? 480,
      language: session['language'] as String?,
      contextBias:
          contextBias is List ? contextBias.cast<String>() : const [],
      diarize: session['diarize'] == true,
      turnDetection:
          session['turn_detection'] != null ? const TurnDetectionConfig() : null,
    );
  }
}
