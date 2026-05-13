/// Image registry — assigns unique IDs to every image in the conversation.
/// Allows BUD-E and the user to reference specific images by ID.
library;

import 'dart:math';

/// A registered image with a unique ID.
class RegisteredImage {
  final String id; // 10-char unique ID like "IMG_a7x3kp"
  final String filePath;
  final String source; // 'uploaded', 'generated', 'received'
  final DateTime timestamp;
  final String? prompt; // generation prompt if generated

  RegisteredImage({
    required this.id,
    required this.filePath,
    required this.source,
    DateTime? timestamp,
    this.prompt,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'source': source,
        'timestamp': timestamp.toIso8601String(),
        if (prompt != null) 'prompt': prompt,
      };
}

/// Manages a registry of all images in the current session.
class ImageRegistry {
  final List<RegisteredImage> _images = [];
  final _random = Random();
  final Set<String> _usedIds = {};

  List<RegisteredImage> get images => List.unmodifiable(_images);

  /// Generate a unique 10-char ID like "IMG_a7x3kp"
  String _generateId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    while (true) {
      final suffix = List.generate(6, (_) => chars[_random.nextInt(chars.length)]).join();
      final id = 'IMG_$suffix';
      if (_usedIds.add(id)) return id;
    }
  }

  /// Register an image and return its unique ID.
  String register(String filePath, {String source = 'uploaded', String? prompt}) {
    // Check if already registered
    final existing = _images.where((img) => img.filePath == filePath).firstOrNull;
    if (existing != null) return existing.id;

    final id = _generateId();
    _images.add(RegisteredImage(
      id: id,
      filePath: filePath,
      source: source,
      prompt: prompt,
    ));
    return id;
  }

  /// Find an image by its ID.
  RegisteredImage? findById(String id) {
    final normalized = id.toUpperCase().startsWith('IMG_') ? id : 'IMG_$id';
    return _images.where((img) =>
        img.id.toLowerCase() == normalized.toLowerCase()).firstOrNull;
  }

  /// Get the most recent N images.
  List<RegisteredImage> recent({int count = 5}) {
    final sorted = List.of(_images)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(count).toList();
  }

  /// Build a summary of all images for the system prompt context.
  String buildContextSummary() {
    if (_images.isEmpty) return '';
    final buf = StringBuffer('=== Bilder in dieser Konversation ===\n');
    for (final img in _images) {
      buf.write('${img.id}: ${img.source}');
      if (img.prompt != null) buf.write(' ("${img.prompt}")');
      buf.writeln();
    }
    return buf.toString();
  }

  void clear() {
    _images.clear();
    _usedIds.clear();
  }
}
