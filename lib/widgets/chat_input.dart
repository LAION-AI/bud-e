import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import '../providers/chat_provider.dart';

class ChatInput extends StatefulWidget {
  const ChatInput({super.key});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final List<String> _attachedFiles = [];
  bool _isDragOver = false;

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachedFiles.isEmpty) return;
    _controller.clear();
    final chat = context.read<ChatProvider>();
    if (_attachedFiles.isNotEmpty) {
      chat.sendMessageWithFiles(text, List.of(_attachedFiles));
      setState(() => _attachedFiles.clear());
    } else {
      chat.sendMessage(text);
    }
    _focusNode.requestFocus();
  }

  Future<void> _handleDroppedFiles(DropDoneDetails details) async {
    final chat = context.read<ChatProvider>();
    for (final xFile in details.files) {
      final path = xFile.path;
      final destPath = await chat.copyFileToWorkspace(path);
      if (destPath != null) {
        setState(() => _attachedFiles.add(destPath));
      }
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    final chat = context.read<ChatProvider>();
    for (final file in result.files) {
      if (file.path == null) continue;
      final destPath = await chat.copyFileToWorkspace(file.path!);
      if (destPath != null) {
        setState(() => _attachedFiles.add(destPath));
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final colors = Theme.of(context).colorScheme;

    // Check if ASR transcription arrived
    if (chat.lastTranscription != null) {
      final text = chat.lastTranscription!;
      chat.lastTranscription = null;
      if (chat.storage.asrAutoSend) {
        // Auto-send: include any attached files
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_attachedFiles.isNotEmpty) {
            chat.sendMessageWithFiles(text, List.of(_attachedFiles));
            setState(() => _attachedFiles.clear());
          } else {
            chat.sendMessage(text);
          }
        });
      } else {
        // Put in text field for review
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _controller.text = text;
          _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: text.length));
          _focusNode.requestFocus();
        });
      }
    }

    return SafeArea(
      child: DropTarget(
        onDragDone: _handleDroppedFiles,
        onDragEntered: (_) => setState(() => _isDragOver = true),
        onDragExited: (_) => setState(() => _isDragOver = false),
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: _isDragOver
              ? colors.primaryContainer.withValues(alpha: 0.3)
              : colors.surface,
          border: _isDragOver
              ? Border.all(color: colors.primary, width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Attached files preview
            if (_attachedFiles.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < _attachedFiles.length; i++)
                      Chip(
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(_iconForFile(_attachedFiles[i]),
                            size: 14, color: colors.primary),
                        label: Text(
                          p.basename(_attachedFiles[i]),
                          style: const TextStyle(fontSize: 11),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () =>
                            setState(() => _attachedFiles.removeAt(i)),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                // Mic button
                _MicButton(
                  isRecording: chat.isRecording,
                  isLoading: chat.isLoading,
                  onToggle: () {
                    if (chat.isRecording) {
                      chat.stopRecordingAndTranscribe();
                    } else {
                      chat.startRecording();
                    }
                  },
                ),
                const SizedBox(width: 4),
                // File attach button
                Tooltip(
                  message: 'Datei anhängen',
                  child: InkWell(
                    onTap: chat.isLoading ? null : _pickFiles,
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.surfaceContainerLow,
                      ),
                      child: Icon(Icons.attach_file,
                          size: 18, color: colors.onSurfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Text field
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !chat.isLoading,
                    textInputAction: TextInputAction.send,
                    maxLines: 4,
                    minLines: 1,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: chat.isRecording
                          ? 'Aufnahme... tippe zum Stoppen'
                          : _attachedFiles.isNotEmpty
                              ? 'Beschreibe was du mit den Dateien machen willst...'
                              : 'Nachricht eingeben...',
                      filled: true,
                      fillColor: chat.isRecording
                          ? colors.errorContainer.withValues(alpha: 0.3)
                          : colors.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Send button
                IconButton.filled(
                  onPressed: chat.isLoading ? chat.cancelStream : _send,
                  icon: Icon(
                    chat.isLoading ? Icons.stop : Icons.send,
                  ),
                  tooltip: chat.isLoading ? 'Stopp' : 'Senden',
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

IconData _iconForFile(String path) {
  final ext = p.extension(path).toLowerCase();
  return switch (ext) {
    '.pdf' => Icons.picture_as_pdf,
    '.md' => Icons.article,
    '.html' || '.htm' => Icons.language,
    '.json' => Icons.data_object,
    '.txt' => Icons.text_snippet,
    '.png' || '.jpg' || '.jpeg' || '.gif' || '.webp' => Icons.image,
    _ => Icons.insert_drive_file,
  };
}

class _MicButton extends StatelessWidget {
  final bool isRecording;
  final bool isLoading;
  final VoidCallback onToggle;

  const _MicButton({
    required this.isRecording,
    required this.isLoading,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Tooltip(
      message: isRecording ? 'Aufnahme stoppen' : 'Aufnahme starten',
      child: InkWell(
        onTap: isLoading ? null : onToggle,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isRecording ? colors.error : colors.secondaryContainer,
          ),
          child: Icon(
            isRecording ? Icons.stop : Icons.mic,
            color: isRecording ? colors.onError : colors.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
