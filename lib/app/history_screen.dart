// The transcript history screen (design P2-D6, task 5.2): the saved
// transcripts — live sessions and file transcriptions — newest first, with
// full-text search, per-entry source (live session or imported file name),
// model, and actual cost, plus delete-all. Tapping an entry opens its detail
// view. The screen renders the repository through providers and owns no
// logic.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mistral/mistral.dart';
import '../session/session_providers.dart';
import '../storage/storage.dart';
import 'formatters.dart';
import 'history_detail_screen.dart';

/// The transcript history screen (transcript-history spec): the app's
/// history list. Reachable from the live session screen's app bar.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(historyListProvider);
    final query = ref.watch(historySearchQueryProvider);
    final config = ref.watch(mistralConfigProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            tooltip: 'Delete all history',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => _confirmDeleteAll(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search transcripts',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) =>
                    ref.read(historySearchQueryProvider.notifier).set(value),
              ),
            ),
            Expanded(
              child: sessionsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Could not load history: $error',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                data: (sessions) {
                  if (sessions.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          query.isEmpty
                              ? 'No transcripts yet.'
                              : 'No transcripts match your search.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: sessions.length,
                    itemBuilder: (context, index) => _HistoryTile(
                      session: sessions[index],
                      config: config,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete all history?'),
        content: const Text(
          'Every transcript and its locally stored audio are removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(sessionRepositoryProvider).deleteAllSessions();
      ref.invalidate(historyListProvider);
    }
  }
}

/// One history entry: source (live session or file name), date, duration,
/// model, and the actual cost when known (transcript-history spec: each
/// entry identifies its source and model).
class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.session, required this.config});

  final StoredSession session;
  final MistralConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isFile = session.source == StoredSession.sourceFile;
    return ListTile(
      leading: Icon(
        isFile ? Icons.audio_file_outlined : Icons.mic_none,
        color: theme.colorScheme.primary,
      ),
      title: Text(isFile ? (session.sourceFileName ?? 'File') : 'Live session'),
      subtitle: Text(
        '${formatDateTime(session.startedAt)} · '
        '${formatElapsed(session.durationSeconds)} · '
        '${modelLabel(session.model, config)}',
      ),
      trailing: session.actualCost != null
          ? Text(
              formatCost(session.actualCost!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HistoryDetailScreen(sessionId: session.id),
        ),
      ),
    );
  }
}
