/// Registry of all available sub-agents.
///
/// The chat provider checks each incoming LLM response chunk for agent
/// triggers and dispatches to the appropriate agent.
library;

import 'agent.dart';

class AgentRegistry {
  final List<Agent> _agents = [];

  void register(Agent agent) => _agents.add(agent);
  void unregister(String name) => _agents.removeWhere((a) => a.name == name);

  List<Agent> get agents => List.unmodifiable(_agents);

  /// Find an agent that can handle the given trigger.
  Agent? findAgent(String trigger) {
    for (final a in _agents) {
      if (a.canHandle(trigger)) return a;
    }
    return null;
  }

  /// Build a system-prompt snippet listing available agents.
  String agentDescriptions() {
    if (_agents.isEmpty) return '';
    final buf = StringBuffer('You have the following capabilities:\n');
    for (final a in _agents) {
      buf.writeln('- ${a.name}: ${a.description}');
    }
    return buf.toString();
  }
}
