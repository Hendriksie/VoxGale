# Tasks

## 1. Spike and Mistral agent client

- [ ] 1.1 Manual on-device spike of the Agents/Conversations API with the user's real key (NEVER from tests; this machine has no device, so leave pending user verification): create a spike agent in Studio, call `GET /v1/agents` and `POST /v1/conversations` with `{agent_id, inputs, stream: false, store: false}` from a debug build (or curl on the user's machine), record the exact request/response shape, the `store: false` behavior, a 404 for an unknown agent, and a long-transcript (~60 min) result in `spike-notes.md` in this change directory (design decisions 1, 11).
- [x] 1.2 Create `lib/mistral/agent/agent_client.dart`: the `AgentClient` interface (`listAgents()`, `sendToAgent({required String agentId, required String transcript})`) and the `AgentInfo` / `AgentReply` value objects with JSON parsing (design decisions 2, 3), and export both files from `lib/mistral/mistral.dart`; verify `flutter analyze` is clean.
- [x] 1.3 Create `lib/mistral/agent/dio_agent_client.dart` (`DioAgentClient` over `POST /v1/conversations` and `GET /v1/agents`, Bearer key, connect 15 s / send 15 s / receive 5 min, `store: false` and `stream: false` always in the send body, sanitized errors that never stringify the `DioException` — design decisions 1, 3, 4), and verify with `test/mistral/agent_client_test.dart` (mocked dio, pattern of `test/mistral/batch_client_test.dart`): agent list parsing, reply/usage parsing, `store: false` present in the request body, error mapping, and an assertion that no thrown message contains the API key.
- [x] 1.4 Run `flutter analyze` and the `test/mistral/` suite; verify green and that no test hits the live API. (Verified: 76/76 in test/mistral/, analyze clean.)

## 2. Storage (Drift schemaVersion 4 → 5)

- [x] 2.1 Add the nullable `agentId` (`agent_id`) column to the `Preferences` table and the nullable `agentReply` (`agent_reply`), `agentReplyAtMs` (`agent_reply_at_ms`), `agentReplyTotalTokens` (`agent_reply_total_tokens`) columns to the `Sessions` table in `lib/storage/app_database.dart`, bump `schemaVersion` to 5 with `if (from < 5) migrator.addColumn(...)` entries, and verify `dart run build_runner build --delete-conflicting-outputs` regenerates `app_database.g.dart` cleanly (design decision 7, migration plan).
- [x] 2.2 Extend `StoredPreferences` with `agentId` (null = unset) in `lib/storage/preferences_repository.dart` — `==`/`hashCode`, load, save — and verify with `test/storage/preferences_repository_test.dart` on `AppDatabase.memory()` plus a file-backed close/reopen case that the field round-trips and defaults to null.
- [x] 2.3 Extend `StoredSession` with the three reply fields and add `saveAgentReply(String sessionId, {required String reply, required int atMs, required int totalTokens})` to `SessionRepository` (unknown id → `ArgumentError`, like `replaceTranscript`) with the Drift implementation updating the sessions row in `lib/storage/session_repository.dart`, and verify with `test/storage/session_repository_test.dart`: save/load round-trip, overwrite on re-send, delete removes the reply, unknown id throws.

## 3. Providers and Settings agent picker

- [x] 3.1 Add `agentClientProvider` (FutureProvider reading the key from `apiKeyStoreProvider` at construction, `StateError` when no key — identical pattern to `batchTranscriptionClientProvider`) and `agentIdProvider` (from `preferencesProvider`) to `lib/session/session_providers.dart` (design decision 5), and verify `flutter analyze` is clean.
- [x] 3.2 Extend `SettingsState` (agents list, `agentLoading`, `agentError`, `selectedAgentId`, with the `_keep` copyWith sentinel pattern) and `SettingsController` with `loadAgents()` (via the agent client, error + retry state on failure, previous selection kept) and `selectAgent(String? id)` (persisted through `_persistPreferences`, invalidates `preferencesProvider`), loading the stored `agentId` in `_load()`; verify with `test/session/settings_controller_test.dart` using a fake `AgentClient`: list populates state, failure sets error and keeps selection, select persists and invalidates, load applies the stored value.
- [x] 3.3 Add an "Agent" section to `lib/app/settings_screen.dart` (below the API key section): a dropdown of the fetched agents by name plus a refresh action, the one-line note that the agent runs with its own tools, and the missing-key state when no key is saved (settings spec delta); verify with `test/app/settings_screen_test.dart` widget tests: picker renders agents and selection, refresh re-lists, list failure shows error + retry, no key → picker not offered.

## 4. Send-to-agent flow

- [x] 4.1 Add `sendToAgent()` to `HistoryDetailController`: builds the payload with `transcriptToMarkdown`, awaits the agent client, persists the reply via `saveAgentReply`, invalidates `historyListProvider`, reloads; state gains `agentSending` and `agentError`; on `MistralApiException` the sanitized message is shown with the previous reply kept (agent-integration spec). Verify with `test/session/history_detail_controller_test.dart` using a fake `AgentClient`: success sends + persists + reloads, API failure sets the sanitized error and keeps the stored reply, no agent selected is a no-op, empty transcript is a no-op.
- [x] 4.2 Add the "Send to agent" app-bar action and the reply card (reply text, agent name, time, token usage, share action via an injectable share function mirroring `transcriptExportProvider`) to `lib/app/history_detail_screen.dart`; the action is enabled only when the record has segments and an agent is selected, otherwise it points to Settings (transcript-history spec delta). Verify with `test/app/history_detail_screen_test.dart` widget tests: action enabled/disabled per state, reply card renders reply + usage, share invokes the injected share with the reply text.
- [x] 4.3 Run `flutter analyze` and the `test/session/` + `test/app/` suites; verify green. (Verified: 307/307, analyze clean.)

## 5. Documentation

- [x] 5.1 Add the agent-flow bullet to `PRIVACY.md` under "Where the data goes": transcript text sent to the Mistral API (Conversations endpoint) under the user's own key with `store: false`, not covered by Mistral's zero-data-retention, and the agent's configured tools may process the transcript (privacy-policy spec delta); verify the policy still matches the privacy-policy spec's plain-language requirements.
- [x] 5.2 Add an `Added` entry under `## [Unreleased]` in `CHANGELOG.md` ("Send a saved transcript to a Mistral agent from the transcript view; pick the agent in Settings; the reply and its token usage are shown and kept with the transcript"), matching the file's Keep a Changelog format.
- [x] 5.3 Mark the "Mistral agent integration" idea in `docs/ideas.md` as promoted (change `2026-10-29-send-transcript-to-agent`), keeping the researched caveats (token pricing, ZDR exclusion, agent tools) as notes.

## 6. Verification

- [x] 6.1 Run `flutter analyze` (clean) and the full `flutter test` suite (all green); verify no test touches a platform channel or the live Mistral/GitHub APIs (all seams faked, per the test-coverage spec). (Verified: analyze clean, 478/478 tests pass.)
- [x] 6.2 Run `openspec validate 2026-10-29-send-transcript-to-agent --strict` and verify the change validates. (Verified: valid.)
- [ ] 6.3 Physical-device run with the user's real key (pending user verification; this machine has no device): save a key, pick an agent in Settings, open a saved transcript, tap "Send to agent", and verify the reply appears with token usage, persists across an app restart, and is shared via the share sheet; verify a send with no agent selected points to Settings and a deleted agent produces a retryable error. Record the result in `spike-notes.md` before archiving.

## Workflow follow-up

- Archive the change (`openspec archive 2026-10-29-send-transcript-to-agent --yes`) only after tests pass, the spike and device run are verified, and the change is reviewed.
- After archiving, run `openspec validate --specs --strict` to confirm the main `agent-integration`, `settings`, `transcript-history`, and `privacy-policy` specs land cleanly.
