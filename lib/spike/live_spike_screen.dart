// ignore_for_file: avoid_print — spike diagnostics need unthrottled console
// output; debugPrint throttles and drops messages under a reconnect flood.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../mistral/mistral.dart';
import 'spike_providers.dart';
import 'wav_writer.dart';

/// Spike A — realtime path (tasks 3.1–3.3).
///
/// Mic -> record PCM16 stream -> tee (WAV file for the post-session
/// diarization pass + realtime client) -> text on screen. Exercises both
/// session modes (turn detection default, live diarization toggle), shows the
/// elapsed/cost estimate while running, and the actual billed usage from
/// `transcription.done` when the session ends.
///
/// The transcript renders as styled runs: transcribed text in the normal style,
/// diagnostic lines (turn boundaries, reconnects, errors, session info) dimmed
/// and italic so the transcript stays readable. The view auto-scrolls to the
/// latest text, and every diagnostic is also debugPrint'ed so it shows up in
/// the `flutter run` console.
class LiveSpikeScreen extends ConsumerStatefulWidget {
  const LiveSpikeScreen({super.key});

  @override
  ConsumerState<LiveSpikeScreen> createState() => _LiveSpikeScreenState();
}

enum SpikeSessionMode { turnDetection, diarize }

/// One run of the transcript: either transcribed text or a dimmed marker line.
class TranscriptRun {
  TranscriptRun.text(this.text) : isMarker = false;
  TranscriptRun.marker(this.text) : isMarker = true;

  final bool isMarker;
  String text;
}

class _LiveSpikeScreenState extends ConsumerState<LiveSpikeScreen> {
  /// Fixed file name in the app's temp directory; the batch spike reads it by
  /// default so a live session's audio can be diarized afterwards. Phase 1
  /// moves session audio to the app's documents directory.
  static String get sessionWavPath =>
      '${Directory.systemTemp.path}/voxtral_spike_session.wav';

  SpikeSessionMode _mode = SpikeSessionMode.turnDetection;
  bool _running = false;
  bool _starting = false;
  bool _enrollReference = false;
  String? _error;
  final List<TranscriptRun> _runs = [];
  String? _speaker;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  int? _actualAudioSeconds;
  double? _actualCost;
  int _reconnects = 0;

  RealtimeSession? _session;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription<RealtimeEvent>? _eventSub;
  WavFileWriter? _wav;
  final ScrollController _scrollController = ScrollController();

  MistralConfig get _config => ref.read(mistralConfigProvider);

  double get _estimatedCost =>
      _elapsed.inSeconds / 60 * _config.realtimeRatePerMinute;

  Future<void> _start() async {
    // Re-entry guard: the Start button stays enabled until the session is up,
    // and a second tap would start a second session + recorder (their reconnect
    // logs interleave and look like bursts).
    if (_starting || _running) {
      return;
    }
    _starting = true;
    try {
      setState(() {
        _error = null;
        _runs.clear();
        _speaker = null;
        _elapsed = Duration.zero;
        _actualAudioSeconds = null;
        _actualCost = null;
        _reconnects = 0;
      });

      final key = await ref.read(apiKeyStoreProvider).readKey();
      if (key == null || key.isEmpty) {
        setState(() => _error =
            'No API key saved. The settings screen is Phase 2 — for this spike, '
            'save your Mistral API key to secure storage first.');
        return;
      }

      final recorder = AudioRecorder();
      // record requests the RECORD_AUDIO runtime permission natively.
      final granted = await recorder.hasPermission();
      if (!granted) {
        setState(() => _error = 'Microphone permission denied.');
        try {
          await recorder.dispose();
        } catch (_) {}
        return;
      }

      // Speaker references require diarization (task 5.3, realtime mode).
      final references = <String, Uint8List>{};
      if (_mode == SpikeSessionMode.diarize && _enrollReference) {
        references['Alice'] = await _loadAsset(
          'assets/spike/reference_tone.wav',
        );
      }
      final sessionConfig = RealtimeSessionConfig(
        diarize: _mode == SpikeSessionMode.diarize,
        turnDetection: _mode == SpikeSessionMode.turnDetection
            ? const TurnDetectionConfig()
            : null,
        speakerReferences: references,
      );

      try {
        final client = WebSocketRealtimeClient(
          apiKey: key,
          config: _config,
          debugLog: (message) => print('[spike] $message'),
        );
        final session = await client.startSession(sessionConfig);
        final wav = await WavFileWriter.create(sessionWavPath);
        final stream = await recorder.startStream(const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ));

        _session = session;
        _recorder = recorder;
        _wav = wav;
        _eventSub = session.events.listen(_onEvent);
        // The initial SessionStarted is emitted before this subscription
        // exists (broadcast stream, no replay), so add the marker locally —
        // the console's `[mistral] session ready` confirms the server applied
        // the mode.
        _runs.add(TranscriptRun.marker(
          '\n[session ready: '
          '${_mode == SpikeSessionMode.diarize ? 'diarize' : 'turn_detection'}]\n',
        ));
        _audioSub = stream.listen((chunk) {
          session.sendAudio(chunk); // realtime transcription
          wav.add(chunk); // saved for the post-session diarization pass
        });
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() => _elapsed += const Duration(seconds: 1));
          }
        });
        setState(() => _running = true);
      } on MistralApiException catch (e) {
        setState(() => _error = e.message);
        try {
          await recorder.dispose();
        } catch (_) {}
      }
    } finally {
      _starting = false;
    }
  }

  void _onEvent(RealtimeEvent event) {
    if (!mounted) {
      return;
    }
    setState(() {
      switch (event) {
        case TextDelta(:final text):
          _appendText(text);
        case SpeakerSegment(:final text, :final speakerId):
          if (_speaker != speakerId) {
            _speaker = speakerId;
            _runs.add(TranscriptRun.marker('[$speakerId] '));
          }
          _appendText(text);
        case TurnStarted(:final timeS):
          _runs.add(TranscriptRun.marker(
              '\n— turn @ ${timeS.toStringAsFixed(1)}s —\n'));
        case TurnEnded(:final timeS):
          _runs.add(TranscriptRun.marker(
              '\n— end @ ${timeS.toStringAsFixed(1)}s —\n'));
        case TurnEagerEnd() || TurnResumed():
          break; // provisional turn signals carry no display text
        case Reconnected(:final dropReason):
          _reconnects++;
          // print, not debugPrint: debugPrint throttles and drops messages
          // under a reconnect flood, which hid the error lines.
          final reason = dropReason == null ? '' : ' — $dropReason';
          print('[spike] reconnected @ ${_elapsed.inSeconds}s$reason');
          _runs.add(TranscriptRun.marker(
              '\n[reconnected @ ${_elapsed.inSeconds}s$reason]\n'));
        case BufferedAudioReplayed(:final seconds):
          print('[spike] replayed ${seconds.toStringAsFixed(1)}s '
              'of buffered audio');
          _runs.add(TranscriptRun.marker(
              '\n[replayed ${seconds.toStringAsFixed(1)}s of buffered audio]\n'));
        case TranscriptionDone(:final usage):
          _actualAudioSeconds = usage.promptAudioSeconds;
          if (usage.promptAudioSeconds != null) {
            _actualCost =
                usage.promptAudioSeconds! / 60 * _config.realtimeRatePerMinute;
          }
        case RealtimeError(:final message):
          _error = message;
          print('[spike] error: $message');
          _runs.add(TranscriptRun.marker('\n[error: $message]\n'));
        case SessionStarted(:final appliedSettings):
          final mode = _describeSettings(appliedSettings);
          print('[spike] session ready: $mode');
          _runs.add(TranscriptRun.marker('\n[session ready: $mode]\n'));
      }
    });
    _scrollToBottom();
  }

  void _appendText(String text) {
    if (_runs.isNotEmpty && !_runs.last.isMarker) {
      _runs.last.text += text;
    } else {
      _runs.add(TranscriptRun.text(text));
    }
  }

  Future<Uint8List> _loadAsset(String asset) async {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// One-word summary of the mode the server actually applied — confirms
  /// whether turn detection / diarization was engaged for this session.
  String _describeSettings(Map<String, dynamic> settings) {
    if (settings.containsKey('turn_detection')) {
      return 'turn_detection';
    }
    if (settings['diarize'] == true) {
      return 'diarize';
    }
    return 'plain';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    await _audioSub?.cancel();
    await _eventSub?.cancel();
    // Null out as we go so dispose() below never double-disposes: record's
    // dispose throws "Recorder has not yet been created or has already been
    // disposed" if called twice.
    final session = _session;
    _session = null;
    if (session != null) {
      try {
        await session.end();
      } catch (_) {}
      try {
        await session.dispose();
      } catch (_) {}
    }
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) {
      try {
        await recorder.stop();
      } catch (_) {}
      try {
        await recorder.dispose();
      } catch (_) {}
    }
    final wav = _wav;
    _wav = null;
    try {
      await wav?.close();
    } catch (_) {}
    if (mounted) {
      setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioSub?.cancel();
    _eventSub?.cancel();
    _scrollController.dispose();
    // Fire-and-forget cleanup; errors are swallowed (the session/recorder may
    // already be disposed by _stop).
    _disposeQuietly(_session?.dispose());
    _disposeQuietly(_recorder?.dispose());
    super.dispose();
  }

  Future<void> _disposeQuietly(Future<void>? future) async {
    try {
      await future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final keyAsync = ref.watch(apiKeyProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Spike A — live transcription')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<SpikeSessionMode>(
              segments: const [
                ButtonSegment(
                  value: SpikeSessionMode.turnDetection,
                  label: Text('Turn detection'),
                ),
                ButtonSegment(
                  value: SpikeSessionMode.diarize,
                  label: Text('Live diarization'),
                ),
              ],
              selected: <SpikeSessionMode>{_mode},
              onSelectionChanged: _running
                  ? null
                  : (selection) => setState(() => _mode = selection.first),
            ),
            if (_mode == SpikeSessionMode.diarize)
              SwitchListTile(
                title: const Text("Enroll reference clip as 'Alice'"),
                subtitle: const Text(
                  'Placeholder tone asset — replace with a 3–15 s voice clip '
                  '(task 5.3)',
                ),
                value: _enrollReference,
                onChanged: _running
                    ? null
                    : (v) => setState(() => _enrollReference = v),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _running ? null : _start,
                  icon: const Icon(Icons.mic),
                  label: const Text('Start'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _running ? _stop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Elapsed ${_elapsed.inMinutes.toString().padLeft(2, '0')}:'
              '${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}'
              '  •  est. cost \$${_estimatedCost.toStringAsFixed(4)}'
              '  •  reconnects: $_reconnects'
              '  •  buffered: '
              '${_session?.bufferedAudioSeconds.toStringAsFixed(1) ?? '0.0'}s',
              style: textTheme.bodyMedium,
            ),
            if (_actualAudioSeconds != null)
              Text(
                'Actual: ${_actualAudioSeconds}s billed  •  actual cost '
                '\$${_actualCost?.toStringAsFixed(4) ?? '?'}',
                style: textTheme.bodyMedium,
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              // One line only — the full error is in the transcript markers.
              Text(
                _error!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Scrollbar(
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: _runs.isEmpty
                        ? SelectableText(
                            '(transcript appears here as you speak)')
                        : SelectableText.rich(
                            TextSpan(
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.4,
                              ),
                              children: [
                                for (final run in _runs)
                                  TextSpan(
                                    text: run.text,
                                    style: run.isMarker
                                        ? TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline,
                                            fontStyle: FontStyle.italic,
                                            fontSize: 13,
                                            height: 1.4,
                                          )
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Session audio saved to: $sessionWavPath',
              style: textTheme.bodySmall,
            ),
            keyAsync.when(
              data: (key) => key == null
                  ? Text(
                      'No API key saved yet.',
                      style: textTheme.bodySmall,
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
