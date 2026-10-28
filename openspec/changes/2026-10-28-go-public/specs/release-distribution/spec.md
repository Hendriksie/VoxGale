# Spec Delta

## ADDED Requirements

### Requirement: Generate release notes from the changelog
The release workflow SHALL generate the GitHub Release notes from the `CHANGELOG.md` section whose heading matches the pushed tag (`## [<tag>]`), and SHALL fall back to a one-line default note when the tag has no changelog section.

#### Scenario: A tag with a changelog section is pushed
- **WHEN** a version tag is pushed and `CHANGELOG.md` contains a `## [<tag>]` section
- **THEN** the published GitHub Release's notes are the content of that section

#### Scenario: A tag without a changelog section is pushed
- **WHEN** a version tag is pushed and `CHANGELOG.md` has no section for the tag
- **THEN** the published GitHub Release carries the default one-line note, and the workflow does not fail
