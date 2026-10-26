// The API key validation client (design P2-D4): a cheap test request that
// proves a candidate key is accepted before the settings screen treats it
// as saved (settings spec: "validate a newly entered API key with a cheap
// test request against the Mistral API before treating it as saved"). The
// candidate key is passed per call, so validation can run before the key is
// stored. Errors are wrapped in [MistralApiException] with a sanitized
// message — a raw [DioException] embeds the request headers (which contain
// the API key), so it is never rethrown or stringified here.

import 'package:dio/dio.dart';

import 'batch/dio_batch_transcription_client.dart';
import 'mistral_api_exception.dart';

/// Validates a candidate Mistral API key (settings spec).
abstract interface class KeyValidationClient {
  /// Throws [MistralApiException] when the key is rejected or the request
  /// cannot reach the API; resolves when the key is accepted.
  Future<void> validate(String apiKey);
}

/// [KeyValidationClient] over `GET /v1/models` using dio — the cheapest
/// authenticated request the API offers (no audio, no cost).
class DioKeyValidationClient implements KeyValidationClient {
  DioKeyValidationClient({Dio? dio, Uri? baseUri})
      : _dio = dio ??
            Dio(DioBatchTranscriptionClient.defaultBaseOptions(
                baseUri ?? _defaultBaseUri));

  static final Uri _defaultBaseUri = Uri(scheme: 'https', host: 'api.mistral.ai');

  /// The receive timeout for the validation request: a key check is quick,
  /// so a stalled call fails instead of hanging forever (the dio gotcha:
  /// dio has no default timeouts).
  static const Duration defaultReceiveTimeout = Duration(seconds: 15);

  final Dio _dio;

  @override
  Future<void> validate(String apiKey) async {
    try {
      await _dio.get<dynamic>(
        '/v1/models',
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
          receiveTimeout: defaultReceiveTimeout,
        ),
      );
    } on DioException catch (error) {
      throw MistralApiException(_messageFromDioError(error, apiKey));
    } catch (error) {
      throw MistralApiException(MistralApiException.sanitize(error, apiKey));
    }
  }

  /// Extracts a user-presentable message without ever touching
  /// [DioException.toString], which embeds request headers (API key
  /// included). A 401/403 means the key was rejected; anything else is a
  /// request failure the user can retry.
  String _messageFromDioError(DioException error, String apiKey) {
    final status = error.response?.statusCode;
    if (error.type == DioExceptionType.badResponse) {
      if (status == 401 || status == 403) {
        return 'The API key was rejected. Check the key and try again.';
      }
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final apiError = data['error'];
        if (apiError is Map<String, dynamic> && apiError['message'] is String) {
          return apiError['message'] as String;
        }
        if (data['message'] is String) {
          return data['message'] as String;
        }
      }
      return 'The validation request failed (HTTP ${status ?? 'unknown'}).';
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Network timeout while validating the API key '
            '(${error.type.name}). Check the connection and try again.';
      case DioExceptionType.cancel:
        return 'The API key validation was cancelled.';
      default:
        final cause = error.error == null
            ? ''
            : ': ${MistralApiException.sanitize(error.error!, apiKey)}';
        return 'Could not reach the Mistral API to validate the key '
            '(${error.type.name}$cause). Try again.';
    }
  }
}
