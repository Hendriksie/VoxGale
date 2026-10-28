# Spec Delta

## ADDED Requirements

### Requirement: Ship an MIT license
The repository SHALL contain a `LICENSE` file with the MIT license text, naming the copyright holder and the year of first publication.

#### Scenario: Repository is cloned
- **WHEN** a visitor clones or browses the repository
- **THEN** a `LICENSE` file is present at the root and GitHub recognizes the MIT license

### Requirement: Maintain a Keep a Changelog changelog
The repository SHALL maintain `CHANGELOG.md` at the root in Keep a Changelog format: an `## [Unreleased]` section at the top, then one `## [<tag>] - <date>` section per released tag, newest first, with changes grouped as Added / Changed / Fixed. Every released tag SHALL have a matching section.

#### Scenario: A new release is prepared
- **WHEN** a version tag is pushed
- **THEN** `CHANGELOG.md` contains a section for that tag describing its user-facing changes

#### Scenario: Changes accumulate between releases
- **WHEN** changes are merged without a release
- **THEN** they are recorded under `## [Unreleased]` and move into the tag's section at release time

### Requirement: Provide contributing, security, and issue boilerplate
The repository SHALL provide `CONTRIBUTING.md` (pointing changes at the OpenSpec proposal flow in `openspec/` and bugs at GitHub issues), `SECURITY.md` (pointing vulnerability reports at GitHub private vulnerability reporting), and a bug-report issue template under `.github/ISSUE_TEMPLATE/`.

#### Scenario: A contributor wants to change the app
- **WHEN** a contributor reads `CONTRIBUTING.md`
- **THEN** they find the OpenSpec proposal flow, the bug-report route, and the rule that tests never hit the live Mistral API

#### Scenario: A researcher finds a vulnerability
- **WHEN** a researcher reads `SECURITY.md`
- **THEN** they find the private reporting route and an explanation of the app's data flows (audio and transcripts go only to `api.mistral.ai` under the user's own key)

### Requirement: Gate pushes and pull requests on analyze and test
The repository SHALL run `flutter analyze` and `flutter test` in a CI workflow on pushes to the default branch and on pull requests.

#### Scenario: A pull request is opened
- **WHEN** a pull request is opened or updated
- **THEN** CI runs `flutter analyze` and `flutter test` and reports the result on the pull request

### Requirement: Keep a future-ideas parking lot
The repository SHALL keep `docs/ideas.md` as the parking lot for ideas that are not yet OpenSpec proposals, linked from the README, with a stated flow: ideas are recorded there and promoted into `openspec/changes/` proposals when they mature.

#### Scenario: A new idea appears
- **WHEN** an idea is recorded
- **THEN** it is added to `docs/ideas.md`, and when it is picked up it becomes an OpenSpec proposal and is marked or removed in the parking lot

### Requirement: Archive the historical project plan under docs
The completed v1 `project-plan.md` SHALL live at `docs/project-plan.md` (not the repository root), marked as the historical record, and every link to it SHALL resolve.

#### Scenario: A visitor follows a link to the project plan
- **WHEN** a visitor follows a `project-plan.md` link from the README or `docs/friction-list.md`
- **THEN** the link resolves to `docs/project-plan.md` and the file is marked as the historical v1 plan superseded by the OpenSpec flow

### Requirement: Keep the README's development links current
The README SHALL link the changelog, the contributing guide, the ideas parking lot, and the archived project plan, and SHALL NOT link to files that do not exist.

#### Scenario: The README is read
- **WHEN** a visitor reads the README Development section
- **THEN** every link in it resolves to an existing file in the repository
