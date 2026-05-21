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
  int _lastMessageCount = 0;
  bool _wasLoading = false;
  bool _userScrolledUp = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final wasUp = _userScrolledUp;
    _userScrolledUp = pos.pixels < pos.maxScrollExtent - 150;
    if (wasUp != _userScrolledUp) setState(() {});
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (animate) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
        _userScrolledUp = false;
      }
    });
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
    final chat = context.watch<ChatProvider>();
    final colors = Theme.of(context).colorScheme;
    final greeting = chat.storage.personaName;

    // Auto-scroll: only on new messages or when streaming finishes
    // Default OFF to prevent UI jitter. User can enable in settings.
    final autoScroll = chat.storage.getSetting('autoScrollEnabled') as bool? ?? false;
    if (chat.messages.length != _lastMessageCount) {
      final isNew = chat.messages.length > _lastMessageCount;
      _lastMessageCount = chat.messages.length;
      if (isNew && !_userScrolledUp) {
        _scrollToBottom(animate: false);
      }
    }
    // Scroll once when streaming finishes (not during)
    if (_wasLoading && !chat.isLoading && autoScroll && !_userScrolledUp) {
      _scrollToBottom();
    }
    _wasLoading = chat.isLoading;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.history),
          tooltip: 'Conversation history',
          onPressed: _showConversationHistory,
        ),
        title: Text(greeting),
        actions: [
          // Wake word toggle
          if (chat.wakeWordService.isReady)
            IconButton(
              icon: Icon(
                chat.isWakeWordListening ? Icons.hearing : Icons.hearing_disabled,
                color: chat.isWakeWordListening ? colors.primary : colors.outline,
              ),
              tooltip: chat.isWakeWordListening ? 'Hey Buddy aus' : 'Hey Buddy an',
              onPressed: () => chat.toggleWakeWord(),
            ),
          // TTS on/off + stop if playing
          IconButton(
            icon: Icon(
              chat.ttsServiceForReplay.isPlaying
                  ? Icons.stop_circle_rounded
                  : chat.ttsEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
              color: chat.ttsServiceForReplay.isPlaying
                  ? colors.error
                  : chat.ttsEnabled ? colors.primary : colors.outline,
            ),
            tooltip: chat.ttsServiceForReplay.isPlaying
                ? 'TTS stoppen'
                : chat.ttsEnabled ? 'TTS aus' : 'TTS an',
            onPressed: () {
              if (chat.ttsServiceForReplay.isPlaying) {
                chat.stopTts();
              } else {
                chat.setTtsEnabled(!chat.ttsEnabled);
              }
            },
          ),
          // New chat
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New chat',
            onPressed: () => chat.clearConversation(),
          ),
          // More menu
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
                  _copyFullConversation(chat);
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
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                chat.messages.isEmpty
                    ? _buildWelcome(context, colors, greeting)
                    : _buildMessageList(context, chat, colors),
                // Scroll-to-bottom button when scrolled up
                if (_userScrolledUp && chat.messages.isNotEmpty)
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
          if (chat.isLoading)
            LinearProgressIndicator(
              backgroundColor: colors.surfaceContainerHighest,
              color: colors.primary,
              minHeight: 2,
            ),
          const ChatInput(),
        ],
      ),
    );
  }

  Widget _buildMessageList(BuildContext context, ChatProvider chat, ColorScheme colors) {
    // Find agent tasks that are NOT attached to any visible message
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

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      itemCount: totalItems,
      itemBuilder: (_, i) {
        // Regular messages
        if (i < chat.messages.length) {
          final msg = chat.messages[i];
          final taskId = msg.metadata['agentTaskId'] as String?;
          final task = taskId != null ? chat.agentTasks[taskId] : null;
          final branchInfo = chat.getBranchInfo(msg.id);
          return MessageBubble(
            message: msg,
            ttsService: chat.ttsServiceForReplay,
            universalApiKey: chat.universalApiKey,
            agentTask: task,
            branchInfo: branchInfo,
            onSwitchBranch: branchInfo != null
                ? (delta) => chat.switchBranch(msg.id, delta) : null,
            onRegenerate: msg.role == MessageRole.assistant
                ? () => chat.regenerateMessage(i) : null,
            onEdit: (_) {
              chat.storage.saveConversation(chat.conversation).catchError((_) {});
              (context as Element).markNeedsBuild();
            },
          );
        }

        // Floating agent tasks (not attached to any message)
        final agentEntry = floatingAgents[i - chat.messages.length];
        return AgentTaskWidget(
          task: agentEntry.value,
          onStop: () => chat.stopAgent(agentEntry.key),
        );
      },
    );
  }

  Widget _buildWelcome(BuildContext context, ColorScheme colors, String name) {
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
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              S.welcomeSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                  _SuggestionChip(suggestion, context),
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
