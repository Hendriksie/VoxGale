# Spec Delta

## MODIFIED Requirements

### Requirement: Export transcripts
The system SHALL export a transcript to plain text or Markdown via the system
share sheet, offering BOTH the export file AND the export text itself (on
Android, the text extra `EXTRA_TEXT` alongside the file stream `EXTRA_STREAM`)
with MIME type `text/plain`, so that text-consuming share targets (chat and
note apps) receive the content as well as file-consuming targets. When the
export text exceeds 500 KB, the system SHALL offer the file only, because the
text extra rides in the share intent's binder transaction (~1 MB total) and a
very large text could make the whole share intent fail.

#### Scenario: User exports
- **WHEN** the user exports a transcript
- **THEN** a text or Markdown file containing the speaker-labelled transcript
  is produced and offered to the share sheet together with the export text

#### Scenario: Text-consuming share target receives the content
- **WHEN** the user shares a transcript export to a share target that reads
  shared text (e.g. a chat app)
- **THEN** the target receives the full export text, not only a file
  reference, and the offer is labelled `text/plain` even for the Markdown
  export

#### Scenario: Very large transcript
- **WHEN** the user exports a transcript whose export text exceeds 500 KB
- **THEN** the share offer contains the export file only (no text extra) and
  the share sheet still opens without error

### Requirement: Export the agent reply
The system SHALL let the user export the displayed agent reply to plain text
via the system share sheet, offering BOTH the reply text (on Android, the
text extra `EXTRA_TEXT`) AND the text file (`EXTRA_STREAM`) with MIME type
`text/plain`, so that text-consuming share targets receive the reply as well
as file-consuming targets. When the reply text exceeds 500 KB, the system
SHALL offer the file only, because the text extra rides in the share intent's
binder transaction (~1 MB total) and a very large reply could make the whole
share intent fail.

#### Scenario: User exports the reply
- **WHEN** an agent reply is displayed and the user chooses to share it
- **THEN** a text file containing the agent's reply is offered to the share
  sheet together with the reply text

#### Scenario: Text-consuming share target receives the reply
- **WHEN** the user shares the agent reply to a share target that reads
  shared text (e.g. a chat app)
- **THEN** the target receives the full reply text, not only a file reference
