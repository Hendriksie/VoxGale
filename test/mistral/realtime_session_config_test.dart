import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/mistral/realtime/realtime_session_config.dart';

void main() {
  test('diarize and turn detection are mutually exclusive', () {
    expect(
      () => RealtimeSessionConfig(
        diarize: true,
        turnDetection: const TurnDetectionConfig(),
      ),
      throwsArgumentError,
    );
  });

  test('speaker references require diarization', () {
    expect(
      () => RealtimeSessionConfig(
        speakerReferences: {'Alice': Uint8List.fromList([1, 2, 3])},
      ),
      throwsArgumentError,
    );
  });

  test('at most 8 speaker references are accepted', () {
    expect(
      () => RealtimeSessionConfig(
        diarize: true,
        speakerReferences: {
          for (var i = 0; i < 9; i++) 'speaker$i': Uint8List.fromList([i]),
        },
      ),
      throwsArgumentError,
    );
  });

  test('session.update JSON carries audio format and streaming delay', () {
    final json = RealtimeSessionConfig().toSessionUpdateJson();

    expect(json['audio_format'], {'encoding': 'pcm_s16le', 'sample_rate': 16000});
    expect(json['target_streaming_delay_ms'], 480);
    expect(json.containsKey('diarize'), isFalse);
    expect(json.containsKey('turn_detection'), isFalse);
    expect(json.containsKey('language'), isFalse);
  });

  test('turn detection mode sends turn_detection and no diarize', () {
    final json = RealtimeSessionConfig(
      turnDetection: TurnDetectionConfig(),
    ).toSessionUpdateJson();

    expect(json['turn_detection'], isA<Map>());
    expect(json.containsKey('diarize'), isFalse);
  });

  test('diarize mode sends diarize and no turn_detection', () {
    final json = RealtimeSessionConfig(diarize: true).toSessionUpdateJson();

    expect(json['diarize'], true);
    expect(json.containsKey('turn_detection'), isFalse);
  });

  test('language, context bias, and speaker references are included', () {
    final json = RealtimeSessionConfig(
      language: 'en',
      contextBias: const ['Northwind', 'Alder Creek Design'],
      diarize: true,
      speakerReferences: {'Alice': Uint8List.fromList([9, 8, 7])},
    ).toSessionUpdateJson();

    expect(json['language'], 'en');
    expect(json['context_bias'], ['Northwind', 'Alder Creek Design']);
    final references = json['speaker_references'] as Map<String, dynamic>;
    expect(base64Decode(references['Alice'] as String), [9, 8, 7]);
  });

  test('turn detection sends only non-default thresholds', () {
    expect(
      const TurnDetectionConfig().toJson(),
      isEmpty,
    );
    expect(
      const TurnDetectionConfig(minSilenceMs: 300).toJson(),
      {'min_silence_ms': 300},
    );
  });
}
