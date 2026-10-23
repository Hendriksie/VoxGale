import '../transcript.dart';

/// Normalized domain events emitted by a [RealtimeSession].
///
/// The API speaks protocol events (`transcription.text.delta`,
/// `transcription.segment`, `turn.*`, ...); this layer normalizes both session
/// modes into one event stream so UI and service code never see protocol
/// shapes and never branch on session mode (design decision D1).
sealed class RealtimeEvent {
  const RealtimeEvent();
}

/// A realtime session became ready with these applied settings. Emitted on the
/// initial connect and again after every reconnect.
final class SessionStarted extends RealtimeEvent {
  const SessionStarted(this.appliedSettings);

  final Map<String, dynamic> appliedSettings;
}

/// A piece of new transcript text (session without diarization).
class TextDelta extends RealtimeEvent {
  const TextDelta(this.text);

  final String text;
}

/// A piece of transcript text labelled with its speaker (session with
/// diarization). Carries a few words at a time, no timestamps.
class SpeakerSegment extends RealtimeEvent {
  const SpeakerSegment({required this.text, required this.speakerId});

  final String text;
  final String speakerId;
}

/// The user started speaking.
class TurnStarted extends RealtimeEvent {
  const TurnStarted(this.timeS);

  final double timeS;
}

/// The user has probably finished (may resume).
class TurnEagerEnd extends RealtimeEvent {
  const TurnEagerEnd(this.timeS);

  final double timeS;
}

/// The user went on after an eager end.
class TurnResumed extends RealtimeEvent {
  const TurnResumed(this.timeS);

  final double timeS;
}

/// The turn is over. [endReason] is `threshold` or `timeout`.
class TurnEnded extends RealtimeEvent {
  const TurnEnded({required this.timeS, required this.endReason});

  final double timeS;
  final String endReason;
}

/// The connection dropped and was re-established. Audio sent while
/// disconnected was buffered locally and replayed; already-emitted text is
/// never corrected or duplicated (deltas are append-only).
final class Reconnected extends RealtimeEvent {
  const Reconnected({this.dropReason});

  /// Why the previous connection dropped, when known (stream error/close
  /// text with the WebSocket close code). Carried here — not only in the
  /// preceding [RealtimeError] — so the drop cause survives even if that
  /// event is lost.
  final String? dropReason;
}

/// The locally buffered audio finished replaying into the re-established
/// session. Emitted once per reconnect, after [Reconnected].
final class BufferedAudioReplayed extends RealtimeEvent {
  const BufferedAudioReplayed(this.seconds);

  /// How many seconds of buffered audio were replayed.
  final double seconds;
}

/// The session finished: the transcript of record.
final class TranscriptionDone extends RealtimeEvent {
  const TranscriptionDone({
    required this.fullText,
    required this.segments,
    required this.language,
    required this.model,
    required this.usage,
  });

  final String fullText;
  final List<TranscriptSegment> segments;
  final String? language;
  final String model;
  final Usage usage;
}

/// An error from the API or the connection. The message is sanitized and never
/// contains the API key.
final class RealtimeError extends RealtimeEvent {
  const RealtimeError({required this.message, this.code});

  final String message;
  final String? code;
}

/// Parses one JSON message from the realtime WebSocket into a domain event.
///
/// Returns null for messages handled internally (`session.created`), for
/// unknown event types (forward compatibility), and for malformed messages.
RealtimeEvent? parseRealtimeEvent(Map<String, dynamic> json) {
  switch (json['type']) {
    case 'session.updated':
      return SessionStarted(
        (json['session'] as Map<String, dynamic>?) ?? const {},
      );
    case 'transcription.text.delta':
      return TextDelta(json['text'] as String? ?? '');
    case 'transcription.segment':
      return SpeakerSegment(
        text: json['text'] as String? ?? '',
        speakerId: json['speaker_id'] as String? ?? '',
      );
    case 'turn.start':
      return TurnStarted((json['time_s'] as num?)?.toDouble() ?? 0);
    case 'turn.eager_end':
      return TurnEagerEnd((json['time_s'] as num?)?.toDouble() ?? 0);
    case 'turn.resume':
      return TurnResumed((json['time_s'] as num?)?.toDouble() ?? 0);
    case 'turn.end':
      return TurnEnded(
        timeS: (json['time_s'] as num?)?.toDouble() ?? 0,
        endReason: json['end_reason'] as String? ?? '',
      );
    case 'transcription.done':
      final segments = (json['segments'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TranscriptSegment.fromJson)
          .toList();
      return TranscriptionDone(
        fullText: json['text'] as String? ?? '',
        segments: segments,
        language: json['language'] as String?,
        model: json['model'] as String? ?? '',
        usage: Usage.fromJson(
          (json['usage'] as Map<String, dynamic>?) ?? const {},
        ),
      );
    case 'error':
      final error = json['error'];
      return RealtimeError(
        message: error is Map<String, dynamic>
            ? error['message'] as String? ?? 'Unknown transcription error'
            : 'Unknown transcription error',
        code: error is Map<String, dynamic> ? error['code'] as String? : null,
      );
    default:
      return null;
  }
}
