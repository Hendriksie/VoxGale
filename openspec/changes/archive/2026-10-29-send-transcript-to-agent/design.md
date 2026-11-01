# Design

## Context

VoxGale already holds the user's Mistral API key in secure storage
(`SecureStorageApiKeyStore`) and talks to `api.mistral.ai` only through
clients in `lib/mistral/` behind interfaces (`BatchTranscriptionClient` over
dio REST, realtime WebSocket client, `KeyValidationClient`). The 2026-10-29
exploration (recorded in `docs/ideas.md` and the project KB) confirmed against
docs.mistral.ai that the Agents/Conversations API lives on the same host and
accepts the same Bearer key: `GET /v1/agents` lists the workspace's agents and
`POST /v1/conversations` with `{agent_id, inputs, stream: false, store: false}`
runs a one-shot agent call and returns the assistant message plus token usage.
Motivation and scope are in `proposal.md`; the behavior contract is in
`specs/agent-integration/spec.md` plus the `settings`, `transcript-history`,
and `privacy-policy` deltas. Current Drift schemaVersion is 4.

## Goals / Non-Goals

**Goals:**

- Send a saved transcript to the user-selected agent with the existing key,
  always with `store: false` (no server-side conversation history).
- Agent picker in Settings (user decision 2026-10-29), chosen ID persisted as
  a non-secret preference.
- The agent's reply is shown on the transcript detail view with its token
  usage, persisted per session, and exportable via the share sheet.
- Everything behind testable seams; no test touches the live API or a
  platform channel.

**Non-Goals:**

- Creating/editing agents, multi-turn conversations (no `conversation_id`
  reuse), streaming (SSE) replies, client-side chunking of long transcripts,
  per-token USD pricing, free-text agent ID entry.

## Decisions

1. **Endpoint: `POST /v1/conversations` with `{agent_id, inputs, stream:
   false, store: false}`.** The reply is the concatenated `content` of the
   `outputs[]` entries with `type: "message.output"` and `role: "assistant"`;
   token usage comes from the response's `usage`. `store: false` is hardcoded
   (privacy: Conversations are stateful and outside Mistral's ZDR coverage).
   Alternatives rejected: the legacy `POST /v1/agents/{id}/completions`
   (current docs steer agent calls to Conversations; the manual spike verifies
   the chosen shape against the live API) and streaming via SSE (adds an
   event parser for no v1 gain — the reply is shown once complete; agents with
   tools can take minutes, so the receive timeout is a fixed 5 minutes).
2. **Agent listing: `GET /v1/agents`**, mapped to a small value object
   (`AgentInfo(id, name, description?)`). The Settings picker shows names
   (dropdown or list dialog) — decided by the user on 2026-10-29 over a
   free-text ID field (opaque `ag_…` IDs, mistypes only fail at send time).
   The chosen ID is stored as `preferences.agent_id`, a nullable plain-text
   column: an agent ID is a workspace object reference, not a credential, so
   unlike the API key it does not belong in secure storage. List failure
   shows an error with retry and keeps the previous selection; there is no
   free-text fallback in v1.
3. **Client shape: `lib/mistral/agent/agent_client.dart`** with
   `abstract interface class AgentClient { Future<List<AgentInfo>>
   listAgents(); Future<AgentReply> sendToAgent({required String agentId,
   required String transcript}); }` and `AgentReply(text, promptTokens,
   completionTokens, totalTokens)`, plus `dio_agent_client.dart`
   (`DioAgentClient`) exported from `lib/mistral/mistral.dart`. Same base URI
   (`https://api.mistral.ai`) and `Authorization: Bearer <key>` header as the
   batch client, so the settings spec's "key only to api.mistral.ai over TLS"
   still holds. Timeouts are explicit (dio has none by default): connect 15 s,
   send 15 s (text payload), receive 5 min fixed (agent + tool runs can be
   slow; there is no audio duration to scale by).
4. **Error handling mirrors `DioBatchTranscriptionClient`**: a raw
   `DioException` embeds the request headers (API key included), so it is
   never stringified — the API error message is extracted from the response
   body, timeouts/statuses mapped to user-presentable text, and the catch-all
   runs through `MistralApiException.sanitize(error, apiKey)`. Tests assert
   the key never appears in a thrown message.
5. **Key handling is unchanged**: an `agentClientProvider` (FutureProvider)
   reads the key from `apiKeyStoreProvider` at construction — exactly like
   `batchTranscriptionClientProvider` — and throws `StateError` when no key
   is saved; the key never reaches a controller or state object. An
   `agentIdProvider` derives the selected agent from `preferencesProvider`.
6. **Payload: the transcript's Markdown export** (`transcriptToMarkdown` in
   `lib/app/transcript_export.dart`), so speaker labels and timestamps survive
   into the agent. Plain text was rejected (loses speaker structure); a bare
   concatenation was rejected (same reason).
7. **Reply persistence: three nullable columns on the `sessions` table** —
   `agent_reply` (text), `agent_reply_at_ms` (epoch ms), `agent_reply_total_tokens`
   (int) — written by a new `SessionRepository.saveAgentReply(sessionId, …)`
   (unknown id → `ArgumentError`, like `replaceTranscript`). `StoredSession`
   gains the three fields; deletion needs no extra code (same row). Drift
   schemaVersion 4 → 5 with `migrator.addColumn` ×3 on sessions and ×1
   (`agent_id`) on preferences; regenerate `app_database.g.dart`. Alternatives
   rejected: a separate `agent_runs` table with full history (more schema and
   UI for v1; can be a later change) and display-only storage (the history
   detail provider is autoDispose — the reply would vanish when the screen
   pops).
8. **Send flow**: `HistoryDetailController.sendToAgent()` builds the Markdown
   payload, awaits the client, persists the reply via the repository,
   invalidates `historyListProvider`, and reloads; state gains `agentSending`
   and `agentError`. The detail screen's app bar gains a "Send to agent" icon
   (enabled when the record has segments and an agent is selected; when no
   agent is selected, tapping it shows a message pointing to Settings), and a
   reply card under the metadata header shows reply text, agent name, time,
   token usage, and a share action (injectable share function over
   `share_plus`, mirroring `transcriptExportProvider`). The send action's
   confirmation copy notes the call is billed per token under the user's key.
9. **Cost display**: the reply card shows raw token usage only. Per-token USD
   pricing is out of scope because the agent's model is configured in Studio,
   not pinned in `MistralConfig`; the cost-indicator spec (per-minute audio
   rates) is deliberately untouched.
10. **Privacy**: `store: false` on every agent request; `PRIVACY.md` gains a
    "Where the data goes" bullet disclosing the flow, the ZDR exclusion, and
    that the agent's configured tools may process the transcript further; the
    Settings agent section carries a one-line note that the agent runs with its
    own tools.
11. **Long transcripts**: v1 sends the full transcript as one input, no
    client-side chunking; if the API rejects the size, the sanitized error
    surfaces with a retry. The manual spike (task 1.1) verifies the practical
    limit with a long transcript and records it in `spike-notes.md`.

## Risks / Trade-offs

- **[Conversations/Agents are outside Mistral's ZDR]** → hardcoded
  `store: false`, privacy-policy disclosure, settings note about agent tools.
- **[API key leaking through error strings]** → the batch client's
  sanitization discipline (never stringify `DioException`; catch-all
  `sanitize`); a client test asserts the key is absent from error messages.
- **[Agents/Conversations API shape drift]** → manual on-device spike with the
  real key (task 1.1, never from tests) verifies the exact request/response
  shape before the client is finalized; the client parses defensively and
  throws a sanitized error when `outputs` has no assistant message.
- **[Long transcript rejected by the agent's context window]** → spike
  records the practical limit; v1 surfaces the API's error with a retry;
  chunking is a possible later idea in `docs/ideas.md`.
- **[Stale agent ID (agent deleted in Studio)]** → send fails with a
  sanitized 404-style error plus retry; the user re-picks in Settings.
- **[Schema downgrade]** → additive columns only; downgrades are already an
  unsupported path (README: install updates over the existing copy), same as
  the previous changes.

## Migration Plan

- Drift schemaVersion 4 → 5: `if (from < 5)` adds `agent_id` to `preferences`
  and `agent_reply`, `agent_reply_at_ms`, `agent_reply_total_tokens` to
  `sessions` via `migrator.addColumn`; regenerate `app_database.g.dart` with
  `dart run build_runner build --delete-conflicting-outputs`. Additive only;
  existing rows read as null (no agent selected, no reply).
- Rollback: install the previous APK; the only persistent effect is the
  additive columns.

## Open Questions

- The practical input-size limit of an agent's model for a long transcript —
  answered by the manual spike (task 1.1, recorded in `spike-notes.md`); does
  not change the specs or the task breakdown.
- Multi-turn follow-ups with the agent (reusing `conversation_id`) — a future
  idea, not this change.
