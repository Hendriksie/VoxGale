// Session models shared by the live-session UI and the capture service
// (design P1-D1/D2, tasks 3.1-3.3): the turn-grouped transcript model, the
// capture lifecycle, and the service-to-UI protocol (commands + events with
// their JSON serialization).

import 'dart:convert';

import '../mistral/mistral.dart';

/// One turn of the live transcript as grouped UI-side by the session
/// controller (design P1-D7).
class TranscriptTurn {
  const TranscriptTurn({
    this.speakerLabel,
    this.text = '',
    this.isProvisional = true,
  });

  /// Speaker label (`speaker_1`, ...), or null without diarization.
  final String? speakerLabel;

  /// Text accumulated for this turn from text deltas / speaker segments.
  final String text;

  /// True while the turn carries provisional live text; false once the
  /// post-session diarization pass finalized the transcript.
  final bool isProvisional;

  TranscriptTurn copyWith({
    String? speakerLabel,
    String? text,
    bool? isProvisional,
  }) =>
      TranscriptTurn(
        speakerLabel: speakerLabel ?? this.speakerLabel,
        text: text ?? this.text,
        isProvisional: isProvisional ?? this.isProvisional,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranscriptTurn &&
          speakerLabel == other.speakerLabel &&
          text == other.text &&
          isProvisional == other.isProvisional;

  @override
  int get hashCode => Object.hash(speakerLabel, text, isProvisional);
}

/// Capture lifecycle of a live session (design P1-D7). The post-session pass
/// states (pass-offered, pass-running, done, pass-failed) belong to the
/// session controller (group 4), which extends this lifecycle.
enum SessionState {
  /// No session running.
  idle,

  /// The capture service is starting (permissions checked, service starting).
  starting,

  /// Capturing and transcribing.
  active,

  /// Paused by the user: capture and transcription paused, the realtime
  /// session stays open (design P1-D2).
  paused,

  /// Stop requested; the graceful end is in flight.
  stopping,

  /// The service ended; the final transcript is being persisted.
  finalizing,

  /// The session ended; the provisional transcript is saved.
  ended,

  /// An unrecoverable error ended the session.
  error,
}

/// A command from the UI isolate to the capture service, sent over the
/// plugin's data channel as its [wireValue] (design P1-D2).
enum CaptureCommand {
  /// Pause capture and transcription; the session stays open.
  pause('pause'),

  /// Resume a paused session.
  resume('resume'),

  /// End the session gracefully and stop the service.
  stop('stop');

  const CaptureCommand(this.wireValue);

  /// The value sent with `FlutterForegroundTask.sendDataToTask`.
  final String wireValue;

  /// Parses a value received from the UI isolate; null for unknown commands.
  static CaptureCommand? fromWire(Object? data) => switch (data) {
        'pause' => pause,
        'resume' => resume,
        'stop' => stop,
        _ => null,
      };
}

/// The typed subset of session events the UI isolate needs, forwarded from
/// the capture service isolate over the plugin's data channel as JSON
/// (design P1-D1): the service owns capture and transcription, the UI only
/// renders this stream.
sealed class SessionEvent {
  const SessionEvent();

  /// Wire form: a JSON object with a `type` discriminator.
  Map<String, dynamic> toJson();

  /// Decodes [json]. Throws [FormatException] for unknown event types.
  static SessionEvent fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'text_delta':
        return SessionTextDelta(json['text'] as String? ?? '');
      case 'speaker_segment':
        return SessionSpeakerSegment(
          text: json['text'] as String? ?? '',
          speakerId: json['speaker_id'] as String? ?? '',
        );
      case 'turn_started':
        return SessionTurnStarted((json['time_s'] as num?)?.toDouble() ?? 0);
      case 'turn_ended':
        return SessionTurnEnded(
          timeS: (json['time_s'] as num?)?.toDouble() ?? 0,
          endReason: json['end_reason'] as String? ?? '',
        );
      case 'reconnected':
        return SessionReconnected(dropReason: json['drop_reason'] as String?);
      case 'buffered_audio_replayed':
        return SessionBufferedAudioReplayed(
          (json['seconds'] as num?)?.toDouble() ?? 0,
        );
      case 'buffered_audio_dropped':
        return SessionBufferedAudioDropped(
          (json['seconds'] as num?)?.toDouble() ?? 0,
        );
      case 'transcription_done':
        return SessionTranscriptionDone(
          fullText: json['full_text'] as String? ?? '',
          segments: _segmentsFromJson(json['segments']),
          language: json['language'] as String?,
          model: json['model'] as String? ?? '',
          usage: _usageFromJson(json['usage']),
        );
      case 'session_ended':
        return SessionEnded(
          sessionId: json['session_id'] as String? ?? '',
          audioPath: json['audio_path'] as String? ?? '',
          fullText: json['full_text'] as String? ?? '',
          segments: _segmentsFromJson(json['segments']),
          language: json['language'] as String?,
          model: json['model'] as String? ?? '',
          usage: _usageFromJson(json['usage']),
        );
      case 'error':
        return SessionError(json['message'] as String? ?? '');
      default:
        throw FormatException('Unknown session event type: ${json['type']}');
    }
  }

  /// Decodes a payload received over the plugin's data channel (a JSON
  /// string), or null when the payload is not a session event.
  static SessionEvent? fromWire(Object? data) {
    if (data is! String) {
      return null;
    }
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  static List<TranscriptSegment> _segmentsFromJson(Object? json) {
    if (json is! List) {
      return const [];
    }
    return [
      for (final item in json)
        if (item is Map<String, dynamic>) TranscriptSegment.fromJson(item),
    ];
  }

  static Usage _usageFromJson(Object? json) {
    return Usage.fromJson(json is Map<String, dynamic> ? json : const {});
  }
}

/// A piece of new provisional transcript text.
final class SessionTextDelta extends SessionEvent {
  const SessionTextDelta(this.text);

  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'text_delta', 'text': text};
}

/// A piece of transcript text labelled with its speaker.
final class SessionSpeakerSegment extends SessionEvent {
  const SessionSpeakerSegment({required this.text, required this.speakerId});

  final String text;
  final String speakerId;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'speaker_segment',
        'text': text,
        'speaker_id': speakerId,
      };
}

/// The user started speaking.
final class SessionTurnStarted extends SessionEvent {
  const SessionTurnStarted(this.timeS);

  /// Start time in seconds within the session audio.
  final double timeS;

  @override
  Map<String, dynamic> toJson() => {'type': 'turn_started', 'time_s': timeS};
}

/// The turn is over.
final class SessionTurnEnded extends SessionEvent {
  const SessionTurnEnded({required this.timeS, required this.endReason});

  /// End time in seconds within the session audio.
  final double timeS;

  /// Why the turn ended (`threshold` or `timeout`).
  final String endReason;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'turn_ended',
        'time_s': timeS,
        'end_reason': endReason,
      };
}

/// The transcription stream reconnected after a drop. Already-displayed text
/// is never rewritten; the transcript shows a marker for the interruption.
final class SessionReconnected extends SessionEvent {
  const SessionReconnected({this.dropReason});

  /// Why the previous connection dropped (close code/reason), when known.
  final String? dropReason;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'reconnected',
        'drop_reason': dropReason,
      };
}

/// Buffered audio finished replaying into the re-established stream.
final class SessionBufferedAudioReplayed extends SessionEvent {
  const SessionBufferedAudioReplayed(this.seconds);

  /// How many seconds of buffered audio were replayed.
  final double seconds;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'buffered_audio_replayed',
        'seconds': seconds,
      };
}

/// Buffered audio was dropped because the reconnect buffer exceeded its cap;
/// the transcript shows a visible gap where the audio was lost.
final class SessionBufferedAudioDropped extends SessionEvent {
  const SessionBufferedAudioDropped(this.seconds);

  /// How many seconds of buffered audio were dropped.
  final double seconds;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'buffered_audio_dropped',
        'seconds': seconds,
      };
}

/// The realtime session finished: the transcript of record as reported by
/// `transcription.done`.
final class SessionTranscriptionDone extends SessionEvent {
  const SessionTranscriptionDone({
    required this.fullText,
    required this.segments,
    this.language,
    required this.model,
    required this.usage,
  });

  final String fullText;
  final List<TranscriptSegment> segments;
  final String? language;
  final String model;
  final Usage usage;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'transcription_done',
        'full_text': fullText,
        'segments': [for (final s in segments) _segmentToJson(s)],
        'language': language,
        'model': model,
        'usage': _usageToJson(usage),
      };
}

/// The capture session ended. Carries everything the UI needs to persist the
/// record via `SessionRepository` (group 4 wires that): the session id, the
/// audio path, the final transcript (full text + segments), and the usage.
final class SessionEnded extends SessionEvent {
  const SessionEnded({
    required this.sessionId,
    required this.audioPath,
    required this.fullText,
    required this.segments,
    this.language,
    required this.model,
    required this.usage,
  });

  /// Stable session id; also the file name of the session audio.
  final String sessionId;

  /// Absolute path of the session audio WAV in app-private storage.
  final String audioPath;

  final String fullText;
  final List<TranscriptSegment> segments;
  final String? language;
  final String model;
  final Usage usage;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'session_ended',
        'session_id': sessionId,
        'audio_path': audioPath,
        'full_text': fullText,
        'segments': [for (final s in segments) _segmentToJson(s)],
        'language': language,
        'model': model,
        'usage': _usageToJson(usage),
      };
}

/// An error from the capture service. The message is sanitized and never
/// contains the API key.
final class SessionError extends SessionEvent {
  const SessionError(this.message);

  final String message;

  @override
  Map<String, dynamic> toJson() => {'type': 'error', 'message': message};
}

Map<String, dynamic> _segmentToJson(TranscriptSegment segment) => {
      'text': segment.text,
      'start': segment.start,
      'end': segment.end,
      'speaker_id': segment.speakerId,
    };

Map<String, dynamic> _usageToJson(Usage usage) => {
      'prompt_audio_seconds': usage.promptAudioSeconds,
    };

/// Maps a normalized [RealtimeEvent] from the Mistral layer to the session
/// event forwarded to the UI isolate, or null for events the UI does not need
/// (the session-ready marker and the provisional turn signals). Pure: no
/// plugin, no IO — unit-testable.
SessionEvent? sessionEventFromRealtime(RealtimeEvent event) {
  switch (event) {
    case TextDelta(:final text):
      return SessionTextDelta(text);
    case SpeakerSegment(:final text, :final speakerId):
      return SessionSpeakerSegment(text: text, speakerId: speakerId);
    case TurnStarted(:final timeS):
      return SessionTurnStarted(timeS);
    case TurnEagerEnd() || TurnResumed():
      return null; // provisional turn signals carry no display text
    case TurnEnded(:final timeS, :final endReason):
      return SessionTurnEnded(timeS: timeS, endReason: endReason);
    case Reconnected(:final dropReason):
      return SessionReconnected(dropReason: dropReason);
    case BufferedAudioReplayed(:final seconds):
      return SessionBufferedAudioReplayed(seconds);
    case BufferedAudioDropped(:final seconds):
      return SessionBufferedAudioDropped(seconds);
    case TranscriptionDone(
          :final fullText,
          :final segments,
          :final language,
          :final model,
          :final usage,
        ):
      return SessionTranscriptionDone(
        fullText: fullText,
        segments: segments,
        language: language,
        model: model,
        usage: usage,
      );
    case RealtimeError(:final message):
      return SessionError(message);
    case SessionStarted():
      return null; // the UI started the service; no event needed
  }
}
