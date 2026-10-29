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

### Requirement: Pause and resume a live session
The system SHALL let the user pause an active session and resume it later. While paused, capture and transcription SHALL pause and the paused period SHALL produce no transcript text; the session SHALL stay open so resuming continues the same transcript. If the transcription stream was closed while paused (for example after a long pause), resuming SHALL re-establish it before audio flows again, and the transcript SHALL continue in the same session.

#### Scenario: User pauses mid-session
- **WHEN** the user pauses an active session
- **THEN** capture and transcription pause, the UI indicates the paused state, and no transcript text is produced while paused

#### Scenario: User resumes a paused session
- **WHEN** the user resumes a paused session
- **THEN** capture and transcription continue in the same session, and the transcript continues appending to the same conversation

#### Scenario: Resume after the stream was closed while paused
- **WHEN** the user resumes a session whose transcription stream was closed while paused
- **THEN** the stream is re-established before audio flows again and the transcript continues in the same session

### Requirement: A paused session sends no audio and advances no session time
While paused, the system SHALL NOT send any audio to the transcription API, so a paused period SHALL accrue no transcription cost, and the elapsed session time shown in the app and in the persistent notification SHALL NOT advance.

#### Scenario: No audio sent while paused
- **WHEN** a live session is paused
- **THEN** no audio is sent to the transcription API, and the paused period accrues no transcription cost

#### Scenario: Elapsed session time frozen while paused
- **WHEN** a live session is paused
- **THEN** the elapsed session time shown in the app and in the persistent notification does not advance until the session resumes

### Requirement: Check background battery restrictions
The system SHALL check whether the app is exempt from battery optimization when a session is about to start or while it is active, and SHALL prompt the user to allow unrestricted background activity when it is not, explaining that capture may otherwise be killed while the screen is off. The system SHALL re-check the exemption when the app returns to the foreground and SHALL dismiss the prompt once the app is exempt, without restarting the app.

#### Scenario: App not exempt from battery optimization
- **WHEN** a session starts and the app is not exempt from battery optimization
- **THEN** the system prompts the user to allow unrestricted background activity, with a way to open the system battery settings

#### Scenario: App already exempt
- **WHEN** a session starts and the app is already exempt from battery optimization
- **THEN** no prompt is shown and the session starts normally

#### Scenario: Exemption granted while the app is backgrounded
- **WHEN** the user grants the exemption in the system battery settings and returns to the app
- **THEN** the prompt is dismissed without restarting the app

### Requirement: Indicate connection interruptions in the session UI
The system SHALL indicate in the session UI, outside the transcript text, when the transcription stream reconnects, when buffered audio is replayed, and when buffered audio was dropped, so the user can tell a seamless session from one with interruptions.

#### Scenario: Reconnect during a session
- **WHEN** the transcription stream drops and reconnects during a session
- **THEN** the session UI shows a connection status indicator for the interruption and the transcript text itself is unchanged

#### Scenario: Buffered audio replayed after reconnect
- **WHEN** buffered audio finishes replaying into the re-established stream
- **THEN** the session UI indicates how much buffered audio was replayed

### Requirement: Keep the device awake while capture is running
The system SHALL hold a partial wake lock for the entire time the capture foreground service is running, so the CPU stays awake for streaming while the screen is off, and SHALL NOT hold any wake lock when no session is active.

#### Scenario: Screen off during a session
- **WHEN** the screen turns off while a capture session is active
- **THEN** a partial wake lock is held for the duration of the session, keeping the CPU awake for capture and transcription

#### Scenario: No session active
- **WHEN** no capture session is active
- **THEN** the system holds no wake lock and the device may sleep normally

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
