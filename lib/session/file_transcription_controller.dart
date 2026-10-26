// The file transcription controller (design P2-D1/D2/D5, tasks 4.1-4.3): a
// Riverpod notifier owning the file-mode state machine
// idle → picked → running → done / error. It picks an audio file through the
// [AudioFilePicker] seam, probes its duration through the
// [AudioDurationProber] seam so the pre-upload cost estimate uses the real
// duration, offers the per-file model choice (defaulting to the settings
// preference), runs the batch transcription with diarization through the
// [BatchTranscriptionClient] interface, and saves the finished transcript to
// history with its source file name, model, and billed usage. The API key
// itself is never read here — only its presence; the key is read inside the
// lib/mistral/ clients only.

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../mistral/mistral.dart';
import '../storage/storage.dart';
import 'capture_service.dart';
import 'session_models.dart';
import 'session_providers.dart';

/// The phase of the file transcription flow (design P2-D1).
enum FileTranscriptionPhase {
  /// No file picked.
  idle,

  /// A file is picked; its duration is probed and the estimate is shown.
  picked,

  /// The transcription request is in flight.
  running,

  /// The transcription finished; the result (and its actual usage) shows.
  done,

  /// The transcription failed; the picked file is kept for a retry.
  error,
}

/// The immutable, UI-ready state of the file transcription flow.
class FileTranscriptionState {
  const FileTranscriptionState({
    this.phase = FileTranscriptionPhase.idle,
    this.fileName,
    this.durationSeconds = 0,
    this.durationKnown = false,
    this.selectedModel,
    this.estimatedCost = 0,
    this.elapsedSeconds = 0,
    this.turns = const [],
    this.billedAudioSeconds,
    this.actualCost,
    this.language,
    this.error = '',
    this.missingApiKey = false,
  });

  /// Where the flow is — see [FileTranscriptionPhase].
  final FileTranscriptionPhase phase;

  /// The picked file's name, when a file is picked (kept on error — the
  /// file-transcription spec: errors surface without losing the file).
  final String? fileName;

  /// The picked file's audio duration in seconds, when probed.
  final int durationSeconds;

  /// Whether the duration could be probed (design P2-D2).
  final bool durationKnown;

  /// The batch model id selected for the picked file.
  final String? selectedModel;

  /// The estimated cost in USD: duration-based while picked, accruing with
  /// the elapsed time while running (cost-indicator spec).
  final double estimatedCost;

  /// Elapsed seconds while the transcription runs.
  final int elapsedSeconds;

  /// The speaker-labelled result turns, once done.
  final List<TranscriptTurn> turns;

  /// Audio seconds billed by the API, once done.
  final int? billedAudioSeconds;

  /// The actual cost in USD, once billed seconds are known.
  final double? actualCost;

  /// The detected (or pinned) language, once known.
  final String? language;

  /// The current error message; empty when there is none.
  final String error;

  /// Whether no API key is saved (the key's presence only).
  final bool missingApiKey;

  /// Whether [error] carries a message.
  bool get hasError => error.isNotEmpty;

  FileTranscriptionState copyWith({
    FileTranscriptionPhase? phase,
    String? fileName,
    int? durationSeconds,
    bool? durationKnown,
    String? selectedModel,
    double? estimatedCost,
    int? elapsedSeconds,
    List<TranscriptTurn>? turns,
    int? billedAudioSeconds,
    double? actualCost,
    String? language,
    String? error,
    bool? missingApiKey,
  }) =>
      FileTranscriptionState(
        phase: phase ?? this.phase,
        fileName: fileName ?? this.fileName,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        durationKnown: durationKnown ?? this.durationKnown,
        selectedModel: selectedModel ?? this.selectedModel,
        estimatedCost: estimatedCost ?? this.estimatedCost,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        turns: turns ?? this.turns,
        billedAudioSeconds: billedAudioSeconds ?? this.billedAudioSeconds,
        actualCost: actualCost ?? this.actualCost,
        language: language ?? this.language,
        error: error ?? this.error,
        missingApiKey: missingApiKey ?? this.missingApiKey,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileTranscriptionState &&
          phase == other.phase &&
          fileName == other.fileName &&
          durationSeconds == other.durationSeconds &&
          durationKnown == other.durationKnown &&
          selectedModel == other.selectedModel &&
          estimatedCost == other.estimatedCost &&
          elapsedSeconds == other.elapsedSeconds &&
          billedAudioSeconds == other.billedAudioSeconds &&
          actualCost == other.actualCost &&
          language == other.language &&
          error == other.error &&
          missingApiKey == other.missingApiKey &&
          turns.length == other.turns.length &&
          _turnsEqual(other);

  bool _turnsEqual(FileTranscriptionState other) {
    for (var i = 0; i < turns.length; i++) {
      if (turns[i] != other.turns[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        phase,
        fileName,
        durationSeconds,
        durationKnown,
        selectedModel,
        estimatedCost,
        elapsedSeconds,
        turns.length,
        Object.hashAll(turns),
        billedAudioSeconds,
        actualCost,
        language,
        error,
        missingApiKey,
      );
}

/// One audio file picked from device storage (design P2-D1).
class PickedAudioFile {
  const PickedAudioFile({
    required this.name,
    required this.path,
    required this.bytes,
  });

  /// The file's display name (sent with the upload).
  final String name;

  /// The file's absolute path (probed for its duration).
  final String path;

  /// The file's contents (uploaded).
  final Uint8List bytes;
}

/// The system file picker seam for audio files (design P2-D1). Injected so
/// controller tests never touch the platform channel.
abstract interface class AudioFilePicker {
  /// Opens the system file picker for one audio file; null when the user
  /// cancels.
  Future<PickedAudioFile?> pick();
}

/// [AudioFilePicker] over the `file_picker` plugin (system file picker,
/// audio files only — one file per transcription, per spec).
class FilePickerAudioFilePicker implements AudioFilePicker {
  @override
  Future<PickedAudioFile?> pick() async {
    // file_picker 13: a static pickFile returning the PlatformFile (null on
    // cancel) — the older FilePicker.platform.pickFiles result is gone.
    final file = await FilePicker.pickFile(type: FileType.audio);
    final path = file?.path;
    if (file == null || path == null) {
      return null;
    }
    return PickedAudioFile(
      name: file.name,
      path: path,
      bytes: await file.xFile.readAsBytes(),
    );
  }
}

/// The audio-duration prober seam (design P2-D2): reads a picked file's
/// duration so the pre-upload cost estimate uses the real duration. Injected
/// so controller tests never touch the platform media APIs.
abstract interface class AudioDurationProber {
  /// The file's audio duration, or null when it cannot be determined.
  Future<Duration?> probe(String path);
}

/// [AudioDurationProber] over `just_audio` (the platform media APIs). Any
/// probing failure (unsupported format, platform error) resolves to null —
/// the estimate then falls back to accruing from the elapsed time while the
/// transcription runs (design P2-D2).
///
/// The raw just_audio call is injectable ([rawProbe]) so the production
/// prober's failure mapping is unit-testable without the platform media
/// APIs; the default raw probe is the just_audio call itself (exercised on a
/// device by the smoke test — in the test environment the platform channel
/// never answers, so the raw call would hang, not throw).
class JustAudioDurationProber implements AudioDurationProber {
  JustAudioDurationProber({Future<Duration?> Function(String path)? rawProbe})
      : _rawProbe = rawProbe ?? probeWithJustAudio;

  final Future<Duration?> Function(String path) _rawProbe;

  /// The raw probe: one just_audio player, disposed after use.
  static Future<Duration?> probeWithJustAudio(String path) async {
    AudioPlayer? player;
    try {
      player = AudioPlayer();
      await player.setFilePath(path);
      return player.duration;
    } finally {
      try {
        await player?.dispose();
      } catch (_) {
        // A disposal failure is not a probing failure.
      }
    }
  }

  @override
  Future<Duration?> probe(String path) async {
    try {
      return await _rawProbe(path);
    } catch (_) {
      return null;
    }
  }
}

/// The file transcription controller (design P2-D1): owns
/// [FileTranscriptionState] and the flow — see the file comment.
class FileTranscriptionController extends Notifier<FileTranscriptionState> {
  @override
  FileTranscriptionState build() {
    ref.onDispose(() {
      _tickSub?.cancel();
    });
    // The key's presence only — the key itself is read inside the
    // lib/mistral/ clients, never here.
    unawaited(_loadKeyPresence());
    return const FileTranscriptionState();
  }

  StreamSubscription<int>? _tickSub;
  Uint8List? _audioBytes;

  Future<void> _loadKeyPresence() async {
    final key = await ref.read(apiKeyStoreProvider).readKey();
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(missingApiKey: key == null || key.isEmpty);
  }

  // -- Public API (the app layer's actions) --------------------------------

  /// Picks an audio file and moves to the picked phase (duration probed,
  /// estimate computed for the default model). A cancelled picker keeps the
  /// current phase. No-op while a transcription is running.
  Future<void> pick() async {
    if (state.phase == FileTranscriptionPhase.running) {
      return;
    }
    final key = await ref.read(apiKeyStoreProvider).readKey();
    if (key == null || key.isEmpty) {
      state = state.copyWith(
        phase: FileTranscriptionPhase.error,
        error: 'No API key saved. Add your Mistral API key in Settings.',
        missingApiKey: true,
      );
      return;
    }
    final picked = await ref.read(audioFilePickerProvider).pick();
    if (picked == null || !ref.mounted) {
      return; // cancelled (or the controller went away)
    }
    _audioBytes = picked.bytes;
    final duration = await ref.read(audioDurationProberProvider).probe(picked.path);
    if (!ref.mounted) {
      return;
    }
    final config = ref.read(mistralConfigProvider);
    final model = await ref.read(defaultBatchModelProvider.future);
    final durationSeconds = duration?.inSeconds ?? 0;
    state = FileTranscriptionState(
      phase: FileTranscriptionPhase.picked,
      fileName: picked.name,
      durationSeconds: durationSeconds,
      durationKnown: duration != null,
      selectedModel: model,
      estimatedCost: duration == null
          ? 0
          : durationSeconds / 60 * config.rateForModel(model),
      missingApiKey: false,
    );
  }

  /// Selects the batch model for the picked file and recomputes the estimate
  /// (file-transcription spec: the model is chosen per file, defaulting to
  /// the settings preference). No-op unless the phase is picked.
  void setModel(String model) {
    if (state.phase != FileTranscriptionPhase.picked) {
      return;
    }
    final config = ref.read(mistralConfigProvider);
    state = state.copyWith(
      selectedModel: model,
      estimatedCost: state.durationKnown
          ? state.durationSeconds / 60 * config.rateForModel(model)
          : 0,
    );
  }

  /// Transcribes the picked file with diarization and saves the result to
  /// history. Runs from the picked phase; a retry runs from the error phase
  /// (the picked file is kept). No-op while running.
  Future<void> transcribe() async {
    final phase = state.phase;
    if (phase != FileTranscriptionPhase.picked &&
        phase != FileTranscriptionPhase.error) {
      return;
    }
    final bytes = _audioBytes;
    final fileName = state.fileName;
    final model = state.selectedModel;
    if (bytes == null || fileName == null || model == null) {
      return;
    }
    state = state.copyWith(
      phase: FileTranscriptionPhase.running,
      error: '',
      elapsedSeconds: 0,
      estimatedCost: 0,
    );
    _tickSub = ref.read(sessionClockProvider).ticks().listen((_) => _onTick());
    try {
      final client = await ref.read(batchTranscriptionClientProvider.future);
      final language = await ref.read(languageHintProvider.future);
      final config = ref.read(mistralConfigProvider);
      final startedAt = ref.read(sessionClockProvider).now();
      final result = await client.transcribe(
        BatchTranscriptionRequest(
          model: model,
          audioBytes: bytes,
          fileName: fileName,
          diarize: true,
          language: language,
          // The client bounds a stalled call proportionally to the audio
          // length — transcribe must fail, never hang forever.
          audioDuration:
              state.durationKnown ? Duration(seconds: state.durationSeconds) : null,
        ),
      );
      final billed = result.usage.promptAudioSeconds;
      final actualCost =
          billed == null ? null : billed / 60 * config.rateForModel(model);
      final durationSeconds =
          state.durationKnown && state.durationSeconds > 0
              ? state.durationSeconds
              : billed ?? 0;
      // Save to history (file-transcription spec: saved with the source file
      // name, the model, and the billed usage).
      final repository = ref.read(sessionRepositoryProvider);
      final sessionId = CaptureService.newSessionId();
      await repository.saveSession(
        StoredSession(
          id: sessionId,
          startedAt: startedAt,
          durationSeconds: durationSeconds,
          model: model,
          status: SessionStatus.finalized,
          billedAudioSeconds: billed,
          actualCost: actualCost,
          language: result.language,
          source: StoredSession.sourceFile,
          sourceFileName: fileName,
        ),
        <StoredSegment>[
          for (var i = 0; i < result.segments.length; i++)
            StoredSegment(
              sessionId: sessionId,
              order: i,
              text: result.segments[i].text,
              speakerLabel: result.segments[i].speakerId,
              startSeconds: result.segments[i].start,
              endSeconds: result.segments[i].end,
            ),
        ],
      );
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        phase: FileTranscriptionPhase.done,
        turns: _resultTurns(result),
        billedAudioSeconds: billed,
        actualCost: actualCost,
        language: result.language,
        durationSeconds: durationSeconds,
      );
    } on MistralApiException catch (e) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        phase: FileTranscriptionPhase.error,
        error: e.message,
      );
    } catch (e) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        phase: FileTranscriptionPhase.error,
        error: 'The file transcription failed: $e',
      );
    } finally {
      await _tickSub?.cancel();
      _tickSub = null;
    }
  }

  // -- Internals -------------------------------------------------------------

  void _onTick() {
    if (state.phase != FileTranscriptionPhase.running) {
      return;
    }
    final config = ref.read(mistralConfigProvider);
    final model = state.selectedModel;
    if (model == null) {
      return;
    }
    final elapsed = state.elapsedSeconds + 1;
    state = state.copyWith(
      elapsedSeconds: elapsed,
      // The estimate accrues with the elapsed time while the transcription
      // runs (cost-indicator spec).
      estimatedCost: elapsed / 60 * config.rateForModel(model),
    );
  }

  /// The labelled turns of a finished transcription (the provisional flag is
  /// false: the batch result is the transcript of record).
  static List<TranscriptTurn> _resultTurns(BatchTranscriptionResult result) {
    if (result.segments.isNotEmpty) {
      return <TranscriptTurn>[
        for (final segment in result.segments)
          TranscriptTurn(
            speakerLabel: segment.speakerId,
            text: segment.text,
            isProvisional: false,
          ),
      ];
    }
    if (result.text.isNotEmpty) {
      return <TranscriptTurn>[
        TranscriptTurn(text: result.text, isProvisional: false),
      ];
    }
    return const [];
  }
}
