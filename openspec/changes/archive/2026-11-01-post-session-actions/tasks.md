# Tasks

Note: depends on `2026-10-29-send-transcript-to-agent` being archived first
(its `agent-integration` spec lands in the main specs then).

## 1. Shared pieces

- [x] 1.1 Extract the export bottom sheet (plain text / Markdown chooser + `transcriptExportProvider` call) from `lib/app/history_detail_screen.dart` into a shared widget (e.g. `lib/app/transcript_share_sheet.dart`) used by both screens, and extract the send-to-agent confirm dialog similarly; verify `flutter analyze` is clean and the existing `test/app/history_detail_screen_test.dart` export tests still pass unchanged.
- [x] 1.2 Create `lib/session/agent_send.dart`: the shared send step (load record by session id via the repository, build the Markdown payload with `transcriptToMarkdown`, call the agent client with the selected agent, persist the reply with `saveAgentReply`) returning the reply, throwing sanitized `MistralApiException`s; refactor `HistoryDetailController.sendToAgent()` to use it; verify `test/session/history_detail_controller_test.dart` still passes and `flutter analyze` is clean.

## 2. Live controller

- [x] 2.1 Add `sendToAgent()` to `LiveSessionController` using the shared helper and `state.sessionId`; state gains `agentSending` and `agentError`; no-op when no session is saved or the transcript is empty or no agent is selected; verify with `test/session/live_session_controller_test.dart` using a fake agent client and in-memory repository: success persists the reply for the saved session, failure sets the sanitized error, no-agent/empty are no-ops.

## 3. Live screen post-session card

- [x] 3.1 Replace `_PassSection`'s shrink-in-done behavior with a post-session card shown in `done` and `passOffered`: in `passOffered` the pass offer (Run/Skip) plus a secondary actions row (Share, Send to agent); in `done` "Session saved" plus the actions row (Send to agent primary when an agent is selected, Share secondary); Send shows a spinner while `agentSending` and the shared `ErrorBanner` with retry on `agentError`; no-agent tap shows the Settings snackbar; Share opens the shared export sheet for the saved record. Verify with `test/app/live_session_screen_test.dart` widget tests: card visible with actions in done and passOffered, absent while active/paused, Run/Skip still primary in passOffered, send calls the controller, share opens the sheet, error banner retry re-sends.

- [x] 3.2 On a successful send from the post-session card, navigate to the saved transcript's history detail view (where the persisted reply card is shown); on failure stay on the live screen with the `ErrorBanner` retry. `LiveSessionController.sendToAgent()` returns whether the send succeeded. Verify with `test/app/live_session_screen_test.dart` widget tests (success pushes the transcript detail with the reply visible, failure stays with the banner) and return-value assertions in `test/session/live_session_controller_test.dart`; `flutter analyze` clean.

## 4. Docs and verification

- [x] 4.1 Add an `Added` entry under `## [Unreleased]` in `CHANGELOG.md` ("After a live session, the home screen offers Share and Send to agent for the saved transcript, alongside the speaker-label pass").
- [x] 4.2 Run `flutter analyze` (clean) and the full `flutter test` suite (all green; no test touches a platform channel or the live APIs), and `openspec validate 2026-11-01-post-session-actions --strict`.
- [x] 4.3 Physical-device check — verified by the user on a physical device 2026-11-01 ("reviewed the change on my phone and it worked great"): stopped a session, used Share and Send to agent from the post-session card; the app opened the saved transcript in History and the agent reply landed on it. Recorded after the archive, which the user explicitly authorized while the check was pending.

## Workflow follow-up

- Archive the change (`openspec archive 2026-11-01-post-session-actions --yes`) only after tests pass, the device check is verified, and the change is reviewed; then `openspec validate --specs --strict`.
