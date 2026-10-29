# Spec Delta

## ADDED Requirements

### Requirement: Disclose the agent data flow
The privacy policy SHALL state that when the user sends a transcript to an
agent, the transcript text is sent to the Mistral API (Conversations endpoint)
under the user's own API key with conversation storage disabled (store=false),
that agent and conversation processing is not covered by Mistral's
zero-data-retention, and that the agent's configured tools (web search,
connectors, document libraries) may process the transcript further.

#### Scenario: User reads the policy
- **WHEN** a user reads the privacy policy
- **THEN** the agent flow, the store=false choice, the zero-data-retention exclusion, and the agent-tools caveat are each stated plainly
