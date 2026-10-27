# Spec Delta

## Purpose

Give every screen a clear, consistent empty and error state — for missing preconditions (API key, microphone permission, network) and for failures (API errors, quota) — so the app never shows a blank or broken screen, and always offers the next step when one exists.

## ADDED Requirements

### Requirement: Show a distinct state for each missing precondition
The system SHALL show a distinct, clearly worded state when a required precondition is missing: no API key saved, microphone permission denied, and no network connection. Each state SHALL name the precondition and SHALL offer the remedy action that resolves it.

#### Scenario: No API key saved
- **WHEN** the user opens a transcription screen and no API key is saved
- **THEN** a missing-key state is shown with an action that opens the settings screen

#### Scenario: Microphone permission denied
- **WHEN** the user starts a live session and microphone permission is denied
- **THEN** the session does not start, and a permission-denied state explains why, with an action to grant the permission or open the system permission settings

#### Scenario: No network connection
- **WHEN** a transcription is started or runs without a network connection
- **THEN** a no-network state is shown with a retry action, and no request is sent

### Requirement: Distinguish API failure kinds in error states
The system SHALL show error states that distinguish authentication failures (an invalid or missing API key), quota or billing exhaustion, and other API failures, each with plain-language wording appropriate to the cause and a remedy action where one exists.

#### Scenario: Invalid API key
- **WHEN** the API rejects a request because the key is invalid
- **THEN** an authentication error state is shown with an action that opens the settings screen, and no audio is sent

#### Scenario: Quota exhausted mid-session
- **WHEN** the API rejects audio mid-session due to quota or billing
- **THEN** a quota error state is shown, the transcript text received so far is preserved, and the session can be saved as-is

#### Scenario: Other API failure
- **WHEN** the API fails for another reason (server error, unreachable endpoint)
- **THEN** an error state explains the failure and offers a retry where retrying is meaningful

### Requirement: Show empty states for empty content
The system SHALL show an empty state with guidance and a primary action wherever a screen's content can be empty: the live transcript with no turns, the transcript history with no saved transcripts, and file transcription mode before a file is picked.

#### Scenario: Live transcript is empty
- **WHEN** the live session screen has no transcript turns to show
- **THEN** an empty state invites the user to start a session instead of showing a blank area

#### Scenario: History is empty
- **WHEN** the history screen has no saved transcripts
- **THEN** an empty state explains that finished transcripts appear here, shown distinctly from a search with no matches

### Requirement: Present error states consistently across screens
The system SHALL present error states consistently on every screen: a full-screen state for blocking failures that end a flow, an inline banner for non-blocking or transient errors, an icon and a plain-language message in both cases, and theme-appropriate error colors in light and dark mode.

#### Scenario: Blocking failure ends a flow
- **WHEN** a failure makes the current flow impossible to continue
- **THEN** the screen shows a full error state with the message and any remedy action

#### Scenario: Transient error during a session
- **WHEN** a non-fatal error occurs while a session continues
- **THEN** an inline banner shows the message without hiding the transcript or the session controls

### Requirement: Sanitize error messages
The system SHALL NOT include the API key, raw HTTP payloads, or server internals in any user-visible error message; error text SHALL be limited to a safe, plain-language description of the failure.

#### Scenario: API error carries internal detail
- **WHEN** an API failure produces a message containing credentials or raw response detail
- **THEN** the user-visible error shows only the sanitized description
