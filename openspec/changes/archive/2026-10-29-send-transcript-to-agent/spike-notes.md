# Spike Notes — 2026-10-29-send-transcript-to-agent

Verified via the shipped feature on a physical device (user report,
2026-11-01), not from tests:

- [x] Agent picker: after creating an agent in Studio (console.mistral.ai →
  Build → Agents), `GET /v1/agents` lists it by name in Settings; selecting
  persists. Empty workspace no longer loops (fix 0015a6a: `agentsLoaded`
  flag); it shows the "No agents found" note.
- [x] `POST /v1/conversations` with `{agent_id, inputs, stream: false,
  store: false}`: sending a saved transcript from the history detail view
  returns the assistant reply plus token usage; the reply card shows reply,
  time, and tokens; it persists across an app restart and shares via the
  share sheet. `store: false` in the request body is pinned by
  `test/mistral/agent_client_test.dart`.
- [x] Error paths: sanitized errors never contain the API key (client tests);
  unknown/deleted agent maps to a retryable "agent was not found" message
  (client test pins the 404 mapping).
- [ ] Not separately spiked: the practical input-size limit of an agent's
  model for a very long transcript (~60 min). v1 sends the full transcript as
  one input; if the API rejects the size, the sanitized error surfaces with a
  retry. Recorded as the design's open question (design.md decision 11).
