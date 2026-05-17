import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../config/api_config.dart';
import '../models/agent_persona.dart';
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
          // ---- Persona Export/Import ----
          _SectionCard(
            icon: Icons.swap_horiz,
            title: S.isEnglish ? 'Persona Export / Import' : 'Persona Export / Import',
            children: [
              Text(
                S.isEnglish
                    ? 'Export or import the complete personality including system prompt, memory, and settings.'
                    : 'Exportiere oder importiere die komplette Persoenlichkeit inkl. System-Prompt, Memory und Einstellungen.',
                style: TextStyle(fontSize: 12, color: colors.outline),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        final chat = context.read<ChatProvider>();
                        final data = {
                          'personaName': chat.storage.personaName,
                          'systemPrompt': chat.storage.systemPrompt,
                          'defaultLanguage': chat.storage.defaultLanguage,
                          'personality': chat.storage.personality,
                          'exportedAt': DateTime.now().toIso8601String(),
                        };
                        final json = const JsonEncoder.withIndent('  ').convert(data);
                        await Clipboard.setData(ClipboardData(text: json));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(S.isEnglish ? 'Persona exported to clipboard' : 'Persona in Zwischenablage exportiert'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.upload, size: 18),
                      label: const Text('Export'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        final clip = await Clipboard.getData(Clipboard.kTextPlain);
                        if (clip?.text == null || clip!.text!.isEmpty) return;
                        try {
                          final data = jsonDecode(clip.text!) as Map<String, dynamic>;
                          final chat = context.read<ChatProvider>();
                          if (data['personaName'] != null) {
                            await chat.storage.updatePersonality({
                              'personaName': data['personaName'],
                            });
                            _personaNameController.text = data['personaName'];
                          }
                          if (data['systemPrompt'] != null) {
                            await chat.storage.setSystemPrompt(data['systemPrompt']);
                            _systemPromptController.text = data['systemPrompt'];
                          }
                          if (data['defaultLanguage'] != null) {
                            await chat.storage.setDefaultLanguage(data['defaultLanguage']);
                            S.setLanguage(data['defaultLanguage']);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(S.isEnglish ? 'Persona imported!' : 'Persona importiert!'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            setState(() {});
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Import error: $e'), behavior: SnackBarBehavior.floating),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Import'),
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
