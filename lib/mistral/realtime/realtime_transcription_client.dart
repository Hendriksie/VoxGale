import 'dart:typed_data';

import 'realtime_events.dart';
import 'realtime_session_config.dart';

/// Client for the Mistral realtime transcription WebSocket API.
///
/// All Mistral API code lives behind this interface (design decision D2): UI
/// and foreground-service code depend only on it and on the normalized
/// [RealtimeEvent] stream, never on protocol details.
abstract interface class RealtimeTranscriptionClient {
  /// Starts a session with [config]. Resolves once the session is configured
  /// and ready to receive audio (all settings are sent before the first audio
  /// chunk; they lock after that).
  Future<RealtimeSession> startSession(RealtimeSessionConfig config);
}

/// One running realtime transcription session.
abstract interface class RealtimeSession {
  /// Normalized domain events for the session.
  Stream<RealtimeEvent> get events;

  /// Sends one chunk of pcm_s16le mono audio. Chunks sent while the connection
  /// is down are buffered locally and replayed after the reconnect, so callers
  /// never need to care about connection state.
  void sendAudio(Uint8List pcmChunk);

  /// Seconds of audio currently buffered locally (sent while disconnected,
  /// not yet replayed). Zero when connected and caught up.
  double get bufferedAudioSeconds;

  /// Ends the session: sends `input_audio.end`, waits for the final
  /// `transcription.done`, and closes the connection.
  Future<void> end();

  /// Releases all resources. The session cannot be used afterwards.
  Future<void> dispose();
}
