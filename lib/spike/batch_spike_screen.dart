import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mistral/mistral.dart';
import 'spike_providers.dart';

/// Spike C — batch path (tasks 5.1 and 5.3).
///
/// Transcribes a hard-coded audio asset through the batch client with
/// `diarize=true`, renders the speaker-labelled segments and the billed
/// usage, and can include a speaker reference clip to exercise named speakers
/// in offline mode (5.3; the live mode equivalent is the diarize toggle on
/// the Spike A screen plus a reference clip in the session config).
class BatchSpikeScreen extends ConsumerStatefulWidget {
  const BatchSpikeScreen({super.key});

  @override
  ConsumerState<BatchSpikeScreen> createState() => _BatchSpikeScreenState();
}

class _BatchSpikeScreenState extends ConsumerState<BatchSpikeScreen> {
  /// Placeholder audio. Replace this asset with a real conversation recording
  /// (or point the constant at a session WAV saved by Spike A) for a
  /// meaningful diarization result.
  static const String sampleAsset = 'assets/spike/sample.wav';

  /// Placeholder reference clip (a tone). Replace with a 3–15 s recording of
  /// a real voice to get named-speaker labels.
  static const String referenceAsset = 'assets/spike/reference_tone.wav';

  bool _useSmallModel = false;
  bool _enrollReference = true;
  bool _running = false;
  String? _error;
  BatchTranscriptionResult? _result;
  double? _estimatedCost;
  String _sourceLabel = 'placeholder asset';

  MistralConfig get _config => ref.read(mistralConfigProvider);

  String get _model =>
      _useSmallModel ? _config.batchSmallModel : _config.batchMiniModel;

  Future<void> _transcribe() async {
    setState(() {
      _running = true;
      _error = null;
      _result = null;
      _estimatedCost = null;
    });

    try {
      final key = await ref.read(apiKeyStoreProvider).readKey();
      if (key == null || key.isEmpty) {
        setState(() {
          _running = false;
          _error = 'No API key saved. The settings screen is Phase 2 — for '
              'this spike, save your Mistral API key to secure storage first.';
        });
        return;
      }

      // Prefer the session WAV saved by Spike A — transcribing it is the
      // post-session diarization pass. Fall back to the placeholder asset.
      final sessionWav = File(
        '${Directory.systemTemp.path}/voxtral_spike_session.wav',
      );
      final Uint8List sampleBytes;
      final String fileName;
      if (await sessionWav.exists()) {
        sampleBytes = await sessionWav.readAsBytes();
        fileName = 'voxtral_spike_session.wav';
        _sourceLabel = 'session WAV from Spike A';
      } else {
        sampleBytes = await _loadAsset(sampleAsset);
        fileName = 'spike_sample.wav';
        _sourceLabel = 'placeholder asset (no session WAV found)';
      }
      // WAV at 16 kHz mono 16-bit: 32,000 bytes per second of audio.
      final audioSeconds = (sampleBytes.length - 44) / 32000;
      setState(() {
        _estimatedCost = audioSeconds / 60 * _config.rateForModel(_model);
      });

      final references = <String, Uint8List>{};
      if (_enrollReference) {
        references['Alice'] = await _loadAsset(referenceAsset);
      }

      // No dio passed: the client builds its own with the Mistral base URL.
      // (Passing a bare Dio() overrides that and the request goes out with no
      // host — "No host specified in URI".)
      final client = DioBatchTranscriptionClient(apiKey: key);
      final result = await client.transcribe(BatchTranscriptionRequest(
        model: _model,
        audioBytes: sampleBytes,
        fileName: fileName,
        diarize: true,
        speakerReferences: references,
        returnLanguage: true,
      ));

      if (mounted) {
        setState(() {
          _running = false;
          _result = result;
        });
      }
    } on MistralApiException catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = e.message;
        });
      }
    }
  }

  Future<Uint8List> _loadAsset(String asset) async {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Spike C — batch transcription')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Use Small Transcribe 3 (flagship diarization)'),
              subtitle: Text('Model: $_model'),
              value: _useSmallModel,
              onChanged: _running
                  ? null
                  : (v) => setState(() => _useSmallModel = v),
            ),
            SwitchListTile(
              title: const Text("Enroll reference clip as 'Alice'"),
              subtitle: const Text(
                'Placeholder tone asset — replace with a 3–15 s voice clip',
              ),
              value: _enrollReference,
              onChanged: _running
                  ? null
                  : (v) => setState(() => _enrollReference = v),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _running ? null : _transcribe,
              icon: const Icon(Icons.audio_file),
              label: const Text('Transcribe sample file'),
            ),
            const SizedBox(height: 12),
            if (_running) const LinearProgressIndicator(),
            if (_estimatedCost != null && !_running)
              Text(
                'Audio: $_sourceLabel\n'
                'Est. cost: \$${_estimatedCost!.toStringAsFixed(4)}',
                style: textTheme.bodyMedium,
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _running ? null : _transcribe,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(
                'Billed: ${_result!.usage.promptAudioSeconds}s'
                '  •  actual cost '
                '\$${((_result!.usage.promptAudioSeconds ?? 0) / 60 * _config.rateForModel(_model)).toStringAsFixed(4)}',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _result!.segments.length,
                  itemBuilder: (context, index) {
                    final segment = _result!.segments[index];
                    final start = segment.start?.toStringAsFixed(1) ?? '?';
                    final end = segment.end?.toStringAsFixed(1) ?? '?';
                    return ListTile(
                      dense: true,
                      title: Text(segment.text.trim()),
                      subtitle: Text(
                        '[${segment.speakerId ?? 'no label'}] ${start}s–${end}s',
                      ),
                    );
                  },
                ),
              ),
            ] else if (!_running)
              const Expanded(
                child: Center(child: Text('(result appears here)')),
              ),
          ],
        ),
      ),
    );
  }
}
