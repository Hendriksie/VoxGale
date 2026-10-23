# Spike Notes — voxtral-v1-foundations

Phase-0 output. Fill in the sections below during the manual spike runs on a
real device with your own Mistral API key, then task 6.4 is satisfied: these
notes must answer the three open questions recorded in design.md.

How to run: `flutter run` on a physical Android device. The home screen has a
**debug-only** "API key" entry (debug builds only; the real settings screen
with key validation is Phase 2) — paste your Mistral API key there once. It is
saved to secure storage at runtime and the spike screens read it from there.
The home screen links to all three spikes.

## Spike A — realtime path (tasks 3.1–3.3)

Screen: "Spike A — live transcription". Run the same conversation twice: once
with **Turn detection** (default), once with **Live diarization**.

- [x] 3.1 Transcript text appeared within seconds of speaking (both modes).
  Result: works. Note: many `[reconnected]` markers during the run even though
  transcription continued — see "Reconnect investigation" below.
- [x] 3.2 Mode comparison on the same conversation:
  - Turn detection: latency OK; turn boundaries now clearly visible
    (`— turn @ Xs —` markers; `[session ready: turn_detection]` confirms the
    server applied the mode).
  - Live diarization: label quality worked great (`speaker_1`/`speaker_2`
    stayed consistent within the session); turns grouped by speaker change.
- [x] 3.3 Cost check: worked great — estimated (elapsed × $0.008) matched the
  `prompt_audio_seconds` reported in `transcription.done`.

Answers design open question: *How does live (streaming) diarization quality
compare to the offline pass on real conversation audio?*

### Reconnect investigation (observed during Spike A)

Many `[reconnected]` markers while transcription continued. Changes made:

- WebSocket pings enabled (15 s) so dead connections are detected proactively.
- The dead channel's socket is now closed on reconnect (previously lingered).
- The spike screen logs `[error: ...]`, `[reconnected @ Ns]`, a reconnect
  counter, and the applied session settings on connect.

To diagnose further, note: how often reconnects happen (every N seconds or
minutes), whether they cluster at speech pauses (server idle-timeout?) or
occur randomly (network), and the `[error: ...]` messages that precede them.

User data (Pixel 9, GrapheneOS): reconnects come in bursts — 3-5 within ~1 s,
never 5+ s of stability. No documented server-side idle timeout or maximum
session duration exists (checked the troubleshooting and limits pages). New
diagnostics in the spike screen: `[error: ... (closeCode: N, closeReason: ...)]`
(the close code is the main clue), a `buffered: Xs` gauge in the status line,
and a `[replayed Xs of buffered audio]` marker. The buffer replay is now PACED
at real time — dumping the whole backlog at once sends audio far faster than
real time, which some servers treat as a protocol problem (a candidate cause
of both the no-catch-up symptom and possibly the storm).

The `AudioTrackShared: obtainBuffer: benign status 'Try again'` lines in the
flutter log are NOT from this app — nothing in the dependency tree creates an
AudioTrack (record uses AudioRecord for capture), and AOSP marks those lines
benign. System media-service noise; ignore.

New data (flutter console, `[spike]` lines): reconnects come in bursts of 3-8
within the same displayed second, recurring every ~28 s. The pasted excerpt
has no `[spike] error:` / `[spike] replayed` lines (likely filtered — re-paste
with `grep '\[spike\]'`). User report: drops cluster more during pauses /
silence, sometimes during speech.

Changes made:

- **WebSocket pings REMOVED.** The `web_socket` package closes the connection
  when a ping goes unanswered, and the server's ping behavior is unverified —
  the ~28 s drop cycle matched the 15 s ping interval (two intervals). The
  pings were a speculative fix and caused the cyclic drops. Re-enable only
  after confirming the server answers pings.
- **Reconnect backoff:** exponential (reconnectDelay doubling, capped at
  10 s) so a flapping connection does not hammer the API.
- **Spike A Start is re-entry-guarded.** A double-tap could start a second
  session + recorder (the button stays enabled until the session is up);
  multiple sessions interleave their reconnect logs and look like bursts.
- **Spike B: single Stop button** — graceful first, force-stops the service if
  it is still running after 2 s.
- **Transcript styling:** transcribed text at 16 pt, markers dimmed + italic
  at 13 pt, compact turn-end marker, and the top error banner is one
  ellipsized line (it used to render huge and red during the storm).

Next diagnostic: re-run and paste ALL `[spike]` lines (`grep '\[spike\]'` on
the full log). Also try making continuous noise (hum / tapping) during pauses:
if the drops stop, the record stream is gapping during silence and the server
is idle-closing the connection.

New data: the unfiltered `[spike]` log still shows ONLY `[spike] reconnected`
lines — no `[spike] error:` and no `[spike] replayed` lines at all, even though
the client emits a RealtimeError before every reconnect and a
BufferedAudioReplayed after every replay. Root cause of the missing lines:
**`debugPrint` throttles and drops messages under a flood** — the reconnect
storm flooded it. All spike diagnostics now use unthrottled `print`, and the
client traces its own lifecycle (connect / stream error with close code /
stream closed with close code / replay) through an optional `debugLog`
callback, printed as `[spike] [mistral] ...`. Audio chunks are also split at
32 KB so one huge message can't make the server close with 1009
(message-too-big).

Next run: paste ALL `[spike]` lines. The close code is the key:
`[spike] error: ... (closeCode: N, ...)` — 1000/1001 means the server closed
the session (likely an idle or session limit; the fix would be a keep-alive
silence feed); 1006 means the network path died.

New data (current build): the keep-alive fired once at session start, but
reconnects continued (~every 3-10 s, in pairs/triples). Still no error lines in
the console — so the drop cause is now carried INSIDE the Reconnected event:
`[spike] reconnected @ Ns — <drop reason with close code>`. Next run: read the
drop reason from the reconnect lines. Also check the transcript IN THE APP
for `[error: ...]` markers — the UI is the zone-proof channel; if the UI
shows them but the console doesn't, it's a logging artifact, not missing
events.

Latest run (current build): `[spike] [mistral] session ready` prints, the
keep-alive fired once, and NO reconnects occurred at all. The record plugin's
default chunk size is ~2x the AudioRecord minimum (~4–8 KB at 16 kHz mono —
well under the 32 KB split cap), so oversized messages were not the cause.
Conclusion: the storm is intermittent, not fixed — the connection code is
identical between storm and quiet runs. If it recurs, the drop reason (close
code) rides inside each `[spike] reconnected @ Ns — ...` line.

- The app transcript now shows `[session ready: <mode>]` at session start
  (added locally — the initial SessionStarted event is emitted before the
  screen subscribes, and broadcast streams don't replay).

### Build check (important)

The current build prints `[spike] [mistral] session ready` at every session
start and before every reconnect. If a log has `[spike] reconnected` lines but
NO `[mistral]` lines, it is from the previous build — reload (`flutter run`
again, or `R` for a full restart) before testing.

### Keep-alive feed (new)

When the mic delivers no audio for 500 ms while connected, the client sends
100 ms of silence so the server does not idle-close the session (reconnects
clustered during pauses on-device; the record stream may also gap mid-speech
on some devices). It logs once when it starts:
`[mistral] keep-alive: feeding silence (no mic audio for 500ms)`. If the
reconnects stop with the feed active, idle-close was the cause; if they
continue, read the close codes (1006 = network path died).

## Spike B — background capture (tasks 4.1–4.2, physical device required)

Screen: "Spike B — background capture". Emulators lie about background capture —
this must run on a physical device.

- [x] 4.1 Device model / Android version: Google Pixel 9, GrapheneOS, Android 17
  - Bug found and fixed: "Start background session" failed with "Microphone
    permission not granted" although Spike A works. Root cause: record's
    hasPermission is activity-bound and returns false in the foreground-service
    isolate (no Activity). Fix: the service no longer checks permission — the
    UI isolate checks before starting the service, and the runtime permission
    is process-wide. Result: the session now starts.
  - Second bug found and fixed: unhandled PlatformException in the flutter
    log — record's dispose throws "Recorder has not yet been created or has
    already been disposed" when called twice (Spike A stop + navigate back).
    All dispose paths are now guarded.
  - Session started, screen turned off. Capture + transcription confirmed
    working screen-off for 30+ minutes (user report: "The 30 min run went
    great. I kept recording while the screen was off.").
  - Bug found: no notification appeared, and the app never asked for the
    notification permission. Root cause: Android 13+ requires the
    POST_NOTIFICATIONS runtime permission; without it the foreground-service
    notification is silently suppressed (the service still runs — the 30-min
    recording worked). Fix: Spike B now requests the notification permission
    before starting the service. Verified: the persistent notification shows
    (user report). Battery drain: dropped from scope (user decision — a
    notification that background capture is running is sufficient).
  - OEM battery-manager quirks: GrapheneOS — if the service is killed
    screen-off, allow background activity / unrestricted battery for the app
    (Settings → Apps → Voxtral Live → Battery), then re-run.
  - Note: Spike B runs turn-detection mode (the hybrid default), so no
    `[speaker_1]`/`[speaker_2]` labels appear there — intended. Speaker labels
    come from Spike A's Live diarization mode (confirmed working) or Spike C's
    batch pass. Turn markers are now one per completed turn (was two).
- [x] 4.2 Airplane mode toggled mid-session. Reconnects still come in bursts
    (3-5 within ~1 s; never 5+ s of stability), but the recovery now works:
    after `[Reconnected]` the buffered audio is transcribed (catch-up text
    confirmed). The old no-catch-up symptom was the replay dumping the whole
    backlog faster than real time — the replay is now paced at real time.
    The burst pattern itself is still unexplained; the
    `[error: ... (closeCode: N, closeReason: ...)]` lines are also
    debugPrint'ed to the flutter console now — paste them here: ____.
    Reconnect delay observed: ____.

## Spike C — batch path and limits (tasks 5.1–5.3)

DEFERRED 2026-10-23 (user decision): the remaining Spike C verification (5.2
limits probe, 5.3 reference clip) moves to a future version — the
file-transcription feature lands in Phase 2 anyway. The batch client
(`lib/mistral/batch/`) stays: built and unit-tested. 5.1 was verified on
device before the deferral (speaker labels + timestamps rendered).

Screen: "Spike C — batch transcription". If a session WAV saved by Spike A
exists, Spike C transcribes THAT (the post-session diarization pass);
otherwise it falls back to `assets/spike/sample.wav`. Replace
`assets/spike/reference_tone.wav` with a 3–15 s recording of a real voice for
named-speaker labels (record one with Spike A: start a session, say a name for
5–10 s, stop; pull the WAV — see "Session files" below — and drop it into the
asset).

- [x] 5.1 Speaker-labelled transcript rendered with speaker IDs and segment
  timestamps (Mini model and, optionally, Small model). Verified on device:
  Spike C transcribes the session WAV with `[speaker]` labels and timestamps
  (the Dio base-URL fix worked).

### Spike UI fixes (this round)

- The transcript now renders transcribed text in the normal style and
  diagnostic lines (turns, reconnects, errors, session info) dimmed + italic,
  and auto-scrolls to the latest text.
- Spike B: re-entering the screen restores the running state (the service
  keeps running when you navigate away without stopping), and there is now a
  "Force stop service" button next to Stop.
- The `[replayed Xs of buffered audio]` marker has a unified format across
  Spike A and Spike B.
- [ ] 5.2 Limits probe (use a long recording; mind the cost — the user's own
  key pays):
  - Maximum audio duration accepted in one request: ____ (Voxtral 2 claimed
    3 hours; unverified for Voxtral 3).
  - Maximum file size accepted: ____.
  - Is the 50%-off batch service tier exposed for the audio transcription
    API? (Try `service_tier` on the request; record the exact field name and
    whether it is accepted.)
- [ ] 5.3 Speaker reference clip exercised in both modes:
  - Batch (Spike C): the "Enroll reference clip as 'Alice'" toggle is on by
    default and loads `assets/spike/reference_tone.wav`. Replace that asset
    with a 3–15 s recording of a real voice: run Spike A, say a name for
    5–10 s, stop; pull the session WAV (see "Session files" below); trim it to
    3–15 s (e.g. `ffmpeg -i session.wav -t 10 alice.wav`); drop it into the
    asset; `flutter run`; run Spike C; check whether segments carry "Alice"
    instead of `speaker_N`. This also answers the offline
    `speaker_references` wire-format question (one JSON `{name: base64}` form
    field — accepted? yes/no. If rejected, record the API error message; the
    fix is isolated in `dio_batch_transcription_client.dart`).
  - Realtime (Spike A): switch to Live diarization, enable the "Enroll
    reference clip as 'Alice'" toggle (new), start a session; segments should
    carry "Alice" as they stream.

Answers design open questions: *maximum audio duration/size for Voxtral 3
file transcription* and *whether the 50%-off batch tier is exposed for audio*.

### Session files — where Spike A's audio lives

The live spike tees the mic stream to a WAV at
`/data/user/0/dev.hendriksie.voxtral_live/cache/voxtral_spike_session.wav`
(the exact path is shown on the spike screen). Pull it off the phone with the
debug build (debuggable, so `run-as` works):

```
adb exec-out run-as dev.hendriksie.voxtral_live \
  cat /data/user/0/dev.hendriksie.voxtral_live/cache/voxtral_spike_session.wav \
  > session.wav
```

## Cost summary

| Run | Model(s) | Minutes | Estimated | Actual (usage) |
| --- | --- | --- | --- | --- |
| Spike A turn detection | realtime | | | |
| Spike A diarize | realtime | | | |
| Spike C | mini / small | | | |
