// The dio implementation of [UpdateCheckClient] (change
// 2026-10-29-update-tracker, design decisions 1-2, 5): an unauthenticated
// `GET {UpdateConfig.apiHostUri}{UpdateConfig.latestReleasePath}` against
// the GitHub Releases API. The request is deliberately unauthenticated —
// no Authorization header and no API key anywhere near this client (spec:
// "Send no credentials or user data with the update check"). GitHub's API
// rejects requests without a User-Agent, so the headers are set
// explicitly. Every failure — network error, HTTP error (404, rate
// limit), non-map JSON, missing or invalid fields — resolves to null: the
// automatic check fails silently and is retried on the next app start.

import 'package:dio/dio.dart';

import 'update_check_client.dart';
import 'update_config.dart';

/// [UpdateCheckClient] over the GitHub Releases API using dio.
class DioUpdateCheckClient implements UpdateCheckClient {
  DioUpdateCheckClient({Dio? dio, Uri? baseUri})
    : _dio = dio ?? Dio(defaultBaseOptions(baseUri ?? UpdateConfig.apiHostUri));

  /// The production dio options: finite connect/receive timeouts (dio has
  /// no default timeouts — a stalled response would otherwise hang the
  /// check forever) and the base URL set via [BaseOptions] (a bare `Dio()`
  /// drops it — project gotcha).
  static BaseOptions defaultBaseOptions(Uri baseUri) => BaseOptions(
    baseUrl: baseUri.toString(),
    connectTimeout: defaultConnectTimeout,
    receiveTimeout: defaultReceiveTimeout,
  );

  /// Timeout for establishing the connection.
  static const Duration defaultConnectTimeout = Duration(seconds: 10);

  /// Timeout for receiving the response (a small JSON document).
  static const Duration defaultReceiveTimeout = Duration(seconds: 10);

  final Dio _dio;

  @override
  Future<UpdateInfo?> fetchLatestRelease() async {
    try {
      final response = await _dio.get<dynamic>(
        UpdateConfig.latestReleasePath,
        options: Options(
          headers: {
            // GitHub's API rejects requests without a User-Agent. No
            // Authorization header: the check stays unauthenticated.
            'User-Agent': 'voxgale-update-check',
            'Accept': 'application/vnd.github+json',
          },
        ),
      );
      // Real dio throws on non-2xx (validateStatus), so this guards a dio
      // configured to accept any status.
      if (response.statusCode != 200) {
        return null;
      }
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return null;
      }
      final tag = data['tag_name'];
      final url = data['html_url'];
      if (tag is! String || url is! String) {
        return null;
      }
      final components = parseVersionTag(tag);
      if (components == null) {
        return null;
      }
      final releasePageUrl = Uri.tryParse(url);
      if (releasePageUrl == null ||
          !releasePageUrl.isAbsolute ||
          releasePageUrl.host.isEmpty) {
        return null;
      }
      return UpdateInfo(
        version: components.join('.'),
        releasePageUrl: releasePageUrl,
      );
    } on DioException {
      // Network failure, timeout, 404, rate limit — the check failed.
      return null;
    } catch (_) {
      // Any other failure (unexpected response shape, parse error): the
      // check failed. Never throw — the automatic check is silent.
      return null;
    }
  }
}
