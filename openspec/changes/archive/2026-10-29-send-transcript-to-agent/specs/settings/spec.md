# Spec Delta

## ADDED Requirements

### Requirement: Offer an agent picker in settings
The system SHALL list the agents of the user's Mistral workspace — fetched
through the Mistral API with the stored API key — in the settings screen and
let the user pick one, SHALL persist the chosen agent locally so it survives
an app restart, and SHALL show an error with a retry when the list cannot be
loaded (no free-text agent ID entry).

#### Scenario: Agents are listed by name
- **WHEN** the user opens the settings screen and an API key is saved
- **THEN** the workspace's agents are fetched and shown by name for selection

#### Scenario: Selection persists across a restart
- **WHEN** the user picks an agent, restarts the app, and reopens the settings screen
- **THEN** the picked agent is still selected

#### Scenario: Agent list cannot be loaded
- **WHEN** the agent list request fails (network or API error)
- **THEN** an error with a retry action is shown and the previously selected agent is kept

#### Scenario: No API key saved
- **WHEN** the user opens the settings screen and no API key is saved
- **THEN** the agent picker is not offered, alongside the existing missing-key state
