// The file transcription screen (design P2-D1, task 4.3): the file-mode UI
// over [FileTranscriptionState] — idle (pick a file), picked (per-file model
// choice + the pre-upload estimate), running (progress with elapsed time and
// the running estimate — the batch API is one-shot, so no partial text), done
// (the speaker-labelled result with its actual usage), error (the picked file
// is kept for a retry). The screen owns no logic; every action goes through
// [FileTranscriptionController].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mistral/mistral.dart';
import '../session/file_transcription_controller.dart';
import '../session/session_providers.dart';
import 'formatters.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'transcript_widgets.dart';

/// The file transcription screen: the app's file mode (file-transcription
/// spec). Reachable from the live session screen's app bar.
class FileTranscriptionScreen extends ConsumerWidget {
  const FileTranscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fileTranscriptionControllerProvider);
    final controller = ref.read(fileTranscriptionControllerProvider.notifier);
    final config = ref.watch(mistralConfigProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Transcribe a file')),
      body: SafeArea(
        child: switch (state.phase) {
          FileTranscriptionPhase.idle =>
            _IdleView(state: state, controller: controller),
          FileTranscriptionPhase.picked =>
            _PickedView(state: state, controller: controller, config: config),
          FileTranscriptionPhase.running => _RunningView(state: state),
          FileTranscriptionPhase.done => _DoneView(state: state, controller: controller),
          FileTranscriptionPhase.error =>
            _ErrorView(state: state, controller: controller),
        },
      ),
    );
  }
}

/// The idle view: the missing-key banner (with a path to settings) and the
/// pick-a-file call to action.
class _IdleView extends StatelessWidget {
  const _IdleView({required this.state, required this.controller});

  final FileTranscriptionState state;
  final FileTranscriptionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (state.missingApiKey) _MissingKeyBanner(),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.audio_file_outlined,
                    size: 56,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Import an audio file',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'It is transcribed with speaker labels and saved to your '
                    'history.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: mistralOrange,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => controller.pick(),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Pick an audio file'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The missing-key banner (settings spec: transcription screens show a
/// missing-key state) with an open-settings action.
class _MissingKeyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.vpn_key_off,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No API key saved. Add your Mistral API key in Settings.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
                child: const Text('Open settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The picked view: the file card, the per-file model choice, the pre-upload
/// estimate, and the transcribe action.
class _PickedView extends StatelessWidget {
  const _PickedView({
    required this.state,
    required this.controller,
    required this.config,
  });

  final FileTranscriptionState state;
  final FileTranscriptionController controller;
  final MistralConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.audio_file,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.fileName ?? '',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.durationKnown
                            ? formatElapsed(state.durationSeconds)
                            : 'Duration unknown',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Model', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: config.batchMiniModel,
              label: const Text('Mini'),
              tooltip: 'Cheaper batch transcription',
            ),
            ButtonSegment(
              value: config.batchSmallModel,
              label: const Text('Small'),
              tooltip: 'Flagship transcription and diarization',
            ),
          ],
          selected: {state.selectedModel ?? config.batchMiniModel},
          onSelectionChanged: (selection) =>
              controller.setModel(selection.first),
        ),
        const SizedBox(height: 16),
        Text(
          state.durationKnown
              ? 'Estimated cost: ${formatCost(state.estimatedCost)}'
              : 'The estimate accrues while the transcription runs.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => controller.pick(),
              child: const Text('Choose a different file'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: mistralOrange,
                foregroundColor: Colors.black,
              ),
              onPressed: () => controller.transcribe(),
              child: const Text('Transcribe'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The running view: progress with the elapsed time and the running estimate.
/// The batch API is one-shot, so no partial transcript text is shown
/// (file-transcription spec).
class _RunningView extends StatelessWidget {
  const _RunningView({required this.state});

  final FileTranscriptionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Transcribing ${state.fileName ?? 'the file'}…',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '${formatElapsed(state.elapsedSeconds)} · '
              'est. ${formatCost(state.estimatedCost)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The done view: the actual usage and the speaker-labelled result (reusing
/// the transcript widgets), saved to history.
class _DoneView extends StatelessWidget {
  const _DoneView({required this.state, required this.controller});

  final FileTranscriptionState state;
  final FileTranscriptionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final billed = state.billedAudioSeconds;
    final actual = state.actualCost;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '${state.fileName ?? ''} · ${formatElapsed(state.durationSeconds)}',
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              if (billed != null && actual != null)
                Text(
                  '$billed s billed · ${formatCost(actual)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Saved to history.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: state.turns.isEmpty
              ? Center(
                  child: Text(
                    'The transcript is empty.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : TranscriptView(
                  turns: state.turns,
                  gapMarkers: const [],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => controller.pick(),
                child: const Text('Transcribe another file'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The error view: the error, the picked file kept (file-transcription spec:
/// errors surface without losing the selected file), and the retry / re-pick
/// actions.
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.state, required this.controller});

  final FileTranscriptionState state;
  final FileTranscriptionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'The file transcription failed',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              state.error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            if (state.fileName != null) ...[
              const SizedBox(height: 8),
              Text(
                state.fileName!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => controller.pick(),
                  child: const Text('Choose a different file'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => controller.transcribe(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
