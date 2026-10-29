# Spec Delta

## ADDED Requirements

### Requirement: Keep the screen on during a live session when enabled
When the "Keep screen on during sessions" preference is on, the system SHALL hold a screen wake lock that keeps the display on for the entire live session — from capture becoming active, through pauses, until the session ends — and SHALL release the screen wake lock when the session ends or fails.

#### Scenario: Screen stays on while a session runs
- **WHEN** the preference is on, a live session is active, and the screen timeout elapses
- **THEN** the display stays on until the session ends

#### Scenario: Pause keeps the screen on
- **WHEN** the preference is on and the user pauses an active session
- **THEN** the display stays on while paused

#### Scenario: Screen wake lock released when the session ends
- **WHEN** the preference is on and the user stops the session
- **THEN** the screen wake lock is released and the screen may turn off normally

#### Scenario: Screen wake lock released when the session fails
- **WHEN** the preference is on and the session ends with an unrecoverable error
- **THEN** the screen wake lock is released

#### Scenario: Backgrounded during a session with the toggle on
- **WHEN** the preference is on, a live session is active, and the app is backgrounded
- **THEN** capture and transcription continue per the existing background-capture requirement, and the screen wake lock does not keep the display on once the app is no longer foregrounded

### Requirement: No screen wake lock when the toggle is off
When the preference is off (the default), the system SHALL NOT hold a screen wake lock: the screen SHALL be allowed to turn off during a session, while the partial wake lock that keeps capture alive with the screen off SHALL still be held for the whole session. When no live session is active, no screen wake lock SHALL be held regardless of the toggle.

#### Scenario: Screen may turn off with the toggle off
- **WHEN** the preference is off, a live session is active, and the screen timeout elapses
- **THEN** the screen turns off and capture continues via the partial wake lock

#### Scenario: No screen wake lock outside sessions
- **WHEN** the preference is on but no live session is active
- **THEN** no screen wake lock is held and the screen turns off normally
