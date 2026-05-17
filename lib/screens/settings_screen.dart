import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../config/api_config.dart';
import '../models/agent_persona.dart';
import '../services/persona_io.dart';
import '../utils/app_strings.dart';
import 'skill_explorer_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _apiKeyController;
  late TextEditingController _systemPromptController;
  late TextEditingController _personaNameController;
  bool _obscureKey = true;
  String? _decodedUrl;

  @override
  void initState() {
    super.initState();
    final chat = context.read<ChatProvider>();
    _apiKeyController = TextEditingController(text: chat.universalApiKey);
    _systemPromptController =
        TextEditingController(text: chat.storage.systemPrompt);
    _personaNameController =
        TextEditingController(text: chat.storage.personaName);
    _updateDecodedUrl();
  }

  void _updateDecodedUrl() {
    setState(() {
      _decodedUrl = decodeMiddlewareBase(_apiKeyController.text);
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _systemPromptController.dispose();
    _personaNameController.dispose();
    super.dispose();
  }

  Future<void> _exportPersonaZip(BuildContext ctx) async {
    final chat = ctx.read<ChatProvider>();
    final io = PersonaIO(chat.storage);

    // Show progress
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(S.isEnglish ? 'Preparing export...' : 'Export wird vorbereitet...'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final zipBytes = await io.exportZip();
      final name = '${chat.storage.personaName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}_persona.zip';

      // Save to a temp file then let user pick where to save
      final result = await FilePicker.platform.saveFile(
        dialogTitle: S.isEnglish ? 'Save Persona ZIP' : 'Persona ZIP speichern',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: zipBytes,
      );

      if (result != null && mounted) {
        // On some platforms saveFile with bytes doesn't write, need to write manually
        if (!result.endsWith('.zip')) return;
        final f = File(result);
        if (!await f.exists()) {
          await f.writeAsBytes(zipBytes);
        }
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(S.isEnglish
                ? 'Persona exported: ${p.basename(result)} (${(zipBytes.length / 1024).toStringAsFixed(0)} KB)'
                : 'Persona exportiert: ${p.basename(result)} (${(zipBytes.length / 1024).toStringAsFixed(0)} KB)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Export error: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _importPersonaZip(BuildContext ctx) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: S.isEnglish ? 'Select Persona ZIP' : 'Persona ZIP auswaehlen',
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) return;

      // Confirm import
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: ctx,
        builder: (c) => AlertDialog(
          title: Text(S.isEnglish ? 'Import Persona?' : 'Persona importieren?'),
          content: Text(S.isEnglish
              ? 'This will replace your current memories, conversations, and settings with the imported persona. Continue?'
              : 'Dies ersetzt deine aktuellen Erinnerungen, Konversationen und Einstellungen mit der importierten Persona. Fortfahren?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(S.isEnglish ? 'Cancel' : 'Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(S.isEnglish ? 'Import' : 'Importieren')),
          ],
        ),
      );

      if (confirm != true) return;

      final chat = ctx.read<ChatProvider>();
      final io = PersonaIO(chat.storage);
      final count = await io.importZip(bytes);

      // Reload personality from imported files
      await chat.storage.reload();
      _personaNameController.text = chat.storage.personaName;
      _systemPromptController.text = chat.storage.systemPrompt;
      S.setLanguage(chat.storage.defaultLanguage);

      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(S.isEnglish ? '$count files imported!' : '$count Dateien importiert!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Import error: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _save() async {
    final chat = context.read<ChatProvider>();
    await chat.setUniversalApiKey(_apiKeyController.text.trim());
    await chat.storage.setSystemPrompt(_systemPromptController.text.trim());
    await chat.storage.updatePersonality({
      'personaName': _personaNameController.text.trim(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Settings saved'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Save'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Persona Export/Import (ZIP) ----
          _SectionCard(
            icon: Icons.swap_horiz,
            title: S.isEnglish ? 'Persona Export / Import' : 'Persona Export / Import',
            children: [
              Text(
                S.isEnglish
                    ? 'Export or import the complete persona as a ZIP file.\n'
                      'Includes: personality, memories, conversations, workspace files, and skills.'
                    : 'Exportiere oder importiere die komplette Persona als ZIP-Datei.\n'
                      'Enthaelt: Persoenlichkeit, Erinnerungen, Konversationen, Arbeitsergebnisse und Skills.',
                style: TextStyle(fontSize: 12, color: colors.outline),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _exportPersonaZip(context),
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: Text(S.isEnglish ? 'Export ZIP' : 'ZIP exportieren'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _importPersonaZip(context),
                      icon: const Icon(Icons.download, size: 18),
                      label: Text(S.isEnglish ? 'Import ZIP' : 'ZIP importieren'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ---- Personality ----
          _SectionCard(
            icon: Icons.face,
            title: 'Personality',
            children: [
              TextField(
                controller: _personaNameController,
                decoration: const InputDecoration(
                  labelText: 'Persona name',
                  hintText: 'BUD-E',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _systemPromptController,
                maxLines: 6,
                minLines: 3,
                decoration: const InputDecoration(
                  labelText: 'System prompt',
                  hintText: 'Define how the assistant behaves...',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 80),
                    child: Icon(Icons.psychology_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Saved to personality.json',
                style: TextStyle(fontSize: 11, color: colors.outline),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ---- Skills ----
          _SectionCard(
            icon: Icons.extension,
            title: S.isEnglish ? 'Skills' : 'Skills',
            children: [
              Text(
                S.isEnglish
                    ? 'Manage which tools and capabilities are available.'
                    : 'Verwalte welche Tools und Faehigkeiten verfuegbar sind.',
                style: TextStyle(fontSize: 12, color: colors.outline),
              ),
              const SizedBox(height: 8),
              Consumer<ChatProvider>(
                builder: (_, chat, __) {
                  final skills = AgentPersona.allSkillDefinitions;
                  final enabled = skills.length; // TODO: per-persona
                  return FilledButton.tonal(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SkillExplorerScreen(
                          enabledSkills: skills.map((s) => s['id']!).toList(),
                          onChanged: (updated) {
                            // TODO: save to persona
                          },
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.extension, size: 18),
                        const SizedBox(width: 8),
                        Text('$enabled/${skills.length} ${S.isEnglish ? "skills active" : "Skills aktiv"}'),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_ios, size: 14),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ---- Connection ----
          _SectionCard(
            icon: Icons.cloud_outlined,
            title: 'Connection',
            children: [
              TextField(
                controller: _apiKeyController,
                obscureText: _obscureKey,
                onChanged: (_) => _updateDecodedUrl(),
                decoration: InputDecoration(
                  labelText: 'Universal API key',
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(_obscureKey
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                      IconButton(
                        icon: const Icon(Icons.restore),
                        tooltip: 'Reset to default',
                        onPressed: () {
                          _apiKeyController.text = kDefaultUniversalKey;
                          _updateDecodedUrl();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _decodedUrl != null
                      ? colors.primaryContainer.withValues(alpha: 0.4)
                      : colors.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _decodedUrl != null
                          ? Icons.cloud_done
                          : Icons.cloud_off,
                      size: 18,
                      color: _decodedUrl != null
                          ? colors.primary
                          : colors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _decodedUrl != null
                            ? 'Middleware: $_decodedUrl'
                            : 'Could not decode middleware URL',
                        style: TextStyle(fontSize: 13, color: colors.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ---- Language ----
          _SectionCard(
            icon: Icons.language,
            title: 'Language',
            children: [
              Consumer<ChatProvider>(
                builder: (_, chat, __) {
                  return DropdownButtonFormField<String>(
                    value: chat.storage.defaultLanguage,
                    decoration: const InputDecoration(
                      labelText: 'Default response language',
                      prefixIcon: Icon(Icons.translate),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Deutsch', child: Text('Deutsch')),
                      DropdownMenuItem(value: 'English', child: Text('English')),
                      DropdownMenuItem(value: 'Francais', child: Text('Francais')),
                      DropdownMenuItem(value: 'Espanol', child: Text('Espanol')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        chat.storage.setDefaultLanguage(v);
                        S.setLanguage(v);
                      }
                    },
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ---- Memory Context ----
          _SectionCard(
            icon: Icons.memory,
            title: 'Memory Context',
            children: [
              Consumer<ChatProvider>(
                builder: (_, chat, __) {
                  return Column(
                    children: [
                      _TokenSlider(
                        label: 'Episodic memory budget',
                        value: chat.storage.episodicTokenBudget,
                        min: 5000,
                        max: 200000,
                        step: 5000,
                        onChanged: (v) => chat.storage.setEpisodicTokenBudget(v),
                      ),
                      const SizedBox(height: 8),
                      _TokenSlider(
                        label: 'Total context budget',
                        value: chat.storage.totalContextBudget,
                        min: 10000,
                        max: 500000,
                        step: 10000,
                        onChanged: (v) => chat.storage.setTotalContextBudget(v),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Episodic: loads recent memory up to budget.\n'
                        'Total: max tokens for episodic + activated semantic knowledge.',
                        style: TextStyle(fontSize: 11, color: colors.outline),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ---- Voice ----
          _SectionCard(
            icon: Icons.record_voice_over_outlined,
            title: 'Voice',
            children: [
              Consumer<ChatProvider>(
                builder: (_, chat, __) => Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Text-to-Speech'),
                      subtitle: const Text('Antworten automatisch vorlesen'),
                      secondary: Icon(
                        chat.ttsEnabled ? Icons.volume_up : Icons.volume_off,
                        color: chat.ttsEnabled ? colors.primary : colors.outline,
                      ),
                      value: chat.ttsEnabled,
                      onChanged: (v) => chat.setTtsEnabled(v),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: const Text('Spracheingabe auto-senden'),
                      subtitle: const Text(
                        'Transkription direkt abschicken statt ins Textfeld'),
                      secondary: Icon(
                        Icons.mic,
                        color: chat.storage.asrAutoSend
                            ? colors.primary : colors.outline,
                      ),
                      value: chat.storage.asrAutoSend,
                      onChanged: (v) {
                        chat.storage.setAsrAutoSend(v);
                        (context as Element).markNeedsBuild();
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: const Text('Audio Autoplay'),
                      subtitle: const Text(
                        'Generierte Musik und Audio automatisch abspielen'),
                      secondary: Icon(
                        Icons.play_circle_outline,
                        color: (chat.storage.getSetting('audioAutoplay') as bool? ?? false)
                            ? colors.primary : colors.outline,
                      ),
                      value: chat.storage.getSetting('audioAutoplay') as bool? ?? false,
                      onChanged: (v) {
                        chat.storage.setSetting('audioAutoplay', v);
                        (context as Element).markNeedsBuild();
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: const Text('Auto-Scroll'),
                      subtitle: const Text(
                        'Automatisch zum letzten Eintrag scrollen'),
                      secondary: Icon(
                        Icons.vertical_align_bottom,
                        color: (chat.storage.getSetting('autoScrollEnabled') as bool? ?? true)
                            ? colors.primary : colors.outline,
                      ),
                      value: chat.storage.getSetting('autoScrollEnabled') as bool? ?? true,
                      onChanged: (v) {
                        chat.storage.setSetting('autoScrollEnabled', v);
                        (context as Element).markNeedsBuild();
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ---- About ----
          _SectionCard(
            icon: Icons.info_outline,
            title: 'About',
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [colors.primary, colors.tertiary],
                      ),
                    ),
                    child: Icon(Icons.school, size: 20, color: colors.onPrimary),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('School Bud-E',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('v0.2.0 — by LAION',
                          style: TextStyle(fontSize: 12, color: colors.outline)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Consumer<ChatProvider>(
                builder: (_, chat, __) => Text(
                  'Data: ${chat.storage.rootPath}',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: colors.outline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TokenSlider extends StatefulWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  const _TokenSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  @override
  State<_TokenSlider> createState() => _TokenSliderState();
}

class _TokenSliderState extends State<_TokenSlider> {
  late double _current;

  @override
  void initState() {
    super.initState();
    _current = widget.value.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final display = _current >= 1000
        ? '${(_current / 1000).toStringAsFixed(0)}k'
        : _current.toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.label, style: const TextStyle(fontSize: 13)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$display tokens',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colors.onPrimaryContainer)),
            ),
          ],
        ),
        Slider(
          value: _current,
          min: widget.min.toDouble(),
          max: widget.max.toDouble(),
          divisions: ((widget.max - widget.min) / widget.step).round(),
          onChanged: (v) => setState(() => _current = v),
          onChangeEnd: (v) => widget.onChanged(v.round()),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
