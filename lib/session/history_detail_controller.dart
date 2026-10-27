// The history detail controller (design P2-D6/D7, tasks 5.3-5.4): a
// Riverpod family notifier owning one transcript's detail state — the stored
// record, the re-offerable post-session pass (with its estimated cost), and
// the delete. The pass re-offer (speaker-attribution spec) reuses
// [DiarizationPass]: it is offered for a provisional session whose audio
// file still exists, and running it replaces the provisional transcript and
// deletes the audio on success, exactly as at session end.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mistral/mistral.dart';
import '../storage/storage.dart';
import 'session_providers.dart';

/// The history detail state for one session (design P2-D6/D7).
class HistoryDetailState {
  const HistoryDetailState({
    this.loading = true,
    this.record,
    this.retainedAudioPath,
    this.passEstimatedCost,
    this.passRunning = false,
    this.error = '',
  });

  /// Whether the record is being loaded.
  final bool loading;

  /// The stored session with its segments, once loaded (null when the
  /// session is gone — e.g. deleted elsewhere).
  final StoredSessionRecord? record;

  /// The retained session audio's path, when a skipped or failed pass can be
  /// re-offered (a provisional session whose audio file still exists).
  final String? retainedAudioPath;

  /// The re-offered pass's estimated cost, when it could be computed.
  final double? passEstimatedCost;

  /// Whether the re-offered pass is running.
  final bool passRunning;

  /// The current error message (the pass failure); empty when there is none.
  final String error;

  /// Whether [error] carries a message.
  bool get hasError => error.isNotEmpty;

  HistoryDetailState copyWith({
    bool? loading,
    StoredSessionRecord? record,
    String? retainedAudioPath,
    double? passEstimatedCost,
    bool? passRunning,
    String? error,
  }) =>
      HistoryDetailState(
        loading: loading ?? this.loading,
        record: record ?? this.record,
        retainedAudioPath: retainedAudioPath ?? this.retainedAudioPath,
        passEstimatedCost: passEstimatedCost ?? this.passEstimatedCost,
        passRunning: passRunning ?? this.passRunning,
        error: error ?? this.error,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistoryDetailState &&
          loading == other.loading &&
          record == other.record &&
          retainedAudioPath == other.retainedAudioPath &&
          passEstimatedCost == other.passEstimatedCost &&
          passRunning == other.passRunning &&
          error == other.error;

  @override
  int get hashCode => Object.hash(
        loading,
        record,
        retainedAudioPath,
        passEstimatedCost,
        passRunning,
        error,
      );
}

/// The history detail controller (design P2-D6/D7): owns
/// [HistoryDetailState] for one session id. The provider is an auto-dispose
/// family — the controller is constructed with the session id.
class HistoryDetailController extends Notifier<HistoryDetailState> {
  HistoryDetailController(this.sessionId);

  /// The session id of the transcript to show.
  final String sessionId;

  @override
  HistoryDetailState build() {
    unawaited(_load());
    return const HistoryDetailState();
  }

  /// Loads the record and, for a provisional session with retained audio,
  /// the re-offerable pass with its estimated cost.
  Future<void> _load() async {
    final record =
        await ref.read(sessionRepositoryProvider).loadSession(sessionId);
    if (!ref.mounted) {
      return;
    }
    if (record == null) {
      state = const HistoryDetailState(loading: false);
      return;
    }
    // The re-offer (speaker-attribution spec): a provisional session whose
    // audio file still exists can run the pass again. The file-existence
    // check matters — a successful pass leaves a stale audioPath in the row
    // (the repository has no "clear audio path" operation).
    String? retained;
    if (record.session.status == SessionStatus.provisional &&
        record.session.audioPath != null) {
      final path = record.session.audioPath!;
      if (await File(path).exists()) {
        retained = path;
      }
    }
    double? estimate;
    if (retained != null) {
      try {
        final pass = await ref.read(diarizationPassProvider.future);
        estimate = await pass.estimateCost(retained);
      } catch (_) {
        // The offer still shows; the estimate is best-effort.
        estimate = null;
      }
    }
    if (!ref.mounted) {
      return;
    }
    state = HistoryDetailState(
      loading: false,
      record: record,
      retainedAudioPath: retained,
      passEstimatedCost: estimate,
    );
  }

  /// Runs the re-offered pass (speaker-attribution spec): replaces the
  /// provisional transcript with the labelled result and deletes the audio
  /// on success; on failure keeps the provisional transcript with an error
  /// and a retry.
  Future<void> runPass() async {
    final record = state.record;
    final audioPath = state.retainedAudioPath;
    if (record == null || audioPath == null || state.passRunning) {
      return;
    }
    state = state.copyWith(passRunning: true, error: '');
    try {
      final pass = await ref.read(diarizationPassProvider.future);
      await pass.run(
        sessionId: record.session.id,
        audioPath: audioPath,
        language: record.session.language,
      );
      if (!ref.mounted) {
        return;
      }
      // The session's status and cost changed — the history list (behind
      // this screen) must re-read it.
      ref.invalidate(historyListProvider);
      // Reload: the transcript is replaced, the session is final, the audio
      // is gone — the offer disappears.
      await _load();
    } on MistralApiException catch (e) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(passRunning: false, error: e.message);
    } catch (e) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        passRunning: false,
        error: 'The speaker-attribution pass failed: $e',
      );
    }
  }

  /// Deletes the transcript (and its locally stored audio,
  /// transcript-history spec). The screen pops afterwards.
  Future<void> delete() async {
    final id = state.record?.session.id;
    if (id == null) {
      return;
    }
    await ref.read(sessionRepositoryProvider).deleteSession(id);
    ref.invalidate(historyListProvider);
  }
}
