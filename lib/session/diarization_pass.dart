// The post-session diarization pass (design P1-D5, task 4.3): a one-shot
// batch transcription with diarize=true over the saved session audio,
// orchestrated in the UI isolate after the live session ends. The pass is
// offered with its estimated cost, replaces the provisional transcript with
// the speaker-labelled result on success (deleting the session audio), and
// preserves the provisional transcript with an error state on failure, so it
// can be retried.

import 'dart:io';
import 'dart:math';

import '../mistral/mistral.dart';
import '../storage/storage.dart';
import 'wav_file_writer.dart';

/// Bytes per second of audio in the session WAV: 16 kHz × mono × 2 bytes
/// (PCM16) — the format [WavFileWriter] records.
int get _wavBytesPerSecond =>
    WavFileWriter.sampleRate *
    WavFileWriter.numChannels *
    WavFileWriter.bitsPerSample ~/
    8;

/// Size of the RIFF/WAVE header [WavFileWriter] writes before the audio data.
const int _wavHeaderBytes = 44;

/// The audio duration of the session WAV at [path], in seconds: the data
/// bytes (the 44-byte header excluded) divided by the byte rate.
Future<double> wavAudioDurationSeconds(String path) async {
  final dataBytes = max(0, await File(path).length() - _wavHeaderBytes);
  return dataBytes / _wavBytesPerSecond;
}

/// The outcome of a successful diarization pass.
class DiarizationPassResult {
  const DiarizationPassResult({
    required this.text,
    required this.segments,
    required this.billedAudioSeconds,
    required this.actualCost,
    this.language,
  });

  /// The full transcript text without labels.
  final String text;

  /// The speaker-labelled, timestamped segments that replaced the
  /// provisional transcript.
  final List<TranscriptSegment> segments;

  /// Audio seconds billed by the pass — the pass's billed quantity.
  final int billedAudioSeconds;

  /// The pass's actual cost in USD (billed seconds × the batch Mini rate).
  final double actualCost;

  /// The language reported by the batch API, when reported.
  final String? language;
}

/// Orchestrates the post-session diarization pass (design P1-D5): one batch
/// transcription of the saved session audio with diarization on, persisted
/// over the provisional transcript. Small and testable: the Mistral layer
/// and the repository are injected, so tests mock them and never hit the
/// live API.
class DiarizationPass {
  DiarizationPass({
    required this.client,
    required this.repository,
    required this.config,
  });

  final BatchTranscriptionClient client;
  final SessionRepository repository;
  final MistralConfig config;

  /// The estimated cost of running the pass on the session audio at
  /// [audioPath]: the audio's duration times the configured per-minute rate
  /// of the batch Mini model the pass uses (cost-indicator spec).
  Future<double> estimateCost(String audioPath) async {
    final seconds = await wavAudioDurationSeconds(audioPath);
    return seconds / 60 * config.batchMiniRatePerMinute;
  }

  /// Runs the pass on the saved session audio: transcribes it with
  /// `diarize=true` and the batch Mini model, replaces the session's
  /// provisional transcript with the speaker-labelled segments (persisted,
  /// marking the session final and recording the pass's billed totals), and
  /// deletes the audio file. Resolves with the outcome; throws — leaving the
  /// provisional transcript and the audio in place — when the request or the
  /// persistence fails, so the pass can be retried (a retry re-reads the
  /// saved audio file).
  Future<DiarizationPassResult> run({
    required String sessionId,
    required String audioPath,
    String? language,
  }) async {
    final audioBytes = await File(audioPath).readAsBytes();
    final result = await client.transcribe(
      BatchTranscriptionRequest(
        model: config.batchMiniModel,
        audioBytes: audioBytes,
        fileName: '$sessionId.wav',
        diarize: true,
        language: language,
      ),
    );
    final segments = <StoredSegment>[
      for (var i = 0; i < result.segments.length; i++)
        StoredSegment(
          sessionId: sessionId,
          order: i,
          text: result.segments[i].text,
          speakerLabel: result.segments[i].speakerId,
          startSeconds: result.segments[i].start,
          endSeconds: result.segments[i].end,
        ),
    ];
    final billedAudioSeconds = result.usage.promptAudioSeconds ?? 0;
    final actualCost = billedAudioSeconds / 60 * config.batchMiniRatePerMinute;
    await repository.replaceTranscript(
      sessionId,
      segments,
      billedAudioSeconds: billedAudioSeconds,
      actualCost: actualCost,
    );
    // Delete the session audio after a successful pass (speaker-attribution
    // spec). The stored session row keeps its audio path — the repository
    // has no "clear audio path" operation; a stale path is harmless (the
    // history delete checks the file's existence) and Phase 2 owns the
    // re-offer/delete UI over it.
    final audio = File(audioPath);
    if (await audio.exists()) {
      await audio.delete();
    }
    return DiarizationPassResult(
      text: result.text,
      segments: result.segments,
      billedAudioSeconds: billedAudioSeconds,
      actualCost: actualCost,
      language: result.language,
    );
  }
}
