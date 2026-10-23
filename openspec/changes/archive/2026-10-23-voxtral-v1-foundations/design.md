# Design

## Context

Greenfield: the app exists only as `project-plan.md`; this change creates the Flutter project and proves the three riskiest paths (realtime streaming, background capture, batch diarization). See proposal.md for motivation.

The exploration phase verified the plan against the live Mistral docs on 2026-10-21 and found the Voxtral 3 family (Public Preview, released 2026-10-20) changes the contract the plan assumed: new model IDs, opt-in realtime diarization, turn detection, a JSON+base64 WebSocket framing, and a session-settings lock. The specs in this change encode the corrected, v1-target behavior; this change implements Phase 0 only.

Hard constraints from project configuration: all Mistral API code lives in `lib/mistral/` behind abstract interfaces; the API key lives in secure storage only and is sent only to `api.mistral.ai` over TLS; the WebSocket client must handle reconnect + local audio buffering; tests mock the Mistral layer and never hit the live API.

## Goals / Non-Goals

**Goals:**
- Prove the realtime path end-to-end (mic → PCM16 → WebSocket → text on screen) in both session modes.
- Prove background capture survives screen-off for 30+ minutes on a real device.
- Prove the batch path (file → diarized, speaker-labelled transcript) and verify the API limits the post-session pass depends on.
- Establish the `lib/mistral/` client layer, the app scaffold, and the orange Material 3 themes that later phases build on.

**Non-Goals:**
- Production live-mode UI, file-import mode, settings screens, transcript history, or the cost indicator beyond what the spikes need (those are Phases 1–2, follow-up changes against the same specs).
- iOS, cloud sync, accounts, text-to-speech, agent integration.
- Compressed audio storage (the spike tees to WAV only).

## Decisions

### D1 — Live-mode speaker strategy: hybrid by default, live diarization as a per-session toggle

A Voxtral 3 realtime session accepts `diarize: true` XOR a `turn_detection` object — setting both returns an error event. The v1 default is the hybrid: the live session runs with turn detection (turn events drive turn grouping), session audio is saved locally, and a post-session batch pass with `diarize=true` produces the speaker-labelled final transcript that replaces the provisional live text. This matches Mistral's own recommended pattern for "answer live + keep a speaker-labelled record". A per-session toggle switches to live diarization (`diarize: true`, segments arrive labelled, turns grouped by speaker change) for users who want labels immediately and accept losing turn events and timestamps.

The `lib/mistral/` realtime client normalizes both event shapes (`transcription.text.delta` + `turn.*`, or `transcription.segment`) into one domain event stream, so the UI never branches on session mode and the toggle is a config value, not a code path.

*Alternatives considered:*
- **Live diarization only** — cheapest (~$0.008/min, no audio retention, no post-session wait) but no silence-based turn events, no timestamps, and preview-model quality. Kept as the toggle, not the default.
- **Dual parallel sessions** (one diarized, one turn-detecting, same mic) — everything live, but 2× realtime cost, 2× sockets, 2× battery/network load. Rejected for v1.

### D2 — Isolate all Mistral API code in `lib/mistral/` behind interfaces

Two interfaces: a realtime WebSocket client and a batch REST client. UI and foreground-service code depend only on the interfaces and on normalized domain events/value objects. This is the mitigation for the biggest identified risk (Voxtral 3 is Public Preview; model IDs, event shapes, and pricing will move) and it makes the whole layer mockable in tests.

*Alternative considered:* a thin API wrapper used directly from UI code — rejected; it couples every screen to protocol details and makes reconnect/buffering logic untestable.

### D3 — Pin full Voxtral 3 model IDs in one config source

Pinned IDs: realtime `voxtral-mini-transcribe-realtime-3-0`; batch `voxtral-mini-transcribe-3-0` and `voxtral-small-transcribe-3-0`. The same config source holds each model's per-minute rate (used by the cost indicator) and the app's cost rates: $0.008/min realtime, $0.0035/min Mini batch, $0.004/min Small batch (standard tier).

*Alternative considered:* `-latest` aliases — rejected because aliases can be silently moved to newer model versions, which would change behavior and price without any code change.

### D4 — The foreground service owns capture and the WebSocket, in its own Dart isolate

Background capture requires an Android foreground service of type `microphone` (declared in the manifest, with the `FOREGROUND_SERVICE_MICROPHONE` permission on API 34+). The service task runs in a separate Dart isolate from the UI, so the recorder and the WebSocket client live there and communicate with the UI isolate through the plugin's data channel (session commands down, normalized transcript events up).

Because a realtime session locks its settings after the first audio chunk, the full session configuration (audio format, streaming delay, language, context bias, diarize XOR turn detection, speaker references) is decided in the UI and handed to the service at session start. Changing any of it mid-session is impossible — a reconnect opens a new session with the identical config.

*Alternative considered:* recording in the UI isolate with the service as a mere keep-alive — rejected; the microphone must be held by the service for background capture to be permitted, and the isolate split is unavoidable with this plugin.

### D5 — One PCM16 stream, fanned out to the WebSocket and a WAV file

The recorder produces a single 16 kHz mono PCM16 stream. It is teed in Dart: base64-encoded ~100 ms chunks go to `input_audio.append`, and the raw chunks are written to a WAV file (~1.9 MB/min) for the post-session diarization pass. WAV is lossless, trivial to write (44-byte header around raw chunks), and accepted by the batch API.

*Alternative considered:* a compressed container (m4a/Opus) — smaller on disk, but adds an encoder dependency and failure modes for zero spike value. Deferred to a later change if storage pressure shows up.

### D6 — Reconnect means a new session with an identical config plus buffered audio

The realtime protocol locks session settings after the first audio chunk, so a dropped connection is recovered by opening a new session, resending `session.update` with the identical config, and replaying the locally buffered audio. Transcript deltas are append-only (the API never corrects earlier text), so already-displayed text needs no reconciliation — the new session's deltas simply continue it.

### D7 — Cost model: estimate during, actual from the API afterwards

During a session, estimated cost = elapsed minutes × the pinned realtime rate, displayed with elapsed minutes. At the end, `transcription.done` carries `usage`, and the batch response carries `usage.prompt_audio_seconds` — the actual billed audio duration — which produces the actual cost shown alongside the estimate. The post-session diarization pass shows its own estimated cost and is skippable.

### D8 — Material 3 themes seeded with Mistral orange, defined upfront

Both light and dark `ColorScheme`s are seeded with `#FF7000` and defined in the scaffold, with orange reserved for accents, the active recording state, and CTAs. Everything built later inherits correct theming from day one.

## Risks / Trade-offs

- **[Realtime 3 and Small 3 are Public Preview]** → event shapes, IDs, and pricing may change before GA. Mitigation: D2 isolation + D3 pinned IDs; the client layer is the only code that changes when the API moves.
- **[Session settings lock after the first audio chunk]** → latency, language, and context bias cannot change mid-session. Mitigation: D4 — the full config is fixed at session start; a reconnect replays the same config (D6).
- **[diarize and turn detection are mutually exclusive per session]** → the hybrid default costs a second API pass and requires keeping audio until it completes. Mitigation: cost visibility with a skippable pass (spec: cost-indicator), audio deleted after the pass by default, and the live-diarization toggle when retention is unwanted.
- **[OEM battery managers kill foreground services]** → background capture may die on aggressive devices. Mitigation: physical-device smoke test (see tasks.md), plus a documented "exclude from battery optimization" onboarding step in a later phase.
- **[Batch API duration/size limits for Voxtral 3 are unverified]** → a long live session might exceed what one post-session pass accepts. Mitigation: Spike C verifies the limit; fallback is chunking the audio into multiple passes.
- **[Overlapping speech is unsupported; segments can overlap]** → naive turn merging can corrupt the transcript. Mitigation: merge consecutive same-speaker segments only when they do not overlap; the spec (speaker-attribution) requires honest display of overlaps.
- **[Base64 JSON framing adds ~33% wire overhead]** → ~43 KB/s at 16 kHz mono. Acceptable on mobile networks; chunk size (~100 ms) is configurable if profiling says otherwise.
- **[Continuous streaming drains battery]** → inherent to the product. Mitigation: the streaming-delay setting (80–2400 ms) is exposed as a quality/battery trade-off; measure in a later phase.
- **[Speaker labels are not stable across sessions]** → speaker_1 in one session is not necessarily the same person in another. Mitigation: the spec forbids implying cross-session identity; enrolled reference clips (up to 8, 3–15 s) provide real identity.

## Migration Plan

Not applicable — greenfield. The change creates the Flutter project at the repository root; there is no existing system to migrate.

## Open Questions

- **ANSWERED (Spike A, 2026-10-22):** live (streaming) diarization quality is
  good on real conversation audio — labels stayed consistent within the
  session (spike-notes.md, task 3.2). The hybrid default stands.
- **DEFERRED with Spike C (user decision, 2026-10-23; moves to a future
  version):**
  - Does the audio transcription API expose the 50%-off batch service tier
    for the post-session pass?
  - What is the maximum audio duration/size for Voxtral 3 file transcription?
  Both were to be verified in Spike C tasks 5.2–5.3, now deferred. A chunking
  fallback covers the duration question if it ever blocks a long session.
- **OPEN (intermittent, instrumented):** the realtime connection sometimes
  drops and reconnects in bursts (~every 3–10 s) while transcription continues
  seamlessly. The latest run had no reconnects; the connection code is
  identical between storm and quiet runs, so the cause is not yet confirmed.
  When it recurs, the drop reason (close code) is carried in the Reconnected
  event's `dropReason`.
