// The live session screen — the app's home (design P1-D6/D7, tasks 5.1-5.4):
// the screen renders [LiveSessionState] directly and owns no session logic;
// every action goes through [LiveSessionController]. The status row carries
// the elapsed time, the estimated cost (live) or the actual usage (after the
// stop, including the post-session pass's), and the subtle connection-status
// indicator. The transcript is turn-grouped with provisional-vs-finalized
// styling and visible gap markers (transcript_widgets.dart).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/live_session_controller.dart';
import '../session/session_providers.dart';
import 'debug_hub_screen.dart';
import 'file_transcription_screen.dart';
import 'formatters.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'transcript_widgets.dart';

/// The live session screen: the app's home in Phase 1 (design P1-D6). The
/// spike harness and the debug-only API key entry live behind the debug-only
/// route opened from the app bar's debug action (a `kDebugMode` const —
/// release builds fold it out).
class LiveSessionScreen extends ConsumerWidget {
  const LiveSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveSessionControllerProvider);
    final controller = ref.read(liveSessionControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voxtral Live'),
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: RecordingIndicator(
              recording: state.phase == LiveSessionPhase.active,
              paused: state.phase == LiveSessionPhase.paused,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Transcribe a file',
            icon: const Icon(Icons.audio_file_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const FileTranscriptionScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const HistoryScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
          if (kDebugMode)
            IconButton(
              tooltip: 'Debug menu',
              icon: const Icon(Icons.bug_report_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DebugHubScreen(),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StatusRow(state: state),
            if (state.batteryPromptNeeded)
              _BatteryPromptBanner(onOpenSettings: controller.openBatterySettings),
            if (state.hasError)
              _ErrorBanner(
                state: state,
                onOpenSettings: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
              ),
            Expanded(
              child: TranscriptView(
                turns: state.turns,
                gapMarkers: state.gapMarkers,
                autoScroll: state.phase == LiveSessionPhase.active,
              ),
            ),
            _PassSection(state: state, controller: controller),
            _ControlsBar(state: state, controller: controller),
          ],
        ),
      ),
    );
  }
}

/// The status row under the app bar: elapsed time (duration once the session
/// ended), the live cost estimate or the actual billed usage, and the subtle
/// connection-status indicator — outside the transcript text
/// (live-transcription spec).
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.state});

  final LiveSessionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = switch (state.phase) {
      LiveSessionPhase.starting ||
      LiveSessionPhase.active ||
      LiveSessionPhase.paused ||
      LiveSessionPhase.stopping =>
        true,
      _ => false,
    };
    final seconds = running ? state.elapsedSeconds : state.durationSeconds;
    final cost = _costText(state, running: running);
    final connection = _connectionInfo(state.connection);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            formatElapsed(seconds),
            style: theme.textTheme.titleMedium,
          ),
          if (cost != null) ...[
            const SizedBox(width: 8),
            Text(
              cost,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const Spacer(),
          if (connection != null)
            Flexible(child: _ConnectionChip(info: connection)),
        ],
      ),
    );
  }

  /// The cost text: the live estimate while running; the actual billed
  /// usage after the stop, with the post-session pass's actuals alongside
  /// when it ran (cost-indicator spec).
  static String? _costText(LiveSessionState state, {required bool running}) {
    if (running) {
      return 'est. ${formatCost(state.estimatedCost)}';
    }
    final billed = state.realtimeBilledSeconds;
    final actual = state.realtimeActualCost;
    if (billed == null || actual == null) {
      return null;
    }
    final passBilled = state.passBilledSeconds;
    final passActual = state.passActualCost;
    final passPart = passBilled != null && passActual != null
        ? ' · pass $passBilled s · ${formatCost(passActual)}'
        : '';
    return '$billed s billed · ${formatCost(actual)}$passPart';
  }

  /// The connection-status text for the subtle indicator, or null when the
  /// stream had no interruption.
  static ({String text, bool dropped})? _connectionInfo(ConnectionStatus c) {
    final parts = <String>[
      if (c.reconnectCount > 0)
        c.reconnectCount == 1
            ? 'Reconnected'
            : 'Reconnected ×${c.reconnectCount}',
      if (c.lastReplayedSeconds != null)
        'Replayed ${c.lastReplayedSeconds!.toStringAsFixed(1)} s',
      if (c.lastDroppedSeconds != null)
        'Dropped ${c.lastDroppedSeconds!.toStringAsFixed(1)} s',
    ];
    if (parts.isEmpty) {
      return null;
    }
    return (text: parts.join(' · '), dropped: c.lastDroppedSeconds != null);
  }
}

/// The subtle connection-status chip (reconnects, buffered-audio replay,
/// dropped audio) — rendered outside the transcript text.
class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.info});

  final ({String text, bool dropped}) info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = info.dropped
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          info.dropped ? Icons.cloud_off : Icons.cloud_sync,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            info.text,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// The error surface: a fatal error card in the error phase; a slim warning
/// row for a transient error while the session runs. The API key is never
/// displayed — only saved/not-saved states (and never the value itself).
/// A missing key gets an open-settings action (the settings screen owns key
/// entry since Phase 2 — the debug-only entry is gone).
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.state, required this.onOpenSettings});

  final LiveSessionState state;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fatal = state.phase == LiveSessionPhase.error;
    final containerColor =
        fatal ? theme.colorScheme.errorContainer : theme.colorScheme.tertiaryContainer;
    final onContainerColor = fatal
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onTertiaryContainer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: containerColor,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                fatal ? Icons.error_outline : Icons.warning_amber_outlined,
                color: onContainerColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.error,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onContainerColor,
                      ),
                    ),
                    if (fatal && state.missingApiKey)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TextButton(
                          onPressed: onOpenSettings,
                          child: const Text('Open settings'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The battery-restriction prompt (live-transcription spec): shown when the
/// app is not exempt from battery optimization — background capture may be
/// killed with the screen off. Dismissible; never blocks the session. The
/// action deep-links to the system battery settings.
class _BatteryPromptBanner extends StatefulWidget {
  const _BatteryPromptBanner({required this.onOpenSettings});

  /// Opens the system battery-optimization settings.
  final Future<void> Function() onOpenSettings;

  @override
  State<_BatteryPromptBanner> createState() => _BatteryPromptBannerState();
}

class _BatteryPromptBannerState extends State<_BatteryPromptBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.battery_alert_outlined,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Allow unrestricted battery use',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    icon: const Icon(Icons.close),
                    color: theme.colorScheme.onSecondaryContainer,
                    onPressed: () => setState(() => _dismissed = true),
                  ),
                ],
              ),
              Text(
                'Background capture may be killed while the screen is off '
                'unless the app is exempt from battery restrictions.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => widget.onOpenSettings(),
                  child: const Text('Open battery settings'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The post-session pass section (design P1-D5, task 5.3): the offer with its
/// estimated cost and the run/skip actions; the running progress; the failure
/// error with a retry. In the done phase the pass's actual usage shows in the
/// status row, next to the realtime actuals.
class _PassSection extends StatelessWidget {
  const _PassSection({required this.state, required this.controller});

  final LiveSessionState state;
  final LiveSessionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (state.phase) {
      case LiveSessionPhase.passOffered:
        return _PassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add speaker labels', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Post-session pass · est. '
                '${formatCost(state.passEstimatedCost ?? 0)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => controller.skipDiarizationPass(),
                    child: const Text('Skip'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: mistralOrange,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => controller.runDiarizationPass(),
                    child: const Text('Run'),
                  ),
                ],
              ),
            ],
          ),
        );
      case LiveSessionPhase.passRunning:
        return _PassCard(
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 12),
              Text(
                'Adding speaker labels…',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        );
      case LiveSessionPhase.passFailed:
        return _PassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The speaker-attribution pass failed: ${state.error}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => controller.runDiarizationPass(),
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
        );
      case LiveSessionPhase.idle ||
          LiveSessionPhase.starting ||
          LiveSessionPhase.active ||
          LiveSessionPhase.paused ||
          LiveSessionPhase.stopping ||
          LiveSessionPhase.finalizing ||
          LiveSessionPhase.done ||
          LiveSessionPhase.error:
        return const SizedBox.shrink();
    }
  }
}

/// The pass card wrapper.
class _PassCard extends StatelessWidget {
  const _PassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}

/// The session controls (task 5.2): start/stop/pause/resume with the
/// enablement the controller's state machine dictates — a progress indicator
/// while a lifecycle transition is in flight; Start (the orange CTA) when no
/// capture is in flight; Stop plus Pause/Resume while capturing.
class _ControlsBar extends StatelessWidget {
  const _ControlsBar({required this.state, required this.controller});

  final LiveSessionState state;
  final LiveSessionController controller;

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case LiveSessionPhase.starting ||
          LiveSessionPhase.stopping ||
          LiveSessionPhase.finalizing ||
          LiveSessionPhase.passRunning:
        return const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        );
      case LiveSessionPhase.idle ||
          LiveSessionPhase.active ||
          LiveSessionPhase.paused ||
          LiveSessionPhase.passOffered ||
          LiveSessionPhase.done ||
          LiveSessionPhase.passFailed ||
          LiveSessionPhase.error:
        break;
    }
    final capturing =
        state.phase == LiveSessionPhase.active || state.phase == LiveSessionPhase.paused;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (state.phase == LiveSessionPhase.active)
            IconButton.filledTonal(
              tooltip: 'Pause',
              icon: const Icon(Icons.pause),
              onPressed: () => controller.pause(),
            ),
          if (state.phase == LiveSessionPhase.paused)
            IconButton.filled(
              tooltip: 'Resume',
              icon: const Icon(Icons.play_arrow),
              onPressed: () => controller.resume(),
            ),
          if (state.phase == LiveSessionPhase.active ||
              state.phase == LiveSessionPhase.paused)
            const SizedBox(width: 12),
          if (capturing)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
              onPressed: () => controller.stop(),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: mistralOrange,
                foregroundColor: Colors.black,
              ),
              icon: const Icon(Icons.mic),
              label: const Text('Start'),
              onPressed: () => controller.start(),
            ),
        ],
      ),
    );
  }
}
