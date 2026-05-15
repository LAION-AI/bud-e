/// Skill Explorer — browse, enable/disable, and manage agent skills.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/agent_persona.dart';
import '../utils/app_strings.dart';

class SkillExplorerScreen extends StatefulWidget {
  final List<String> enabledSkills;
  final ValueChanged<List<String>> onChanged;

  const SkillExplorerScreen({
    super.key,
    required this.enabledSkills,
    required this.onChanged,
  });

  @override
  State<SkillExplorerScreen> createState() => _SkillExplorerScreenState();
}

class _SkillExplorerScreenState extends State<SkillExplorerScreen> {
  late Set<String> _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = Set.from(widget.enabledSkills);
  }

  void _toggle(String id) {
    setState(() {
      if (_enabled.contains(id)) {
        _enabled.remove(id);
      } else {
        _enabled.add(id);
      }
    });
    widget.onChanged(_enabled.toList());
  }

  void _exportSkills() {
    final data = {
      'exportedAt': DateTime.now().toIso8601String(),
      'enabledSkills': _enabled.toList(),
    };
    final json = const JsonEncoder.withIndent('  ').convert(data);
    Clipboard.setData(ClipboardData(text: json));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.isEnglish ? 'Skills exported to clipboard' : 'Skills in Zwischenablage exportiert'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final skills = AgentPersona.allSkillDefinitions;

    // Group by category
    final categories = <String, List<Map<String, String>>>{};
    for (final skill in skills) {
      categories.putIfAbsent(skill['category']!, () => []).add(skill);
    }

    final categoryNames = {
      'research': S.isEnglish ? 'Research' : 'Recherche',
      'creative': S.isEnglish ? 'Creative' : 'Kreativ',
      'memory': S.isEnglish ? 'Memory' : 'Gedaechtnis',
      'education': S.isEnglish ? 'Education' : 'Bildung',
      'files': S.isEnglish ? 'Files & Documents' : 'Dateien & Dokumente',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(S.isEnglish ? 'Skill Explorer' : 'Skill-Explorer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload),
            tooltip: S.isEnglish ? 'Export skills' : 'Skills exportieren',
            onPressed: _exportSkills,
          ),
          TextButton(
            onPressed: () {
              setState(() => _enabled = Set.from(
                  AgentPersona.allSkillDefinitions.map((s) => s['id']!)));
              widget.onChanged(_enabled.toList());
            },
            child: Text(S.isEnglish ? 'Enable All' : 'Alle aktivieren'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            S.isEnglish
                ? '${_enabled.length}/${skills.length} skills enabled'
                : '${_enabled.length}/${skills.length} Skills aktiviert',
            style: TextStyle(color: colors.outline, fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final category in categories.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                categoryNames[category.key] ?? category.key,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ),
            ...category.value.map((skill) => _SkillCard(
                  skill: skill,
                  enabled: _enabled.contains(skill['id']),
                  onToggle: () => _toggle(skill['id']!),
                  colors: colors,
                )),
          ],
        ],
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  final Map<String, String> skill;
  final bool enabled;
  final VoidCallback onToggle;
  final ColorScheme colors;

  const _SkillCard({
    required this.skill,
    required this.enabled,
    required this.onToggle,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: enabled
          ? colors.primaryContainer.withValues(alpha: 0.3)
          : colors.surfaceContainerHighest.withValues(alpha: 0.3),
      child: ListTile(
        leading: Text(skill['icon'] ?? '🔧', style: const TextStyle(fontSize: 28)),
        title: Text(
          skill['name'] ?? '',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: enabled ? colors.onSurface : colors.outline,
          ),
        ),
        subtitle: Text(
          skill['description'] ?? '',
          style: TextStyle(fontSize: 12, color: colors.outline),
        ),
        trailing: Switch(
          value: enabled,
          onChanged: (_) => onToggle(),
        ),
        onTap: onToggle,
      ),
    );
  }
}
