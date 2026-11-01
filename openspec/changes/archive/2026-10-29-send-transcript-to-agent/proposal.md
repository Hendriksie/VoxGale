# Proposal

## Why

A transcript is most useful after the session ends — summarizing, extracting
action items, filing notes — but VoxGale stops at the transcript. The
parking-lot idea from the v1 plan (§9, `docs/ideas.md`) is to let the user
send a saved transcript to a Mistral agent they configured in their own
workspace. Researched 2026-10-29 against docs.mistral.ai: the
Agents/Conversations API on `api.mistral.ai` accepts the same Bearer API key
the app already holds in secure storage, so no new credential, host, or
dependency is involved. This change promotes the idea.

## What Changes

- New capability **`agent-integration`**: a Mistral agent client in
  `lib/mistral/agent/` behind an interface (`listAgents()` over
  `GET /v1/agents`, `sendToAgent()` over `POST /v1/conversations` with
  `store: false, stream: false`), a "Send to agent" action on the transcript
  detail screen that sends the transcript's Markdown export, and the agent's
  reply shown on the detail screen with its token usage and persisted as the
  session's latest reply.
- Settings gains an **agent picker** (user decision 2026-10-29): the
  workspace's agents are listed through the API and the chosen agent ID is
  persisted as a non-secret preference — no free-text agent ID field.
- `PRIVACY.md` and the privacy-policy spec disclose the agent data flow: same
  host and key, conversation storage disabled (`store: false`), not covered by
  Mistral's zero-data-retention, and the agent's own tools may process the
  transcript.
- Spec deltas: new `agent-integration`; ADDED requirements to `settings`,
  `transcript-history`, and `privacy-policy`.
- Explicitly NOT in this change: creating or editing agents in the app,
  streaming replies (SSE), multi-turn conversations with an agent, client-side
  chunking of long transcripts, per-token USD pricing (the reply shows raw
  token usage — agent calls are not audio-priced, so the cost-indicator spec is
  untouched), and a free-text agent ID fallback.

## Capabilities

### New Capabilities

- `agent-integration`: sending a saved transcript to the user-selected
  Mistral agent with the app's own API key, never retaining conversation
  history server-side, and showing and persisting the agent's reply with its
  token usage.

### Modified Capabilities

- `settings`: new requirement to offer an agent picker backed by the
  workspace's agents (via the API with the stored key) and persist the chosen
  agent.
- `transcript-history`: new requirements for the "Send to agent" action on
  the transcript detail view and for exporting the agent reply.
- `privacy-policy`: new requirement to disclose the agent data flow
  (`store: false`, ZDR exclusion, agent tools).

## Impact

- Code: new `lib/mistral/agent/` (`agent_client.dart` interface + value
  objects, `dio_agent_client.dart`) exported from `lib/mistral/mistral.dart`;
  providers in `lib/session/session_providers.dart` (`agentClientProvider`
  reads the key from `ApiKeyStore` at construction like the batch client,
  `agentIdProvider` from preferences); Drift: `agent_id` column on the
  `preferences` table and agent-reply columns on `sessions` (schemaVersion
  4 → 5, additive migration, regenerate `app_database.g.dart`);
  `StoredPreferences.agentId`, `SessionRepository.saveAgentReply`,
  `StoredSession` reply fields; `SettingsState`/`SettingsController` gain the
  picker state and `loadAgents()`/`selectAgent()`; `lib/app/settings_screen.dart`
  gains an agent section; `HistoryDetailController` gains `sendToAgent()`;
  `lib/app/history_detail_screen.dart` gains the action and a reply card;
  `transcript_export.dart`'s Markdown builder is reused as the payload.
- Dependencies: none new — dio, drift, share_plus are already present.
- Tests: mocktail fake `AgentClient` for controller/widget tests; the dio
  client tested with a mocked HTTP layer (pattern of
  `test/mistral/batch_client_test.dart`), asserting `store: false` in the
  request body and that error messages never contain the API key; storage
  round-trip and close/reopen tests. No test ever hits the live API.
- Manual spike (pending user run on a physical device with their real key,
  never from tests): verify the `POST /v1/conversations` request/response
  shape, `store: false` behavior, and a long transcript against the live API;
  record results in `spike-notes.md` in this change.
- Docs: `CHANGELOG.md` Unreleased Added entry; `docs/ideas.md` marks the
  "Mistral agent integration" idea as promoted by this change; `PRIVACY.md`
  gains the agent-flow bullet.
