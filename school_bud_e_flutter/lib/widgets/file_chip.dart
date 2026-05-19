/// Clickable file chip — opens, shares, or copies file path.
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class FileChip extends StatelessWidget {
  final String filePath;
  const FileChip({super.key, required this.filePath});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = p.basename(filePath);
    final ext = p.extension(filePath).toLowerCase();

    return Tooltip(
      message: filePath,
      child: InkWell(
        onTap: () => OpenFilex.open(filePath),
        onLongPress: () => _showFileMenu(context),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.secondaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconForExt(ext), size: 14, color: colors.primary),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.more_vert, size: 12, color: colors.outline),
            ],
          ),
        ),
      ),
    );
  }

  void _showFileMenu(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                p.basename(filePath),
                style: TextStyle(fontWeight: FontWeight.w600, color: colors.onSurface),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open'),
              subtitle: Text(filePath, style: const TextStyle(fontSize: 11)),
              onTap: () { Navigator.pop(ctx); OpenFilex.open(filePath); },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share via...'),
              subtitle: const Text('WhatsApp, Email, Drive, etc.'),
              onTap: () async {
                Navigator.pop(ctx);
                await Share.shareXFiles([XFile(filePath)]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy path'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: filePath));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Path copied'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 1)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Open folder'),
              onTap: () {
                Navigator.pop(ctx);
                OpenFilex.open(p.dirname(filePath));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  IconData _iconForExt(String ext) {
    return switch (ext) {
      '.pdf' => Icons.picture_as_pdf,
      '.doc' || '.docx' || '.rtf' || '.odt' => Icons.description,
      '.pptx' || '.ppt' => Icons.slideshow,
      '.md' => Icons.article,
      '.html' || '.htm' => Icons.language,
      '.json' => Icons.data_object,
      '.txt' || '.log' => Icons.text_snippet,
      '.csv' || '.xls' || '.xlsx' => Icons.table_chart,
      '.png' || '.jpg' || '.jpeg' || '.gif' || '.webp' => Icons.image,
      '.wav' || '.mp3' || '.ogg' || '.m4a' || '.flac' => Icons.audiotrack,
      _ => Icons.insert_drive_file,
    };
  }
}
