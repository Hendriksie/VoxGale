# Spec Delta

## ADDED Requirements

### Requirement: Offer a keep-screen-on toggle in settings
The system SHALL offer a "Keep screen on during sessions" toggle in the settings screen's transcription preferences, defaulting to off, and SHALL persist the toggle's state locally so it survives an app restart.

#### Scenario: Toggle defaults to off
- **WHEN** the user opens the settings screen and has never changed the toggle
- **THEN** the toggle is shown off

#### Scenario: Toggle persists across a restart
- **WHEN** the user enables the toggle, restarts the app, and reopens the settings screen
- **THEN** the toggle is shown on

#### Scenario: Toggle can be turned off again
- **WHEN** the user disables the toggle
- **THEN** the off state is persisted and the screen may turn off normally during sessions again
