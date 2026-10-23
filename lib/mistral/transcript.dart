// Value objects shared by the realtime and batch transcription clients.

/// One labelled segment of a transcript.
class TranscriptSegment {
  const TranscriptSegment({
    required this.text,
    this.start,
    this.end,
    this.speakerId,
  });

  final String text;

  /// Start time in seconds, or null when the source carries no timestamps
  /// (realtime segments arrive without start/end).
  final double? start;

  /// End time in seconds, or null as above.
  final double? end;

  /// Speaker label (`speaker_1`, an enrolled name, ...), or null when the
  /// transcript was produced without diarization.
  final String? speakerId;

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      text: json['text'] as String? ?? '',
      start: (json['start'] as num?)?.toDouble(),
      end: (json['end'] as num?)?.toDouble(),
      speakerId: json['speaker_id'] as String?,
    );
  }
}

/// Billed usage reported by the API.
class Usage {
  const Usage({this.promptAudioSeconds});

  /// Duration of audio the model processed, in seconds — the billed quantity
  /// for per-minute audio pricing. Null when the API did not report it.
  final int? promptAudioSeconds;

  factory Usage.fromJson(Map<String, dynamic> json) {
    final seconds = json['prompt_audio_seconds'];
    return Usage(
      promptAudioSeconds: seconds is num ? seconds.round() : null,
    );
  }
}
