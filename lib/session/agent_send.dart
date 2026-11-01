// The shared send-to-agent step (change 2026-11-01-post-session-actions,
// design decision 2): one implementation of the send flow used by both the
// history detail controller and the live session controller, so the two can
// never drift — load the record by session id via the repository, build the
// Markdown payload with `transcriptToMarkdown`, call the agent client with
// the selected agent (a one-shot conversation; the client always sends
// store=false), and persist the reply with `saveAgentReply`. API failures
// leave the Mistral layer as sanitized [MistralApiException]s, which the
// controllers map to their error state.

import '../app/transcript_export.dart';
import '../mistral/mistral.dart';
import '../storage/storage.dart';

/// Sends the transcript of session [sessionId] to the agent [agentId] and
/// persists the reply with the session (agent-integration spec). Returns the
/// agent's reply.
///
/// Throws a [MistralApiException] with a sanitized message when the record is
/// gone or the transcript is empty; API failures propagate from the client as
/// sanitized [MistralApiException]s.
Future<AgentReply> sendSessionToAgent({
  required SessionRepository repository,
  required AgentClient client,
  required MistralConfig config,
  required String sessionId,
  required String agentId,
}) async {
  final record = await repository.loadSession(sessionId);
  if (record == null) {
    throw MistralApiException('This transcript is no longer available.');
  }
  if (record.segments.isEmpty) {
    throw MistralApiException('The transcript is empty.');
  }
  final payload = transcriptToMarkdown(
    record.session,
    record.segments,
    config,
  );
  final reply = await client.sendToAgent(
    agentId: agentId,
    transcript: payload,
  );
  await repository.saveAgentReply(
    record.session.id,
    reply: reply.text,
    atMs: DateTime.now().millisecondsSinceEpoch,
    totalTokens: reply.totalTokens ?? 0,
  );
  return reply;
}
