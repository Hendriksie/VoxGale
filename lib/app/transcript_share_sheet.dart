// The shared transcript actions (change 2026-11-01-post-session-actions,
// design decisions 2-3): the export bottom sheet (the plain-text / Markdown
// chooser + the `transcriptExportProvider` share call) and the send-to-agent
// confirm dialog, extracted from the history detail screen so the live
// screen's post-session card reuses the exact same flows — no duplicated
// behavior. The share step stays behind the injectable
// `transcriptExportProvider`, so no platform channel is touched in widget
// tests.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mistral/mistral.dart';
import '../session/session_providers.dart';
import '../storage/storage.dart';
import 'transcript_export.dart';

/// Shows the plain-text / Markdown export chooser for [record] and shares the
/// chosen export via [transcriptExportProvider] (transcript-history spec:
/// export via the share sheet). Used by both the history detail screen and
/// the live screen's post-session card.
Future<void> showTranscriptExportSheet(
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

/// The send-to-agent confirmation dialog (agent-integration spec): it states
/// the data flow — a one-shot conversation, nothing stored server-side,
/// billed per token under the user's API key, the agent runs with its own
/// tools. Returns whether the send should run.
Future<bool> showSendToAgentConfirmDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Send to agent?'),
      content: const Text(
        'The full transcript is sent to your agent as a one-shot '
        'conversation; no conversation history is kept. The call is '
        'billed per token under your API key, and the agent runs with its '
        'own tools.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Send'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// The shared send-to-agent prompt flow (agent-integration spec): without a
/// selected agent the user is pointed to Settings and nothing is sent;
/// otherwise the confirm dialog runs. Returns whether the send should run.
Future<bool> confirmSendToAgent(BuildContext context, WidgetRef ref) async {
  final agentId = await ref.read(agentIdProvider.future);
  if (!context.mounted) {
    return false;
  }
  if (agentId == null || agentId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Select an agent in Settings first.')),
    );
    return false;
  }
  return showSendToAgentConfirmDialog(context);
}
