# speaker-attribution Specification

## Purpose
Attribute transcript segments to speakers so the user can see who said what, in both live and file transcription, including naming known speakers from reference voice clips.

## Requirements

### Requirement: Label speakers in file transcripts
The system SHALL label each segment of a file transcript with a speaker identifier (for example speaker_1, speaker_2).

#### Scenario: Two-person recording
- **WHEN** a file with two speakers is transcribed with diarization
- **THEN** consecutive segments from the same speaker share one label and speaker changes are visible

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

### Requirement: Support live speaker labels as a per-session option
The system SHALL offer a per-session option to receive speaker labels live during the session instead of waiting for the post-session pass.

#### Scenario: Live diarization enabled
- **WHEN** a session is started with live speaker labels enabled
- **THEN** transcript text arrives labelled with speaker identifiers as it is spoken, and turns are grouped by speaker change

### Requirement: Name speakers with reference clips
The system SHALL let the user enroll a speaker by name with a short reference voice clip (3–15 seconds), up to 8 speakers, and SHALL use enrolled names as the speaker labels in transcripts that include those voices.

#### Scenario: Enrolled speaker recognized
- **WHEN** a transcript is produced with diarization and an enrolled speaker's reference clip, and that speaker is present in the audio
- **THEN** that speaker's segments carry the enrolled name instead of a generic label

#### Scenario: More than 8 speakers enrolled
- **WHEN** the user tries to enroll a ninth speaker
- **THEN** the system explains the limit of 8 and asks the user to remove one first

### Requirement: Keep speaker labels scoped to their source
The system SHALL NOT imply that a generic speaker label (such as speaker_1) refers to the same person across different transcripts or sessions.

#### Scenario: Same label in two sessions
- **WHEN** two different sessions both contain a segment labelled speaker_1
- **THEN** the UI does not merge or equate the two labels; only enrolled reference clips create cross-session identity

### Requirement: Display overlapping speech honestly
The system SHALL display segments from two speakers that overlap in time without cutting either segment short.

#### Scenario: Two people talk at once
- **WHEN** two speakers talk over each other
- **THEN** both speakers' segments are shown for the overlapping period
