import 'dart:typed_data';

import '../transcript.dart';

/// Client for the Mistral batch (file) transcription REST API.
///
/// All Mistral API code lives behind this interface (design decision D2).
abstract interface class BatchTranscriptionClient {
  /// Transcribes one audio file. Resolves with the speaker-labelled transcript
  /// when [BatchTranscriptionRequest.diarize] is set.
  Future<BatchTranscriptionResult> transcribe(BatchTranscriptionRequest request);
}

/// One batch transcription request.
class BatchTranscriptionRequest {
  const BatchTranscriptionRequest({
    required this.model,
    required this.audioBytes,
    required this.fileName,
    this.diarize = true,
    this.language,
    this.contextBias = const [],
    this.speakerReferences = const {},
    this.returnLanguage = false,
    this.audioDuration,
  });

  /// Batch model ID (Mini or Small Transcribe 3).
  final String model;

  /// The audio file contents.
  final Uint8List audioBytes;

  /// File name sent with the upload.
  final String fileName;

  /// Label each segment with its speaker. Requires segment timestamps, which
  /// the client always requests when diarization is on.
  final bool diarize;

  /// ISO 639-1 language code, or null to let the model detect the language.
  final String? language;

  /// Names and terms the model should spell correctly (repeated form field).
  final List<String> contextBias;

  /// Enrolled speakers: name -> reference voice clip (3-15 s). Requires
  /// [diarize].
  final Map<String, Uint8List> speakerReferences;

  /// Ask the API to report the detected language in the response.
  final bool returnLanguage;

  /// The audio's duration, when the caller knows it. The client uses it to
  /// bound the request's receive timeout proportionally to the audio length,
  /// so a stalled call fails instead of hanging forever.
  final Duration? audioDuration;
}

/// The result of a batch transcription.
class BatchTranscriptionResult {
  const BatchTranscriptionResult({
    required this.text,
    required this.segments,
    required this.language,
    required this.model,
    required this.usage,
  });

  /// The full transcript without labels.
  final String text;

  /// Labelled, timestamped segments (empty unless requested).
  final List<TranscriptSegment> segments;

  /// The detected or pinned language, when reported.
  final String? language;

  final String model;

  /// Billed usage; [Usage.promptAudioSeconds] is the billed quantity.
  final Usage usage;

  factory BatchTranscriptionResult.fromJson(Map<String, dynamic> json) {
    final segments = (json['segments'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TranscriptSegment.fromJson)
        .toList();
    return BatchTranscriptionResult(
      text: json['text'] as String? ?? '',
      segments: segments,
      language: json['language'] as String?,
      model: json['model'] as String? ?? '',
      usage: Usage.fromJson(
        (json['usage'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}
