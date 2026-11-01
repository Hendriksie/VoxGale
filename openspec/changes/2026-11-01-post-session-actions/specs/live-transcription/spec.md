# Spec Delta

## ADDED Requirements

### Requirement: Offer post-session actions on the live screen
The system SHALL offer Share and Send to agent for a just-saved live session
on the live screen, in the post-session card shown when the session's phase is
done or passOffered, combined with the post-session speaker-label pass offer
when one applies.

#### Scenario: Session saved, pass offered
- **WHEN** a live session is saved and the speaker-label pass is offered
- **THEN** the post-session card shows the pass offer (Run/Skip) together with Share and Send to agent actions

#### Scenario: Session saved, pass skipped or done
- **WHEN** a live session is saved and no pass is offered (skipped or already run)
- **THEN** the post-session card still offers Share and Send to agent for that session

#### Scenario: Session recording
- **WHEN** a live session is active or paused
- **THEN** no post-session actions are shown on the live screen

### Requirement: Send to agent from the live screen uses the same flow as from history
The system SHALL send the just-saved session's transcript to the selected
agent with the same confirmation, payload (Markdown export), server-side
storage disabled, reply persistence, and sanitized retryable error as the
send-to-agent action on the transcript detail view.

#### Scenario: Send from the live screen succeeds
- **WHEN** the user taps Send to agent on the post-session card and confirms
- **THEN** the transcript is sent to the selected agent, the reply is persisted with the session, and a confirmation is shown

#### Scenario: Send from the live screen with no agent selected
- **WHEN** the user taps Send to agent and no agent is selected in Settings
- **THEN** the user is pointed to Settings and no request is sent
