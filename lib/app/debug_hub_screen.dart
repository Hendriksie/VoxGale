import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../spike/background_spike_screen.dart';
import '../spike/batch_spike_screen.dart';
import '../spike/live_spike_screen.dart';
import '../spike/spike_providers.dart';

/// The debug-only hub (design P1-D6, task 5.5): the Phase-0 spike harness
/// and the debug-only API key entry, moved off the home screen (the live
/// session screen is home now). Reachable only from the live screen's app
/// bar debug action, which is shown only when `kDebugMode` (a const —
/// release builds fold it out).
///
/// The harness stays because the deferred Spike C probes (API limits, speaker
/// reference clips) still need it; removing it is a later change (with Phase
/// 2 file mode). The API key entry is DEBUG-ONLY: the real settings screen
/// (with key validation) is a Phase 2 feature. The key is only ever written
/// to secure storage at runtime — never to source control, logs, or crash
/// reports — and is never displayed (only saved/not-saved).
class DebugHubScreen extends ConsumerWidget {
  const DebugHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keyAsync = ref.watch(apiKeyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Debug menu')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Phase 0 — spike harness (debug only)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'These screens prove the core paths against the live Mistral API '
            'with your own key. They are kept for the deferred Spike C probes; '
            'removal is a later change.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.mic),
            title: const Text('Spike A — live transcription'),
            subtitle: const Text('Mic to realtime WebSocket, both session modes'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LiveSpikeScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync),
            title: const Text('Spike B — background capture'),
            subtitle: const Text('Foreground service, screen-off capture'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BackgroundSpikeScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.audio_file),
            title: const Text('Spike C — batch transcription'),
            subtitle: const Text('File to speaker-labelled transcript'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BatchSpikeScreen()),
            ),
          ),
          if (kDebugMode) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.vpn_key),
              title: const Text('API key (debug)'),
              subtitle: Text(
                keyAsync.when(
                  data: (key) =>
                      key == null || key.isEmpty ? 'not saved' : 'saved',
                  loading: () => 'checking…',
                  error: (_, _) => 'error',
                ),
              ),
              onTap: () => _showApiKeyDialog(context, ref),
            ),
          ],
        ],
      ),
    );
  }

  /// Debug-only key entry. The key is saved to secure storage at runtime and
  /// never leaves the device except to `api.mistral.ai` over TLS (the client
  /// layer attaches it to the Authorization header only).
  Future<void> _showApiKeyDialog(BuildContext context, WidgetRef ref) async {
    final store = ref.read(apiKeyStoreProvider);
    final outcome = await showDialog<String?>(
      context: context,
      builder: (_) => _ApiKeyDialog(
        onSave: (key) async {
          await store.saveKey(key);
          ref.invalidate(apiKeyProvider);
        },
        onClear: () async {
          await store.deleteKey();
          ref.invalidate(apiKeyProvider);
        },
      ),
    );
    if (outcome != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(outcome)));
    }
  }
}

/// The debug key-entry dialog. Owns its [TextEditingController] so the
/// controller is disposed with the dialog, not while it is still animating
/// out.
class _ApiKeyDialog extends StatefulWidget {
  const _ApiKeyDialog({required this.onSave, required this.onClear});

  final Future<void> Function(String key) onSave;
  final Future<void> Function() onClear;

  @override
  State<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<_ApiKeyDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mistral API key (debug only)'),
      content: TextField(
        controller: _controller,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: 'API key',
          hintText: 'sk-…',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            // Look up the Navigator before the async gap.
            final navigator = Navigator.of(context);
            await widget.onClear();
            if (mounted) {
              navigator.pop('API key cleared');
            }
          },
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final key = _controller.text.trim();
            // Look up the Navigator before the async gap.
            final navigator = Navigator.of(context);
            if (key.isEmpty) {
              if (mounted) {
                navigator.pop();
              }
              return;
            }
            await widget.onSave(key);
            if (mounted) {
              navigator.pop('API key saved to secure storage');
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
