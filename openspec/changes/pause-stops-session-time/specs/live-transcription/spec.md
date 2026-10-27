# Spec Delta

## MODIFIED Requirements

### Requirement: Pause and resume a live session
The system SHALL let the user pause an active session and resume it later. While paused, capture and transcription SHALL pause and the paused period SHALL produce no transcript text; the session SHALL stay open so resuming continues the same transcript. While paused, the system SHALL NOT send any audio to the transcription API (a paused period SHALL accrue no transcription cost), and the elapsed session time shown in the app and in the persistent notification SHALL NOT advance. If the transcription stream was closed while paused (for example after a long pause), resuming SHALL re-establish it before audio flows again, and the transcript SHALL continue in the same session.

#### Scenario: User pauses mid-session
- **WHEN** the user pauses an active session
- **THEN** capture and transcription pause, the UI indicates the paused state, no transcript text is produced while paused, no audio is sent to the transcription API, and the elapsed session time stops advancing

#### Scenario: User resumes a paused session
- **WHEN** the user resumes a paused session
- **THEN** capture and transcription continue in the same session, the elapsed session time continues from where it paused, and the transcript continues appending to the same conversation

#### Scenario: Resume after the stream was closed while paused
- **WHEN** the user resumes a session whose transcription stream was closed while paused
- **THEN** the stream is re-established before audio flows again and the transcript continues in the same session
