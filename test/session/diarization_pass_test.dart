import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxtral_live/mistral/mistral.dart';
import 'package:voxtral_live/session/diarization_pass.dart';
import 'package:voxtral_live/storage/storage.dart';

class MockBatchTranscriptionClient extends Mock
    implements BatchTranscriptionClient {}

class MockSessionRepository extends Mock implements SessionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      BatchTranscriptionRequest(
        model: 'model',
        audioBytes: Uint8List(0),
        fileName: 'file.wav',
      ),
    );
    registerFallbackValue(<StoredSegment>[]);
    registerFallbackValue(0);
    registerFallbackValue(0.0);
  });

  late MockBatchTranscriptionClient client;
  late MockSessionRepository repository;
  late DiarizationPass pass;
  late Directory tempDir;

  const config = MistralConfig.defaults;

  setUp(() async {
    client = MockBatchTranscriptionClient();
    repository = MockSessionRepository();
    pass = DiarizationPass(
      client: client,
      repository: repository,
      config: config,
    );
    tempDir = await Directory.systemTemp.createTemp('voxtral_pass_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  /// Writes a WAV file with [dataBytes] of audio data and returns its path.
  Future<String> writeWav(String name, int dataBytes) async {
    final file = File('${tempDir.path}/$name');
    // The 44-byte header [WavFileWriter] writes, then zeroed audio data.
    await file.writeAsBytes(List<int>.filled(44 + dataBytes, 0));
    return file.path;
  }

  void stubReplaceTranscript() {
    when(
      () => repository.replaceTranscript(
        any(),
        any(),
        billedAudioSeconds: any(named: 'billedAudioSeconds'),
        actualCost: any(named: 'actualCost'),
      ),
    ).thenAnswer((_) async {});
  }

  group('wavAudioDurationSeconds', () {
    test('is the data bytes divided by the byte rate (header excluded)',
        () async {
      final path = await writeWav('a.wav', 32000 * 30); // 30 s of audio
      expect(await wavAudioDurationSeconds(path), 30);
    });

    test('clamps a corrupt (header-only) file to zero', () async {
      final path = await writeWav('b.wav', 0);
      expect(await wavAudioDurationSeconds(path), 0);
    });
  });

  group('estimateCost', () {
    test('is the audio duration times the batch Mini per-minute rate',
        () async {
      final path = await writeWav('c.wav', 32000 * 60); // 60 s of audio
      // 60 s / 60 × 0.0035 USD/min.
      expect(await pass.estimateCost(path), closeTo(0.0035, 1e-9));
    });
  });

  group('run', () {
    test('transcribes the saved audio with diarize=true on the batch Mini '
        'model, replaces the transcript, and deletes the audio', () async {
      final path = await writeWav('session-1.wav', 32000 * 30);
      final audioBytes = await File(path).readAsBytes();
      BatchTranscriptionRequest? request;
      when(() => client.transcribe(any())).thenAnswer((invocation) async {
        request =
            invocation.positionalArguments[0] as BatchTranscriptionRequest;
        return const BatchTranscriptionResult(
          text: 'Hello world',
          segments: [
            TranscriptSegment(
              text: 'Hello ',
              speakerId: 'speaker_1',
              start: 0,
              end: 1.5,
            ),
            TranscriptSegment(
              text: 'world',
              speakerId: 'speaker_2',
              start: 1.5,
              end: 2.5,
            ),
          ],
          language: 'en',
          model: 'voxtral-mini-transcribe-3-0',
          usage: Usage(promptAudioSeconds: 30),
        );
      });
      String? replacedId;
      List<StoredSegment>? replacedSegments;
      int? replacedBilled;
      double? replacedCost;
      when(
        () => repository.replaceTranscript(
          any(),
          any(),
          billedAudioSeconds: any(named: 'billedAudioSeconds'),
          actualCost: any(named: 'actualCost'),
        ),
      ).thenAnswer((invocation) async {
        replacedId = invocation.positionalArguments[0] as String;
        replacedSegments =
            invocation.positionalArguments[1] as List<StoredSegment>;
        replacedBilled = invocation.namedArguments[#billedAudioSeconds] as int;
        replacedCost = invocation.namedArguments[#actualCost] as double;
      });

      final result = await pass.run(
        sessionId: 'session-1',
        audioPath: path,
        language: 'en',
      );

      // The request: the saved WAV, the batch Mini model, diarization on.
      expect(request, isNotNull);
      expect(request!.model, config.batchMiniModel);
      expect(request!.diarize, isTrue);
      expect(request!.fileName, 'session-1.wav');
      expect(request!.audioBytes, audioBytes);
      expect(request!.language, 'en');
      // The transcript is replaced and the session marked final with the
      // pass's billed totals.
      expect(replacedId, 'session-1');
      expect(replacedSegments, [
        const StoredSegment(
          sessionId: 'session-1',
          order: 0,
          text: 'Hello ',
          speakerLabel: 'speaker_1',
          startSeconds: 0,
          endSeconds: 1.5,
        ),
        const StoredSegment(
          sessionId: 'session-1',
          order: 1,
          text: 'world',
          speakerLabel: 'speaker_2',
          startSeconds: 1.5,
          endSeconds: 2.5,
        ),
      ]);
      expect(replacedBilled, 30);
      expect(
        replacedCost,
        closeTo(30 / 60 * config.batchMiniRatePerMinute, 1e-12),
      );
      // The audio is deleted after the successful pass.
      expect(await File(path).exists(), isFalse);
      // The outcome carries the labelled segments and the actual usage.
      expect(result.text, 'Hello world');
      expect(result.segments, hasLength(2));
      expect(result.segments.first.speakerId, 'speaker_1');
      expect(result.billedAudioSeconds, 30);
      expect(
        result.actualCost,
        closeTo(30 / 60 * config.batchMiniRatePerMinute, 1e-12),
      );
      expect(result.language, 'en');
    });

    test('keeps the provisional transcript and the audio when the request '
        'fails, so the pass can be retried', () async {
      final path = await writeWav('session-2.wav', 32000 * 10);
      when(() => client.transcribe(any()))
          .thenThrow(MistralApiException('quota exceeded'));

      await expectLater(
        pass.run(sessionId: 'session-2', audioPath: path),
        throwsA(isA<MistralApiException>()),
      );
      verifyNever(
        () => repository.replaceTranscript(
          any(),
          any(),
          billedAudioSeconds: any(named: 'billedAudioSeconds'),
          actualCost: any(named: 'actualCost'),
        ),
      );
      // The audio is kept (the retry re-reads it).
      expect(await File(path).exists(), isTrue);

      // A retry re-reads the saved audio and succeeds.
      when(() => client.transcribe(any())).thenAnswer(
        (_) async => const BatchTranscriptionResult(
          text: 'Retry',
          segments: [
            TranscriptSegment(
              text: 'Retry',
              speakerId: 'speaker_1',
              start: 0,
              end: 1,
            ),
          ],
          language: 'en',
          model: 'voxtral-mini-transcribe-3-0',
          usage: Usage(promptAudioSeconds: 10),
        ),
      );
      stubReplaceTranscript();
      final result = await pass.run(sessionId: 'session-2', audioPath: path);
      expect(result.text, 'Retry');
      expect(result.billedAudioSeconds, 10);
      expect(await File(path).exists(), isFalse);
    });
  });
}
