/// Conversation model with tree branching support.
///
/// Messages form a tree: each message has a parent and can have multiple
/// children (branches). The displayed [messages] list is the "active path"
/// from root to the current leaf. Regenerating a response creates a new
/// sibling branch. Users can navigate between branches.
library;

import 'message.dart';

class Conversation {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;

  /// All messages in the conversation (every branch).
  final Map<String, Message> _allMessages = {};

  /// Parent → ordered list of child IDs.
  final Map<String, List<String>> _children = {};

  /// At each branch point, which child index is currently active.
  final Map<String, int> _activeChild = {};

  /// The currently displayed linear path (root → active leaf).
  /// Rebuilt whenever a branch is switched.
  List<Message> _activePath = [];

  Conversation({
    required this.id,
    this.title = 'New Chat',
    List<Message>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now() {
    // Import flat message list (backward compat + initial load)
    if (messages != null && messages.isNotEmpty) {
      _importLinearMessages(messages);
    }
  }

  /// The active path — what the UI displays.
  List<Message> get messages => _activePath;

  /// Add a message to the conversation tree.
  void addMessage(Message msg) {
    // Determine parent: last message in active path
    final parentId = _activePath.isNotEmpty ? _activePath.last.id : null;
    msg.parentId = parentId;

    _allMessages[msg.id] = msg;
    if (parentId != null) {
      _children.putIfAbsent(parentId, () => []);
      _children[parentId]!.add(msg.id);
      _activeChild[parentId] = _children[parentId]!.length - 1;
    }
    _activePath.add(msg);
  }

  /// Get branch info for a message: (currentIndex, totalSiblings).
  /// Returns null if the message has no siblings.
  ({int index, int total})? getBranchInfo(String msgId) {
    final msg = _allMessages[msgId];
    if (msg == null) return null;
    final parentId = msg.parentId;
    if (parentId == null) return null;
    final siblings = _children[parentId];
    if (siblings == null || siblings.length <= 1) return null;
    final idx = siblings.indexOf(msgId);
    if (idx < 0) return null;
    return (index: idx, total: siblings.length);
  }

  /// Switch to a sibling branch. [delta] is -1 (previous) or +1 (next).
  /// Returns true if the branch changed.
  bool switchBranch(String msgId, int delta) {
    final msg = _allMessages[msgId];
    if (msg == null) return false;
    final parentId = msg.parentId;
    if (parentId == null) return false;
    final siblings = _children[parentId];
    if (siblings == null || siblings.length <= 1) return false;

    final currentIdx = siblings.indexOf(msgId);
    final newIdx = (currentIdx + delta).clamp(0, siblings.length - 1);
    if (newIdx == currentIdx) return false;

    _activeChild[parentId] = newIdx;

    // Rebuild active path: keep everything up to and including parent,
    // then follow the new branch
    final parentPathIdx = _activePath.indexWhere((m) => m.id == parentId);
    if (parentPathIdx < 0) return false;

    _activePath = _activePath.sublist(0, parentPathIdx + 1);
    _walkBranch(siblings[newIdx]);
    return true;
  }

  /// Prepare for regeneration at [msgIndex] in the active path.
  /// Removes this message and everything after from the active path.
  /// Returns the parent message ID (for generating a new response).
  String? prepareRegenerate(int msgIndex) {
    if (msgIndex < 0 || msgIndex >= _activePath.length) return null;
    final msg = _activePath[msgIndex];
    final parentId = msg.parentId;

    // Truncate active path at this point
    _activePath = _activePath.sublist(0, msgIndex);
    return parentId;
  }

  /// Total number of messages across all branches.
  int get totalMessageCount => _allMessages.length;

  void autoTitle() {
    for (final m in _activePath) {
      if (m.role == MessageRole.user && m.content.trim().isNotEmpty) {
        final raw = m.content.trim();
        title = raw.length > 50 ? '${raw.substring(0, 47)}...' : raw;
        return;
      }
    }
  }

  /// Import a flat list of messages (no branching info).
  void _importLinearMessages(List<Message> msgs) {
    String? lastId;
    for (final msg in msgs) {
      _allMessages[msg.id] = msg;
      msg.parentId ??= lastId;
      if (lastId != null) {
        _children.putIfAbsent(lastId, () => []);
        if (!_children[lastId]!.contains(msg.id)) {
          _children[lastId]!.add(msg.id);
        }
        _activeChild[lastId] = _children[lastId]!.indexOf(msg.id);
      }
      lastId = msg.id;
    }
    _rebuildActivePath();
  }

  /// Walk from a message ID, following active children, appending to path.
  void _walkBranch(String msgId) {
    final msg = _allMessages[msgId];
    if (msg == null) return;
    _activePath.add(msg);

    final kids = _children[msgId];
    if (kids != null && kids.isNotEmpty) {
      final activeIdx = (_activeChild[msgId] ?? kids.length - 1)
          .clamp(0, kids.length - 1);
      _walkBranch(kids[activeIdx]);
    }
  }

  /// Rebuild the active path from root.
  void _rebuildActivePath() {
    _activePath = [];
    // Find root: a message with no parent
    final roots = _allMessages.values
        .where((m) => m.parentId == null || !_allMessages.containsKey(m.parentId))
        .toList();
    if (roots.isEmpty) return;

    // Sort by timestamp, pick the first
    roots.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _walkBranch(roots.first.id);
  }

  Map<String, dynamic> toJson() {
    // Serialize ALL messages (not just active path)
    final allMsgList = _allMessages.values.map((m) => m.toJson()).toList();

    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'messageCount': _activePath.length,
      'totalMessages': _allMessages.length,
      'messages': allMsgList,
      if (_activeChild.isNotEmpty) 'activeChild': _activeChild,
    };
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final msgs = (json['messages'] as List?)
            ?.map((m) => Message.fromJson(m as Map<String, dynamic>))
            .toList() ??
        [];

    final conv = Conversation(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'New Chat',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      messages: msgs,
    );

    // Restore active child indices
    final savedActive = json['activeChild'] as Map<String, dynamic>?;
    if (savedActive != null) {
      for (final e in savedActive.entries) {
        conv._activeChild[e.key] = e.value as int;
      }
      conv._rebuildActivePath();
    }

    return conv;
  }
}
