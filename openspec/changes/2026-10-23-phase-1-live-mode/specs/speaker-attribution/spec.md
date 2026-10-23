# Spec Delta

## MODIFIED Requirements

### Requirement: Produce the speaker-labelled final transcript for live sessions
The system SHALL, by default, offer a post-session batch transcription pass with diarization on the saved session audio when a live session ends, showing the pass's estimated cost and letting the user run it or skip it. When the pass runs, the system SHALL replace the provisional live transcript with the speaker-labelled result, and SHALL delete the session audio after a successful pass unless the user has chosen to keep recordings.

#### Scenario: Live session finalized
- **WHEN** a live session ends and the post-session diarization pass completes
- **THEN** the session's transcript is updated to show speaker-labelled segments, replacing the provisional streaming text, and the session audio is deleted

#### Scenario: Post-session pass fails
- **WHEN** the post-session diarization pass fails
- **THEN** the provisional live transcript is preserved, an error state explains the failure, and the user can retry the pass

#### Scenario: User skips the post-session pass
- **WHEN** a live session ends and the user skips the offered diarization pass
- **THEN** the provisional live transcript is kept as the transcript of record, no batch request is sent, and the session audio is kept so the pass can still be run later
