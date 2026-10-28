import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/session/file_transcription_controller.dart';

void main() {
  // The production [JustAudioDurationProber] reads a file's duration through
  // the platform media APIs (design P2-D2). The raw just_audio call itself
  // needs a device (covered by the smoke test — in the test environment the
  // platform channel never answers, so it would hang, not throw); the
  // prober's own logic — pass the duration through, map any failure to null
  // — is covered here directly. Phase-1 lesson: an injected seam's
  // production implementation still gets direct test coverage — fakes hide
  // production-only paths.
  group('JustAudioDurationProber', () {
    test('passes the probed duration through', () async {
      final prober = JustAudioDurationProber(
        rawProbe: (_) async => const Duration(seconds: 42),
      );

      expect(await prober.probe('/tmp/interview.mp3'),
          const Duration(seconds: 42));
    });

    test('maps a probing failure (unsupported format, platform error) to '
        'null', () async {
      final prober = JustAudioDurationProber(
        rawProbe: (_) async => throw StateError('no media platform'),
      );

      expect(await prober.probe('/tmp/interview.mp3'), isNull);
    });

    test('maps a synchronous raw-probe throw to null', () async {
      final prober = JustAudioDurationProber(
        rawProbe: (_) => throw StateError('no media platform'),
      );

      expect(await prober.probe('/tmp/interview.mp3'), isNull);
    });
  });
}
