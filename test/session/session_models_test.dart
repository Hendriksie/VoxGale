import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voxtral_live/mistral/realtime/realtime_events.dart';
import 'package:voxtral_live/mistral/transcript.dart';
import 'package:voxtral_live/session/session_models.dart';

void main() {
  group('SessionEvent JSON round-trip', () {
    final events = <SessionEvent>[
      const SessionTextDelta('Hello '),
      const SessionSpeakerSegment(text: 'world', speakerId: 'speaker_1'),
      const SessionTurnStarted(1.5),
      const SessionTurnEnded(timeS: 4.25, endReason: 'threshold'),
      const SessionReconnected(dropReason: 'closeCode: 1006'),
      const SessionReconnected(),
      const SessionBufferedAudioReplayed(12.5),
      const SessionBufferedAudioDropped(3.75),
      SessionTranscriptionDone(
        fullText: 'Hello world',
        segments: const [
          TranscriptSegment(text: 'Hello ', start: 0, end: 1.5),
          TranscriptSegment(
            text: 'world',
            start: 1.5,
            end: 2.5,
            speakerId: 'speaker_1',
          ),
        ],
        language: 'en',
        model: 'voxtral-mini-transcribe-realtime-3-0',
        usage: const Usage(promptAudioSeconds: 61),
      ),
      SessionEnded(
        sessionId: 'session-1',
        audioPath: '/docs/sessions/session-1.wav',
        fullText: 'Hello world',
        segments: const [TranscriptSegment(text: 'Hello world')],
        language: 'en',
        model: 'voxtral-mini-transcribe-realtime-3-0',
        usage: const Usage(promptAudioSeconds: 61),
      ),
      const SessionError('boom'),
    ];

    test('the round-trip list covers every SessionEvent subtype', () {
      final covered = events.map((e) => e.runtimeType).toSet();
      expect(covered, {
        SessionTextDelta,
        SessionSpeakerSegment,
        SessionTurnStarted,
        SessionTurnEnded,
        SessionReconnected,
        SessionBufferedAudioReplayed,
        SessionBufferedAudioDropped,
        SessionTranscriptionDone,
        SessionEnded,
        SessionError,
      });
    });

    test('every event type survives a JSON round-trip', () {
      for (final event in events) {
        final wire = jsonEncode(event.toJson());
        final decoded = SessionEvent.fromJson(
          jsonDecode(wire) as Map<String, dynamic>,
        );
        expect(decoded.toJson(), event.toJson(), reason: wire);
      }
    });

    test('fromWire decodes a JSON string payload from the data channel', () {
      const event = SessionTextDelta('hi');
      final decoded = SessionEvent.fromWire(jsonEncode(event.toJson()));
      expect(decoded, isA<SessionTextDelta>());
      expect(decoded!.toJson(), event.toJson());
    });

    test('fromWire returns null for payloads that are not session events',
        () {
      expect(SessionEvent.fromWire('not json'), isNull);
      expect(SessionEvent.fromWire(42), isNull);
      expect(SessionEvent.fromWire(jsonEncode(['a'])), isNull);
      expect(SessionEvent.fromWire(jsonEncode({'type': 'nope'})), isNull);
    });

    test('fromJson rejects unknown event types', () {
      expect(
        () => SessionEvent.fromJson(const {'type': 'nope'}),
        throwsFormatException,
      );
    });
  });

  group('sessionEventFromRealtime', () {
    final cases = <RealtimeEvent, SessionEvent?>{
      const TextDelta('a'): const SessionTextDelta('a'),
      const SpeakerSegment(text: 'b', speakerId: 'speaker_1'):
          const SessionSpeakerSegment(text: 'b', speakerId: 'speaker_1'),
      const TurnStarted(1.5): const SessionTurnStarted(1.5),
      const TurnEnded(timeS: 4.25, endReason: 'threshold'):
          const SessionTurnEnded(timeS: 4.25, endReason: 'threshold'),
      const Reconnected(dropReason: 'closeCode: 1006'):
          const SessionReconnected(dropReason: 'closeCode: 1006'),
      const Reconnected(): const SessionReconnected(),
      const BufferedAudioReplayed(12.5):
          const SessionBufferedAudioReplayed(12.5),
      const BufferedAudioDropped(3.75):
          const SessionBufferedAudioDropped(3.75),
      TranscriptionDone(
        fullText: 'hi',
        segments: const [TranscriptSegment(text: 'hi')],
        language: 'en',
        model: 'm',
        usage: const Usage(promptAudioSeconds: 3),
      ): SessionTranscriptionDone(
        fullText: 'hi',
        segments: const [TranscriptSegment(text: 'hi')],
        language: 'en',
        model: 'm',
        usage: const Usage(promptAudioSeconds: 3),
      ),
      const RealtimeError(message: 'boom'): const SessionError('boom'),
      // Events the UI does not need:
      const SessionStarted({}): null,
      const TurnEagerEnd(1): null,
      const TurnResumed(1): null,
    };

    test('maps every domain event subtype', () {
      for (final entry in cases.entries) {
        final mapped = sessionEventFromRealtime(entry.key);
        if (entry.value == null) {
          expect(mapped, isNull, reason: entry.key.runtimeType.toString());
        } else {
          expect(
            mapped!.toJson(),
            entry.value!.toJson(),
            reason: entry.key.runtimeType.toString(),
          );
        }
      }
    });
  });

  group('CaptureCommand', () {
    test('wire values round-trip', () {
      for (final command in CaptureCommand.values) {
        expect(CaptureCommand.fromWire(command.wireValue), command);
      }
    });

    test('unknown payloads parse to null', () {
      expect(CaptureCommand.fromWire('restart'), isNull);
      expect(CaptureCommand.fromWire(42), isNull);
      expect(CaptureCommand.fromWire(null), isNull);
    });
  });

  group('TranscriptTurn', () {
    test('copyWith accumulates text and keeps the speaker label', () {
      const turn = TranscriptTurn(speakerLabel: 'speaker_1', text: 'Hello');
      final updated = turn.copyWith(text: 'Hello world');
      expect(updated.text, 'Hello world');
      expect(updated.speakerLabel, 'speaker_1');
      expect(updated.isProvisional, isTrue);
    });

    test('a finalized turn is not provisional', () {
      final turn =
          const TranscriptTurn(text: 'hi').copyWith(isProvisional: false);
      expect(turn.isProvisional, isFalse);
    });

    test('value equality', () {
      expect(
        const TranscriptTurn(speakerLabel: 's', text: 't'),
        const TranscriptTurn(speakerLabel: 's', text: 't'),
      );
      expect(
        const TranscriptTurn(text: 't'),
        isNot(const TranscriptTurn(text: 't', isProvisional: false)),
      );
    });
  });
}
