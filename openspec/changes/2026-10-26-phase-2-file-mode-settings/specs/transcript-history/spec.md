# Spec Delta

## ADDED Requirements

### Requirement: Provide a transcript history entry point in the app's main UI
The system SHALL provide an entry point to the transcript history in the app's main navigation, which opens the history list.

#### Scenario: User opens history
- **WHEN** the user taps the history action in the app's main UI
- **THEN** the history list opens, showing saved transcripts newest first

### Requirement: Identify the source of each history entry
The system SHALL identify each history entry's source — a live session or an imported file with its file name — together with the model used and, when known, the actual cost, in both the history list and the detail view.

#### Scenario: History list shows sources
- **WHEN** the user opens the history list
- **THEN** each entry shows its date, duration, source (live session or file name), and model

#### Scenario: File transcription appears with its source
- **WHEN** a file transcription is saved to history
- **THEN** it appears in the same history list as live sessions, identified by its source file name
