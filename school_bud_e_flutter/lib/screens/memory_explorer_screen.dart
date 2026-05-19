import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/chat_provider.dart';
import '../widgets/file_chip.dart';

class MemoryExplorerScreen extends StatefulWidget {
  const MemoryExplorerScreen({super.key});

  @override
  State<MemoryExplorerScreen> createState() => _MemoryExplorerScreenState();
}

enum _SortMode { name, modified, created, size }

class _MemoryExplorerScreenState extends State<MemoryExplorerScreen> {
  String _currentRelPath = '';
  String? _selectedFile;
  String _fileContent = '';
  List<FileSystemEntity> _entries = [];
  List<FileSystemEntity> _allEntries = []; // unfiltered
  Map<String, FileStat> _statCache = {};
  bool _loading = true;
  _SortMode _sortMode = _SortMode.modified;
  bool _sortAscending = false; // descending by default for date
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDir(''));
  }

  Future<void> _loadDir(String relPath) async {
    setState(() => _loading = true);
    final storage = context.read<ChatProvider>().storage;
    final entries = await storage.listDirectory(relPath);
    // Cache stats for all files
    final stats = <String, FileStat>{};
    for (final e in entries) {
      stats[e.path] = await e.stat();
    }
    setState(() {
      _currentRelPath = relPath;
      _allEntries = entries;
      _statCache = stats;
      _selectedFile = null;
      _fileContent = '';
      _searchQuery = '';
      _searchController.clear();
      _loading = false;
    });
    _applySortAndFilter();
  }

  void _applySortAndFilter() {
    if (_searchQuery.isNotEmpty) {
      // Recursive search across subfolders
      _recursiveSearch();
      return;
    }

    var list = List<FileSystemEntity>.from(_allEntries);
    _sortEntries(list);
    setState(() => _entries = list);
  }

  Future<void> _recursiveSearch() async {
    final q = _searchQuery.toLowerCase();
    final rootPath = context.read<ChatProvider>().storage.rootPath;
    final basePath = _currentRelPath.isEmpty
        ? rootPath
        : p.join(rootPath, _currentRelPath);
    final dir = Directory(basePath);
    if (!await dir.exists()) {
      setState(() => _entries = []);
      return;
    }

    final results = <FileSystemEntity>[];
    await for (final entity in dir.list(recursive: true)) {
      if (p.basename(entity.path).toLowerCase().contains(q)) {
        results.add(entity);
        // Cache stat for new entries
        if (!_statCache.containsKey(entity.path)) {
          _statCache[entity.path] = await entity.stat();
        }
      }
    }

    _sortEntries(results);
    if (_searchQuery.toLowerCase() == q) {
      setState(() => _entries = results);
    }
  }

  void _sortEntries(List<FileSystemEntity> list) {
    list.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;
      if (aIsDir && bIsDir) {
        return p.basename(a.path).compareTo(p.basename(b.path));
      }

      final aStat = _statCache[a.path];
      final bStat = _statCache[b.path];
      int cmp;
      switch (_sortMode) {
        case _SortMode.name:
          cmp = p.basename(a.path).toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase());
        case _SortMode.modified:
          cmp = (aStat?.modified ?? DateTime(0))
              .compareTo(bStat?.modified ?? DateTime(0));
        case _SortMode.created:
          cmp = (aStat?.changed ?? DateTime(0))
              .compareTo(bStat?.changed ?? DateTime(0));
        case _SortMode.size:
          cmp = (aStat?.size ?? 0).compareTo(bStat?.size ?? 0);
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  Future<void> _loadFile(String relPath) async {
    final storage = context.read<ChatProvider>().storage;
    final content = await storage.readFileContent(relPath);
    setState(() {
      _selectedFile = relPath;
      _fileContent = content;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _breadcrumbs {
    if (_currentRelPath.isEmpty) return ['SchoolBudE'];
    return ['SchoolBudE', ..._currentRelPath.split(RegExp(r'[/\\]'))];
  }

  void _navigateBreadcrumb(int index) {
    if (index == 0) {
      _loadDir('');
    } else {
      final parts = _currentRelPath.split(RegExp(r'[/\\]'));
      _loadDir(parts.sublist(0, index).join('/'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rootPath = context.read<ChatProvider>().storage.rootPath;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory Explorer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Open in file explorer',
            onPressed: () {
              final fullPath = _currentRelPath.isEmpty
                  ? rootPath
                  : p.join(rootPath, _currentRelPath);
              Process.run('explorer', [fullPath]);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _loadDir(_currentRelPath),
          ),
        ],
      ),
      body: Column(
        children: [
          // Breadcrumb bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Icon(Icons.folder_special, size: 16, color: colors.primary),
                  const SizedBox(width: 4),
                  for (var i = 0; i < _breadcrumbs.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(Icons.chevron_right,
                            size: 16, color: colors.outline),
                      ),
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => _navigateBreadcrumb(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Text(
                          _breadcrumbs[i],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: i == _breadcrumbs.length - 1
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: i == _breadcrumbs.length - 1
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Search & sort bar
          if (_selectedFile == null && !_loading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(bottom: BorderSide(color: colors.outlineVariant)),
              ),
              child: Row(
                children: [
                  // Search field
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Dateiname suchen...',
                          hintStyle: const TextStyle(fontSize: 13),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                    _applySortAndFilter();
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: colors.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        ),
                        onChanged: (v) {
                          _searchQuery = v;
                          _applySortAndFilter();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Sort dropdown
                  PopupMenuButton<_SortMode>(
                    tooltip: 'Sortierung',
                    icon: Icon(_sortModeIcon, size: 20, color: colors.onSurfaceVariant),
                    onSelected: (mode) {
                      if (mode == _sortMode) {
                        setState(() => _sortAscending = !_sortAscending);
                      } else {
                        setState(() {
                          _sortMode = mode;
                          _sortAscending = mode == _SortMode.name;
                        });
                      }
                      _applySortAndFilter();
                    },
                    itemBuilder: (_) => [
                      _sortMenuItem(_SortMode.name, Icons.sort_by_alpha, 'Name'),
                      _sortMenuItem(_SortMode.modified, Icons.edit_calendar, 'Änderungsdatum'),
                      _sortMenuItem(_SortMode.created, Icons.calendar_today, 'Erstellungsdatum'),
                      _sortMenuItem(_SortMode.size, Icons.storage, 'Dateigröße'),
                    ],
                  ),
                  // Ascending/descending toggle
                  IconButton(
                    icon: Icon(
                      _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 18,
                      color: colors.primary,
                    ),
                    tooltip: _sortAscending ? 'Aufsteigend' : 'Absteigend',
                    onPressed: () {
                      setState(() => _sortAscending = !_sortAscending);
                      _applySortAndFilter();
                    },
                  ),
                ],
              ),
            ),

          // Main content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _selectedFile != null
                    ? _buildFileView(colors)
                    : _buildDirectoryView(colors),
          ),
        ],
      ),
    );
  }

  IconData get _sortModeIcon => switch (_sortMode) {
    _SortMode.name => Icons.sort_by_alpha,
    _SortMode.modified => Icons.edit_calendar,
    _SortMode.created => Icons.calendar_today,
    _SortMode.size => Icons.storage,
  };

  PopupMenuItem<_SortMode> _sortMenuItem(_SortMode mode, IconData icon, String label) {
    final isActive = _sortMode == mode;
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Icon(icon, size: 18, color: isActive ? Theme.of(context).colorScheme.primary : null),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          )),
          if (isActive) ...[
            const Spacer(),
            Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 16, color: Theme.of(context).colorScheme.primary),
          ],
        ],
      ),
    );
  }

  Widget _buildDirectoryView(ColorScheme colors) {
    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_searchQuery.isNotEmpty ? Icons.search_off : Icons.folder_off,
                size: 48, color: colors.outline),
            const SizedBox(height: 8),
            Text(_searchQuery.isNotEmpty ? 'Keine Treffer' : 'Empty folder',
                style: TextStyle(color: colors.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _entries.length,
      itemBuilder: (_, i) {
        final entity = _entries[i];
        final name = p.basename(entity.path);
        final isDir = entity is Directory;
        final rootPath = context.read<ChatProvider>().storage.rootPath;
        final relPath = p.relative(entity.path, from: rootPath);

        // Show subfolder path when searching recursively
        final currentBase = _currentRelPath.isEmpty
            ? rootPath
            : p.join(rootPath, _currentRelPath);
        final relFromCurrent = p.relative(entity.path, from: currentBase);
        final inSubfolder = _searchQuery.isNotEmpty &&
            relFromCurrent.contains(Platform.pathSeparator);
        final subfolderHint = inSubfolder
            ? p.dirname(relFromCurrent).replaceAll('\\', '/')
            : null;

        return ListTile(
          leading: Icon(
            isDir ? Icons.folder : _iconForFile(name),
            color: isDir ? colors.primary : colors.onSurfaceVariant,
          ),
          title: Text(name, style: const TextStyle(fontSize: 14)),
          subtitle: isDir
              ? null
              : Builder(builder: (_) {
                  final stat = _statCache[entity.path];
                  if (stat == null) return const SizedBox();
                  final sizeDate = '${_formatSize(stat.size)} — ${_formatDate(stat.modified)}';
                  if (subfolderHint != null) {
                    return Text(
                      '$subfolderHint/ — $sizeDate',
                      style: TextStyle(fontSize: 11, color: colors.outline),
                    );
                  }
                  return Text(
                    sizeDate,
                    style: TextStyle(fontSize: 11, color: colors.outline),
                  );
                }),
          trailing: isDir
              ? Icon(Icons.chevron_right, color: colors.outline)
              : null,
          dense: true,
          onTap: () {
            if (isDir) {
              _loadDir(relPath);
            } else if (_isBinaryFile(name)) {
              // Binary files: open with system app
              OpenFilex.open(entity.path);
            } else {
              _loadFile(relPath);
            }
          },
          onLongPress: isDir ? null : () => _showFileActions(context, entity.path, name),
        );
      },
    );
  }

  Widget _buildFileView(ColorScheme colors) {
    final fileName = p.basename(_selectedFile!);
    return Column(
      children: [
        // File header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.3),
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              Icon(_iconForFile(fileName), size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(fileName,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: colors.onSurface)),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy content',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _fileContent));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 18),
                tooltip: 'Back to folder',
                onPressed: () => setState(() {
                  _selectedFile = null;
                  _fileContent = '';
                }),
              ),
            ],
          ),
        ),
        // File content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              _fileContent,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: colors.onSurface,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _isBinaryFile(String name) {
    final ext = p.extension(name).toLowerCase();
    return {'.pptx', '.ppt', '.docx', '.doc', '.pdf', '.xlsx', '.xls',
        '.png', '.jpg', '.jpeg', '.gif', '.webp', '.mp3', '.wav',
        '.ogg', '.m4a', '.zip', '.apk'}.contains(ext);
  }

  void _showFileActions(BuildContext ctx, String fullPath, String name) {
    final colors = Theme.of(ctx).colorScheme;
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(name, style: TextStyle(fontWeight: FontWeight.w600, color: colors.onSurface)),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open with system app'),
              onTap: () { Navigator.pop(c); OpenFilex.open(fullPath); },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy file path'),
              subtitle: Text(fullPath, style: const TextStyle(fontSize: 10)),
              onTap: () {
                Navigator.pop(c);
                Clipboard.setData(ClipboardData(text: fullPath));
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Path copied'), behavior: SnackBarBehavior.floating),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share via...'),
              subtitle: const Text('WhatsApp, Email, Drive, etc.'),
              onTap: () async {
                Navigator.pop(c);
                await Share.shareXFiles([XFile(fullPath)]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Open containing folder'),
              onTap: () { Navigator.pop(c); OpenFilex.open(p.dirname(fullPath)); },
            ),
            if (!_isBinaryFile(name))
              ListTile(
                leading: const Icon(Icons.visibility),
                title: const Text('View content'),
                onTap: () {
                  Navigator.pop(c);
                  final rootPath = context.read<ChatProvider>().storage.rootPath;
                  _loadFile(p.relative(fullPath, from: rootPath));
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  IconData _iconForFile(String name) {
    final ext = p.extension(name).toLowerCase();
    return switch (ext) {
      '.json' => Icons.data_object,
      '.txt' || '.log' => Icons.text_snippet,
      '.pdf' => Icons.picture_as_pdf,
      '.docx' || '.doc' => Icons.description,
      '.pptx' || '.ppt' => Icons.slideshow,
      '.html' || '.htm' => Icons.language,
      '.png' || '.jpg' || '.jpeg' || '.gif' || '.webp' => Icons.image,
      '.mp3' || '.wav' || '.ogg' || '.m4a' => Icons.audiotrack,
      '.md' => Icons.article,
      _ => Icons.insert_drive_file,
    };
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
