// Unit tests for [DioUpdateCheckClient] (change 2026-10-29-update-tracker,
// task 3.2). The dio instance is mocked with mocktail — these tests never
// hit the live GitHub API (same rule as the Mistral API tests). Every
// failure path must resolve to null: the automatic update check fails
// silently.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxgale/update/dio_update_check_client.dart';
import 'package:voxgale/update/update_check_client.dart';
import 'package:voxgale/update/update_config.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late DioUpdateCheckClient client;

  const releasePageUrl =
      'https://github.com/Hendriksie/VoxGale/releases/tag/v1.3.0';

  setUp(() {
    dio = MockDio();
    client = DioUpdateCheckClient(dio: dio);
  });

  void stubGet(Future<Response<dynamic>> Function(Invocation) answer) {
    when(() => dio.get(any(), options: any(named: 'options')))
        .thenAnswer(answer);
  }

  Response<dynamic> jsonResponse(Object? data, {int statusCode = 200}) =>
      Response<dynamic>(
        requestOptions: RequestOptions(path: UpdateConfig.latestReleasePath),
        data: data,
        statusCode: statusCode,
      );

  DioException dioError(int statusCode) => DioException(
    requestOptions: RequestOptions(path: UpdateConfig.latestReleasePath),
    response: Response<dynamic>(
      requestOptions: RequestOptions(path: UpdateConfig.latestReleasePath),
      statusCode: statusCode,
    ),
    type: DioExceptionType.badResponse,
  );

  test(
    'the happy path parses tag_name and html_url into an UpdateInfo',
    () async {
      stubGet(
        (_) async => jsonResponse(const {
          'tag_name': 'v1.3.0',
          'html_url': releasePageUrl,
        }),
      );

      final info = await client.fetchLatestRelease();

      expect(
        info,
        UpdateInfo(version: '1.3.0', releasePageUrl: Uri.parse(releasePageUrl)),
      );
    },
  );

  test('the request targets the pinned endpoint with a User-Agent and no '
      'Authorization header', () async {
    stubGet(
      (_) async => jsonResponse(const {
        'tag_name': 'v1.3.0',
        'html_url': releasePageUrl,
      }),
    );

    await client.fetchLatestRelease();

    final captured = verify(
      () => dio.get(captureAny(), options: captureAny(named: 'options')),
    ).captured;
    expect(captured.whereType<String>().single, UpdateConfig.latestReleasePath);
    final options = captured.whereType<Options>().single;
    // GitHub's API requires a User-Agent; the check is unauthenticated.
    expect(options.headers?['User-Agent'], 'voxgale-update-check');
    expect(options.headers?['Accept'], 'application/vnd.github+json');
    expect(options.headers?['Authorization'], isNull);
  });

  test('a 404 DioException resolves to null', () async {
    when(() => dio.get(any(), options: any(named: 'options')))
        .thenThrow(dioError(404));

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('a rate-limit DioException resolves to null', () async {
    when(() => dio.get(any(), options: any(named: 'options')))
        .thenThrow(dioError(403));

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('a network DioException resolves to null', () async {
    when(() => dio.get(any(), options: any(named: 'options'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: UpdateConfig.latestReleasePath),
        type: DioExceptionType.connectionError,
      ),
    );

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('a non-200 response resolves to null', () async {
    stubGet(
      (_) async => jsonResponse(const {
        'tag_name': 'v1.3.0',
        'html_url': releasePageUrl,
      }, statusCode: 503),
    );

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('a non-map JSON body resolves to null', () async {
    stubGet((_) async => jsonResponse(const ['not', 'a', 'map']));

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('a JSON string body resolves to null', () async {
    stubGet((_) async => jsonResponse('"release"'));

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('a missing tag_name resolves to null', () async {
    stubGet((_) async => jsonResponse(const {'html_url': releasePageUrl}));

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('a missing html_url resolves to null', () async {
    stubGet((_) async => jsonResponse(const {'tag_name': 'v1.3.0'}));

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('a non-semver tag resolves to null', () async {
    stubGet(
      (_) async => jsonResponse(const {
        'tag_name': 'nightly',
        'html_url': releasePageUrl,
      }),
    );

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('a two-component tag resolves to null', () async {
    stubGet(
      (_) async =>
          jsonResponse(const {'tag_name': 'v1.3', 'html_url': releasePageUrl}),
    );

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('a prerelease tag resolves to null', () async {
    stubGet(
      (_) async => jsonResponse(const {
        'tag_name': 'v1.3.0-beta',
        'html_url': releasePageUrl,
      }),
    );

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('an invalid html_url resolves to null', () async {
    stubGet(
      (_) async =>
          jsonResponse(const {'tag_name': 'v1.3.0', 'html_url': 'not a url'}),
    );

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('a relative html_url resolves to null', () async {
    stubGet(
      (_) async => jsonResponse(const {
        'tag_name': 'v1.3.0',
        'html_url': '/releases/tag/v1.3.0',
      }),
    );

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('a non-string tag_name resolves to null', () async {
    stubGet(
      (_) async =>
          jsonResponse(const {'tag_name': 130, 'html_url': releasePageUrl}),
    );

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('an unexpected throw from dio resolves to null', () async {
    when(() => dio.get(any(), options: any(named: 'options')))
        .thenThrow(StateError('unexpected'));

    expect(await client.fetchLatestRelease(), isNull);
  });

  test('the production base options pin the base URL and finite timeouts', () {
    final options = DioUpdateCheckClient.defaultBaseOptions(
      UpdateConfig.apiHostUri,
    );

    expect(options.baseUrl, UpdateConfig.apiHostUri.toString());
    expect(options.connectTimeout, const Duration(seconds: 10));
    expect(options.receiveTimeout, const Duration(seconds: 10));
  });
}
