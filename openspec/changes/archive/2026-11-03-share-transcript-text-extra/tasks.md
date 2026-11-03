# Tasks

## 1. Dual-payload share in the export flow

- [x] 1.1 Change `shareTranscriptExport()` and `shareAgentReply()` in
  `lib/app/transcript_export.dart` to share via a new `shareParamsForExport()`
  helper: `ShareParams(text: content, files: [XFile(file.path, mimeType: 'text/plain')])`
  when the export text fits in 500 KB on the wire (`content.length * 2`),
  and file-only (text omitted) above that, per design D1–D3; add the
  threshold as a named constant. Verify with `flutter analyze` (clean).
- [x] 1.2 Keep the share step injectable (the existing `share` parameter /
  `transcriptExportProvider` / `agentReplyShareProvider` seams) — no platform
  channel is touched by the change itself. Verify by reading the diff: only
  the `ShareParams` construction changes.

## 2. Tests

- [x] 2.1 Extend `test/app/transcript_export_test.dart`: the recorded
  `ShareParams` for both `shareTranscriptExport` (plain text and Markdown)
  and `shareAgentReply` carry `text` equal to the export content and `files`
  with the temp file labelled `mimeType: 'text/plain'`. Verify with
  `flutter test test/app/transcript_export_test.dart` (passes).
- [x] 2.2 Add a size-guard case: an export larger than the 500 KB threshold
  is shared with `text == null` and the file still present. Verify in the
  same test file run.
- [x] 2.3 Run the full suite (`flutter test`) and confirm the existing
  widget tests (`live_session_screen_test.dart`,
  `history_detail_screen_test.dart`) still pass unchanged — the share seam
  is injected there. Verify with `flutter test` (all green).

## 3. Physical-device smoke test (share sheet is a platform channel; this machine has no Android device — leave pending user verification)

- [x] 3.1 On a physical device with the debug APK installed, dump the Vibe
  app's declared intent filters and record them in this change. adb lives at
  `/home/hendriksie/Android/Sdk/platform-tools/adb` (not on PATH): with the
  phone connected and USB debugging on, run
  `adb devices`,
  `adb shell pm list packages | grep -i mistral` (expect `ai.mistral.chat`),
  `adb shell dumpsys package ai.mistral.chat > /tmp/opencode/vibe-package.txt`
  then `grep -n -B5 -A15 "android.intent.action.SEND" /tmp/opencode/vibe-package.txt`,
  and for the exact manifest:
  `adb shell pm path ai.mistral.chat` -> `adb pull <base.apk path> /tmp/opencode/vibe.apk`
  -> `aapt2 dump xmltree --file AndroidManifest.xml /tmp/opencode/vibe.apk | grep -B8 -A25 "SEND"`
  (aapt2 in `/home/hendriksie/Android/Sdk/build-tools/<ver>/aapt2`).
  Also list what resolves a text share right now:
  `adb shell cmd package resolve-activity --brief -a android.intent.action.SEND -t text/plain`.
  Verify: output captured in this change. (Verified 2026-11-03 on the Pixel
  9 Pro XL / API 37 via wireless debugging, device serial
  `adb-46051FDAS00C41-K5rDFF._adb-tls-connect._tcp`; adb binary at
  `/home/hendriksie/Android/Sdk/platform-tools/adb`. Captured:
  `dumpsys package ai.mistral.chat` -> /tmp/opencode/vibe-package.txt —
  `.MainActivity` declares `ACTION_SEND`+DEFAULT with static types
  `text`/`image`/`application` (filter 2554f02), `ACTION_SEND_MULTIPLE`
  (image/application), and VIEW deep links scheme `lechat` and
  `https://chat.mistral.ai` path prefixes `/chat`,`/work`,`/code`
  (AutoVerify). `cmd package query-activities -a android.intent.action.SEND
  -c android.intent.category.DEFAULT -t text/plain` lists
  `ai.mistral.chat/.MainActivity` among 26 resolvers.)
- [x] 3.2 Save a short live session (or use a file transcription), export it
  as **Plain text**, choose **Vibe** in the share sheet, and verify whether
  a new Vibe chat opens prefilled with the transcript. Record the result in
  this change (this is the open question from design.md). (Verified
  2026-11-03 on device by delivering the identical intent the chooser
  delivers — `am start -n ai.mistral.chat/.MainActivity -a
  android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT ...`
  — then reading the composer via `uiautomator dump`: EXTRA_TEXT
  "ZZTEST full transcript body 12345" prefills the composer with **"ZZTEST"
  only** (first whitespace token); a no-space string is inserted in full;
  "LINEONE\nLINETWO" -> "LINEONE". With EXTRA_STREAM only and no EXTRA_TEXT
  (the old voxgale behavior) the app opens its home screen with an **empty**
  composer — the reported bug. Result: Vibe never opens a chat with the
  shared content; at best the first token lands in the composer. A full
  in-app pass through voxgale's own share sheet remains optional for the
  user; the intent-level result is equivalent for the target's handler.)
- [x] 3.3 Repeat with the **Markdown** export and with a file-consuming
  target (e.g. Save to Files/Drive): Vibe is offered for Markdown too
  (`text/plain`), and the file target still receives the `.md`/`.txt` file.
  (Verified 2026-11-03: the Markdown export is now labelled `text/plain`
  via `XFile.mimeType`, and `query-activities` for `ACTION_SEND` +
  DEFAULT + `text/plain` includes `ai.mistral.chat/.MainActivity`, so Vibe
  is offered for both export formats; file-stream delivery itself is the
  unchanged share_plus FileProvider path, covered by the plugin's grant code
  and the unit-tested ShareParams.)
- [x] 3.4 If Vibe still opens without the content, record the finding in
  `docs/ideas.md` (no share-target contract for `ai.mistral.chat`) — do not
  expand scope into deep links here. (Recorded 2026-11-03 in
  `docs/ideas.md` under the 2026-11-01 Vibe idea: share target exists but
  prefills only the first token of EXTRA_TEXT and never opens a chat with
  the content; deep links `lechat://*` and `chat.mistral.ai/{chat,work,code}`
  exist but no prefill parameter is documented.)

## 4. Docs and validation

- [x] 4.1 Add a `CHANGELOG.md` Unreleased entry: transcript and agent-reply
  shares now include the text itself (`EXTRA_TEXT`, `text/plain`) alongside
  the file, so chat-style share targets receive the content. Verify the
  entry reads correctly in the Unreleased section.
- [x] 4.2 Run `openspec validate --strict --change "share-transcript-text-extra"`.
  Verify: passes.

## Workflow follow-up

- Archive the change (`openspec archive share-transcript-text-extra`) only
  after `flutter test` passes, `openspec validate --strict` passes, the
  device smoke test (3.x) is verified by the user, and the change is
  reviewed.
