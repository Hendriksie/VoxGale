import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxtral_live/mistral/mistral_api_exception.dart';
import 'package:voxtral_live/mistral/mistral_config.dart';
import 'package:voxtral_live/mistral/realtime/realtime_events.dart';
import 'package:voxtral_live/mistral/realtime/realtime_session_config.dart';
import 'package:voxtral_live/mistral/realtime/web_socket_realtime_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class MockWebSocketChannel extends Mock implements WebSocketChannel {}

/// A [WebSocketSink] that records everything sent to it, in order.
class RecordingWebSocketSink implements WebSocketSink {
  final List<Object?> messages = [];
  bool closed = false;

  @override
  void add(Object? data) => messages.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final _ in stream) {}
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
  }

  @override
  Future<void> get done async {}

  List<Map<String, dynamic>> jsonMessages() => messages
      .whereType<String>()
      .map((m) => jsonDecode(m) as Map<String, dynamic>)
      .toList();
}

void main() {
  /// Lets the event loop run until [condition] holds (with a timeout).
  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  MockWebSocketChannel mockChannel(
    StreamController<String> incoming,
    RecordingWebSocketSink sink,
  ) {
    final channel = MockWebSocketChannel();
    when(() => channel.stream).thenAnswer((_) => incoming.stream);
    when(() => channel.sink).thenAnswer((_) => sink);
    when(() => channel.ready).thenAnswer((_) async {});
    return channel;
  }

  test('full lifecycle: config before audio, base64 chunks, end, done', () async {
    final incoming = StreamController<String>();
    final sink = RecordingWebSocketSink();
    final channel = mockChannel(incoming, sink);

    final uris = <Uri>[];
    final client = WebSocketRealtimeClient(
      apiKey: 'test-key',
      config: MistralConfig.defaults,
      keepAliveAfter: null,
      channelFactory: (uri, headers) {
        uris.add(uri);
        expect(headers, {'Authorization': 'Bearer test-key'});
        return channel;
      },
    );

    final sessionFuture = client.startSession(
      RealtimeSessionConfig(turnDetection: TurnDetectionConfig()),
    );
    incoming.add(jsonEncode({'type': 'session.created', 'session': {}}));
    incoming.add(jsonEncode({
      'type': 'session.updated',
      'session': {'turn_detection': <String, dynamic>{}},
    }));
    final session = await sessionFuture;

    // session.update went out before any audio, with the full config.
    expect(sink.jsonMessages(), hasLength(1));
    final update = sink.jsonMessages().single;
    expect(update['type'], 'session.update');
    expect(update['session']['turn_detection'], isA<Map>());
    expect(update['session']['audio_format'], {
      'encoding': 'pcm_s16le',
      'sample_rate': 16000,
    });
    expect(update['session']['target_streaming_delay_ms'], 480);
    expect(
      uris.single.toString(),
      contains('voxtral-mini-transcribe-realtime-3-0'),
    );

    final events = <RealtimeEvent>[];
    final sub = session.events.listen(events.add);

    session.sendAudio(Uint8List.fromList([1, 2, 3, 4]));
    final messages = sink.jsonMessages();
    expect(messages[1]['type'], 'input_audio.append');
    expect(base64Decode(messages[1]['audio'] as String), [1, 2, 3, 4]);

    incoming.add(jsonEncode({'type': 'transcription.text.delta', 'text': ' hello'}));
    incoming.add(jsonEncode({'type': 'turn.start', 'time_s': 0.12}));
    incoming.add(jsonEncode({
      'type': 'turn.end',
      'time_s': 2.5,
      'end_reason': 'threshold',
    }));

    final doneFuture = session.end();
    expect(sink.jsonMessages().last, {'type': 'input_audio.end'});
    incoming.add(jsonEncode({
      'type': 'transcription.done',
      'text': ' hello',
      'segments': [],
      'language': 'en',
      'model': 'voxtral-mini-transcribe-realtime-3-0',
      'usage': {'prompt_audio_seconds': 3},
    }));
    await doneFuture;
    await pumpEventQueue();

    // Note: SessionStarted is emitted at connect time, before subscribers
    // can attach to the broadcast stream (the UI learns of reconnects via
    // Reconnected), so it is intentionally not asserted here.
    expect(events.whereType<TextDelta>().single.text, ' hello');
    expect(events.whereType<TurnStarted>().single.timeS, 0.12);
    expect(events.whereType<TurnEnded>().single.endReason, 'threshold');
    final done = events.whereType<TranscriptionDone>().single;
    expect(done.fullText, ' hello');
    expect(done.usage.promptAudioSeconds, 3);

    expect(sink.closed, isTrue);
    await sub.cancel();
    await session.dispose();
    await incoming.close();
  });

  test('diarize mode streams transcription.segment events instead of deltas',
      () async {
    final incoming = StreamController<String>();
    final sink = RecordingWebSocketSink();
    final channel = mockChannel(incoming, sink);

    final client = WebSocketRealtimeClient(
      apiKey: 'test-key',
      config: MistralConfig.defaults,
      keepAliveAfter: null,
      channelFactory: (uri, headers) => channel,
    );

    final sessionFuture = client.startSession(
      RealtimeSessionConfig(diarize: true),
    );
    incoming.add(jsonEncode({'type': 'session.created', 'session': {}}));
    incoming.add(jsonEncode({
      'type': 'session.updated',
      'session': {'diarize': true},
    }));
    final session = await sessionFuture;

    expect(
      (sink.jsonMessages().single['session'] as Map)['diarize'],
      true,
    );

    final events = <RealtimeEvent>[];
    final sub = session.events.listen(events.add);
    incoming.add(jsonEncode({
      'type': 'transcription.segment',
      'text': ' Hi,',
      'start': null,
      'end': null,
      'speaker_id': 'speaker_2',
    }));
    await pumpEventQueue();

    final segment = events.whereType<SpeakerSegment>().single;
    expect(segment.text, ' Hi,');
    expect(segment.speakerId, 'speaker_2');

    await sub.cancel();
    await session.dispose();
    await incoming.close();
  });

  test('reconnects with the identical config and replays buffered audio',
      () async {
    final incoming1 = StreamController<String>();
    final incoming2 = StreamController<String>();
    final sink1 = RecordingWebSocketSink();
    final sink2 = RecordingWebSocketSink();
    final channel1 = mockChannel(incoming1, sink1);
    final channel2 = mockChannel(incoming2, sink2);

    var call = 0;
    final log = <String>[];
    final client = WebSocketRealtimeClient(
      apiKey: 'test-key',
      config: MistralConfig.defaults,
      keepAliveAfter: null,
      reconnectDelay: const Duration(milliseconds: 10),
      channelFactory: (uri, headers) => [channel1, channel2][call++],
      debugLog: log.add,
    );

    final sessionFuture = client.startSession(
      RealtimeSessionConfig(language: 'en'),
    );
    incoming1.add(jsonEncode({'type': 'session.created', 'session': {}}));
    incoming1.add(jsonEncode({'type': 'session.updated', 'session': {}}));
    final session = await sessionFuture;

    final events = <RealtimeEvent>[];
    final sub = session.events.listen(events.add);

    session.sendAudio(Uint8List.fromList([1])); // sent on channel 1
    expect(
      sink1.jsonMessages().where((m) => m['type'] == 'input_audio.append'),
      hasLength(1),
    );

    // The connection drops; audio sent meanwhile is buffered locally.
    incoming1.addError(Exception('network down'));
    // Stream delivery is asynchronous: wait until the client has processed
    // the drop (and marked itself disconnected) before sending more audio.
    await waitFor(() => events.whereType<RealtimeError>().isNotEmpty);
    session.sendAudio(Uint8List.fromList([2]));
    session.sendAudio(Uint8List.fromList([3]));
    expect(
      sink1.jsonMessages().where((m) => m['type'] == 'input_audio.append'),
      hasLength(1),
    );
    // The buffer gauge reports the buffered audio while disconnected.
    expect(session.bufferedAudioSeconds, greaterThan(0));

    // The client opens a second connection.
    await waitFor(() => call == 2);
    expect(call, 2);

    incoming2.add(jsonEncode({'type': 'session.created', 'session': {}}));
    await pumpEventQueue();
    // Identical config is resent on the new session before any audio.
    final update = sink2.jsonMessages().single;
    expect(update['type'], 'session.update');
    expect(update['session']['language'], 'en');

    incoming2.add(jsonEncode({
      'type': 'session.updated',
      'session': update['session'],
    }));
    await pumpEventQueue();

    // Buffered audio is replayed after the session is ready again.
    final appends = sink2
        .jsonMessages()
        .where((m) => m['type'] == 'input_audio.append')
        .toList();
    expect(appends, hasLength(2));
    expect(base64Decode(appends[0]['audio'] as String), [2]);
    expect(base64Decode(appends[1]['audio'] as String), [3]);

    expect(events.whereType<Reconnected>(), hasLength(1));
    // The drop reason travels inside the Reconnected event.
    expect(
      events.whereType<Reconnected>().single.dropReason,
      contains('network down'),
    );
    expect(events.whereType<RealtimeError>(), hasLength(1));
    // The replay is reported once it completes.
    final replayed = events.whereType<BufferedAudioReplayed>().single;
    expect(replayed.seconds, greaterThan(0));
    expect(session.bufferedAudioSeconds, 0);
    // The trace log saw the drop and the recovery.
    expect(log.any((m) => m.contains('stream error')), isTrue);
    expect(log.where((m) => m.contains('session ready')), hasLength(2));

    // Text continues seamlessly: deltas are append-only, never rewritten.
    incoming2.add(jsonEncode({'type': 'transcription.text.delta', 'text': ' world'}));
    await pumpEventQueue();
    expect(events.whereType<TextDelta>().single.text, ' world');

    final doneFuture = session.end();
    incoming2.add(jsonEncode({
      'type': 'transcription.done',
      'text': ' world',
      'segments': [],
      'language': 'en',
      'model': 'voxtral-mini-transcribe-realtime-3-0',
      'usage': {'prompt_audio_seconds': 1},
    }));
    await doneFuture;

    await sub.cancel();
    await session.dispose();
    await incoming1.close();
    await incoming2.close();
  });

  test('drops the oldest buffered audio beyond the cap and emits '
      'BufferedAudioDropped', () async {
    final incoming1 = StreamController<String>();
    final incoming2 = StreamController<String>();
    final sink1 = RecordingWebSocketSink();
    final sink2 = RecordingWebSocketSink();
    final channel1 = mockChannel(incoming1, sink1);
    final channel2 = mockChannel(incoming2, sink2);

    var call = 0;
    final log = <String>[];
    // Cap = 100 ms of audio = 3,200 bytes at 16 kHz PCM16 mono (32 KB/s), so
    // the buffer holds two 1,600-byte (50 ms) chunks; the rest is dropped.
    final client = WebSocketRealtimeClient(
      apiKey: 'test-key',
      config: MistralConfig.defaults,
      keepAliveAfter: null,
      reconnectDelay: const Duration(milliseconds: 10),
      bufferCap: const Duration(milliseconds: 100),
      channelFactory: (uri, headers) => [channel1, channel2][call++],
      debugLog: log.add,
    );

    Uint8List chunk(int marker) {
      final bytes = Uint8List(1600);
      bytes[0] = marker;
      return bytes;
    }

    final sessionFuture = client.startSession(RealtimeSessionConfig());
    incoming1.add(jsonEncode({'type': 'session.created', 'session': {}}));
    incoming1.add(jsonEncode({'type': 'session.updated', 'session': {}}));
    final session = await sessionFuture;

    final events = <RealtimeEvent>[];
    final sub = session.events.listen(events.add);

    // The connection drops; the outage outlasts the buffer cap.
    incoming1.addError(Exception('network down'));
    await waitFor(() => events.whereType<RealtimeError>().isNotEmpty);

    // Four 50 ms chunks arrive while disconnected; the cap holds two.
    session.sendAudio(chunk(1));
    session.sendAudio(chunk(2));
    session.sendAudio(chunk(3));
    session.sendAudio(chunk(4));
    // The drop events are delivered on the broadcast stream asynchronously.
    await pumpEventQueue();
    expect(
      sink1.jsonMessages().where((m) => m['type'] == 'input_audio.append'),
      isEmpty,
    );

    // The oldest chunks (1, 2) were dropped: one event per drop, and the
    // gauge reports only what is still buffered (2 chunks = 0.1 s).
    final dropped = events.whereType<BufferedAudioDropped>().toList();
    expect(dropped, hasLength(2));
    expect(dropped[0].seconds, closeTo(0.05, 1e-9));
    expect(dropped[1].seconds, closeTo(0.05, 1e-9));
    expect(session.bufferedAudioSeconds, closeTo(0.1, 1e-9));
    expect(
      log.any((m) => m.contains('dropped') && m.contains('buffered audio')),
      isTrue,
    );

    // The client reconnects; only the surviving chunks (3, 4) are replayed,
    // oldest first — nothing is duplicated or reordered.
    await waitFor(() => call == 2);
    incoming2.add(jsonEncode({'type': 'session.created', 'session': {}}));
    incoming2.add(jsonEncode({'type': 'session.updated', 'session': {}}));
    await waitFor(() => events.whereType<BufferedAudioReplayed>().isNotEmpty);

    final appends = sink2
        .jsonMessages()
        .where((m) => m['type'] == 'input_audio.append')
        .toList();
    expect(appends, hasLength(2));
    expect(base64Decode(appends[0]['audio'] as String)[0], 3);
    expect(base64Decode(appends[1]['audio'] as String)[0], 4);
    expect(
      events.whereType<BufferedAudioReplayed>().single.seconds,
      closeTo(0.1, 1e-9),
    );
    expect(events.whereType<Reconnected>(), hasLength(1));
    expect(session.bufferedAudioSeconds, 0);

    final doneFuture = session.end();
    incoming2.add(jsonEncode({
      'type': 'transcription.done',
      'text': '',
      'segments': [],
      'language': 'en',
      'model': 'voxtral-mini-transcribe-realtime-3-0',
      'usage': {'prompt_audio_seconds': 1},
    }));
    await doneFuture;

    await sub.cancel();
    await session.dispose();
    await incoming1.close();
    await incoming2.close();
  });

  test('oversized audio chunks are split into multiple messages', () async {
    final incoming = StreamController<String>();
    final sink = RecordingWebSocketSink();
    final channel = mockChannel(incoming, sink);

    final client = WebSocketRealtimeClient(
      apiKey: 'test-key',
      config: MistralConfig.defaults,
      keepAliveAfter: null,
      channelFactory: (uri, headers) => channel,
    );
    final sessionFuture = client.startSession(RealtimeSessionConfig());
    incoming.add(jsonEncode({'type': 'session.created', 'session': {}}));
    incoming.add(jsonEncode({'type': 'session.updated', 'session': {}}));
    final session = await sessionFuture;

    // 40,000 bytes in, two messages out: 32,768 + 7,232.
    session.sendAudio(Uint8List(40000));
    final appends = sink
        .jsonMessages()
        .where((m) => m['type'] == 'input_audio.append')
        .toList();
    expect(appends, hasLength(2));
    expect(base64Decode(appends[0]['audio'] as String).length, 32768);
    expect(base64Decode(appends[1]['audio'] as String).length, 7232);

    await session.dispose();
    await incoming.close();
  });

  test('keep-alive feeds silence when the mic stops delivering', () async {
    final incoming = StreamController<String>();
    final sink = RecordingWebSocketSink();
    final channel = mockChannel(incoming, sink);

    final client = WebSocketRealtimeClient(
      apiKey: 'test-key',
      config: MistralConfig.defaults,
      channelFactory: (uri, headers) => channel,
      keepAliveAfter: const Duration(milliseconds: 50),
    );
    final sessionFuture = client.startSession(RealtimeSessionConfig());
    incoming.add(jsonEncode({'type': 'session.created', 'session': {}}));
    incoming.add(jsonEncode({'type': 'session.updated', 'session': {}}));
    final session = await sessionFuture;

    // No audio for >50 ms -> the feed sends a 100 ms silence chunk.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final appends = sink
        .jsonMessages()
        .where((m) => m['type'] == 'input_audio.append')
        .toList();
    expect(appends, isNotEmpty);
    expect(base64Decode(appends.first['audio'] as String), Uint8List(3200));

    await session.dispose();
    await incoming.close();
  });

  test('a connection failure surfaces a sanitized MistralApiException',
      () async {
    const secret = 'sk-super-secret';
    final client = WebSocketRealtimeClient(
      apiKey: secret,
      config: MistralConfig.defaults,
      keepAliveAfter: null,
      channelFactory: (uri, headers) =>
          throw Exception('connect failed for ${headers['Authorization']}'),
    );

    await expectLater(
      client.startSession(RealtimeSessionConfig()),
      throwsA(
        isA<MistralApiException>()
            .having((e) => e.message, 'message', isNot(contains(secret))),
      ),
    );
  });
}
