# live-transcription Specification

## Purpose
Capture live conversation audio on Android — including while the app is backgrounded or the screen is off — stream it to the Mistral realtime transcription API with the user's own key, and show the transcript as it is spoken.

## Requirements

### Requirement: Start and stop a live recording session
The system SHALL let the user start and stop a live recording session. While recording, the UI SHALL show an unmistakable recording state; while the app is backgrounded, a persistent notification SHALL indicate that capture is active.

#### Scenario: Start with microphone permission granted
- **WHEN** the user starts a session and microphone permission is granted
- **THEN** capture begins, the recording indicator appears, and transcript text starts appearing as speech is detected

#### Scenario: Start without microphone permission
- **WHEN** the user starts a session without microphone permission
- **THEN** the system requests the permission; if denied, the session does not start and a clear error state explains why

### Requirement: Show the live transcript as it is spoken
The system SHALL display transcription text as it arrives, grouped into conversation turns. Provisional streaming text SHALL be visually distinct from finalized text.

#### Scenario: Text arrives during speech
- **WHEN** a person speaks during an active session
- **THEN** the words appear in the transcript within a few seconds, appended to the current turn

#### Scenario: Turn boundary closes a turn block
- **WHEN** the speaker pauses long enough for the session to detect the end of a turn
- **THEN** the current turn is closed and the next speech opens a new turn block

### Requirement: Continue capture while backgrounded
The system SHALL continue audio capture while the app is backgrounded or the screen is off, using an Android foreground service of type microphone.

#### Scenario: Screen off during a session
- **WHEN** the screen turns off or the app is backgrounded during an active session
- **THEN** capture and transcription continue, the persistent notification remains, and the transcript keeps growing until the user stops the session

### Requirement: Recover from network interruptions
The system SHALL reconnect the transcription stream automatically after a network drop, buffering audio locally while disconnected, and SHALL never lose or rewrite transcript text that was already displayed.

#### Scenario: Connection drops mid-session
- **WHEN** the network connection drops for a period during an active session
- **THEN** the system reconnects, sends the buffered audio, and the transcript continues without gaps or duplicated text

### Requirement: Respect audio focus
The system SHALL pause capture when another application takes audio focus (for example an incoming phone call) and resume when focus returns.

#### Scenario: Phone call during a session
- **WHEN** an incoming call takes audio focus during an active session
- **THEN** capture pauses, the UI indicates the pause, and capture resumes when the call ends

### Requirement: Finalize and save the session on stop
The system SHALL end the stream when the user stops, produce the final transcript of record for the session, and save the session locally.

#### Scenario: User stops the session
- **WHEN** the user stops an active session
- **THEN** the stream ends gracefully, the final transcript is shown, and the session is saved to local history

### Requirement: Surface capture and API errors without crashing
The system SHALL show clear error states for a missing or invalid API key, denied microphone permission, missing network, and API errors such as quota exhaustion. The API key SHALL never appear in logs or error messages.

#### Scenario: Invalid API key
- **WHEN** a session is started with an invalid API key
- **THEN** the session does not start, an authentication error state is shown with a way to open settings, and no audio is sent

#### Scenario: Quota exhausted mid-session
- **WHEN** the API rejects audio mid-session due to quota or billing
- **THEN** an error state is shown, the text received so far is preserved, and the session can be saved as-is
