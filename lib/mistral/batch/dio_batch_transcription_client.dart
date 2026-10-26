// ignore_for_file: prefer_initializing_formals — the client takes the API key
// as a public `apiKey` parameter (a private named parameter would not be
// callable from other libraries).

import 'dart:convert';

import 'package:dio/dio.dart';

import '../mistral_api_exception.dart';
import 'batch_transcription_client.dart';

/// [BatchTranscriptionClient] over `POST /v1/audio/transcriptions`
/// (multipart form) using dio — no official Dart SDK exists.
///
/// Errors are wrapped in [MistralApiException] with a sanitized message: a raw
/// [DioException] embeds the request headers (which contain the API key), so
/// it is never rethrown or stringified here.
class DioBatchTranscriptionClient implements BatchTranscriptionClient {
  DioBatchTranscriptionClient({
    required String apiKey,
    Dio? dio,
    Uri? baseUri,
  })  : _apiKey = apiKey,
        _dio = dio ?? Dio(defaultBaseOptions(baseUri ?? _defaultBaseUri));

  static final Uri _defaultBaseUri = Uri(scheme: 'https', host: 'api.mistral.ai');

  /// The production dio options: finite connect/send timeouts. Without
  /// them a batch call can wait forever — a stalled response left the
  /// post-session pass spinning indefinitely (found by on-device testing).
  static BaseOptions defaultBaseOptions(Uri baseUri) => BaseOptions(
        baseUrl: baseUri.toString(),
        connectTimeout: defaultConnectTimeout,
        sendTimeout: defaultSendTimeout,
      );

  /// Timeout for establishing the connection.
  static const Duration defaultConnectTimeout = Duration(seconds: 15);

  /// Timeout for sending the request (the audio upload dominates it).
  static const Duration defaultSendTimeout = Duration(minutes: 5);

  /// Receive timeout when the request carries no
  /// [BatchTranscriptionRequest.audioDuration].
  static const Duration defaultReceiveTimeout = Duration(minutes: 10);

  /// The smallest receive timeout: even a few seconds of audio get a full
  /// minute before a stalled response is treated as a timeout.
  static const Duration receiveTimeoutFloor = Duration(seconds: 60);

  /// The receive timeout for a request: proportional to the audio duration
  /// (batch transcription is faster than realtime, so twice the audio
  /// length is generous), floored at [receiveTimeoutFloor]; the fixed
  /// [defaultReceiveTimeout] when the duration is unknown.
  static Duration receiveTimeoutFor(Duration? audioDuration) {
    final duration = audioDuration;
    if (duration == null) {
      return defaultReceiveTimeout;
    }
    final doubled = duration * 2;
    return doubled < receiveTimeoutFloor ? receiveTimeoutFloor : doubled;
  }

  final String _apiKey;
  final Dio _dio;

  @override
  Future<BatchTranscriptionResult> transcribe(
    BatchTranscriptionRequest request,
  ) async {
    final form = FormData();
    form.fields.add(MapEntry('model', request.model));
    form.files.add(MapEntry(
      'file',
      MultipartFile.fromBytes(request.audioBytes, filename: request.fileName),
    ));
    if (request.diarize) {
      // Diarization labels segments, so it requires segment timestamps.
      form.fields.add(const MapEntry('diarize', 'true'));
      form.fields.add(const MapEntry('timestamp_granularities', 'segment'));
    }
    if (request.language != null) {
      form.fields.add(MapEntry('language', request.language!));
    }
    for (final term in request.contextBias) {
      form.fields.add(MapEntry('context_bias', term));
    }
    if (request.speakerReferences.isNotEmpty) {
      // NOTE: the offline wire format for speaker references is not in the
      // public OpenAPI spec. Serialized as one JSON field {name: base64},
      // matching the documented realtime session.update shape. Spike C
      // (task 5.3) verifies this against the live API; if the field is
      // rejected, this is the only place to change.
      form.fields.add(MapEntry(
        'speaker_references',
        jsonEncode({
          for (final entry in request.speakerReferences.entries)
            entry.key: base64Encode(entry.value),
        }),
      ));
    }
    if (request.returnLanguage) {
      form.fields.add(const MapEntry('return_language', 'true'));
    }

    try {
      final response = await _dio.post<dynamic>(
        '/v1/audio/transcriptions',
        data: form,
        options: Options(
          headers: {'Authorization': 'Bearer $_apiKey'},
          receiveTimeout: receiveTimeoutFor(request.audioDuration),
        ),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return BatchTranscriptionResult.fromJson(data);
      }
      throw MistralApiException(
        'Unexpected response from the transcription API',
      );
    } on DioException catch (error) {
      throw MistralApiException(_messageFromDioError(error));
    } catch (error) {
      throw MistralApiException(MistralApiException.sanitize(error, _apiKey));
    }
  }

  /// Extracts a user-presentable message without ever touching
  /// [DioException.toString], which embeds request headers (API key included).
  String _messageFromDioError(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final apiError = data['error'];
      if (apiError is Map<String, dynamic> && apiError['message'] is String) {
        return apiError['message'] as String;
      }
      if (data['message'] is String) {
        return data['message'] as String;
      }
      if (data['detail'] is String) {
        return data['detail'] as String;
      }
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Network timeout while calling the transcription API '
            '(${error.type.name})';
      case DioExceptionType.badResponse:
        return 'Transcription API returned an error '
            '(${error.response?.statusCode ?? 'unknown'})';
      case DioExceptionType.cancel:
        return 'Transcription request cancelled';
      default:
        // Include the underlying cause (e.g. a SocketException from a
        // connection reset mid-upload) so network flakiness is diagnosable.
        final cause = error.error == null
            ? ''
            : ': ${MistralApiException.sanitize(error.error!, _apiKey)}';
        return 'Could not reach the transcription API '
            '(${error.type.name}$cause)';
    }
  }
}
