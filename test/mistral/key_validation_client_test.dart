import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxgale/mistral/key_validation_client.dart';
import 'package:voxgale/mistral/mistral_api_exception.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late DioKeyValidationClient client;

  setUp(() {
    dio = MockDio();
    client = DioKeyValidationClient(dio: dio);
  });

  Options captureOptions() {
    final captured = verify(
      () => dio.get(
        any(),
        options: captureAny(named: 'options'),
      ),
    ).captured;
    return captured.whereType<Options>().single;
  }

  test('a 200 response means the key is valid', () async {
    when(() => dio.get(any(), options: any(named: 'options'))).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: '/v1/models'),
        data: const {'data': []},
        statusCode: 200,
      ),
    );

    await client.validate('test-key');

    final options = captureOptions();
    expect(options.headers?['Authorization'], 'Bearer test-key');
    // The receive timeout is finite (dio has no default timeouts).
    expect(options.receiveTimeout, isNotNull);
  });

  test('a 401 means the key was rejected', () async {
    when(() => dio.get(any(), options: any(named: 'options'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/v1/models'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/v1/models'),
          statusCode: 401,
          data: const {
            'error': {'message': 'Invalid API key'},
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      client.validate('test-key'),
      throwsA(isA<MistralApiException>().having(
        (e) => e.message,
        'message',
        contains('rejected'),
      )),
    );
  });

  test('a 403 means the key was rejected', () async {
    when(() => dio.get(any(), options: any(named: 'options'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/v1/models'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/v1/models'),
          statusCode: 403,
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      client.validate('test-key'),
      throwsA(isA<MistralApiException>().having(
        (e) => e.message,
        'message',
        contains('rejected'),
      )),
    );
  });

  test('another HTTP error surfaces the API message and is retryable',
      () async {
    when(() => dio.get(any(), options: any(named: 'options'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/v1/models'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/v1/models'),
          statusCode: 500,
          data: const {
            'error': {'message': 'Internal server error'},
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      client.validate('test-key'),
      throwsA(isA<MistralApiException>().having(
        (e) => e.message,
        'message',
        'Internal server error',
      )),
    );
  });

  test('a timeout is a retryable network error', () async {
    when(() => dio.get(any(), options: any(named: 'options'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/v1/models'),
        type: DioExceptionType.receiveTimeout,
      ),
    );

    await expectLater(
      client.validate('test-key'),
      throwsA(isA<MistralApiException>().having(
        (e) => e.message,
        'message',
        contains('timeout'),
      )),
    );
  });

  test('an unreachable API is a retryable error', () async {
    when(() => dio.get(any(), options: any(named: 'options'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/v1/models'),
        type: DioExceptionType.connectionError,
      ),
    );

    await expectLater(
      client.validate('test-key'),
      throwsA(isA<MistralApiException>().having(
        (e) => e.message,
        'message',
        contains('Could not reach'),
      )),
    );
  });

  test('no error message ever contains the API key', () async {
    const key = 'sk-secret-test-key';
    when(() => dio.get(any(), options: any(named: 'options'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/v1/models'),
        type: DioExceptionType.connectionError,
        error: 'SocketException for $key',
      ),
    );

    String? message;
    try {
      await client.validate(key);
    } on MistralApiException catch (e) {
      message = e.message;
    }

    expect(message, isNotNull);
    expect(message, isNot(contains(key)));
    expect('MistralApiException: $message', isNot(contains(key)));
  });
}
