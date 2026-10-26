import 'package:flutter/material.dart';

import '../spike/background_spike_screen.dart';
import '../spike/batch_spike_screen.dart';
import '../spike/live_spike_screen.dart';

/// The debug-only hub (design P1-D6, task 5.5): the Phase-0 spike harness,
/// moved off the home screen (the live session screen is home now).
/// Reachable only from the live screen's app bar debug action, which is
/// shown only when `kDebugMode` (a const — release builds fold it out).
///
/// The harness stays because the deferred Spike C probes (API limits, speaker
/// reference clips) still need it; removing it is a later change. The API
/// key entry that used to live here is gone — the production settings screen
/// (Phase 2, with key validation) replaced it.
class DebugHubScreen extends StatelessWidget {
  const DebugHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
        ],
      ),
    );
  }
}
