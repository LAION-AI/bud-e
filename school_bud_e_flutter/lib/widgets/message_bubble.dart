import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../models/agent_task.dart';
import '../providers/chat_provider.dart';
import '../services/tts_service.dart';
import 'agent_task_widget.dart';
import 'file_chip.dart';

final _toolBlockPattern = RegExp(r'\[\[.*?\]\]', dotAll: true);
final _codeBlockPattern = RegExp(r'```(\w*)\n([\s\S]*?)```');

enum _SegmentType { text, toolBlock, codeBlock }

List<_ContentSegment> _parseContent(String content) {
  final segments = <_ContentSegment>[];

  // First pass: extract code blocks
  final parts = <({int start, int end, _SegmentType type, String text, String? lang})>[];

  for (final m in _codeBlockPattern.allMatches(content)) {
    parts.add((start: m.start, end: m.end, type: _SegmentType.codeBlock,
        text: m.group(2) ?? '', lang: m.group(1)));
  }
  for (final m in _toolBlockPattern.allMatches(content)) {
    final overlaps = parts.any((p) => m.start >= p.start && m.start < p.end);
    if (!overlaps) {
      parts.add((start: m.start, end: m.end, type: _SegmentType.toolBlock,
          text: m.group(0)!, lang: null));
    }
  }
  parts.sort((a, b) => a.start.compareTo(b.start));

  var lastEnd = 0;
  for (final part in parts) {
    if (part.start > lastEnd) {
      final text = content.substring(lastEnd, part.start).trim();
      if (text.isNotEmpty) segments.add(_ContentSegment(text, _SegmentType.text));
    }
    segments.add(_ContentSegment(part.text, part.type, lang: part.lang));
    lastEnd = part.end;
  }
  if (lastEnd < content.length) {
    final text = content.substring(lastEnd).trim();
    if (text.isNotEmpty) segments.add(_ContentSegment(text, _SegmentType.text));
  }
  if (segments.isEmpty && content.isNotEmpty) {
    segments.add(_ContentSegment(content, _SegmentType.text));
  }
  return segments;
}

class _ContentSegment {
  final String text;
  final _SegmentType type;
  final String? lang;
  _ContentSegment(this.text, this.type, {this.lang});
  bool get isToolBlock => type == _SegmentType.toolBlock;
  bool get isCodeBlock => type == _SegmentType.codeBlock;
}

class MessageBubble extends StatelessWidget {
  final Message message;
  final ValueChanged<String>? onEdit;
  final TtsService? ttsService;
  final String? universalApiKey;
  final AgentTask? agentTask;
  final ({int index, int total})? branchInfo;
  final void Function(int delta)? onSwitchBranch;
  final VoidCallback? onRegenerate;

  const MessageBubble({
    super.key,
    required this.message,
    this.onEdit,
    this.ttsService,
    this.universalApiKey,
    this.agentTask,
    this.branchInfo,
    this.onSwitchBranch,
    this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    if (message.content.contains('[[tool_result')) {
      return _ToolResultBubble(content: message.content);
    }

    final isUser = message.role == MessageRole.user;
    final colors = Theme.of(context).colorScheme;
    final segments = _parseContent(message.content);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 48 : 12,
          right: isUser ? 12 : 48,
          top: 3,
          bottom: 3,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Message bubble
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: isUser
                    ? colors.primary
                    : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Inline generated image
                  if (message.metadata['inlineImageB64'] != null)
                    _InlineImage(
                      b64: message.metadata['inlineImageB64'] as String,
                      filePath: message.attachedFiles.isNotEmpty
                          ? message.attachedFiles.first : null,
                    ),
                  // Inline audio player for audio files
                  for (final af in message.attachedFiles)
                    if (_isAudioFile(af))
                      _InlineAudioPlayer(filePath: af),
                  // Document file chips (clickable)
                  if (message.attachedFiles.any((f) => _isDocFile(f)))
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 4),
                      child: Wrap(
                        spacing: 6, runSpacing: 4,
                        children: [
                          for (final af in message.attachedFiles)
                            if (_isDocFile(af)) FileChip(filePath: af),
                        ],
                      ),
                    ),
                  for (final seg in segments)
                    if (seg.isToolBlock)
                      _CollapsibleToolBlock(
                        content: seg.text,
                        textColor: isUser ? colors.onPrimary : colors.outline,
                      )
                    else if (seg.isCodeBlock)
                      _CodeBlock(code: seg.text, language: seg.lang ?? '')
                    else
                      _RichTextWithFiles(
                        text: seg.text,
                        textColor: isUser ? colors.onPrimary : colors.onSurface,
                      ),
                ],
              ),
            ),
            // Agent task status (if this message triggered an agent)
            if (agentTask != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: AgentTaskWidget(
                  task: agentTask!,
                  onStop: () => context.read<ChatProvider>().stopAgent(agentTask!.id),
                ),
              ),
            // Actions row: timestamp + copy + edit
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 2, right: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.outline.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _SmallAction(
                    icon: Icons.copy,
                    tooltip: 'Kopieren',
                    color: colors.outline.withValues(alpha: 0.4),
                    onTap: () {
                      // Copy clean text (without tool blocks)
                      final clean = message.content
                          .replaceAll(_toolBlockPattern, '')
                          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
                          .trim();
                      Clipboard.setData(ClipboardData(text: clean));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Kopiert'),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    },
                  ),
                  _SmallAction(
                    icon: Icons.edit,
                    tooltip: 'Bearbeiten',
                    color: colors.outline.withValues(alpha: 0.4),
                    onTap: () => _showEditDialog(context),
                  ),
                  // TTS play/stop toggle
                  if (!isUser && ttsService != null && universalApiKey != null)
                    _TtsToggle(
                      ttsService: ttsService!,
                      text: message.content
                          .replaceAll(_toolBlockPattern, '')
                          .trim(),
                      universalApiKey: universalApiKey!,
                      color: colors.outline.withValues(alpha: 0.4),
                    ),
                  // Regenerate button (assistant only)
                  if (!isUser && onRegenerate != null)
                    _SmallAction(
                      icon: Icons.refresh,
                      tooltip: 'Neu generieren',
                      color: colors.outline.withValues(alpha: 0.4),
                      onTap: onRegenerate!,
                    ),
                  // Branch navigation
                  if (branchInfo != null) ...[
                    const SizedBox(width: 4),
                    _SmallAction(
                      icon: Icons.chevron_left,
                      tooltip: 'Vorheriger Branch',
                      color: branchInfo!.index > 0
                          ? colors.primary : colors.outline.withValues(alpha: 0.2),
                      onTap: branchInfo!.index > 0
                          ? () => onSwitchBranch?.call(-1) : () {},
                    ),
                    Text(
                      '${branchInfo!.index + 1}/${branchInfo!.total}',
                      style: TextStyle(fontSize: 10, color: colors.outline),
                    ),
                    _SmallAction(
                      icon: Icons.chevron_right,
                      tooltip: 'Nächster Branch',
                      color: branchInfo!.index < branchInfo!.total - 1
                          ? colors.primary : colors.outline.withValues(alpha: 0.2),
                      onTap: branchInfo!.index < branchInfo!.total - 1
                          ? () => onSwitchBranch?.call(1) : () {},
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          message.role == MessageRole.user ? 'Nachricht bearbeiten' : 'Antwort bearbeiten',
        ),
        content: TextField(
          controller: controller,
          maxLines: 10,
          minLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              message.content = controller.text;
              onEdit?.call(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// ---- Small action button under the bubble ----
class _SmallAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _SmallAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 13, color: color),
        ),
      ),
    );
  }
}

// ---- TTS play/stop toggle ----
class _TtsToggle extends StatefulWidget {
  final TtsService ttsService;
  final String text;
  final String universalApiKey;
  final Color color;

  const _TtsToggle({
    required this.ttsService,
    required this.text,
    required this.universalApiKey,
    required this.color,
  });

  @override
  State<_TtsToggle> createState() => _TtsToggleState();
}

class _TtsToggleState extends State<_TtsToggle> {
  bool _playing = false;

  void _toggle() async {
    if (_playing || widget.ttsService.isPlaying) {
      await widget.ttsService.stop();
      setState(() => _playing = false);
    } else {
      if (widget.text.isEmpty) return;
      setState(() => _playing = true);
      await widget.ttsService.speakAndPlay(widget.text, widget.universalApiKey);
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _playing || widget.ttsService.isPlaying;
    return Tooltip(
      message: isActive ? 'Stopp' : 'Vorlesen',
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            isActive ? Icons.stop_circle_outlined : Icons.volume_up,
            size: 13,
            color: isActive
                ? Theme.of(context).colorScheme.primary
                : widget.color,
          ),
        ),
      ),
    );
  }
}

// ---- Collapsible tool block ----
class _CollapsibleToolBlock extends StatefulWidget {
  final String content;
  final Color textColor;
  const _CollapsibleToolBlock({required this.content, required this.textColor});

  @override
  State<_CollapsibleToolBlock> createState() => _CollapsibleToolBlockState();
}

class _CollapsibleToolBlockState extends State<_CollapsibleToolBlock> {
  bool _expanded = false;

  String get _label {
    if (widget.content.contains('tool:memory_search')) return 'Memory Search';
    if (widget.content.contains('tool:wikipedia')) return 'Wikipedia';
    if (widget.content.contains('tool:memory_save')) return 'Memory Save';
    if (widget.content.contains('tool:run_agent')) return 'Agent Task';
    if (widget.content.contains('tool:generate_image')) return 'Bild generieren';
    if (widget.content.contains('tool_result')) return 'Tool Result';
    return 'Tool Call';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: colors.outline),
                  const SizedBox(width: 4),
                  Icon(Icons.build_circle_outlined, size: 14, color: colors.outline),
                  const SizedBox(width: 4),
                  Text(_label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.outline)),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 6),
                SelectableText(widget.content,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                        height: 1.4)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Tool result bubble (collapsed center bar) ----
class _ToolResultBubble extends StatefulWidget {
  final String content;
  const _ToolResultBubble({required this.content});

  @override
  State<_ToolResultBubble> createState() => _ToolResultBubbleState();
}

class _ToolResultBubbleState extends State<_ToolResultBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 40),
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.tertiaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search, size: 14, color: colors.outline),
                    const SizedBox(width: 4),
                    Text('Tool-Ergebnisse',
                        style: TextStyle(fontSize: 11, color: colors.outline)),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                        size: 14, color: colors.outline),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    widget.content
                        .replaceAll('[[tool_result]]', '')
                        .replaceAll('[[/tool_result]]', '')
                        .trim(),
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: colors.onSurfaceVariant,
                        height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline generated image with click-to-fullscreen and download.
class _InlineImage extends StatelessWidget {
  final String b64;
  final String? filePath;
  const _InlineImage({required this.b64, this.filePath});

  @override
  Widget build(BuildContext context) {
    final bytes = base64Decode(b64);
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image preview (click to fullscreen)
          GestureDetector(
            onTap: () => _showFullscreen(context, bytes),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 350, maxHeight: 350),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Action buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (filePath != null) ...[
                _SmallAction(
                  icon: Icons.download,
                  tooltip: 'Öffnen',
                  color: colors.primary,
                  onTap: () => OpenFilex.open(filePath!),
                ),
                const SizedBox(width: 4),
              ],
              _SmallAction(
                icon: Icons.fullscreen,
                tooltip: 'Vollbild',
                color: colors.outline.withValues(alpha: 0.6),
                onTap: () => _showFullscreen(context, bytes),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showFullscreen(BuildContext context, List<int> bytes) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.memory(Uint8List.fromList(bytes)),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            if (filePath != null)
              Positioned(
                bottom: 8,
                right: 8,
                child: FloatingActionButton.small(
                  onPressed: () => OpenFilex.open(filePath!),
                  child: const Icon(Icons.download),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

bool _isAudioFile(String path) {
  final ext = p.extension(path).toLowerCase();
  return {'.wav', '.mp3', '.ogg', '.m4a', '.flac', '.aac'}.contains(ext);
}

bool _isDocFile(String path) {
  final ext = p.extension(path).toLowerCase();
  return {'.docx', '.doc', '.pdf', '.pptx', '.ppt', '.html', '.htm',
      '.rtf', '.md', '.txt', '.csv', '.xlsx'}.contains(ext);
}

/// Inline audio player with play/pause, seek bar, and duration.
class _InlineAudioPlayer extends StatefulWidget {
  final String filePath;
  const _InlineAudioPlayer({required this.filePath});

  @override
  State<_InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<_InlineAudioPlayer> {
  final _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() { _playing = false; _position = Duration.zero; });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      if (_position == Duration.zero) {
        await _player.play(DeviceFileSource(widget.filePath));
      } else {
        await _player.resume();
      }
      setState(() => _playing = true);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = p.basename(widget.filePath);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.secondaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Play/Pause button
                GestureDetector(
                  onTap: _toggle,
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary,
                    ),
                    child: Icon(
                      _playing ? Icons.pause : Icons.play_arrow,
                      color: colors.onPrimary, size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Seek bar + time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: colors.primary,
                          inactiveTrackColor: colors.outlineVariant,
                          thumbColor: colors.primary,
                        ),
                        child: Slider(
                          min: 0,
                          max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                          value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble().clamp(1, double.infinity)),
                          onChanged: (v) {
                            _player.seek(Duration(milliseconds: v.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(_position),
                                style: TextStyle(fontSize: 10, color: colors.outline)),
                            Text(_fmt(_duration),
                                style: TextStyle(fontSize: 10, color: colors.outline)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Download/open button
                IconButton(
                  icon: Icon(Icons.download, size: 18, color: colors.outline),
                  onPressed: () => OpenFilex.open(widget.filePath),
                  tooltip: 'Öffnen',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                ),
              ],
            ),
            // File name
            Padding(
              padding: const EdgeInsets.only(left: 44),
              child: Text(name,
                  style: TextStyle(fontSize: 10, color: colors.outline),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders text with clickable URLs and file paths.
class _RichTextWithFiles extends StatelessWidget {
  final String text;
  final Color textColor;
  const _RichTextWithFiles({required this.text, required this.textColor});

  // Match Windows absolute paths like C:\Users\...\file.ext
  static final _pathRegex = RegExp(
    r'[A-Z]:[/\\](?:[^\s\n"<>|*?]|[ ](?=[^\s]))+\.\w{1,5}',
    caseSensitive: false,
  );

  // Match URLs (http/https) — stops at whitespace, quotes, parentheses (unless part of URL)
  static final _urlRegex = RegExp(
    r'https?://[^\s<>")\]]+',
    caseSensitive: false,
  );

  // Match markdown links: [text](url)
  static final _mdLinkRegex = RegExp(
    r'\[([^\]]+)\]\((https?://[^\s)]+)\)',
  );

  // Match image IDs like IMG_a7x3kp
  static final _imgIdRegex = RegExp(r'\bIMG_[a-z0-9]{4,8}\b');

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final baseStyle = TextStyle(color: textColor, fontSize: 14.5, height: 1.45);

    // Collect all matches (paths, URLs, markdown links) and sort by position
    final matches = <({int start, int end, String type, String value, String? label})>[];

    for (final m in _mdLinkRegex.allMatches(text)) {
      matches.add((start: m.start, end: m.end, type: 'mdlink', value: m.group(2)!, label: m.group(1)));
    }
    // Only add raw URLs that aren't inside a markdown link
    for (final m in _urlRegex.allMatches(text)) {
      final overlaps = matches.any((e) => m.start >= e.start && m.start < e.end);
      if (!overlaps) {
        matches.add((start: m.start, end: m.end, type: 'url', value: m.group(0)!, label: null));
      }
    }
    for (final m in _pathRegex.allMatches(text)) {
      final overlaps = matches.any((e) => m.start >= e.start && m.start < e.end);
      if (!overlaps) {
        matches.add((start: m.start, end: m.end, type: 'path', value: m.group(0)!, label: null));
      }
    }
    for (final m in _imgIdRegex.allMatches(text)) {
      final overlaps = matches.any((e) => m.start >= e.start && m.start < e.end);
      if (!overlaps) {
        matches.add((start: m.start, end: m.end, type: 'img', value: m.group(0)!, label: null));
      }
    }

    if (matches.isEmpty) {
      return SelectableText.rich(_buildMarkdownSpans(text, baseStyle));
    }

    matches.sort((a, b) => a.start.compareTo(b.start));

    // Build rich text with clickable spans
    final spans = <InlineSpan>[];
    var lastEnd = 0;

    for (final match in matches) {
      // Text before this match (with markdown formatting)
      if (match.start > lastEnd) {
        spans.addAll(_buildMarkdownSpans(text.substring(lastEnd, match.start), baseStyle).children ?? [TextSpan(text: text.substring(lastEnd, match.start))]);
      }

      if (match.type == 'img') {
        // Resolve IMG_xxx to inline image
        final chat = context.read<ChatProvider>();
        final img = chat.imageRegistry.findById(match.value);
        if (img != null && File(img.filePath).existsSync()) {
          spans.add(WidgetSpan(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400, maxHeight: 400),
                  child: Image.file(File(img.filePath), fit: BoxFit.contain),
                ),
              ),
            ),
          ));
        } else {
          spans.add(TextSpan(
            text: match.value,
            style: TextStyle(color: colors.primary, fontFamily: 'monospace', fontSize: 12),
          ));
        }
      } else if (match.type == 'path') {
        final path = match.value.replaceAll('"', '').replaceAll("'", '');
        if (File(path).existsSync()) {
          // Inline file chip as WidgetSpan
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: FileChip(filePath: path),
            ),
          ));
        } else {
          spans.add(TextSpan(
            text: path,
            style: TextStyle(fontFamily: 'monospace', decoration: TextDecoration.underline),
          ));
        }
      } else {
        // URL or markdown link — clickable
        final url = match.value;
        final displayText = match.label ?? url;
        spans.add(TextSpan(
          text: displayText,
          style: TextStyle(
            color: colors.primary,
            decoration: TextDecoration.underline,
            decorationColor: colors.primary.withValues(alpha: 0.5),
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        ));
      }

      lastEnd = match.end;
    }

    // Text after last match (with markdown formatting)
    if (lastEnd < text.length) {
      spans.addAll(_buildMarkdownSpans(text.substring(lastEnd), baseStyle).children ?? [TextSpan(text: text.substring(lastEnd))]);
    }

    return SelectableText.rich(
      TextSpan(style: baseStyle, children: spans),
    );
  }

  /// Parse **bold** and *italic* markdown into styled TextSpans.
  static TextSpan _buildMarkdownSpans(String text, TextStyle baseStyle) {
    final children = <InlineSpan>[];
    // Match **bold** and *italic* patterns
    final mdRegex = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');
    var lastEnd = 0;

    for (final m in mdRegex.allMatches(text)) {
      if (m.start > lastEnd) {
        children.add(TextSpan(text: text.substring(lastEnd, m.start)));
      }
      if (m.group(1) != null) {
        // **bold**
        children.add(TextSpan(
          text: m.group(1),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (m.group(2) != null) {
        // *italic*
        children.add(TextSpan(
          text: m.group(2),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      }
      lastEnd = m.end;
    }
    if (lastEnd < text.length) {
      children.add(TextSpan(text: text.substring(lastEnd)));
    }
    if (children.isEmpty) {
      children.add(TextSpan(text: text));
    }
    return TextSpan(style: baseStyle, children: children);
  }
}

/// Styled code block with syntax label, copy button, and edit support.
class _CodeBlock extends StatefulWidget {
  final String code;
  final String language;
  const _CodeBlock({required this.code, required this.language});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _editing = false;
  bool _running = false;
  String? _output;
  bool _needsInput = false;
  final List<String> _inputHistory = [];
  late TextEditingController _ctrl;
  final _inputCtrl = TextEditingController();

  bool get _isPython =>
      widget.language.toLowerCase() == 'python' ||
      widget.language.toLowerCase() == 'py';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.code);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _runCode({String? extraInput}) async {
    final chat = context.read<ChatProvider>();
    final code = _editing ? _ctrl.text : widget.code;
    setState(() { _running = true; _output = null; _needsInput = false; });

    final inputs = List<String>.from(_inputHistory);
    if (extraInput != null) inputs.add(extraInput);

    final result = await chat.runPythonFromUI(code, inputs: inputs);

    if (!mounted) return;
    setState(() {
      _running = false;
      _output = result;
      _needsInput = result.contains('Eingabe erforderlich') ||
          result.contains('Eingabe') && result.contains('EOFError');
      if (extraInput != null) _inputHistory.add(extraInput);
    });
  }

  void _submitInput() {
    final text = _inputCtrl.text;
    if (text.isEmpty) return;
    _inputCtrl.clear();
    _runCode(extraInput: text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lang = widget.language.isNotEmpty ? widget.language : 'code';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D3F),
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                Text(lang,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF8888AA),
                        fontFamily: 'monospace')),
                const Spacer(),
                if (_isPython && !_running) ...[
                  _MiniButton(
                    icon: Icons.play_arrow,
                    label: 'Run',
                    onTap: () {
                      _inputHistory.clear();
                      _runCode();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                _MiniButton(
                  icon: Icons.copy,
                  label: 'Copy',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _editing ? _ctrl.text : widget.code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: const Text('Code copied'),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating),
                    );
                  },
                ),
                const SizedBox(width: 8),
                _MiniButton(
                  icon: _editing ? Icons.check : Icons.edit,
                  label: _editing ? 'Done' : 'Edit',
                  onTap: () => setState(() => _editing = !_editing),
                ),
              ],
            ),
          ),
          // Code content
          Padding(
            padding: const EdgeInsets.all(12),
            child: _editing
                ? TextField(
                    controller: _ctrl,
                    maxLines: null,
                    style: const TextStyle(
                      fontSize: 13, fontFamily: 'monospace',
                      color: Color(0xFFCDD6F4), height: 1.5,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                : SelectableText(
                    widget.code,
                    style: const TextStyle(
                      fontSize: 13, fontFamily: 'monospace',
                      color: Color(0xFFCDD6F4), height: 1.5,
                    ),
                  ),
          ),
          // Output section
          if (_output != null || _running)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF3D3D5F))),
              ),
              padding: const EdgeInsets.all(12),
              child: _running
                  ? const Row(
                      children: [
                        SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2,
                                color: Color(0xFF8888AA))),
                        SizedBox(width: 8),
                        Text('Wird ausgefuehrt...',
                            style: TextStyle(fontSize: 12, color: Color(0xFF8888AA),
                                fontFamily: 'monospace')),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ausgabe:',
                            style: TextStyle(fontSize: 11, color: Color(0xFF8888AA),
                                fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        SelectableText(
                          _output!,
                          style: const TextStyle(
                            fontSize: 13, fontFamily: 'monospace',
                            color: Color(0xFFA6E3A1), height: 1.5,
                          ),
                        ),
                      ],
                    ),
            ),
          // Interactive input field
          if (_needsInput && !_running)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF3D3D5F))),
                color: Color(0xFF252540),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.keyboard, size: 16, color: Color(0xFF8888AA)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      style: const TextStyle(
                        fontSize: 13, fontFamily: 'monospace',
                        color: Color(0xFFCDD6F4),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Eingabe...',
                        hintStyle: TextStyle(color: Color(0xFF666688)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 6),
                      ),
                      onSubmitted: (_) => _submitInput(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _submitInput,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3498DB),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Senden',
                          style: TextStyle(fontSize: 12, color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MiniButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: const Color(0xFF8888AA)),
            const SizedBox(width: 3),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF8888AA))),
          ],
        ),
      ),
    );
  }
}
