import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../models/agent_task.dart';
import '../providers/chat_provider.dart';
import '../utils/app_strings.dart';
import '../widgets/message_bubble.dart';
import '../widgets/agent_task_widget.dart';
import '../widgets/chat_input.dart';
import 'settings_screen.dart';
import 'debug_screen.dart';
import 'memory_explorer_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  bool _userScrolledUp = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
    _userScrolledUp = false;
    setState(() {});
  }

  void _copyFullConversation(ChatProvider chat) {
    if (chat.messages.isEmpty) return;
    final buf = StringBuffer();
    buf.writeln('=== BUD-E Konversation ===');
    buf.writeln('ID: ${chat.conversation.id}');
    buf.writeln('Titel: ${chat.conversation.title}');
    buf.writeln('Nachrichten: ${chat.messages.length}');
    buf.writeln('${'=' * 40}\n');

    for (final m in chat.messages) {
      final role = m.role.name.toUpperCase();
      final time = '${m.timestamp.hour.toString().padLeft(2, '0')}:'
          '${m.timestamp.minute.toString().padLeft(2, '0')}';
      buf.writeln('[$time] $role:');
      buf.writeln(m.content);
      if (m.attachedFiles.isNotEmpty) {
        buf.writeln('  Dateien: ${m.attachedFiles.join(', ')}');
      }
      final taskId = m.metadata['agentTaskId'] as String?;
      if (taskId != null) {
        final task = chat.agentTasks[taskId];
        if (task != null) {
          buf.writeln('  Agent: ${task.status.name}');
          for (final s in task.steps) buf.writeln('    - $s');
          for (final f in task.generatedFiles) buf.writeln('    File: $f');
        }
      }
      buf.writeln();
    }

    Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${chat.messages.length} Nachrichten kopiert'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _showConversationHistory() async {
    final chat = context.read<ChatProvider>();
    final convos = await chat.listConversations();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text('Conversations',
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New'),
                    onPressed: () {
                      chat.clearConversation();
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: convos.isEmpty
                  ? const Center(child: Text('No saved conversations'))
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: convos.length,
                      itemBuilder: (_, i) {
                        final c = convos[i];
                        return ListTile(
                          leading: const Icon(Icons.chat_bubble_outline),
                          title: Text(c['title'] ?? 'Untitled',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${c['messageCount'] ?? 0} messages',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(ctx).colorScheme.outline),
                          ),
                          dense: true,
                          onTap: () {
                            chat.loadConversation(c['id']);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Selector<ChatProvider, ({String name, bool wwReady, bool wwListening, bool ttsPlaying, bool ttsEnabled})>(
          selector: (_, p) => (
            name: p.storage.personaName,
            wwReady: p.wakeWordService.isReady,
            wwListening: p.isWakeWordListening,
            ttsPlaying: p.ttsServiceForReplay.isPlaying,
            ttsEnabled: p.ttsEnabled,
          ),
          builder: (ctx, s, _) => AppBar(
            leading: IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Conversation history',
              onPressed: _showConversationHistory,
            ),
            title: Text(s.name),
            actions: [
              if (s.wwReady)
                IconButton(
                  icon: Icon(
                    s.wwListening ? Icons.hearing : Icons.hearing_disabled,
                    color: s.wwListening ? colors.primary : colors.outline,
                  ),
                  tooltip: s.wwListening ? 'Hey Buddy aus' : 'Hey Buddy an',
                  onPressed: () => ctx.read<ChatProvider>().toggleWakeWord(),
                ),
              IconButton(
                icon: Icon(
                  s.ttsPlaying
                      ? Icons.stop_circle_rounded
                      : s.ttsEnabled
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                  color: s.ttsPlaying
                      ? colors.error
                      : s.ttsEnabled ? colors.primary : colors.outline,
                ),
                tooltip: s.ttsPlaying
                    ? 'TTS stoppen'
                    : s.ttsEnabled ? 'TTS aus' : 'TTS an',
                onPressed: () {
                  final chat = ctx.read<ChatProvider>();
                  if (s.ttsPlaying) {
                    chat.stopTts();
                  } else {
                    chat.setTtsEnabled(!s.ttsEnabled);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.add_comment_outlined),
                tooltip: 'New chat',
                onPressed: () => ctx.read<ChatProvider>().clearConversation(),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  switch (v) {
                    case 'settings':
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen()));
                    case 'debug':
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const DebugScreen()));
                    case 'memory':
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const MemoryExplorerScreen()));
                    case 'copy_all':
                      _copyFullConversation(ctx.read<ChatProvider>());
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'copy_all',
                      child: ListTile(leading: Icon(Icons.copy_all),
                          title: Text('Gesamte Konversation kopieren'), dense: true, contentPadding: EdgeInsets.zero)),
                  const PopupMenuItem(value: 'memory',
                      child: ListTile(leading: Icon(Icons.folder_special),
                          title: Text('Memory Explorer'), dense: true, contentPadding: EdgeInsets.zero)),
                  const PopupMenuItem(value: 'debug',
                      child: ListTile(leading: Icon(Icons.bug_report),
                          title: Text('Debug Log'), dense: true, contentPadding: EdgeInsets.zero)),
                  const PopupMenuItem(value: 'settings',
                      child: ListTile(leading: Icon(Icons.settings),
                          title: Text('Settings'), dense: true, contentPadding: EdgeInsets.zero)),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    // Only track user-initiated drags — ignore layout/content changes
                    if (n is ScrollUpdateNotification && n.dragDetails != null) {
                      final pos = _scrollController.position;
                      // In a reversed list, 0 = bottom, positive = scrolled up
                      final nowUp = pos.pixels > 150;
                      if (nowUp != _userScrolledUp) {
                        _userScrolledUp = nowUp;
                        setState(() {});
                      }
                    }
                    return false;
                  },
                  child: Consumer<ChatProvider>(
                    builder: (ctx, chat, _) {
                      if (chat.messages.isEmpty) {
                        return _buildWelcome(ctx, colors);
                      }
                      return _buildMessageList(ctx, chat);
                    },
                  ),
                ),
                if (_userScrolledUp)
                  Positioned(
                    bottom: 8,
                    right: 16,
                    child: FloatingActionButton.small(
                      onPressed: _scrollToBottom,
                      backgroundColor: colors.primaryContainer,
                      child: Icon(Icons.keyboard_arrow_down, color: colors.primary),
                    ),
                  ),
              ],
            ),
          ),
          Selector<ChatProvider, bool>(
            selector: (_, p) => p.isLoading,
            builder: (_, loading, __) => loading
                ? LinearProgressIndicator(
                    backgroundColor: colors.surfaceContainerHighest,
                    color: colors.primary,
                    minHeight: 2,
                  )
                : const SizedBox.shrink(),
          ),
          const ChatInput(),
        ],
      ),
    );
  }

  Widget _buildMessageList(BuildContext ctx, ChatProvider chat) {
    final attachedTaskIds = <String>{};
    for (final msg in chat.messages) {
      final tid = msg.metadata['agentTaskId'] as String?;
      if (tid != null) attachedTaskIds.add(tid);
    }
    final floatingAgents = chat.agentTasks.entries
        .where((e) => !attachedTaskIds.contains(e.key) &&
            (e.value.status == AgentTaskStatus.running ||
             e.value.status == AgentTaskStatus.pending))
        .toList();

    final totalItems = chat.messages.length + floatingAgents.length;

    // reversed list: index 0 = newest item (bottom of screen)
    // Floating agents come first (they're newest), then messages in reverse
    return ListView.builder(
      controller: _scrollController,
      reverse: true, // anchor at bottom — no auto-scroll needed
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      itemCount: totalItems,
      cacheExtent: 2000,
      itemBuilder: (_, i) {
        // First N items in reversed list = floating agents (shown at bottom)
        if (i < floatingAgents.length) {
          final agentEntry = floatingAgents[floatingAgents.length - 1 - i];
          return AgentTaskWidget(
            task: agentEntry.value,
            onStop: () => chat.stopAgent(agentEntry.key),
          );
        }

        // Messages in reverse order
        final msgIdx = chat.messages.length - 1 - (i - floatingAgents.length);
        if (msgIdx < 0 || msgIdx >= chat.messages.length) {
          return const SizedBox.shrink();
        }
        final msg = chat.messages[msgIdx];
        final taskId = msg.metadata['agentTaskId'] as String?;
        final task = taskId != null ? chat.agentTasks[taskId] : null;
        final branchInfo = chat.getBranchInfo(msg.id);
        return RepaintBoundary(
          key: ValueKey(msg.id),
          child: MessageBubble(
            message: msg,
            ttsService: chat.ttsServiceForReplay,
            universalApiKey: chat.universalApiKey,
            agentTask: task,
            branchInfo: branchInfo,
            onSwitchBranch: branchInfo != null
                ? (delta) => chat.switchBranch(msg.id, delta) : null,
            onRegenerate: msg.role == MessageRole.assistant
                ? () => chat.regenerateMessage(msgIdx) : null,
            onEdit: (_) {
              chat.storage.saveConversation(chat.conversation).catchError((_) {});
              setState(() {});
            },
          ),
        );
      },
    );
  }

  Widget _buildWelcome(BuildContext ctx, ColorScheme colors) {
    final name = ctx.read<ChatProvider>().storage.personaName;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [colors.primary, colors.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(Icons.emoji_emotions_rounded,
                  size: 50, color: colors.onPrimary),
            ),
            const SizedBox(height: 20),
            Text(
              S.welcomeTitle(name),
              style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              S.welcomeSubtitle,
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final suggestion in S.welcomeSuggestions)
                  _SuggestionChip(suggestion, ctx),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String text;
  final BuildContext ctx;
  const _SuggestionChip(this.text, this.ctx);

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 13)),
      avatar: const Icon(Icons.lightbulb_outline, size: 16),
      onPressed: () => ctx.read<ChatProvider>().sendMessage(text),
    );
  }
}
