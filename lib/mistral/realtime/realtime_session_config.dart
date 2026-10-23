import 'dart:convert';
import 'dart:typed_data';

/// Configuration for one realtime transcription session.
///
/// A Voxtral 3 realtime session takes `diarize` XOR `turn_detection` — setting
/// both returns an error event — and locks all settings once the first audio
/// chunk arrives, so the full config is fixed at session start.
class RealtimeSessionConfig {
  RealtimeSessionConfig({
    this.sampleRate = 16000,
    this.targetStreamingDelayMs = 480,
    this.language,
    this.contextBias = const [],
    this.diarize = false,
    this.turnDetection,
    this.speakerReferences = const {},
  }) {
    if (diarize && turnDetection != null) {
      throw ArgumentError(
        'diarize and turn_detection are mutually exclusive in one realtime '
        'session',
      );
    }
    if (speakerReferences.isNotEmpty && !diarize) {
      throw ArgumentError('speaker_references require diarize=true');
    }
    if (speakerReferences.length > 8) {
      throw ArgumentError('At most 8 speaker references are supported');
    }
  }

  /// PCM sample rate of the audio that will be sent. The audio format is always
  /// pcm_s16le mono.
  final int sampleRate;

  /// Speed/accuracy trade-off: any integer from 80 to 1200, or 2400.
  final int targetStreamingDelayMs;

  /// ISO 639-1 language code, or null to let the model detect the language.
  final String? language;

  /// Names and terms the model should spell correctly.
  final List<String> contextBias;

  /// Label each piece of text with its speaker (replaces text deltas with
  /// labelled segment events). Mutually exclusive with [turnDetection].
  final bool diarize;

  /// Know when each speaker turn starts and ends. Mutually exclusive with
  /// [diarize]. Null disables turn detection.
  final TurnDetectionConfig? turnDetection;

  /// Enrolled speakers: name -> reference voice clip (3-15 s). Segments from
  /// a matching voice carry the enrolled name instead of a generic label.
  /// Requires [diarize].
  final Map<String, Uint8List> speakerReferences;

  /// The `session` object of the `session.update` message. Must be sent before
  /// the first audio chunk; settings lock after that.
  Map<String, dynamic> toSessionUpdateJson() {
    final session = <String, dynamic>{
      'audio_format': {'encoding': 'pcm_s16le', 'sample_rate': sampleRate},
      'target_streaming_delay_ms': targetStreamingDelayMs,
    };
    if (language != null) {
      session['language'] = language;
    }
    if (contextBias.isNotEmpty) {
      session['context_bias'] = contextBias;
    }
    if (diarize) {
      session['diarize'] = true;
    }
    if (turnDetection != null) {
      session['turn_detection'] = turnDetection!.toJson();
    }
    if (speakerReferences.isNotEmpty) {
      session['speaker_references'] = {
        for (final entry in speakerReferences.entries)
          entry.key: base64Encode(entry.value),
      };
    }
    return session;
  }
}

/// Turn detection thresholds. Only non-default values are sent; an empty
/// object applies the API defaults.
class TurnDetectionConfig {
  const TurnDetectionConfig({
    this.startThreshold = 0.5,
    this.eagerEndThreshold = 0.5,
    this.endThreshold = 0.33,
    this.minSilenceMs = 500,
    this.endTimeoutMs = 3000,
  });

  final double startThreshold;
  final double eagerEndThreshold;
  final double endThreshold;
  final int minSilenceMs;
  final int endTimeoutMs;

  static const TurnDetectionConfig _defaults = TurnDetectionConfig();

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (startThreshold != _defaults.startThreshold) {
      json['start_threshold'] = startThreshold;
    }
    if (eagerEndThreshold != _defaults.eagerEndThreshold) {
      json['eager_end_threshold'] = eagerEndThreshold;
    }
    if (endThreshold != _defaults.endThreshold) {
      json['end_threshold'] = endThreshold;
    }
    if (minSilenceMs != _defaults.minSilenceMs) {
      json['min_silence_ms'] = minSilenceMs;
    }
    if (endTimeoutMs != _defaults.endTimeoutMs) {
      json['end_timeout_ms'] = endTimeoutMs;
    }
    return json;
  }
}
