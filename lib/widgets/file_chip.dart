/// Clickable file chip — opens a file with the system default app.
library;

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

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
                constraints: const BoxConstraints(maxWidth: 250),
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
              const SizedBox(width: 2),
              Icon(Icons.open_in_new, size: 10, color: colors.outline),
            ],
          ),
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
