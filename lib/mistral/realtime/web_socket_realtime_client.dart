// ignore_for_file: prefer_initializing_formals — the public clients take the
// API key as a public `apiKey` parameter (a private named parameter would not
// be callable from other libraries).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart' show IOWebSocketChannel;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../mistral_api_exception.dart';
import '../mistral_config.dart';
import 'realtime_events.dart';
import 'realtime_session_config.dart';
import 'realtime_transcription_client.dart';

/// Factory for WebSocket channels, injectable for tests.
typedef WebSocketChannelFactory = WebSocketChannel Function(
  Uri uri,
  Map<String, String> headers,
);

/// Production factory: connects with the API key in the Authorization header.
///
/// Pings are deliberately DISABLED: the `web_socket` package closes the
/// connection when a ping goes unanswered, and this server's ping behavior is
/// unverified — on-device, enabling 15 s pings produced a reconnect roughly
/// every 28 s (two ping intervals), i.e. the pings caused the drops. Re-enable
/// only after confirming the server answers pings.
WebSocketChannel defaultWebSocketChannelFactory(
  Uri uri,
  Map<String, String> headers,
) =>
    IOWebSocketChannel.connect(uri, headers: headers);

/// [RealtimeTranscriptionClient] speaking the Voxtral 3 realtime WebSocket
/// protocol directly (no official Dart SDK exists).
///
/// Session lifecycle: connect -> `session.created` -> `session.update` (all
/// settings, before any audio) -> `session.updated` -> `input_audio.append`
/// chunks (base64 in JSON) -> `input_audio.end` -> `transcription.done`.
///
/// On a connection drop the session reconnects with the identical config and
/// replays locally buffered audio (design decision D6). Errors that leave this
/// layer are sanitized and never contain the API key.
class WebSocketRealtimeClient implements RealtimeTranscriptionClient {
  WebSocketRealtimeClient({
    required String apiKey,
    required MistralConfig config,
    Uri? baseUri,
    WebSocketChannelFactory? channelFactory,
    this.reconnectDelay = const Duration(seconds: 1),
    this.keepAliveAfter = const Duration(milliseconds: 500),
    this.bufferCap = const Duration(minutes: 5),
    this.debugLog,
  })  : _apiKey = apiKey,
        _uri = (baseUri ?? _defaultBaseUri).replace(
          path: '/v1/audio/transcriptions/realtime',
          queryParameters: {'model': config.realtimeModel},
        ),
        _channelFactory = channelFactory ?? defaultWebSocketChannelFactory;

  static final Uri _defaultBaseUri = Uri(scheme: 'wss', host: 'api.mistral.ai');

  final String _apiKey;
  final Uri _uri;
  final WebSocketChannelFactory _channelFactory;

  /// Delay between reconnect attempts.
  final Duration reconnectDelay;

  /// When the microphone delivers no audio for this long while connected, a
  /// small silence chunk is sent so the server does not idle-close the
  /// session. On-device, reconnects clustered during pauses (and the record
  /// stream may gap mid-speech on some devices). Null disables the feed.
  final Duration? keepAliveAfter;

  /// Maximum audio buffered while disconnected, replayed after the reconnect.
  /// Beyond the cap the OLDEST chunks are dropped and a [BufferedAudioDropped]
  /// event is emitted (design decision P1-D3): the default 5 minutes of PCM16
  /// mono at 16 kHz is 9,600,000 bytes, so a long outage cannot grow the buffer
  /// without bound (the spike left it unbounded). Injectable so tests can use
  /// a tiny cap.
  final Duration bufferCap;

  /// Optional trace log for connection lifecycle (connect, stream error with
  /// close code, reconnect, replay). Used by the spike harness; never logged
  /// in production.
  final void Function(String message)? debugLog;

  @override
  Future<RealtimeSession> startSession(RealtimeSessionConfig config) async {
    try {
      return await WebSocketRealtimeSession._start(
        config: config,
        apiKey: _apiKey,
        uri: _uri,
        channelFactory: _channelFactory,
        reconnectDelay: reconnectDelay,
        keepAliveAfter: keepAliveAfter,
        bufferCap: bufferCap,
        debugLog: debugLog,
      );
    } catch (error) {
      throw MistralApiException(
        MistralApiException.sanitize(error, _apiKey),
      );
    }
  }
}

class WebSocketRealtimeSession implements RealtimeSession {
  WebSocketRealtimeSession._({
    required RealtimeSessionConfig config,
    required String apiKey,
    required Uri uri,
    required WebSocketChannelFactory channelFactory,
    required Duration reconnectDelay,
    required Duration bufferCap,
    this.keepAliveAfter,
    this.debugLog,
  })  : _config = config,
        _apiKey = apiKey,
        _uri = uri,
        _channelFactory = channelFactory,
        _reconnectDelay = reconnectDelay,
        _bufferCap = bufferCap;

  final RealtimeSessionConfig _config;
  final String _apiKey;
  final Uri _uri;
  final WebSocketChannelFactory _channelFactory;
  final Duration _reconnectDelay;

  /// Maximum audio held in [_audioBuffer] (design decision P1-D3).
  final Duration _bufferCap;
  final Duration? keepAliveAfter;
  final void Function(String message)? debugLog;

  void _log(String message) => debugLog?.call('[mistral] $message');

  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();

  /// Audio captured while disconnected, replayed after the reconnect. Capped
  /// at [_bufferCap] of audio (design decision P1-D3); beyond the cap the
  /// oldest chunks are dropped (see [_bufferAudio]).
  final List<Uint8List> _audioBuffer = [];

  /// Total bytes currently in [_audioBuffer]; kept in sync so the cap check
  /// and [bufferedAudioSeconds] stay O(1).
  int _bufferedBytes = 0;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _incoming;
  Completer<void>? _readyCompleter;
  Completer<void>? _doneCompleter;

  bool _connected = false;
  bool _flushing = false;
  bool _ending = false;
  bool _disposed = false;
  bool _reconnecting = false;

  /// Set by [setPaused]: while paused, no audio is sent (no keep-alive
  /// silence, so the pause costs nothing) and disconnects are not retried.
  bool _paused = false;

  Timer? _keepAliveTimer;
  DateTime? _lastAudioSentAt;
  bool _keepAliveFed = false;

  static Future<WebSocketRealtimeSession> _start({
    required RealtimeSessionConfig config,
    required String apiKey,
    required Uri uri,
    required WebSocketChannelFactory channelFactory,
    required Duration reconnectDelay,
    required Duration bufferCap,
    Duration? keepAliveAfter,
    void Function(String message)? debugLog,
  }) async {
    final session = WebSocketRealtimeSession._(
      config: config,
      apiKey: apiKey,
      uri: uri,
      channelFactory: channelFactory,
      reconnectDelay: reconnectDelay,
      bufferCap: bufferCap,
      keepAliveAfter: keepAliveAfter,
      debugLog: debugLog,
    );
    await session._connect();
    return session;
  }

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  /// Connects (or reconnects) and waits until the session is configured and
  /// ready for audio.
  Future<void> _connect() async {
    _readyCompleter = Completer<void>();
    _channel = _channelFactory(_uri, {
      'Authorization': 'Bearer $_apiKey',
    });
    try {
      await _channel!.ready;
    } catch (error) {
      _log('connect failed: ${MistralApiException.sanitize(error, _apiKey)}');
      rethrow;
    }
    _incoming =
        _channel!.stream.listen(_onMessage, onError: _onStreamError, onDone: _onStreamDone);
    await _readyCompleter!.future;
    _log('session ready');
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) {
      return; // protocol is JSON text messages
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return; // ignore malformed messages
    }
    if (json['type'] == 'session.created') {
      // All settings go out before the first audio chunk; they lock after.
      _sendJson({
        'type': 'session.update',
        'session': _config.toSessionUpdateJson(),
      });
      return;
    }
    final event = parseRealtimeEvent(json);
    if (event == null) {
      return;
    }
    if (event is SessionStarted) {
      _connected = true;
      _lastAudioSentAt = DateTime.now();
      _keepAliveFed = false;
      _startKeepAlive();
      _flushBuffer();
      final ready = _readyCompleter;
      if (ready != null && !ready.isCompleted) {
        ready.complete();
      }
    }
    if (event is TranscriptionDone) {
      final done = _doneCompleter;
      if (done != null && !done.isCompleted) {
        done.complete();
      }
    }
    _events.add(event);
  }

  void _onStreamError(Object error) {
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(error);
    }
    final message = _streamErrorMessage(error);
    _log('stream error: $message');
    _events.add(RealtimeError(message: message));
    _stopKeepAlive();
    _handleDisconnect(dropReason: message);
  }

  void _onStreamDone() {
    if (_ending || _disposed) {
      return;
    }
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(
        StateError('Connection closed before the session was ready'),
      );
    }
    final message = _streamErrorMessage('Connection closed');
    _log('stream closed: $message');
    _events.add(RealtimeError(message: message));
    _stopKeepAlive();
    _handleDisconnect(dropReason: message);
  }

  /// While connected, feeds 100 ms of silence whenever the microphone has
  /// delivered no audio for [keepAliveAfter], so the server does not
  /// idle-close the session (reconnects clustered during pauses on-device).
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    final threshold = keepAliveAfter;
    if (threshold == null) {
      return;
    }
    _keepAliveTimer =
        Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_connected || _ending || _disposed) {
        return;
      }
      final last = _lastAudioSentAt;
      if (last == null) {
        return;
      }
      if (DateTime.now().difference(last) > threshold) {
        // 100 ms of silence at 16 kHz mono PCM16 = 3200 zero bytes.
        _sendAudioChunk(Uint8List(3200));
        _lastAudioSentAt = DateTime.now();
        if (!_keepAliveFed) {
          _keepAliveFed = true;
          _log('keep-alive: feeding silence (no mic audio for '
              '${threshold.inMilliseconds}ms)');
        }
      }
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  /// Error text with the WebSocket close code/reason attached when available —
  /// the close code is the main clue for why a connection dropped.
  String _streamErrorMessage(Object error) {
    final base = MistralApiException.sanitize(error, _apiKey);
    final closeCode = _channel?.closeCode;
    final closeReason = _channel?.closeReason;
    if (closeCode == null && closeReason == null) {
      return base;
    }
    return '$base (closeCode: $closeCode, closeReason: ${closeReason ?? '-'})';
  }

  /// Reconnects with the identical config and replays buffered audio.
  Future<void> _handleDisconnect({String? dropReason}) async {
    if (_reconnecting || _ending || _disposed) {
      return;
    }
    _reconnecting = true;
    _connected = false;
    // Best-effort cleanup of the dead channel so its socket does not linger
    // (with many reconnects, leaked sockets add up).
    final deadChannel = _channel;
    await _incoming?.cancel();
    try {
      await deadChannel?.sink
          .close()
          .timeout(const Duration(seconds: 2), onTimeout: () {});
    } catch (_) {
      // Already dead.
    }
    if (_paused) {
      // While paused no audio is sent, so the server may idle-close the
      // silent session; reconnecting now would loop (close → connect →
      // close). The resume reconnects instead (design PS-D1).
      _reconnecting = false;
      return;
    }
    var attempts = 0;
    while (!_ending && !_disposed) {
      // Exponential backoff (capped) so a flapping connection does not
      // hammer the API: reconnectDelay, 2x, 4x, ... up to 10 s.
      final delayMs = (_reconnectDelay.inMilliseconds * (1 << attempts))
          .clamp(0, 10000);
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      attempts++;
      if (_ending || _disposed) {
        break;
      }
      try {
        await _connect();
        _events.add(Reconnected(dropReason: dropReason));
        _reconnecting = false;
        return;
      } catch (_) {
        // Connection failed again; keep retrying with backoff.
      }
    }
    _reconnecting = false;
  }

  @override
  void setPaused(bool paused) {
    if (_paused == paused) {
      return;
    }
    _paused = paused;
    if (paused) {
      // No audio while paused — including no keep-alive silence — so the
      // pause is free; a disconnect while paused is left for the resume
      // (the server may idle-close a silent session; retrying now would
      // loop close → connect → close) (design PS-D1).
      _stopKeepAlive();
    } else {
      _startKeepAlive();
      if (!_connected && !_reconnecting && !_ending && !_disposed) {
        // The stream may have been closed while paused; re-establish it
        // before audio flows again. Audio captured meanwhile is buffered
        // and replayed by the reconnect path.
        unawaited(_handleDisconnect());
      }
    }
  }

  @override
  void sendAudio(Uint8List pcmChunk) {
    if (_ending || _disposed) {
      return;
    }
    _keepAliveFed = false;
    // Split oversized chunks: one huge base64 JSON message can make the
    // server close the connection (WebSocket 1009, message too big).
    const maxBytes = 32768;
    if (pcmChunk.length > maxBytes) {
      for (var i = 0; i < pcmChunk.length; i += maxBytes) {
        final end = (i + maxBytes).clamp(0, pcmChunk.length);
        sendAudio(pcmChunk.sublist(i, end));
      }
      return;
    }
    if (_connected && !_flushing) {
      _sendAudioChunk(pcmChunk);
    } else {
      _bufferAudio(pcmChunk);
    }
  }

  /// Buffers one chunk captured while disconnected. The buffer is capped at
  /// [_bufferCap] of audio (design decision P1-D3): beyond the cap the OLDEST
  /// chunks are dropped and a [BufferedAudioDropped] event is emitted, so a
  /// long outage cannot grow the buffer without bound (the spike left it
  /// unbounded). Already-emitted transcript text is never rewritten.
  void _bufferAudio(Uint8List pcmChunk) {
    _audioBuffer.add(pcmChunk);
    _bufferedBytes += pcmChunk.length;
    final bytesPerSecond = _config.sampleRate * 2; // 16-bit mono PCM
    final maxBytes =
        (_bufferCap.inMilliseconds * bytesPerSecond / 1000).round();
    var droppedBytes = 0;
    while (_bufferedBytes > maxBytes && _audioBuffer.isNotEmpty) {
      final oldest = _audioBuffer.removeAt(0);
      _bufferedBytes -= oldest.length;
      droppedBytes += oldest.length;
    }
    if (droppedBytes > 0) {
      final seconds = droppedBytes / bytesPerSecond;
      _log('dropped ${seconds.toStringAsFixed(1)}s of buffered audio '
          '(cap ${_bufferCap.inSeconds}s)');
      _events.add(BufferedAudioDropped(seconds));
    }
  }

  @override
  double get bufferedAudioSeconds {
    // 16-bit mono PCM: 2 bytes per sample. The gauge shrinks as old chunks
    // are dropped beyond the cap.
    return _bufferedBytes / (_config.sampleRate * 2);
  }

  void _sendAudioChunk(Uint8List pcmChunk) {
    _lastAudioSentAt = DateTime.now();
    _sendJson({
      'type': 'input_audio.append',
      'audio': base64Encode(pcmChunk),
    });
  }

  /// Replays the buffered audio into the re-established session, paced at
  /// real time (the documented way to stream audio). Pacing matters: dumping
  /// the whole backlog at once sends audio far faster than real time, which
  /// some servers treat as a protocol problem. While the flush runs, new
  /// chunks keep buffering so ordering is preserved.
  Future<void> _flushBuffer() async {
    if (_flushing) {
      return;
    }
    _flushing = true;
    var replayedBytes = 0;
    final bytesPerSecond = _config.sampleRate * 2; // 16-bit mono PCM
    try {
      while (_audioBuffer.isNotEmpty && !_ending && !_disposed) {
        final chunk = _audioBuffer.removeAt(0);
        _bufferedBytes -= chunk.length;
        _sendAudioChunk(chunk);
        replayedBytes += chunk.length;
        final ms = (chunk.length / bytesPerSecond * 1000).round();
        if (ms > 0) {
          await Future<void>.delayed(Duration(milliseconds: ms));
        }
      }
    } finally {
      _flushing = false;
    }
    if (replayedBytes > 0) {
      final seconds = replayedBytes / bytesPerSecond;
      _log('replayed ${seconds.toStringAsFixed(1)}s of buffered audio');
      _events.add(BufferedAudioReplayed(seconds));
    }
  }

  void _sendJson(Map<String, dynamic> json) {
    _channel?.sink.add(jsonEncode(json));
  }

  @override
  Future<void> end() async {
    if (_ending) {
      return;
    }
    _ending = true;
    _stopKeepAlive();
    _doneCompleter = Completer<void>();
    _sendJson({'type': 'input_audio.end'});
    await _doneCompleter!.future
        .timeout(const Duration(seconds: 30), onTimeout: () {});
    await _incoming?.cancel();
    await _channel?.sink.close();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _stopKeepAlive();
    await _incoming?.cancel();
    await _channel?.sink.close();
    await _events.close();
  }
}
