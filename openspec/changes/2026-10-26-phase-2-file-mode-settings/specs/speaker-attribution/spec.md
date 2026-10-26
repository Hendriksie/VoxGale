# Spec Delta

## ADDED Requirements

### Requirement: Re-offer a skipped or failed post-session pass from the transcript detail view
The system SHALL offer, in the history detail view of a saved live session whose post-session diarization pass was skipped or failed, to run the pass on the retained session audio, showing the pass's estimated cost before it runs. A pass run from the detail view SHALL replace the provisional transcript with the speaker-labelled result and delete the session audio after success, exactly as when the pass runs at session end.

#### Scenario: Skipped pass re-offered
- **WHEN** the user opens the detail view of a session whose pass was skipped and the session audio is still retained
- **THEN** the view offers to run the pass, showing its estimated cost

#### Scenario: Failed pass retryable from the detail view
- **WHEN** the user opens the detail view of a session whose pass failed and the session audio is still retained
- **THEN** the view offers to retry the pass, showing its estimated cost

#### Scenario: Re-offered pass completes
- **WHEN** a pass re-offered from the detail view completes successfully
- **THEN** the provisional transcript is replaced with the speaker-labelled result and the session audio is deleted

#### Scenario: No audio retained
- **WHEN** the user opens the detail view of a session whose audio was already deleted
- **THEN** no pass offer is shown
