// The transcript widgets of the live session screen (design P1-D7, task
// 5.1): the turn-grouped transcript with provisional-vs-finalized styling,
// the visible gap markers where buffered audio was dropped, and the pulsing
// orange recording indicator. The screen renders LiveSessionState; these
// widgets own no session logic.

import 'package:flutter/material.dart';

import '../session/session_models.dart';
import 'error_states.dart';
import 'theme.dart';

/// The turn-grouped transcript: provisional (streaming) turns in a lighter,
/// italic style; the finalized diarized transcript solid. Gap markers render
/// as dimmed, italic marker rows at the position of each drop. Auto-scrolls
/// to the latest text while [autoScroll] is set (the session is active).
class TranscriptView extends StatefulWidget {
  const TranscriptView({
    super.key,
    required this.turns,
    required this.gapMarkers,
    this.autoScroll = false,
    this.emptyMessage = 'Start a session to see the live transcript.',
  });

  /// The turn-grouped transcript (see [LiveSessionState.turns]).
  final List<TranscriptTurn> turns;

  /// The gap markers (see [LiveSessionState.gapMarkers]).
  final List<TranscriptGap> gapMarkers;

  /// Whether to keep the view scrolled to the latest text.
  final bool autoScroll;

  /// The empty state's message when there are no turns — the caller picks
  /// the wording appropriate to its context (the live screen's idle state
  /// invites starting a session; a session that has run simply has no
  /// transcript yet).
  final String emptyMessage;

  @override
  State<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends State<TranscriptView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TranscriptView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.turns != widget.turns || oldWidget.gapMarkers != widget.gapMarkers;
    if (widget.autoScroll && changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = transcriptItems(widget.turns, widget.gapMarkers);
    if (items.isEmpty) {
      // The empty-transcript state (empty-error-states spec): guidance, not
      // a blank area. The wording comes from [emptyMessage] — the live
      // screen's idle state invites starting a session; a session that has
      // run shows a plain "no transcript yet".
      return EmptyStateView(
        icon: Icons.mic_none,
        message: widget.emptyMessage,
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }
}

/// Flattens the turns and gap markers into the transcript's item list: each
/// turn block followed by the gap markers recorded at its position; markers
/// recorded before any turn existed render at the top.
List<Widget> transcriptItems(
  List<TranscriptTurn> turns,
  List<TranscriptGap> gapMarkers,
) {
  final items = <Widget>[
    for (final gap in gapMarkers.where((g) => g.afterTurnIndex < 0))
      GapMarkerRow(
        key: ValueKey('gap-top-${gap.droppedSeconds}'),
        droppedSeconds: gap.droppedSeconds,
      ),
  ];
  for (var i = 0; i < turns.length; i++) {
    items.add(TranscriptTurnBlock(key: ValueKey('turn-$i'), turn: turns[i]));
    for (final gap in gapMarkers.where((g) => g.afterTurnIndex == i)) {
      items.add(
        GapMarkerRow(
          key: ValueKey('gap-$i-${gap.droppedSeconds}'),
          droppedSeconds: gap.droppedSeconds,
        ),
      );
    }
  }
  // Defensive: a marker past the last turn renders at the bottom.
  for (final gap in gapMarkers.where((g) => g.afterTurnIndex >= turns.length)) {
    items.add(
      GapMarkerRow(
        key: ValueKey('gap-end-${gap.droppedSeconds}'),
        droppedSeconds: gap.droppedSeconds,
      ),
    );
  }
  return items;
}

/// One turn of the transcript: a speaker chip above the block when the turn
/// carries a label, and the text — lighter and italic while provisional, solid
/// once the post-session pass finalized the transcript.
class TranscriptTurnBlock extends StatelessWidget {
  const TranscriptTurnBlock({super.key, required this.turn});

  /// The turn to render.
  final TranscriptTurn turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provisional = turn.isProvisional;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (turn.speakerLabel != null) ...[
            _SpeakerChip(label: turn.speakerLabel!),
            const SizedBox(height: 4),
          ],
          Text(
            turn.text,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: provisional
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
              fontStyle: provisional ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}

/// The speaker chip above a labelled turn block.
class _SpeakerChip extends StatelessWidget {
  const _SpeakerChip({required this.label});

  /// The speaker label (`speaker_1`, ...).
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// The visible gap marker at the point where buffered audio was dropped
/// (live-transcription spec): a dimmed, italic marker row.
class GapMarkerRow extends StatelessWidget {
  const GapMarkerRow({super.key, required this.droppedSeconds});

  /// How many seconds of audio could not be recovered.
  final double droppedSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(
            Icons.report_problem_outlined,
            size: 16,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '— ${droppedSeconds.toStringAsFixed(1)} s of audio could not be '
              'recovered —',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The recording indicator in the app bar: unmistakable while recording — a
/// pulsing orange dot (~1 s loop, Mistral orange); a static paused icon while
/// paused; a static hollow dot otherwise. Owns its pulse animation.
class RecordingIndicator extends StatefulWidget {
  const RecordingIndicator({
    super.key,
    required this.recording,
    required this.paused,
  });

  /// Whether the session is actively capturing (the pulsing state).
  final bool recording;

  /// Whether the session is paused (the static paused-icon state).
  final bool paused;

  @override
  State<RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<RecordingIndicator>
    with SingleTickerProviderStateMixin {
  static const Duration _pulsePeriod = Duration(seconds: 1);

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: _pulsePeriod,
  )..repeat(reverse: true);

  @override
  void didUpdateWidget(covariant RecordingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recording != oldWidget.recording) {
      if (widget.recording) {
        _pulse.repeat(reverse: true);
      } else {
        _pulse.stop();
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.paused) {
      return Semantics(
        label: 'Paused',
        child: Icon(
          Icons.pause_circle_outline,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    if (!widget.recording) {
      return Semantics(
        label: 'Not recording',
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: theme.colorScheme.outline),
          ),
        ),
      );
    }
    return Semantics(
      label: 'Recording',
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final opacity = 0.35 + 0.65 * _pulse.value;
          return Container(
            key: const ValueKey('recording-dot'),
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: mistralOrange.withValues(alpha: opacity),
            ),
          );
        },
      ),
    );
  }
}
