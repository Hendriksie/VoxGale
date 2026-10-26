// The transcript history detail screen (design P2-D6/D7, tasks 5.3-5.4):
// one transcript's metadata header (date, duration, source, model, actual
// cost when known), the speaker-labelled transcript (reusing the transcript
// widgets), the export action (plain text or Markdown via the share sheet),
// the delete action, and the re-offer of a skipped or failed post-session
// diarization pass with its estimated cost. The screen renders
// [HistoryDetailState] and owns no logic.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mistral/mistral.dart';
import '../session/history_detail_controller.dart';
import '../session/session_models.dart';
import '../session/session_providers.dart';
import '../storage/storage.dart';
import 'formatters.dart';
import 'theme.dart';
import 'transcript_export.dart';
import 'transcript_widgets.dart';

/// The history detail screen: one saved transcript (transcript-history and
/// speaker-attribution specs).
class HistoryDetailScreen extends ConsumerWidget {
  const HistoryDetailScreen({super.key, required this.sessionId});

  /// The session id of the transcript to show.
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(historyDetailControllerProvider(sessionId));
    final controller =
        ref.read(historyDetailControllerProvider(sessionId).notifier);
    final config = ref.watch(mistralConfigProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcript'),
        actions: [
          IconButton(
            tooltip: 'Export',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: state.record == null
                ? null
                : () => _showExportSheet(context, ref, state.record!, config),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: state.record == null
                ? null
                : () => _confirmDelete(context, controller),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (state.loading) {
          true => const Center(child: CircularProgressIndicator()),
          false => state.record == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'This transcript is no longer available.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _DetailBody(
                  state: state,
                  controller: controller,
                  config: config,
                ),
        },
      ),
    );
  }

  Future<void> _showExportSheet(
    BuildContext context,
    WidgetRef ref,
    StoredSessionRecord record,
    MistralConfig config,
  ) async {
    final markdown = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: const Text('Plain text'),
              onTap: () => Navigator.of(context).pop(false),
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Markdown'),
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (markdown == null || !context.mounted) {
      return;
    }
    try {
      await ref.read(transcriptExportProvider)(
        record,
        config,
        markdown: markdown,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export the transcript: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    HistoryDetailController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete transcript?'),
        content: const Text(
          'The transcript and its locally stored audio are removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await controller.delete();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

/// The detail body: the metadata header, the pass re-offer (when
/// applicable), and the transcript.
class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.state,
    required this.controller,
    required this.config,
  });

  final HistoryDetailState state;
  final HistoryDetailController controller;
  final MistralConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = state.record!.session;
    final segments = state.record!.segments;
    final isFile = session.source == StoredSession.sourceFile;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isFile
                    ? (session.sourceFileName ?? 'File')
                    : 'Live session',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${formatDateTime(session.startedAt)} · '
                '${formatElapsed(session.durationSeconds)} · '
                '${modelLabel(session.model, config)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (session.actualCost != null) ...[
                const SizedBox(height: 2),
                Text(
                  session.billedAudioSeconds != null
                      ? '${session.billedAudioSeconds} s billed · '
                          '${formatCost(session.actualCost!)}'
                      : formatCost(session.actualCost!),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (state.retainedAudioPath != null)
          _PassReofferCard(state: state, controller: controller),
        Expanded(
          child: segments.isEmpty
              ? Center(
                  child: Text(
                    'The transcript is empty.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : TranscriptView(
                  turns: <TranscriptTurn>[
                    for (final segment in segments)
                      TranscriptTurn(
                        speakerLabel: segment.speakerLabel,
                        text: segment.text,
                        isProvisional: false,
                      ),
                  ],
                  gapMarkers: const [],
                ),
        ),
      ],
    );
  }
}

/// The re-offer card (speaker-attribution spec): a provisional session whose
/// audio is retained offers the post-session diarization pass again, with its
/// estimated cost; running it replaces the transcript and deletes the audio.
class _PassReofferCard extends StatelessWidget {
  const _PassReofferCard({required this.state, required this.controller});

  final HistoryDetailState state;
  final HistoryDetailController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add speaker labels',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                state.passEstimatedCost != null
                    ? 'Post-session pass · est. '
                        '${formatCost(state.passEstimatedCost!)}'
                    : 'Post-session pass on the retained audio',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (state.hasError) ...[
                const SizedBox(height: 8),
                Text(
                  state.error,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: state.passRunning
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: mistralOrange,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () => controller.runPass(),
                        child: const Text('Run'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
