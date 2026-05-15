/// Chat message model with multimodal support.
library;

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

enum MessageRole { system, user, assistant }

class Message {
  final String id;
  final MessageRole role;
  String content;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  /// File paths attached to this message (images, PDFs, etc.)
  final List<String> attachedFiles;

  Message({
    required this.id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
    List<String>? attachedFiles,
  })  : timestamp = timestamp ?? DateTime.now(),
        metadata = metadata ?? {},
        attachedFiles = attachedFiles ?? [];

  factory Message.user(String content, {String? id, List<String>? files}) =>
      Message(
        id: id ?? _uid(),
        role: MessageRole.user,
        content: content,
        attachedFiles: files,
      );

  factory Message.assistant(String content, {String? id, List<String>? files}) =>
      Message(
        id: id ?? _uid(),
        role: MessageRole.assistant,
        attachedFiles: files,
        content: content,
      );

  factory Message.system(String content, {String? id}) => Message(
        id: id ?? _uid(),
        role: MessageRole.system,
        content: content,
      );

  /// Serialise to the OpenAI chat-completions format.
  /// If files are attached, uses multimodal content array format.
  Map<String, dynamic> toApiMap() {
    if (attachedFiles.isEmpty) {
      return {'role': role.name, 'content': content};
    }

    // Multimodal: array of content parts
    final parts = <Map<String, dynamic>>[];

    // Text part first
    if (content.isNotEmpty) {
      parts.add({'type': 'text', 'text': content});
    }

    // File parts
    for (final filePath in attachedFiles) {
      try {
        final file = File(filePath);
        if (!file.existsSync()) continue;
        final bytes = file.readAsBytesSync();
        final b64 = base64Encode(bytes);
        final ext = p.extension(filePath).toLowerCase();

        if (_isImage(ext)) {
          final mime = _mimeForExt(ext);
          parts.add({
            'type': 'image_url',
            'image_url': {'url': 'data:$mime;base64,$b64'},
          });
        } else if (ext == '.pdf') {
          parts.add({
            'type': 'input_file',
            'data': b64,
            'mime_type': 'application/pdf',
          });
        }
        // Text files are already included in the content string
      } catch (_) {}
    }

    return {'role': role.name, 'content': parts};
  }

  /// Parent message ID for tree branching.
  String? get parentId => metadata['parentId'] as String?;
  set parentId(String? id) {
    if (id != null) { metadata['parentId'] = id; } else { metadata.remove('parentId'); }
  }

  /// Full JSON serialisation for persistence.
  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        if (metadata.isNotEmpty) 'metadata': metadata,
        if (attachedFiles.isNotEmpty) 'attachedFiles': attachedFiles,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String? ?? _uid(),
        role: MessageRole.values.byName(json['role'] as String),
        content: json['content'] as String,
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : null,
        metadata: json['metadata'] as Map<String, dynamic>?,
        attachedFiles: (json['attachedFiles'] as List?)
            ?.map((e) => e.toString())
            .toList(),
      );

  static String _uid() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  static bool _isImage(String ext) =>
      {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'}.contains(ext);

  static String _mimeForExt(String ext) => switch (ext) {
        '.png' => 'image/png',
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.gif' => 'image/gif',
        '.webp' => 'image/webp',
        '.bmp' => 'image/bmp',
        _ => 'application/octet-stream',
      };
}
