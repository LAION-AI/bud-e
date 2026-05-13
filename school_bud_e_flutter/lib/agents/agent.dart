/// Base class for sub-agents.
///
/// Sub-agents handle specialised capabilities (image gen, web search,
/// document analysis, etc.). The core chat flow delegates to registered
/// agents when it detects a matching trigger in the LLM response.
library;

import '../models/message.dart';

/// Result returned by an agent after processing.
class AgentResult {
  final String text;
  final Map<String, dynamic>? data;

  const AgentResult({required this.text, this.data});
}

/// Interface every sub-agent must implement.
abstract class Agent {
  /// Human-readable name shown in the UI.
  String get name;

  /// Short description used in the system prompt so the LLM knows
  /// which agents are available.
  String get description;

  /// Returns `true` when this agent can handle the given [trigger].
  bool canHandle(String trigger);

  /// Process the trigger and return a result.
  Future<AgentResult> execute({
    required String trigger,
    required List<Message> conversationContext,
    required String universalApiKey,
  });
}
