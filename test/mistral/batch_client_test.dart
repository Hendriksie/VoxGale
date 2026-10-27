// Coverage audit (Phase 3 group 4, task 4.1 — test-coverage spec). The
// spec's list for the batch client, and where each item lives:
//   multipart params .... 'posts multipart with diarize and segment
//                         timestamps, parses the result' (model, file,
//                         diarize), 'context_bias is repeated once per
//                         entry' (language), 'speaker references are
//                         serialized as a JSON name-to-base64 field', plus
//                         the parameter tests this group added: 'the request
//                         carries the model, diarization, and language
//                         parameters the flow selected', 'diarize=false
//                         omits the diarization fields', 'return_language
//                         adds the field'
//   diarization params .. 'posts multipart with diarize and segment
//                         timestamps' (diarize=true +
//                         timestamp_granularities=segment)
//   request timeouts .... the 'timeouts' group (the production base options
//                         carry finite connect/send timeouts, the receive
//                         timeout scales with the audio, the per-request
//                         override reaches the dio call)
//   error kinds ......... 'API errors surface the response message and never
//                         the API key' (the API-message path), the 'error
//                         kinds' group this group added (401/403/429/413 on
//                         both the status path and the API-message path:
//                         sanitized, distinguishable, no key, no retry), the
//                         non-API-failure and non-JSON-response tests
// Gaps the audit found and this group filled: the authentication (401/403),
// quota (429), and file-limit (413) error kinds had no coverage at all, nor
// did the no-retry pin, the diarize=false and return_language parameter
// cases, or the non-API/non-JSON response paths. The mapping pins as-is:
// when the rejection carries no parseable API message the surfaced message
// names the HTTP status (what the app's failure taxonomy distinguishes the
// kinds by — see error_states.dart's classifyFailure); when the API's message
// is present it surfaces verbatim. One pinned wart, reported not fixed (this
// group is tests only): the non-JSON-response error is thrown inside the
// try, so the generic catch re-wraps it and the message carries a doubled
// 'MistralApiException:' prefix — still sanitized, still the generic kind.
// No production-code change was needed for any spec-listed behavior.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxtral_live/app/error_states.dart';
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

  test('the request carries the model, diarization, and language parameters '
      'the flow selected', () async {
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
      diarize: true,
      language: 'de',
    ));

    final (form, _) = captureRequest(dio);
    final fields = {for (final f in form.fields) f.key: f.value};
    expect(fields['model'], 'voxtral-mini-transcribe-3-0');
    expect(fields['diarize'], 'true');
    expect(fields['timestamp_granularities'], 'segment');
    expect(fields['language'], 'de');
    // Off unless the flow asked for it.
    expect(fields.containsKey('return_language'), isFalse);
    expect(form.files.single.key, 'file');
    expect(form.files.single.value.filename, 'meeting.wav');
  });

  test('diarize=false omits the diarization fields', () async {
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
      diarize: false,
    ));

    final (form, _) = captureRequest(dio);
    final keys = form.fields.map((f) => f.key).toList();
    expect(keys, isNot(contains('diarize')));
    expect(keys, isNot(contains('timestamp_granularities')));
    // The model and the file still go out.
    expect(keys, contains('model'));
    expect(form.files.single.key, 'file');
  });

  test('return_language=true adds the return_language field', () async {
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
      returnLanguage: true,
    ));

    final (form, _) = captureRequest(dio);
    final fields = {for (final f in form.fields) f.key: f.value};
    expect(fields['return_language'], 'true');
  });

  /// Runs one transcription against [dio] and returns the surfaced
  /// [MistralApiException] (failing the test when none surfaces).
  Future<MistralApiException> transcribeFailure(MockDio dio, String secret) async {
    try {
      await DioBatchTranscriptionClient(apiKey: secret, dio: dio).transcribe(
        BatchTranscriptionRequest(
          model: 'voxtral-mini-transcribe-3-0',
          audioBytes: Uint8List.fromList([1]),
          fileName: 'a.wav',
        ),
      );
      fail('the rejection should surface a MistralApiException');
    } on MistralApiException catch (error) {
      return error;
    }
  }

  group('error kinds (authentication, quota, file limit)', () {
    RequestOptions authorizedRequest(String secret) => RequestOptions(
          path: '/v1/audio/transcriptions',
          headers: {'Authorization': 'Bearer $secret'},
        );

    // A rejection whose body carries no parseable API message (a proxy or
    // gateway error page): the client's message names the HTTP status, which
    // is what the app's failure taxonomy distinguishes the kinds by
    // (classifyFailure reads 401/403 as auth, 429 as quota).
    DioException statusRejection(String secret, int status) => DioException(
          requestOptions: authorizedRequest(secret),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/v1/audio/transcriptions'),
            statusCode: status,
            data: '<html>Bad Gateway</html>',
          ),
        );

    for (final (status, kind) in [
      (401, FailureKind.auth),
      (403, FailureKind.auth),
      (429, FailureKind.quota),
      // A file-limit rejection has no dedicated failure kind; the message
      // still names the status, so it stays distinguishable from the others.
      (413, FailureKind.generic),
    ]) {
      test('a $status rejection surfaces a sanitized message naming the '
          'status (${kind.name}), never the key, with no retry', () async {
        const secret = 'sk-super-secret';
        final dio = MockDio();
        when(
          () => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        ).thenThrow(statusRejection(secret, status));

        final failure = await transcribeFailure(dio, secret);

        expect(failure.message, contains('($status)'));
        expect(failure.message, isNot(contains(secret)));
        // The failure taxonomy reads the kind off the status alone.
        expect(classifyFailure(failure), kind);
        // Non-retryable: exactly one request went out.
        verify(
          () => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        ).called(1);
      });
    }

    // A rejection whose body carries the API's own message: it surfaces
    // verbatim (the 422 behavior pinned above), distinguishable by its
    // wording.
    for (final (status, apiMessage, kind) in [
      (401, 'Invalid API key', FailureKind.auth),
      (403, 'Forbidden: the key is disabled', FailureKind.auth),
      (429, 'You have exceeded your API quota', FailureKind.quota),
      (
        413,
        'Audio file exceeds the maximum allowed size',
        FailureKind.generic,
      ),
    ]) {
      test('a $status rejection with an API message surfaces that message '
          '(${kind.name}), never the key, with no retry', () async {
        const secret = 'sk-super-secret';
        final dio = MockDio();
        when(
          () => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        ).thenThrow(DioException(
          requestOptions: authorizedRequest(secret),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/v1/audio/transcriptions'),
            statusCode: status,
            data: {
              'error': {'message': apiMessage},
            },
          ),
        ));

        final failure = await transcribeFailure(dio, secret);

        expect(failure.message, apiMessage);
        expect(failure.message, isNot(contains(secret)));
        expect(classifyFailure(failure), kind);
        // Non-retryable: exactly one request went out.
        verify(
          () => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        ).called(1);
      });
    }
  });

  test('a non-API failure (an SDK-internal error) surfaces sanitized — '
      'never the API key', () async {
    const secret = 'sk-super-secret';
    final dio = MockDio();
    when(
      () => dio.post(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(StateError('dio exploded for Bearer $secret'));

    final failure = await transcribeFailure(dio, secret);

    expect(failure.message, contains('dio exploded'));
    expect(failure.message, isNot(contains(secret)));
    verify(
      () => dio.post(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).called(1);
  });

  test('a non-JSON success response surfaces a generic API error', () async {
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
        data: 'OK',
        statusCode: 200,
      ),
    );

    final client = DioBatchTranscriptionClient(apiKey: 'test-key', dio: dio);
    // Pinned as-is: the "unexpected response" throw sits inside the try, so
    // the generic catch re-wraps it and the surfaced message carries the
    // doubled prefix. Still sanitized and still the generic kind (a cosmetic
    // wart noted for a possible future cleanup — this group is tests only).
    await expectLater(
      client.transcribe(BatchTranscriptionRequest(
        model: 'voxtral-mini-transcribe-3-0',
        audioBytes: Uint8List.fromList([1]),
        fileName: 'a.wav',
      )),
      throwsA(
        isA<MistralApiException>().having(
          (e) => e.message,
          'message',
          'MistralApiException: Unexpected response from the '
              'transcription API',
        ),
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
