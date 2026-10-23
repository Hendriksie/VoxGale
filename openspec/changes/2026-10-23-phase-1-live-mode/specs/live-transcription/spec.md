# Spec Delta

## ADDED Requirements

### Requirement: Pause and resume a live session
The system SHALL let the user pause an active session and resume it later. While paused, capture and transcription SHALL pause and the paused period SHALL produce no transcript text; the session SHALL stay open so resuming continues the same transcript.

#### Scenario: User pauses mid-session
- **WHEN** the user pauses an active session
- **THEN** capture and transcription pause, the UI indicates the paused state, and no transcript text is produced while paused

#### Scenario: User resumes a paused session
- **WHEN** the user resumes a paused session
- **THEN** capture and transcription continue in the same session and the transcript continues appending to the same conversation

### Requirement: Check background battery restrictions
The system SHALL check whether the app is exempt from battery optimization when a session is about to start or while it is active, and SHALL prompt the user to allow unrestricted background activity when it is not, explaining that capture may otherwise be killed while the screen is off.

#### Scenario: App not exempt from battery optimization
- **WHEN** a session starts and the app is not exempt from battery optimization
- **THEN** the system prompts the user to allow unrestricted background activity, with a way to open the system battery settings

#### Scenario: App already exempt
- **WHEN** a session starts and the app is already exempt from battery optimization
- **THEN** no prompt is shown and the session starts normally

### Requirement: Indicate connection interruptions in the session UI
The system SHALL indicate in the session UI, outside the transcript text, when the transcription stream reconnects, when buffered audio is replayed, and when buffered audio was dropped, so the user can tell a seamless session from one with interruptions.

#### Scenario: Reconnect during a session
- **WHEN** the transcription stream drops and reconnects during a session
- **THEN** the session UI shows a connection status indicator for the interruption and the transcript text itself is unchanged

#### Scenario: Buffered audio replayed after reconnect
- **WHEN** buffered audio finishes replaying into the re-established stream
- **THEN** the session UI indicates how much buffered audio was replayed

## MODIFIED Requirements

### Requirement: Continue capture while backgrounded
The system SHALL run audio capture and transcription in an Android foreground service of type microphone for the entire live session, not only while backgrounded, and SHALL show a persistent notification that indicates capture is active, displays the elapsed session time, and offers a stop action.

#### Scenario: Screen off during a session
- **WHEN** the screen turns off or the app is backgrounded during an active session
- **THEN** capture and transcription continue, the persistent notification remains with the elapsed time, and the transcript keeps growing until the user stops the session

#### Scenario: Notification stop action used while backgrounded
- **WHEN** the user taps the stop action in the persistent notification while the app is backgrounded
- **THEN** the session ends gracefully and the final transcript is saved

### Requirement: Recover from network interruptions
The system SHALL reconnect the transcription stream automatically after a network drop, buffering audio locally while disconnected up to a bounded limit, and SHALL never lose or rewrite transcript text that was already displayed. When the buffer limit is exceeded, the oldest buffered audio SHALL be dropped and the transcript SHALL show a visible gap marker at the point where audio was lost.

#### Scenario: Connection drops mid-session
- **WHEN** the network connection drops for a period during an active session
- **THEN** the system reconnects, sends the buffered audio, and the transcript continues without duplicated text

#### Scenario: Disconnection longer than the buffer limit
- **WHEN** the network connection stays down longer than the local buffer can hold
- **THEN** the oldest buffered audio is dropped, and after reconnecting the transcript shows a gap marker where the lost audio would have been transcribed
