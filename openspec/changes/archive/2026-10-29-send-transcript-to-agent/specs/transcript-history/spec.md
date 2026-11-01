# Spec Delta

## ADDED Requirements

### Requirement: Offer a send-to-agent action on the transcript detail view
The system SHALL provide a "Send to agent" action on the transcript detail
view, enabled when the transcript has content and an agent is selected in
Settings.

#### Scenario: Action available
- **WHEN** the user opens a saved transcript that has segments and an agent is selected
- **THEN** the "Send to agent" action is enabled

#### Scenario: Transcript empty or no agent selected
- **WHEN** the user opens a saved transcript with no segments, or no agent is selected
- **THEN** the "Send to agent" action is disabled or hidden

### Requirement: Export the agent reply
The system SHALL let the user export the displayed agent reply to plain text
via the system share sheet.

#### Scenario: User exports the reply
- **WHEN** an agent reply is displayed and the user chooses to share it
- **THEN** a text file containing the agent's reply is offered to the share sheet
