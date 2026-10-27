# Spec Delta

## ADDED Requirements

### Requirement: Keep the device awake while capture is running
The system SHALL hold a partial wake lock for the entire time the capture foreground service is running, so the CPU stays awake for streaming while the screen is off, and SHALL NOT hold any wake lock when no session is active.

#### Scenario: Screen off during a session
- **WHEN** the screen turns off while a capture session is active
- **THEN** a partial wake lock is held for the duration of the session, keeping the CPU awake for capture and transcription

#### Scenario: No session active
- **WHEN** no capture session is active
- **THEN** the system holds no wake lock and the device may sleep normally
