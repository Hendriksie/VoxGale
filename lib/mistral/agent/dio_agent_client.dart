// ignore_for_file: prefer_initializing_formals — like the batch client, the
// API key is a public `apiKey` parameter (a private named parameter would not
// be callable from other libraries).

import 'dart:convert';

import 'package:dio/dio.dart';

import '../mistral_api_exception.dart';
import 'agent_client.dart';

/// [AgentClient] over the Agents/Conversations API using dio — no official
/// Dart SDK exists. `GET /v1/agents` lists the workspace's agents;
/// `POST /v1/conversations` with `{agent_id, inputs, stream: false,
/// store: false}` runs a one-shot agent call and returns the assistant
/// message plus token usage (change 2026-10-29-send-transcript-to-agent,
/// design decision 1). `store: false` is hardcoded: Conversations are
/// stateful and outside Mistral's zero-data-retention coverage, so no
/// conversation history must be kept server-side (design decision 10).
///
/// Errors are wrapped in [MistralApiException] with a sanitized message: a raw
/// [DioException] embeds the request headers (which contain the API key), so
/// it is never rethrown or stringified here.
class DioAgentClient implements AgentClient {
  DioAgentClient({
    required String apiKey,
    Dio? dio,
    Uri? baseUri,
  })  : _apiKey = apiKey,
        _dio = dio ?? Dio(defaultBaseOptions(baseUri ?? _defaultBaseUri));

  static final Uri _defaultBaseUri = Uri(scheme: 'https', host: 'api.mistral.ai');

  /// The production dio options: finite connect/send timeouts. Without them a
  /// call can wait forever (dio has no default timeouts).
  static BaseOptions defaultBaseOptions(Uri baseUri) => BaseOptions(
        baseUrl: baseUri.toString(),
        connectTimeout: defaultConnectTimeout,
        sendTimeout: defaultSendTimeout,
      );

  /// Timeout for establishing the connection.
  static const Duration defaultConnectTimeout = Duration(seconds: 15);

  /// Timeout for sending the request (the payload is text, so quick).
  static const Duration defaultSendTimeout = Duration(seconds: 15);

  /// The receive timeout for agent calls: fixed, not scaled — an agent with
  /// tools (web search, connectors) can take minutes, and there is no audio
  /// duration to scale by.
  static const Duration defaultReceiveTimeout = Duration(minutes: 5);

  final String _apiKey;
  final Dio _dio;

  @override
  Future<List<AgentInfo>> listAgents() async {
    try {
      final response = await _dio.get<dynamic>(
        '/v1/agents',
        options: _authOptions,
      );
      final data = response.data;
      final list = data is Map<String, dynamic> && data['data'] is List
          ? data['data'] as List
          : data is List
              ? data
              : null;
      if (list == null) {
        throw MistralApiException('Unexpected response from the agents API');
      }
      return [
        for (final entry in list)
          if (entry is Map<String, dynamic>) AgentInfo.fromJson(entry),
      ];
    } on MistralApiException {
      rethrow;
    } on DioException catch (error) {
      throw MistralApiException(_messageFromDioError(error));
    } catch (error) {
      throw MistralApiException(MistralApiException.sanitize(error, _apiKey));
    }
  }

  @override
  Future<AgentReply> sendToAgent({
    required String agentId,
    required String transcript,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/v1/conversations',
        data: jsonEncode({
          'agent_id': agentId,
          'inputs': transcript,
          'stream': false,
          'store': false,
        }),
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: defaultReceiveTimeout,
        ),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw MistralApiException('Unexpected response from the agents API');
      }
      return AgentReply.fromJson(data);
    } on MistralApiException {
      rethrow;
    } on DioException catch (error) {
      throw MistralApiException(_messageFromDioError(error));
    } catch (error) {
      throw MistralApiException(MistralApiException.sanitize(error, _apiKey));
    }
  }

  Options get _authOptions => Options(
        headers: {'Authorization': 'Bearer $_apiKey'},
        receiveTimeout: defaultReceiveTimeout,
      );

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
    final status = error.response?.statusCode;
    switch (error.type) {
      case DioExceptionType.badResponse:
        if (status == 401 || status == 403) {
          return 'The API key was rejected. Check the key in Settings and try again.';
        }
        if (status == 404) {
          return 'The selected agent was not found. Pick another agent in Settings.';
        }
        return 'The agents API returned an error '
            '(${status ?? 'unknown'})';
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Network timeout while calling the agents API '
            '(${error.type.name})';
      case DioExceptionType.cancel:
        return 'The agent request was cancelled';
      default:
        // Include the underlying cause (e.g. a SocketException) so network
        // flakiness is diagnosable — sanitized, so the key never leaks.
        final cause = error.error == null
            ? ''
            : ': ${MistralApiException.sanitize(error.error!, _apiKey)}';
        return 'Could not reach the agents API '
            '(${error.type.name}$cause)';
    }
  }
}
