/// Client for the Mistral Agents/Conversations API: listing the workspace's
/// agents and sending a transcript to one of them as a one-shot conversation
/// (change 2026-10-29-send-transcript-to-agent, design decisions 2-3).
///
/// All Mistral API code lives behind this interface (the lib/mistral hard
/// constraint), so the layer stays mockable in tests — the live API is never
/// called from tests.
abstract interface class AgentClient {
  /// Lists the agents of the workspace the API key belongs to
  /// (`GET /v1/agents`).
  Future<List<AgentInfo>> listAgents();

  /// Sends [transcript] to the agent [agentId] as a one-shot conversation
  /// (`POST /v1/conversations`). Server-side conversation storage is always
  /// disabled by the implementation — see [AgentReply].
  Future<AgentReply> sendToAgent({
    required String agentId,
    required String transcript,
  });
}

/// One agent of the user's workspace (`GET /v1/agents`). An agent ID is a
/// workspace object reference, not a credential — unlike the API key it is
/// not secret and may be stored in plain preferences.
class AgentInfo {
  const AgentInfo({required this.id, required this.name, this.description});

  /// The agent id (`ag_…`), passed as `agent_id` when sending.
  final String id;

  /// The human-readable name shown in the agent picker.
  final String name;

  /// The agent's description, when set in Studio.
  final String? description;

  factory AgentInfo.fromJson(Map<String, dynamic> json) => AgentInfo(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentInfo &&
          id == other.id &&
          name == other.name &&
          description == other.description;

  @override
  int get hashCode => Object.hash(id, name, description);
}

/// The reply of an agent to a sent transcript (`POST /v1/conversations`
/// response: the assistant `message.output` entries plus token usage).
class AgentReply {
  const AgentReply({
    required this.text,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  /// The assistant's reply text (the `message.output` contents joined).
  final String text;

  /// Token usage reported by the API, when present.
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  factory AgentReply.fromJson(Map<String, dynamic> json) {
    final outputs = json['outputs'];
    final parts = <String>[
      if (outputs is List)
        for (final entry in outputs)
          if (entry is Map<String, dynamic> &&
              entry['type'] == 'message.output' &&
              entry['role'] == 'assistant')
            ..._contentParts(entry['content']),
    ];
    final usage = json['usage'];
    int? token(String key) {
      final value = usage is Map<String, dynamic> ? usage[key] : null;
      return value is num ? value.round() : null;
    }

    return AgentReply(
      text: parts.join('\n\n'),
      promptTokens: token('prompt_tokens'),
      completionTokens: token('completion_tokens'),
      totalTokens: token('total_tokens'),
    );
  }

  /// The text parts of one output entry's content: a plain string, or a list
  /// of content chunks (`{type: 'text', text: ...}`).
  static List<String> _contentParts(dynamic content) {
    if (content is String) {
      return content.isEmpty ? const [] : [content];
    }
    if (content is List) {
      return [
        for (final chunk in content)
          if (chunk is Map<String, dynamic> &&
              chunk['type'] == 'text' &&
              chunk['text'] is String)
            chunk['text'] as String,
      ];
    }
    return const [];
  }
}
