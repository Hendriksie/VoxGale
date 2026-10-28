import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/mistral/realtime/realtime_events.dart';

/// Fixtures recorded from the Voxtral 3 realtime transcription documentation
/// (event shapes as of 2026-10-21).
void main() {
  test('session.updated becomes SessionStarted with the applied settings', () {
    final event = parseRealtimeEvent({
      'type': 'session.updated',
      'session': {'target_streaming_delay_ms': 480},
    });

    expect(event, isA<SessionStarted>());
    expect(
      (event as SessionStarted).appliedSettings['target_streaming_delay_ms'],
      480,
    );
  });

  test('transcription.text.delta becomes a TextDelta carrying its own spaces', () {
    final event = parseRealtimeEvent({
      'type': 'transcription.text.delta',
      'text': ' for',
    });

    expect(event, isA<TextDelta>());
    expect((event as TextDelta).text, ' for');
  });

  test('transcription.segment becomes a SpeakerSegment without timestamps', () {
    final event = parseRealtimeEvent({
      'type': 'transcription.segment',
      'text': ' today?',
      'start': null,
      'end': null,
      'speaker_id': 'speaker_1',
    });

    expect(event, isA<SpeakerSegment>());
    final segment = event as SpeakerSegment;
    expect(segment.text, ' today?');
    expect(segment.speakerId, 'speaker_1');
  });

  test('turn events parse time and end reason', () {
    expect(
      parseRealtimeEvent({'type': 'turn.start', 'time_s': 0.0}),
      isA<TurnStarted>().having((e) => e.timeS, 'timeS', 0.0),
    );
    expect(
      parseRealtimeEvent({'type': 'turn.eager_end', 'time_s': 1.36}),
      isA<TurnEagerEnd>(),
    );
    expect(
      parseRealtimeEvent({'type': 'turn.resume', 'time_s': 1.44}),
      isA<TurnResumed>(),
    );
    final ended = parseRealtimeEvent({
      'type': 'turn.end',
      'time_s': 35.12,
      'end_reason': 'threshold',
    });
    expect(ended, isA<TurnEnded>());
    expect((ended as TurnEnded).endReason, 'threshold');
  });

  test('transcription.done parses the transcript of record and usage', () {
    final event = parseRealtimeEvent({
      'type': 'transcription.done',
      'text': 'Hello there.',
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
          'text': 'there.',
          'start': 1.2,
          'end': 2.0,
          'speaker_id': 'speaker_2',
        },
      ],
      'language': 'en',
      'model': 'voxtral-mini-transcribe-realtime-3-0',
      'usage': {'prompt_audio_seconds': 34},
    });

    expect(event, isA<TranscriptionDone>());
    final done = event as TranscriptionDone;
    expect(done.fullText, 'Hello there.');
    expect(done.segments, hasLength(2));
    expect(done.segments.first.speakerId, 'speaker_1');
    expect(done.segments.last.end, 2.0);
    expect(done.usage.promptAudioSeconds, 34);
  });

  test('an error event becomes a RealtimeError with message and code', () {
    final event = parseRealtimeEvent({
      'type': 'error',
      'error': {
        'message': 'Diarization is not compatible with turn detection.',
        'code': 'invalid_session_config',
      },
    });

    expect(event, isA<RealtimeError>());
    final error = event as RealtimeError;
    expect(error.message, 'Diarization is not compatible with turn detection.');
    expect(error.code, 'invalid_session_config');
  });

  test('session.created, unknown types, and malformed input return null', () {
    expect(parseRealtimeEvent({'type': 'session.created', 'session': {}}), isNull);
    expect(parseRealtimeEvent({'type': 'some.future.event'}), isNull);
    expect(parseRealtimeEvent({}), isNull);
  });
}
