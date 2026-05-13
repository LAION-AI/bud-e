import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/debug_log.dart';
import '../providers/chat_provider.dart';
import '../config/api_config.dart';
import 'memory_explorer_screen.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear log',
            onPressed: () => DebugLog.instance.clear(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Live Log'),
            Tab(text: 'Context'),
            Tab(text: 'Memory'),
            Tab(text: 'Agents'),
            Tab(text: 'Config'),
            Tab(text: 'Ctx History'),
            Tab(text: 'Mem Updates'),
            Tab(text: 'Files'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _LiveLogTab(),
          _ContextTab(),
          _MemoryTab(),
          _AgentsTab(),
          _ConfigTab(),
          _ContextHistoryTab(),
          _MemoryUpdatesTab(),
          _FilesTab(),
        ],
      ),
    );
  }
}

// =============================================================================
// Tab 1: Live Log — all debug events in real-time
// =============================================================================
class _LiveLogTab extends StatefulWidget {
  const _LiveLogTab();

  @override
  State<_LiveLogTab> createState() => _LiveLogTabState();
}

class _LiveLogTabState extends State<_LiveLogTab> {
  DebugSource? _filter;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Source filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              FilterChip(
                label: const Text('All'),
                selected: _filter == null,
                onSelected: (_) => setState(() => _filter = null),
              ),
              const SizedBox(width: 4),
              for (final src in DebugSource.values)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: FilterChip(
                    label: Text(src.name),
                    selected: _filter == src,
                    onSelected: (_) => setState(
                        () => _filter = _filter == src ? null : src),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Log entries
        Expanded(
          child: ListenableBuilder(
            listenable: DebugLog.instance,
            builder: (_, __) {
              final entries = _filter == null
                  ? DebugLog.instance.entries
                  : DebugLog.instance.entriesFor(_filter!);

              if (entries.isEmpty) {
                return Center(
                  child: Text('No log entries',
                      style: TextStyle(color: colors.onSurfaceVariant)),
                );
              }

              // Auto-scroll to bottom
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients) {
                  _scrollController.jumpTo(
                      _scrollController.position.maxScrollExtent);
                }
              });

              return ListView.builder(
                controller: _scrollController,
                itemCount: entries.length,
                itemBuilder: (_, i) => _LogEntryTile(entry: entries[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final DebugEntry entry;
  const _LogEntryTile({required this.entry});

  Color _sourceColor(DebugSource src) {
    switch (src) {
      case DebugSource.contextConstructor:
        return Colors.blue;
      case DebugSource.mainAgent:
        return Colors.green;
      case DebugSource.asr:
        return Colors.orange;
      case DebugSource.tts:
        return Colors.purple;
      case DebugSource.updater:
        return Colors.teal;
      case DebugSource.memory:
        return Colors.indigo;
      case DebugSource.agentRegistry:
        return Colors.red;
      case DebugSource.system:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = entry.timestamp;
    final time =
        '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}:'
        '${ts.second.toString().padLeft(2, '0')}.'
        '${ts.millisecond.toString().padLeft(3, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(time,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(width: 6),
          // Source badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: _sourceColor(entry.source).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              entry.sourceLabel.toUpperCase(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _sourceColor(entry.source),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Message
          Expanded(
            child: Text(
              entry.message,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Tab 2: Context — what gets sent to the LLM
// =============================================================================
class _ContextTab extends StatelessWidget {
  const _ContextTab();

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final contextMsgs = chat.memory.contextWindow();
    final systemPrompt = chat.storage.systemPrompt;
    final colors = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // System prompt section
        _SectionHeader('System Prompt (${systemPrompt.length} chars)'),
        Container(
          padding: const EdgeInsets.all(8),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: SelectableText(
            systemPrompt,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),

        // Context window
        _SectionHeader('Context Window (${contextMsgs.length}/${chat.memory.maxContextMessages})'),
        if (contextMsgs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Empty — no messages yet',
                style: TextStyle(color: colors.onSurfaceVariant)),
          )
        else
          for (final msg in contextMsgs)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: msg.role.name == 'user'
                    ? colors.primaryContainer.withValues(alpha: 0.3)
                    : msg.role.name == 'system'
                        ? colors.tertiaryContainer.withValues(alpha: 0.3)
                        : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        msg.role.name.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${msg.content.length} chars',
                        style: TextStyle(
                            fontSize: 10, color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    msg.content.length > 500
                        ? '${msg.content.substring(0, 500)}...'
                        : msg.content,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

// =============================================================================
// Tab 3: Memory — all messages and summaries
// =============================================================================
class _MemoryTab extends StatelessWidget {
  const _MemoryTab();

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final allMsgs = chat.memory.allMessages;
    final summary = chat.memory.memorySummary;
    final colors = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SectionHeader('Memory Store'),
        _InfoRow('Total messages', '${allMsgs.length}'),
        _InfoRow('Context window size', '${chat.memory.maxContextMessages}'),
        _InfoRow('Messages in context', '${chat.memory.contextWindow().length}'),
        _InfoRow('Messages outside context',
            '${allMsgs.length - chat.memory.contextWindow().length}'),
        const SizedBox(height: 12),

        // Summary
        _SectionHeader('Memory Summary'),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            summary ?? '(no summaries yet — future feature)',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: summary != null
                  ? colors.onSurface
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // All messages
        _SectionHeader('All Messages (${allMsgs.length})'),
        for (var i = 0; i < allMsgs.length; i++)
          _MessageRow(index: i, message: allMsgs[i]),
      ],
    );
  }
}

class _MessageRow extends StatelessWidget {
  final int index;
  final dynamic message; // Message
  const _MessageRow({required this.index, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final inContext =
        context.read<ChatProvider>().memory.contextWindow().contains(message);

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: inContext
            ? colors.surfaceContainerHighest
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        border: inContext
            ? Border.all(color: colors.primary.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          Text('#$index',
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: colors.onSurfaceVariant)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: message.role.name == 'user'
                  ? Colors.blue.withValues(alpha: 0.15)
                  : Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              message.role.name,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message.content.length > 100
                  ? '${message.content.substring(0, 100)}...'
                  : message.content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (inContext)
            Icon(Icons.check_circle, size: 14, color: colors.primary),
        ],
      ),
    );
  }
}

// =============================================================================
// Tab 4: Agents — registered sub-agents
// =============================================================================
class _AgentsTab extends StatelessWidget {
  const _AgentsTab();

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final agents = chat.agents.agents;
    final colors = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SectionHeader('Agent Registry'),
        _InfoRow('Registered agents', '${agents.length}'),
        const SizedBox(height: 12),

        if (agents.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(Icons.extension_off, size: 48, color: colors.outline),
                const SizedBox(height: 8),
                Text('No agents registered yet',
                    style: TextStyle(color: colors.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(
                  'Agents can be registered to handle image generation, '
                  'web search, document analysis, and more.',
                  style: TextStyle(
                      fontSize: 12, color: colors.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          for (final agent in agents)
            Card(
              child: ListTile(
                leading: const Icon(Icons.extension),
                title: Text(agent.name),
                subtitle: Text(agent.description),
              ),
            ),

        const SizedBox(height: 24),

        // Agent system prompt injection preview
        _SectionHeader('Agent Prompt Injection'),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            chat.agents.agentDescriptions().isEmpty
                ? '(no agent descriptions to inject)'
                : chat.agents.agentDescriptions(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Tab 5: Config — API key, middleware URL, storage state
// =============================================================================
class _ConfigTab extends StatelessWidget {
  const _ConfigTab();

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final key = chat.universalApiKey;
    final parts = splitUniversalKey(key);
    final decodedUrl = decodeMiddlewareBase(key);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SectionHeader('API Configuration'),
        _InfoRow('API key (prefix)', '${parts.apiKey.substring(0, parts.apiKey.length.clamp(0, 12))}...'),
        _InfoRow('Key suffix', parts.suffix.isNotEmpty
            ? '${parts.suffix.substring(0, parts.suffix.length.clamp(0, 12))}...'
            : '(none)'),
        _InfoRow('Decoded middleware URL', decodedUrl ?? '(failed to decode)'),
        _InfoRow('Chat endpoint', middlewareUrl(key, '/v1/chat/completions') ?? 'N/A'),
        _InfoRow('ASR endpoint', middlewareUrl(key, '/v1/audio/transcriptions') ?? 'N/A'),
        _InfoRow('TTS endpoint', middlewareUrl(key, '/v1/audio/speech') ?? 'N/A'),

        const SizedBox(height: 16),
        _SectionHeader('Settings'),
        _InfoRow('TTS enabled', chat.ttsEnabled.toString()),
        _InfoRow('System prompt length', '${chat.storage.systemPrompt.length} chars'),

        const SizedBox(height: 16),
        _SectionHeader('Conversation'),
        _InfoRow('Conversation ID', chat.conversation.id),
        _InfoRow('Title', chat.conversation.title),
        _InfoRow('Messages', '${chat.messages.length}'),
        _InfoRow('Created', chat.conversation.createdAt.toIso8601String()),
        _InfoRow('Updated', chat.conversation.updatedAt.toIso8601String()),

        const SizedBox(height: 16),
        _SectionHeader('Runtime'),
        _InfoRow('Is loading', chat.isLoading.toString()),
        _InfoRow('Is recording', chat.isRecording.toString()),
        _InfoRow('Debug log entries', '${DebugLog.instance.entries.length}'),

        const SizedBox(height: 16),
        _SectionHeader('Data Storage'),
        _InfoRow('Root path', chat.storage.rootPath),
        _InfoRow('Persona name', chat.storage.personaName),
      ],
    );
  }
}

// =============================================================================
// Tab 6: Context History — see how context was built for each exchange
// =============================================================================
class _ContextHistoryTab extends StatelessWidget {
  const _ContextHistoryTab();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DebugLog.instance,
      builder: (_, __) {
        final snapshots = DebugLog.instance.contextSnapshots;
        if (snapshots.isEmpty) {
          return const Center(child: Text('Noch keine Kontextkonstruktionen aufgezeichnet.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: snapshots.length,
          itemBuilder: (_, i) {
            final s = snapshots[snapshots.length - 1 - i]; // newest first
            return _ContextSnapshotCard(snapshot: s, index: snapshots.length - i);
          },
        );
      },
    );
  }
}

class _ContextSnapshotCard extends StatefulWidget {
  final ContextSnapshot snapshot;
  final int index;
  const _ContextSnapshotCard({required this.snapshot, required this.index});

  @override
  State<_ContextSnapshotCard> createState() => _ContextSnapshotCardState();
}

class _ContextSnapshotCardState extends State<_ContextSnapshotCard> {
  bool _expanded = false;
  String? _expandedSection;

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final colors = Theme.of(context).colorScheme;
    final time = '${s.timestamp.hour.toString().padLeft(2, '0')}:'
        '${s.timestamp.minute.toString().padLeft(2, '0')}:'
        '${s.timestamp.second.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: colors.primary),
                  const SizedBox(width: 8),
                  Text('#${widget.index} $time',
                      style: TextStyle(fontWeight: FontWeight.bold,
                          fontSize: 13, color: colors.primary)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.userMessage.length > 50
                          ? '${s.userMessage.substring(0, 50)}...'
                          : s.userMessage,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${s.totalTokens} tok',
                        style: TextStyle(fontSize: 10,
                            color: colors.onPrimaryContainer, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow('Episodisch', '${s.episodicTokens} tokens'),
                  _InfoRow('Semantisch', '${s.semanticTokens} tokens'),
                  _InfoRow('Aktivierte Memories', '${s.activatedMemories.length}'),
                  if (s.activatedMemories.isNotEmpty)
                    for (final m in s.activatedMemories)
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text('• $m',
                            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                      ),
                  const SizedBox(height: 8),
                  // Expandable sections
                  _ExpandableSection(
                    title: 'System Prompt',
                    content: s.systemPrompt,
                    color: Colors.blue,
                    isExpanded: _expandedSection == 'system',
                    onToggle: () => setState(() =>
                        _expandedSection = _expandedSection == 'system' ? null : 'system'),
                  ),
                  _ExpandableSection(
                    title: 'Episodischer Kontext',
                    content: s.episodicContext.isEmpty ? '(leer)' : s.episodicContext,
                    color: Colors.green,
                    isExpanded: _expandedSection == 'episodic',
                    onToggle: () => setState(() =>
                        _expandedSection = _expandedSection == 'episodic' ? null : 'episodic'),
                  ),
                  _ExpandableSection(
                    title: 'Semantischer Kontext',
                    content: s.semanticContext.isEmpty ? '(leer)' : s.semanticContext,
                    color: Colors.orange,
                    isExpanded: _expandedSection == 'semantic',
                    onToggle: () => setState(() =>
                        _expandedSection = _expandedSection == 'semantic' ? null : 'semantic'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpandableSection extends StatelessWidget {
  final String title;
  final String content;
  final Color color;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _ExpandableSection({
    required this.title,
    required this.content,
    required this.color,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border(left: BorderSide(color: color, width: 3)),
            ),
            child: Row(
              children: [
                Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: color),
                const SizedBox(width: 4),
                Text(title,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                const Spacer(),
                Text('${content.length} chars',
                    style: TextStyle(fontSize: 10, color: colors.outline)),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              content,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colors.onSurface,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Tab 7: Memory Updates — see what the updater wrote
// =============================================================================
class _MemoryUpdatesTab extends StatelessWidget {
  const _MemoryUpdatesTab();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DebugLog.instance,
      builder: (_, __) {
        final updates = DebugLog.instance.memoryUpdates;
        if (updates.isEmpty) {
          return const Center(child: Text('Noch keine Memory-Updates aufgezeichnet.'));
        }
        final colors = Theme.of(context).colorScheme;
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: updates.length,
          itemBuilder: (_, i) {
            final u = updates[updates.length - 1 - i]; // newest first
            final time = '${u.timestamp.hour.toString().padLeft(2, '0')}:'
                '${u.timestamp.minute.toString().padLeft(2, '0')}:'
                '${u.timestamp.second.toString().padLeft(2, '0')}';
            final hasError = u.error != null;

            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              color: hasError ? colors.errorContainer.withValues(alpha: 0.3) : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          hasError ? Icons.error_outline : Icons.check_circle_outline,
                          size: 16,
                          color: hasError ? colors.error : colors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(time,
                            style: TextStyle(fontWeight: FontWeight.bold,
                                fontSize: 12, color: colors.primary)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${u.durationMs}ms',
                              style: TextStyle(fontSize: 10,
                                  color: colors.onSecondaryContainer)),
                        ),
                        const Spacer(),
                        if (u.conceptsCreated > 0)
                          _Badge('+${u.conceptsCreated} new', Colors.green),
                        if (u.conceptsUpdated > 0)
                          _Badge('${u.conceptsUpdated} upd', Colors.blue),
                      ],
                    ),
                    if (u.episodicSummary != null) ...[
                      const SizedBox(height: 6),
                      Text(u.episodicSummary!,
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic,
                              color: colors.onSurfaceVariant)),
                    ],
                    if (u.updatedFiles.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      for (final f in u.updatedFiles)
                        Text('  • $f',
                            style: TextStyle(fontFamily: 'monospace', fontSize: 10,
                                color: colors.outline)),
                    ],
                    if (hasError) ...[
                      const SizedBox(height: 4),
                      Text('Error: ${u.error}',
                          style: TextStyle(fontSize: 11, color: colors.error)),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

// =============================================================================
// Tab 8: Files — quick link to Memory Explorer
// =============================================================================
class _FilesTab extends StatelessWidget {
  const _FilesTab();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rootPath = context.read<ChatProvider>().storage.rootPath;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_special, size: 64, color: colors.primary),
            const SizedBox(height: 16),
            Text('Memory File Browser',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Browse semantic memory, episodic memory, working memory, '
              'conversations, settings, and personality files.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              rootPath,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colors.outline,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Open Memory Explorer'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MemoryExplorerScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Shared widgets
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
