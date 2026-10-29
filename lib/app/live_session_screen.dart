// The live session screen — the app's home (design P1-D6/D7, tasks 5.1-5.4):
// the screen renders [LiveSessionState] directly and owns no session logic;
// every action goes through [LiveSessionController]. The status row carries
// the elapsed time, the estimated cost (live) or the actual usage (after the
// stop, including the post-session pass's), the pause indication (worded
// differently when another app took audio focus), and the subtle
// connection-status indicator. The transcript is turn-grouped with
// provisional-vs-finalized styling and visible gap markers
// (transcript_widgets.dart). The screen also presents the update dialog
// when the update check controller publishes a newer release (change
// 2026-10-29-update-tracker, tasks 6.1-6.2, design decision 10).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/live_session_controller.dart';
import '../session/session_providers.dart';
import '../update/update_check_controller.dart';
import '../update/update_dialog.dart';
import '../update/update_providers.dart';
import 'error_states.dart';
import 'file_transcription_screen.dart';
import 'formatters.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'transcript_widgets.dart';

/// The live session screen: the app's home (design P1-D6). The Phase-0 spike
/// harness and its debug-only route were removed in Phase 4 — the app bar
/// carries only the production actions (file transcription, history, settings).
/// A [WidgetsBindingObserver] re-checks the battery exemption when the app
/// returns to the foreground, so the battery prompt dismisses once the user
/// has granted it (live-transcription spec; dogfood friction 2026-10-28).
class LiveSessionScreen extends ConsumerStatefulWidget {
  const LiveSessionScreen({super.key});

  @override
  ConsumerState<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends ConsumerState<LiveSessionScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The battery exemption may have changed in the system settings
      // while the app was backgrounded.
      unawaited(
        ref
            .read(liveSessionControllerProvider.notifier)
            .recheckBatteryExemption(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveSessionControllerProvider);
    final controller = ref.read(liveSessionControllerProvider.notifier);
    // The throttled, silent update check fires once per app run (design
    // decision 10; the update-tracker spec's "Check for a newer release
    // on app start").
    ref.watch(updateCheckOnStartProvider);
    // Present the update dialog when a check publishes a newer version
    // (design decision 10; the spec's "Show the update dialog once per
    // version" — the controller already gates on the recording session
    // and the once-per-version notification, and the manual check
    // publishes even when the version was already notified).
    ref.listen<UpdateCheckState>(
      updateCheckControllerProvider,
      (previous, next) {
        final available = next.available;
        if (available != null &&
            available != previous?.available &&
            context.mounted) {
          unawaited(showUpdateDialog(
            context,
            controller: ref.read(updateCheckControllerProvider.notifier),
            info: available,
            installedVersion: next.installedVersion,
          ));
        }
      },
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('VoxGale'),
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
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StatusRow(state: state),
            if (state.batteryPromptNeeded)
              _BatteryPromptBanner(onOpenSettings: controller.openBatterySettings),
            if (state.hasError && state.phase != LiveSessionPhase.error)
              ErrorBanner(
                kind: classifyFailure(state.error),
                message: state.error,
              ),
            Expanded(
              child: state.phase == LiveSessionPhase.error
                  ? _FatalErrorView(state: state, controller: controller)
                  : TranscriptView(
                      turns: state.turns,
                      gapMarkers: state.gapMarkers,
                      autoScroll: state.phase == LiveSessionPhase.active,
                      emptyMessage: _emptyTranscriptMessage(state.phase),
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

/// The empty-transcript message for [phase] (empty-error-states spec): an
/// invitation to start a session only when no session is in flight and the
/// last one did not fail; once a session has run, the transcript area simply
/// has no transcript yet — inviting to "start a session" mid-session or after
/// one ended would be wrong.
String _emptyTranscriptMessage(LiveSessionPhase phase) {
  switch (phase) {
    case LiveSessionPhase.idle:
    case LiveSessionPhase.error:
      return 'Start a session to see the live transcript.';
    case LiveSessionPhase.starting:
    case LiveSessionPhase.active:
    case LiveSessionPhase.paused:
    case LiveSessionPhase.stopping:
    case LiveSessionPhase.finalizing:
    case LiveSessionPhase.done:
    case LiveSessionPhase.passOffered:
    case LiveSessionPhase.passRunning:
    case LiveSessionPhase.passFailed:
      return 'No transcript yet.';
  }
}

/// The status row under the app bar: elapsed time (duration once the session
/// ended), the live cost estimate or the actual billed usage, the pause
/// indication (worded differently when another app took audio focus), and
/// the subtle connection-status indicator — outside the transcript text
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
    // A pause caused by another app taking audio focus (design P3-D2,
    // live-transcription "Respect audio focus") is worded differently from
    // a user pause.
    final pausedText = switch (state.phase) {
      LiveSessionPhase.paused =>
        state.pausedByAudioFocus
            ? 'Paused — another app is using audio'
            : 'Paused',
      _ => null,
    };
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
          if (pausedText != null) ...[
            const SizedBox(width: 8),
            Text(
              pausedText,
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

/// The fatal error surface (empty-error-states spec): a blocking failure
/// ended the flow, so the transcript area shows the full-screen
/// [ErrorStateView] — the shared taxonomy's icon, the state's message, and
/// the remedy action the kind maps to. The API key is never displayed — only
/// saved/not-saved states (and never the value itself). A missing key or a
/// rejected key gets an open-settings action (the settings screen owns key
/// entry since Phase 2 — the debug-only entry is gone); a mic-permission
/// failure re-requests the permission; anything else offers a retry (the
/// controls bar's Start remains available too).
class _FatalErrorView extends StatelessWidget {
  const _FatalErrorView({required this.state, required this.controller});

  final LiveSessionState state;
  final LiveSessionController controller;

  @override
  Widget build(BuildContext context) {
    final kind = classifyFailure(state.error);
    final VoidCallback remedy = switch (kind) {
      FailureKind.missingKey || FailureKind.auth => () =>
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
      FailureKind.micPermissionDenied => () => controller.requestMicPermission(),
      _ => () => controller.start(),
    };
    return ErrorStateView(kind: kind, message: state.error, onRemedy: remedy);
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
