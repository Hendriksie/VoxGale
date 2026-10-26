import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxtral_live/mistral/batch/batch_transcription_client.dart';
import 'package:voxtral_live/mistral/batch/dio_batch_transcription_client.dart';
import 'package:voxtral_live/mistral/mistral_api_exception.dart';

class MockDio extends Mock implements Dio {}

void main() {
  final responseData = {
    'model': 'voxtral-mini-transcribe-3-0',
    'text': 'Hello world',
    'language': 'en',
    'segments': [
      {
        'type': 'transcription_segment',
        'text': 'Hello ',
        'start': 0.0,
        'end': 1.0,
        'speaker_id': 'speaker_1',
      },
      {
        'type': 'transcription_segment',
        'text': 'world',
        'start': 1.0,
        'end': 2.0,
        'speaker_id': 'speaker_2',
      },
    ],
    'usage': {
      'prompt_audio_seconds': 2,
      'prompt_tokens': 3,
      'total_tokens': 10,
      'completion_tokens': 5,
    },
  };

  (FormData, Options) captureRequest(MockDio dio) {
    final captured = verify(
      () => dio.post(
        any(),
        data: captureAny(named: 'data'),
        options: captureAny(named: 'options'),
      ),
    ).captured;
    // Find by type: the capture order of positional/named matchers is an
    // implementation detail of mocktail.
    return (
      captured.whereType<FormData>().single,
      captured.whereType<Options>().single,
    );
  }

  test('posts multipart with diarize and segment timestamps, parses the result',
      () async {
    final dio = MockDio();
    when(
      () => dio.post(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: '/v1/audio/transcriptions'),
        data: responseData,
        statusCode: 200,
      ),
    );

    final client = DioBatchTranscriptionClient(apiKey: 'test-key', dio: dio);
    final result = await client.transcribe(BatchTranscriptionRequest(
      model: 'voxtral-mini-transcribe-3-0',
      audioBytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'meeting.wav',
    ));

    final (form, options) = captureRequest(dio);
    final fields = {for (final f in form.fields) f.key: f.value};
    expect(fields['model'], 'voxtral-mini-transcribe-3-0');
    expect(fields['diarize'], 'true');
    expect(fields['timestamp_granularities'], 'segment');
    expect(form.files.single.key, 'file');
    expect(form.files.single.value.filename, 'meeting.wav');
    expect(form.files.single.value.length, 3);
    expect(options.headers?['Authorization'], 'Bearer test-key');

    expect(result.text, 'Hello world');
    expect(result.segments, hasLength(2));
    expect(result.segments.first.speakerId, 'speaker_1');
    expect(result.segments.first.start, 0.0);
    expect(result.segments.last.end, 2.0);
    expect(result.usage.promptAudioSeconds, 2);
  });

  test('context_bias is repeated once per entry', () async {
    final dio = MockDio();
    when(
      () => dio.post(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: '/v1/audio/transcriptions'),
        data: responseData,
        statusCode: 200,
      ),
    );

    final client = DioBatchTranscriptionClient(apiKey: 'test-key', dio: dio);
    await client.transcribe(BatchTranscriptionRequest(
      model: 'voxtral-mini-transcribe-3-0',
      audioBytes: Uint8List.fromList([1]),
      fileName: 'a.wav',
      contextBias: ['Northwind', 'Alder Creek Design'],
      language: 'en',
    ));

    final (form, _) = captureRequest(dio);
    final bias = form.fields
        .where((f) => f.key == 'context_bias')
        .map((f) => f.value)
        .toList();
    expect(bias, ['Northwind', 'Alder Creek Design']);
    final fields = {for (final f in form.fields) f.key: f.value};
    expect(fields['language'], 'en');
  });

  test('speaker references are serialized as a JSON name-to-base64 field',
      () async {
    final dio = MockDio();
    when(
      () => dio.post(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: '/v1/audio/transcriptions'),
        data: responseData,
        statusCode: 200,
      ),
    );

    final client = DioBatchTranscriptionClient(apiKey: 'test-key', dio: dio);
    await client.transcribe(BatchTranscriptionRequest(
      model: 'voxtral-mini-transcribe-3-0',
      audioBytes: Uint8List.fromList([1]),
      fileName: 'a.wav',
      speakerReferences: {'Alice': Uint8List.fromList([9, 8, 7])},
    ));

    final (form, _) = captureRequest(dio);
    final fields = {for (final f in form.fields) f.key: f.value};
    final references =
        jsonDecode(fields['speaker_references'] as String) as Map<String, dynamic>;
    expect(base64Decode(references['Alice'] as String), [9, 8, 7]);
  });

  test('API errors surface the response message and never the API key',
      () async {
    const secret = 'sk-super-secret';
    final dio = MockDio();
    when(
      () => dio.post(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(DioException(
      requestOptions: RequestOptions(
        path: '/v1/audio/transcriptions',
        headers: {'Authorization': 'Bearer $secret'},
      ),
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/v1/audio/transcriptions'),
        statusCode: 422,
        data: {
          'error': {'message': 'When diarize is set to True, the timestamp '
              'granularity must be set to [\'segment\']'},
        },
      ),
    ));

    final client = DioBatchTranscriptionClient(apiKey: secret, dio: dio);

    await expectLater(
      client.transcribe(BatchTranscriptionRequest(
        model: 'voxtral-mini-transcribe-3-0',
        audioBytes: Uint8List.fromList([1]),
        fileName: 'a.wav',
      )),
      throwsA(
        isA<MistralApiException>()
            .having((e) => e.message, 'message', contains('timestamp granularity'))
            .having((e) => e.message, 'message', isNot(contains(secret))),
      ),
    );
  });

  test('network failures surface a generic message without the API key',
      () async {
    const secret = 'sk-super-secret';
    final dio = MockDio();
    when(
      () => dio.post(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(DioException(
      requestOptions: RequestOptions(
        path: '/v1/audio/transcriptions',
        headers: {'Authorization': 'Bearer $secret'},
      ),
      type: DioExceptionType.connectionError,
      error: Exception('Bearer $secret'),
    ));

    final client = DioBatchTranscriptionClient(apiKey: secret, dio: dio);

    await expectLater(
      client.transcribe(BatchTranscriptionRequest(
        model: 'voxtral-mini-transcribe-3-0',
        audioBytes: Uint8List.fromList([1]),
        fileName: 'a.wav',
      )),
      throwsA(
        isA<MistralApiException>()
            .having((e) => e.message, 'message',
                allOf(contains('Could not reach the transcription API'),
                    contains('connectionError')))
            .having((e) => e.message, 'message', isNot(contains(secret))),
      ),
    );
  });

  group('timeouts', () {
    test('the production dio options carry finite connect and send timeouts',
        () {
      final options = DioBatchTranscriptionClient.defaultBaseOptions(
        Uri(scheme: 'https', host: 'api.mistral.ai'),
      );
      expect(options.connectTimeout, const Duration(seconds: 15));
      expect(options.sendTimeout, const Duration(minutes: 5));
    });

    test('receiveTimeoutFor is proportional to the audio duration with a '
        'floor', () {
      // Unknown duration: the fixed default.
      expect(
        DioBatchTranscriptionClient.receiveTimeoutFor(null),
        const Duration(minutes: 10),
      );
      // Short audio: the floor applies.
      expect(
        DioBatchTranscriptionClient.receiveTimeoutFor(
            const Duration(seconds: 5)),
        const Duration(seconds: 60),
      );
      // Twice the audio length, once past the floor.
      expect(
        DioBatchTranscriptionClient.receiveTimeoutFor(
            const Duration(minutes: 5)),
        const Duration(minutes: 10),
      );
      expect(
        DioBatchTranscriptionClient.receiveTimeoutFor(
            const Duration(minutes: 30)),
        const Duration(minutes: 60),
      );
    });

    test('the request receive timeout reaches the dio call', () async {
      final dio = MockDio();
      when(
        () => dio.post(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/v1/audio/transcriptions'),
          data: responseData,
          statusCode: 200,
        ),
      );

      final client = DioBatchTranscriptionClient(apiKey: 'test-key', dio: dio);
      await client.transcribe(BatchTranscriptionRequest(
        model: 'voxtral-mini-transcribe-3-0',
        audioBytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'meeting.wav',
        audioDuration: const Duration(minutes: 30),
      ));

      final (_, options) = captureRequest(dio);
      expect(options.receiveTimeout, const Duration(minutes: 60));
    });

    test('a request without a duration gets the fixed default receive '
        'timeout', () async {
      final dio = MockDio();
      when(
        () => dio.post(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/v1/audio/transcriptions'),
          data: responseData,
          statusCode: 200,
        ),
      );

      final client = DioBatchTranscriptionClient(apiKey: 'test-key', dio: dio);
      await client.transcribe(BatchTranscriptionRequest(
        model: 'voxtral-mini-transcribe-3-0',
        audioBytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'meeting.wav',
      ));

      final (_, options) = captureRequest(dio);
      expect(options.receiveTimeout, const Duration(minutes: 10));
    });
  });
}
