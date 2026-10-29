// Tests for the agent client (change 2026-10-29-send-transcript-to-agent,
// tasks 1.2-1.3, design decisions 1-4): the agent list parsing (GET
// /v1/agents, both the {data: [...]} envelope and a bare list), the send
// request (POST /v1/conversations with agent_id, the transcript as inputs,
// stream:false and store:false always set, Bearer auth) and reply/usage
// parsing (string and chunked message.output contents), the timeouts, and the
// sanitized error mapping — a raw DioException embeds the API key in its
// headers, so no error message may ever contain it. The dio layer is mocked;
// the live API is never called from tests.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxgale/mistral/agent/agent_client.dart';
import 'package:voxgale/mistral/agent/dio_agent_client.dart';
import 'package:voxgale/mistral/mistral_api_exception.dart';

class MockDio extends Mock implements Dio {}

void main() {
  const replyData = {
    'conversation_id': 'conv_123',
    'outputs': [
      {
        'type': 'tool.execution',
        'name': 'web_search',
        'role': 'assistant',
        'content': '',
      },
      {
        'type': 'message.output',
        'role': 'assistant',
        'content': 'Summary: ',
      },
      {
        'type': 'message.output',
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'three action items.'},
        ],
      },
      {
        'type': 'message.output',
        'role': 'user',
        'content': 'should be ignored',
      },
    ],
    'usage': {
      'prompt_tokens': 1200,
      'completion_tokens': 85.4,
      'total_tokens': 1285,
    },
    'object': 'conversation.response',
  };

  (String, Map<String, dynamic>, Options) capturePost(MockDio dio) {
    final captured = verify(
      () => dio.post(
        captureAny(),
        data: captureAny(named: 'data'),
        options: captureAny(named: 'options'),
      ),
    ).captured;
    // Two Strings are captured (the positional path and the JSON body) —
    // mocktail's capture order is an implementation detail, so pick them by
    // shape: the path starts with '/', the body with '{'.
    final strings = captured.whereType<String>().toList();
    final path = strings.singleWhere((s) => s.startsWith('/'));
    final body = strings.singleWhere((s) => s.startsWith('{'));
    return (
      path,
      jsonDecode(body) as Map<String, dynamic>,
      captured.whereType<Options>().single,
    );
  }

  group('listAgents', () {
    test('parses the {data: [...]} envelope', () async {
      final dio = MockDio();
      when(() => dio.get(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/v1/agents'),
          data: {
            'data': [
              {'id': 'ag_1', 'name': 'Summarizer', 'description': 'Summarizes'},
              {'id': 'ag_2', 'name': 'Note filer'},
            ],
          },
          statusCode: 200,
        ),
      );

      final client = DioAgentClient(apiKey: 'test-key', dio: dio);
      final agents = await client.listAgents();

      expect(agents, [
        const AgentInfo(id: 'ag_1', name: 'Summarizer', description: 'Summarizes'),
        const AgentInfo(id: 'ag_2', name: 'Note filer'),
      ]);
      final captured = verify(
        () => dio.get(captureAny(), options: captureAny(named: 'options')),
      ).captured;
      expect(captured.whereType<String>().single, '/v1/agents');
      expect(
        captured.whereType<Options>().single.headers?['Authorization'],
        'Bearer test-key',
      );
    });

    test('parses a bare list response', () async {
      final dio = MockDio();
      when(() => dio.get(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/v1/agents'),
          data: [
            {'id': 'ag_9', 'name': 'Solo'},
          ],
          statusCode: 200,
        ),
      );

      final agents = await DioAgentClient(apiKey: 'k', dio: dio).listAgents();
      expect(agents.single, const AgentInfo(id: 'ag_9', name: 'Solo'));
    });

    test('a non-list success response surfaces a generic API error', () async {
      final dio = MockDio();
      when(() => dio.get(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/v1/agents'),
          data: 'OK',
          statusCode: 200,
        ),
      );

      await expectLater(
        DioAgentClient(apiKey: 'k', dio: dio).listAgents(),
        throwsA(
          isA<MistralApiException>().having(
            (e) => e.message,
            'message',
            'Unexpected response from the agents API',
          ),
        ),
      );
    });
  });

  group('sendToAgent', () {
    test('posts the one-shot conversation with store:false and parses the '
        'reply and usage', () async {
      final dio = MockDio();
      when(
        () => dio.post(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/v1/conversations'),
          data: replyData,
          statusCode: 200,
        ),
      );

      final client = DioAgentClient(apiKey: 'test-key', dio: dio);
      final reply = await client.sendToAgent(
        agentId: 'ag_1',
        transcript: '# Transcript\nHello',
      );

      final (path, body, options) = capturePost(dio);
      expect(path, '/v1/conversations');
      expect(body['agent_id'], 'ag_1');
      expect(body['inputs'], '# Transcript\nHello');
      expect(body['stream'], false);
      // Privacy: no conversation history is kept server-side.
      expect(body['store'], false);
      expect(options.headers?['Authorization'], 'Bearer test-key');
      expect(
        options.headers?['Content-Type'],
        'application/json',
      );

      // Only assistant message.output entries, string and chunked contents.
      expect(reply.text, 'Summary: \n\nthree action items.');
      expect(reply.promptTokens, 1200);
      expect(reply.completionTokens, 85);
      expect(reply.totalTokens, 1285);
    });

    test('a reply without outputs surfaces an empty text, not a crash',
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
          requestOptions: RequestOptions(path: '/v1/conversations'),
          data: {'outputs': <dynamic>[], 'usage': <String, dynamic>{}},
          statusCode: 200,
        ),
      );

      final reply = await DioAgentClient(apiKey: 'k', dio: dio).sendToAgent(
        agentId: 'ag_1',
        transcript: 'hi',
      );
      expect(reply.text, '');
      expect(reply.totalTokens, isNull);
    });
  });

  group('error kinds', () {
    Future<MistralApiException> sendFailure(MockDio dio, String secret) async {
      try {
        await DioAgentClient(apiKey: secret, dio: dio).sendToAgent(
          agentId: 'ag_1',
          transcript: 'hi',
        );
        fail('the rejection should surface a MistralApiException');
      } on MistralApiException catch (error) {
        return error;
      }
    }

    test('an API error surfaces the response message and never the API key',
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
          path: '/v1/conversations',
          headers: {'Authorization': 'Bearer $secret'},
        ),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/v1/conversations'),
          statusCode: 422,
          data: {
            'error': {'message': 'inputs exceeds the model context window'},
          },
        ),
      ));

      final failure = await sendFailure(dio, secret);
      expect(failure.message, 'inputs exceeds the model context window');
      expect(failure.message, isNot(contains(secret)));
    });

    test('a 404 surfaces the agent-not-found message, never the key', () async {
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
          path: '/v1/conversations',
          headers: {'Authorization': 'Bearer $secret'},
        ),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/v1/conversations'),
          statusCode: 404,
          data: '<html>Not Found</html>',
        ),
      ));

      final failure = await sendFailure(dio, secret);
      expect(failure.message, contains('agent was not found'));
      expect(failure.message, isNot(contains(secret)));
    });

    test('a 401 surfaces the rejected-key message, never the key', () async {
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
          path: '/v1/conversations',
          headers: {'Authorization': 'Bearer $secret'},
        ),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/v1/conversations'),
          statusCode: 401,
          data: 'Unauthorized',
        ),
      ));

      final failure = await sendFailure(dio, secret);
      expect(failure.message, contains('API key was rejected'));
      expect(failure.message, isNot(contains(secret)));
    });

    test('a network failure surfaces a generic sanitized message', () async {
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
          path: '/v1/conversations',
          headers: {'Authorization': 'Bearer $secret'},
        ),
        type: DioExceptionType.connectionError,
        error: Exception('Bearer $secret'),
      ));

      final failure = await sendFailure(dio, secret);
      expect(failure.message, contains('Could not reach the agents API'));
      expect(failure.message, isNot(contains(secret)));
    });

    test('a receive timeout surfaces a timeout message, never the key',
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
          path: '/v1/conversations',
          headers: {'Authorization': 'Bearer $secret'},
        ),
        type: DioExceptionType.receiveTimeout,
      ));

      final failure = await sendFailure(dio, secret);
      expect(failure.message, contains('Network timeout'));
      expect(failure.message, isNot(contains(secret)));
    });
  });

  group('timeouts', () {
    test('the production dio options carry finite connect and send timeouts',
        () {
      final options = DioAgentClient.defaultBaseOptions(
        Uri(scheme: 'https', host: 'api.mistral.ai'),
      );
      expect(options.connectTimeout, const Duration(seconds: 15));
      expect(options.sendTimeout, const Duration(seconds: 15));
    });

    test('the send request carries the fixed 5-minute receive timeout '
        '(agent + tool runs can be slow)', () async {
      final dio = MockDio();
      when(
        () => dio.post(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/v1/conversations'),
          data: replyData,
          statusCode: 200,
        ),
      );

      await DioAgentClient(apiKey: 'k', dio: dio).sendToAgent(
        agentId: 'ag_1',
        transcript: 'hi',
      );

      final (_, _, options) = capturePost(dio);
      expect(options.receiveTimeout, const Duration(minutes: 5));
    });

    test('the list request carries the fixed receive timeout too', () async {
      final dio = MockDio();
      when(() => dio.get(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/v1/agents'),
          data: {'data': <dynamic>[]},
          statusCode: 200,
        ),
      );

      await DioAgentClient(apiKey: 'k', dio: dio).listAgents();

      final captured = verify(
        () => dio.get(any(), options: captureAny(named: 'options')),
      ).captured;
      expect(
        captured.whereType<Options>().single.receiveTimeout,
        const Duration(minutes: 5),
      );
    });
  });
}
