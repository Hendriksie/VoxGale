# Tasks

Note: depends on `2026-10-29-send-transcript-to-agent` being archived first
(its `agent-integration` spec lands in the main specs then).

## 1. Shared pieces

- [ ] 1.1 Extract the export bottom sheet (plain text / Markdown chooser + `transcriptExportProvider` call) from `lib/app/history_detail_screen.dart` into a shared widget (e.g. `lib/app/transcript_share_sheet.dart`) used by both screens, and extract the send-to-agent confirm dialog similarly; verify `flutter analyze` is clean and the existing `test/app/history_detail_screen_test.dart` export tests still pass unchanged.
- [ ] 1.2 Create `lib/session/agent_send.dart`: the shared send step (load record by session id via the repository, build the Markdown payload with `transcriptToMarkdown`, call the agent client with the selected agent, persist the reply with `saveAgentReply`) returning the reply, throwing sanitized `MistralApiException`s; refactor `HistoryDetailController.sendToAgent()` to use it; verify `test/session/history_detail_controller_test.dart` still passes and `flutter analyze` is clean.

## 2. Live controller

- [ ] 2.1 Add `sendToAgent()` to `LiveSessionController` using the shared helper and `state.sessionId`; state gains `agentSending` and `agentError`; no-op when no session is saved or the transcript is empty or no agent is selected; verify with `test/session/live_session_controller_test.dart` using a fake agent client and in-memory repository: success persists the reply for the saved session, failure sets the sanitized error, no-agent/empty are no-ops.

## 3. Live screen post-session card

- [ ] 3.1 Replace `_PassSection`'s shrink-in-done behavior with a post-session card shown in `done` and `passOffered`: in `passOffered` the pass offer (Run/Skip) plus a secondary actions row (Share, Send to agent); in `done` "Session saved" plus the actions row (Send to agent primary when an agent is selected, Share secondary); Send shows a spinner while `agentSending` and the shared `ErrorBanner` with retry on `agentError`; no-agent tap shows the Settings snackbar; Share opens the shared export sheet for the saved record. Verify with `test/app/live_session_screen_test.dart` widget tests: card visible with actions in done and passOffered, absent while active/paused, Run/Skip still primary in passOffered, send calls the controller, share opens the sheet, error banner retry re-sends.

## 4. Docs and verification

- [ ] 4.1 Add an `Added` entry under `## [Unreleased]` in `CHANGELOG.md` ("After a live session, the home screen offers Share and Send to agent for the saved transcript, alongside the speaker-label pass").
- [ ] 4.2 Run `flutter analyze` (clean) and the full `flutter test` suite (all green; no test touches a platform channel or the live APIs), and `openspec validate 2026-11-01-post-session-actions --strict`.
- [ ] 4.3 Physical-device check (pending user verification; no device on this machine): stop a session, use Share and Send to agent from the post-session card, verify the reply lands on the transcript in History; record the result before archiving.

## Workflow follow-up

- Archive the change (`openspec archive 2026-11-01-post-session-actions --yes`) only after tests pass, the device check is verified, and the change is reviewed; then `openspec validate --specs --strict`.
