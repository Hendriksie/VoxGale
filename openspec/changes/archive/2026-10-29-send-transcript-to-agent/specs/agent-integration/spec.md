# Spec Delta

## Purpose

Let the user send a saved transcript to a Mistral agent they selected in their
own workspace, using the app's own API key, and keep the agent's reply with
the transcript on the device.

## ADDED Requirements

### Requirement: Send a transcript to the selected agent
The system SHALL let the user send a saved transcript to the agent selected in
Settings, from the transcript's detail view, over the Mistral API with the
app's stored API key, and SHALL show the agent's reply on the detail view.

#### Scenario: Send succeeds
- **WHEN** the user taps "Send to agent" on a saved transcript and an agent is selected
- **THEN** the transcript text is sent to that agent and the agent's reply is displayed on the detail view

#### Scenario: No agent selected
- **WHEN** the user opens a transcript's detail view and no agent is selected in Settings
- **THEN** the "Send to agent" action is unavailable and the user is pointed to Settings

#### Scenario: Agent call fails
- **WHEN** the agent call fails (rejected key, unknown agent, network, API error)
- **THEN** a sanitized error message is shown with a retry, and any previously stored reply for the transcript is kept

### Requirement: Send the transcript as its Markdown export
The system SHALL send the transcript to the agent as the transcript's Markdown
export, so speaker labels and timestamps are preserved in the payload.

#### Scenario: Payload carries speaker labels
- **WHEN** a speaker-labelled transcript is sent to an agent
- **THEN** the request payload contains the speaker-labelled Markdown export of the transcript

### Requirement: Never retain conversation history server-side
The system SHALL send every agent request with server-side conversation
storage disabled, so no conversation history is kept on Mistral's side.

#### Scenario: Request disables storage
- **WHEN** a transcript is sent to an agent
- **THEN** the request to the Mistral API disables storage of the conversation (store=false)

### Requirement: Persist the latest agent reply per transcript
The system SHALL store the most recent agent reply (text, time, and token
usage) together with the transcript, overwriting any previous reply when the
transcript is sent again, and SHALL delete the reply when the transcript is
deleted.

#### Scenario: Reply survives an app restart
- **WHEN** a transcript was sent to an agent, the app is restarted, and the transcript is reopened
- **THEN** the stored agent reply is still shown

#### Scenario: Re-send overwrites the reply
- **WHEN** a transcript is sent to an agent again
- **THEN** the stored reply is replaced by the new reply

#### Scenario: Deleting the transcript deletes the reply
- **WHEN** a transcript with a stored agent reply is deleted
- **THEN** the reply is removed together with the transcript

### Requirement: Show the agent reply's token usage
The system SHALL display the token usage (prompt, completion, and total
tokens) reported by the API together with the agent's reply, and SHALL NOT
show a per-minute audio cost estimate for agent calls.

#### Scenario: Reply arrives with usage
- **WHEN** an agent reply arrives and the API reported token usage
- **THEN** the usage is displayed alongside the reply, with no per-minute audio cost estimate
