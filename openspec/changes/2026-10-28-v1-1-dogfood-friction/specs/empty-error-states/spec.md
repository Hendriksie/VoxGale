# Spec Delta

## MODIFIED Requirements

### Requirement: Show a distinct state for each missing precondition
The system SHALL show a distinct, clearly worded state when a required precondition is missing: no API key saved, microphone permission denied, and no network connection. Each state SHALL name the precondition and SHALL offer the remedy action that resolves it. The missing-key state SHALL track the key's current presence: it is shown while no key is saved and dismissed as soon as a key is saved, without restarting the app.

#### Scenario: No API key saved
- **WHEN** the user opens a transcription screen and no API key is saved
- **THEN** a missing-key state is shown with an action that opens the settings screen

#### Scenario: Microphone permission denied
- **WHEN** the user starts a live session and microphone permission is denied
- **THEN** the session does not start, and a permission-denied state explains why, with an action to grant the permission or open the system permission settings

#### Scenario: No network connection
- **WHEN** a transcription is started or runs without a network connection
- **THEN** a no-network state is shown with a retry action, and no request is sent

#### Scenario: Key saved while the missing-key state is shown
- **WHEN** a key is saved in settings while a transcription screen shows the missing-key state
- **THEN** the missing-key state is dismissed without restarting the app

#### Scenario: Key removed while a transcription screen is open
- **WHEN** the saved key is removed in settings while a transcription screen is open
- **THEN** the missing-key state is shown again without restarting the app
