# Ideas — the VoxGale parking lot

Raw ideas and observations that are not (yet) OpenSpec proposals. When an
idea matures, promote it: create a proposal in `openspec/changes/` (see
[CONTRIBUTING.md](../CONTRIBUTING.md)) and mark or remove it here. The
historical v1 plan lives at [project-plan.md](project-plan.md).

## From the v1 project plan (§9, historical)

- **Mistral agent integration** — PROMOTED (change
  `2026-10-29-send-transcript-to-agent`): after a session, the user sends
  the transcript to a Mistral agent they've configured (summarize, extract
  action items, file notes). Keep the data model export-friendly so this is
  a drop-in feature. Researched 2026-10-29 against docs.mistral.ai: the
  same user API key authenticates the Agents/Conversations API on
  `api.mistral.ai` — `GET /v1/agents` lists the workspace's agents and
  `POST /v1/conversations` with `{agent_id, inputs, stream: false,
  store: false}` runs a one-shot agent call and returns the assistant
  message plus token usage. Integration points: a new `lib/mistral/agent/`
  client behind an interface (API key read from `ApiKeyStore` at provider
  construction, exactly like the batch client), the agent ID as a
  non-secret `StoredPreferences` field in Settings, and a "Send to agent"
  action on the history detail screen reusing the export builders for the
  payload. Caveats found in the docs: agent calls are token-priced, not
  per-minute audio, so the cost-indicator rates don't apply (the response
  carries token usage instead); Agents/Conversations are stateful and
  explicitly outside Mistral's zero-data-retention coverage, so always
  send with `store: false` and state the flow in PRIVACY.md; an agent with
  tools (web search, connectors, libraries) may forward transcript content
  to those tools — that is the user's own agent configuration, worth a UI
  note. Decided 2026-10-29: the agent is chosen with a picker populated
  from `GET /v1/agents` (agent names shown, chosen ID stored), not a
  free-text field. Open questions before proposing: persist the agent's
  reply per session or display/share-only, transcript length vs the agent
  model's context window, and a manual on-device spike of
  `POST /v1/conversations` with the real key (never from tests).
- **Automatic speaker naming** — batch diarization yields "Speaker 1 /
  Speaker 2" segments; let users rename speakers once, store a local
  speaker profile, and map known voices to names in future captures.
  Interim trick: feed known speaker names as context-biasing keyphrases so
  transcription at least spells names correctly.
- **Live translation** — Small Transcribe 3 supports it.
- **Widgets / quick-start tile** — start a session from the home screen.
- **Wear OS companion.**
- **iOS port** — the architecture allows it later; Android first.
- **On-device wake word** to start sessions hands-free.

## Open observations from dogfooding ([friction-list.md](friction-list.md))

- **Session lost when the battery exemption is revoked mid-session** — on
  GrapheneOS, revoking the exemption while the app was backgrounded killed
  the capture service and the session was gone (severity: data lost).
  Candidate follow-up: detect a dead capture service on resume and offer to
  recover or restart the session, or warn when the exemption is revoked
  mid-session.

## Open questions from the Phase-0 spikes (cancelled probes)

- Realtime API limits — max session length, concurrent sessions.
- The 50%-off batch tier — eligibility and how it bills.
- The `speaker_references` wire format — could enable voice enrollment
  later.

## New ideas (2026-10-28, from the maintainer)

- **In-app update check** — promoted (change `2026-10-29-update-tracker`):
  the update tracker and the manual "check for updates" action in Settings
  are implemented; the version source of truth is the GitHub Releases API.
  Still parked: a full in-app updater — download + install flow (Android's
  package installer always requires user confirmation for sideloaded
  APKs), full vs delta APK, signature verification of the downloaded
  artifact.
- **Keep the screen on during sessions** — promoted (change
  `2026-10-29-keep-screen-on-during-sessions`): a Settings toggle (off by
  default) that holds the screen wake lock (`FLAG_KEEP_SCREEN_ON` via
  `wakelock_plus`) for the whole live session, including pauses, released
  on stop/error. Scope settled as live sessions only; the existing partial
  wake lock for background capture is untouched. Still parked: a dimmed
  keep-screen-on mode (the toggle keeps the current brightness).

## New ideas (2026-11-01, from the maintainer)

- **Send a transcript to Vibe (as a new chat in the Vibe app)** — researched
  2026-11-01 against docs.mistral.ai: **not possible with the API key alone
  today.** Vibe Work chats (chat.mistral.ai/work, web + mobile) are
  account-session state stored for history (explicitly outside Mistral's
  ZDR) with no public REST API to create or prefill one — the only
  API-key-accessible chat surface is Studio's Conversations/Agents API
  (`/v1/conversations`), which is what the shipped agent integration uses,
  and those conversations do not appear in the Vibe app. Vibe share links
  share Canvas artifacts only ("your chat messages aren't shared"). No
  documented deep link / query param opens a new Vibe chat with a prefilled
  prompt. Skills in Work are invoked by the user with `@`/slash — not
  attachable programmatically. Possible angles when this matures: (a) share
  the transcript via the Android share sheet / an intent into the Vibe
  mobile app if it registers a text share target (needs a device spike);
  (b) open `https://chat.mistral.ai/work` alongside the exported transcript
  (paste manually); (c) ask Mistral for a Vibe chat API or prefill deep link.
  Open question: whether the Vibe mobile app accepts shared text into a new
  chat.

## Add yours

<!-- One idea per bullet: what it is, why it would be good, open questions. -->
