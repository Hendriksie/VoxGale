# Tasks

## 1. Scaffold the Flutter app

- [x] 1.1 Create the Flutter project (Android-first) at the repository root, inside the existing git repo; verify `flutter analyze` runs and `flutter build apk --debug` succeeds
- [x] 1.2 Add dependencies — flutter_riverpod, record, flutter_foreground_task, web_socket_channel, dio, flutter_secure_storage, drift, and mocktail (dev) — with the one-line justifications recorded in proposal.md; verify `flutter pub get` succeeds
- [x] 1.3 Define Material 3 light and dark themes seeded with Mistral orange #FF7000 plus a minimal app shell with a home route; verify both themes render correctly in a widget test
- [x] 1.4 Declare Android requirements in the manifest: RECORD_AUDIO permission, the foreground service with android:foregroundServiceType="microphone", and the FOREGROUND_SERVICE_MICROPHONE permission (API 34+); verify the manifest merges via a debug build

## 2. Build the lib/mistral/ client layer

- [x] 2.1 Create the single config source pinning model IDs (voxtral-mini-transcribe-realtime-3-0, voxtral-mini-transcribe-3-0, voxtral-small-transcribe-3-0) and per-minute rates ($0.008 / $0.0035 / $0.004); verify a unit test loads and exposes them
- [x] 2.2 Define the realtime client interface and the normalized domain event model (text delta, speaker-labelled segment, turn start/end, done with usage, error) so UI code never sees protocol event shapes; verify mocktail-based unit tests against recorded event fixtures
- [x] 2.3 Implement the realtime WebSocket client: Bearer-auth connect, wait for session.created, send session.update with the full config before any audio (settings lock), stream base64 input_audio.append chunks, send input_audio.end, parse the full event catalog including error events; verify unit tests with a mocked WebSocket channel — never the live API
- [x] 2.4 Implement reconnect with local audio buffering: on drop, open a new session with the identical config and replay buffered audio, keeping already-displayed text intact (deltas are append-only); verify a unit test that simulates a mid-stream disconnect
- [x] 2.5 Implement the batch REST client: multipart POST /v1/audio/transcriptions with model, file, diarize=true, timestamp_granularities=segment, optional language and context_bias; parse speaker-labelled segments and usage.prompt_audio_seconds; verify unit tests with a mocked HTTP client — never the live API
- [x] 2.6 Wire API key access: the key is read from secure storage and injected only into the lib/mistral/ clients, never logged or included in errors; verify a unit test that client failures never leak the key

## 3. Spike A — realtime path (manual proof against the live API)

- [x] 3.1 Wire mic → record PCM16 stream (16 kHz mono) → realtime client → text on screen; verify by running the spike and speaking: transcript text appears within seconds
- [x] 3.2 Run Spike A in both session modes (turn_detection and diarize) on the same conversation; verify a written spike note records latency, turn grouping, and label quality for both modes (answers the design's open question on diarization quality)
- [x] 3.3 Capture usage from transcription.done during the spike; verify the reported billed duration matches elapsed time within a small tolerance and that estimated vs actual cost math is correct

## 4. Spike B — background capture (physical-device smoke test)

- [x] 4.1 PHYSICAL-DEVICE SMOKE TEST: start a session, then turn the screen off; verify on a real device (emulators lie about background capture) that capture and transcription continue for 30+ minutes screen-off, the persistent notification remains, and the transcript keeps growing
- [x] 4.2 On the same physical device, toggle airplane mode mid-session; verify the client reconnects, buffered audio is transcribed, and the transcript continues without gaps or duplicates

## 5. Spike C — batch path and limits verification (manual proof against the live API)

- [x] 5.1 Transcribe a hard-coded file through the batch client with diarize=true; verify the speaker-labelled transcript renders with speaker IDs and segment timestamps
- [ ] 5.2 Verify the Voxtral 3 file-transcription limits with a long file (maximum duration/size) and whether the 50%-off batch service tier is exposed for audio; verify a written spike note records both answers (answers the design's open questions on limits and batch tier)
- [ ] 5.3 Exercise a speaker reference clip (3–15 s) in both batch and realtime modes; verify segments carry the enrolled speaker's name

> Deferred 2026-10-23 (user decision): tasks 5.2 and 5.3 move to a future
> version — the batch/file-transcription feature lands in Phase 2 anyway.
> The batch client (`lib/mistral/batch/`) stays: built and unit-tested. 5.1 was
> verified on device before the deferral.
>
> 6.4 closed 2026-10-23: spike-notes.md is the collected phase output. Every
> open question in design.md is answered (live diarization quality) or
> explicitly deferred with the Spike C deferral (batch tier, max duration).

## 6. Integration checks

- [x] 6.1 Run the full unit test suite; verify all tests pass with the Mistral layer mocked and no live API calls
- [x] 6.2 Run flutter analyze; verify zero issues
- [x] 6.3 Run openspec validate --strict for this change; verify it passes
- [x] 6.4 Collect the spike notes from groups 3–5 into the phase output; verify the notes answer all open questions recorded in design.md

## Workflow follow-up

- Review the change (proposal, specs, design, tasks, spike notes) before archiving.
- Archive the change only after tests pass and the review is complete.
