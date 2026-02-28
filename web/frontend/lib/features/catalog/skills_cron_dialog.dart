import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/terminal_client.dart';
import '../shell/shell_page.dart' show terminalClientProvider;

class SkillsCronDialog extends ConsumerStatefulWidget {
  const SkillsCronDialog({super.key});

  @override
  ConsumerState<SkillsCronDialog> createState() => _SkillsCronDialogState();
}

class _SkillsCronDialogState extends ConsumerState<SkillsCronDialog> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _skills = [];
  List<Map<String, dynamic>> _cronJobs = [];

  int _skillsPage = 0;
  int _cronPage = 0;
  static const int _pageSize = 12;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Map<String, dynamic> _decodeJsonObject(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    try {
      final parsed = jsonDecode(trimmed);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}

    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final parsed = jsonDecode(trimmed.substring(start, end + 1));
      if (parsed is Map<String, dynamic>) return parsed;
    }
    throw const FormatException('No JSON object found in output');
  }

  Future<void> _loadData() async {
    final client = ref.read(terminalClientProvider);
    if (!client.isConnected || !client.isAuthenticated) {
      try {
        await client.connect();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 400));
    }

    if (!client.isAuthenticated) {
      setState(() {
        _error = 'terminal proxy not connected';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final skillsRaw = await client.executeCommandForOutput(
        'skills list --json',
        timeout: const Duration(seconds: 45),
      );
      final cronRaw = await client.executeCommandForOutput(
        'cron list --json',
        timeout: const Duration(seconds: 30),
      );

      final skillsJson = _decodeJsonObject(skillsRaw);
      final cronJson = _decodeJsonObject(cronRaw);

      final skills = ((skillsJson['skills'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      final jobs = ((cronJson['jobs'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      if (!mounted) return;
      setState(() {
        _skills = skills;
        _cronJobs = jobs;
        _skillsPage = 0;
        _cronPage = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'failed to load skills/cron: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _slicePage(List<Map<String, dynamic>> rows, int page) {
    final start = page * _pageSize;
    if (start >= rows.length) return const [];
    final end = (start + _pageSize).clamp(0, rows.length);
    return rows.sublist(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final skillsPages = (_skills.length / _pageSize).ceil().clamp(1, 9999);
    final cronPages = (_cronJobs.length / _pageSize).ceil().clamp(1, 9999);

    final skillsPageRows = _slicePage(_skills, _skillsPage);
    final cronPageRows = _slicePage(_cronJobs, _cronPage);

    return Dialog(
      backgroundColor: t.surfaceBase,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: t.border, width: 0.5),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.82,
        height: MediaQuery.of(context).size.height * 0.82,
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  Text('skills / cron', style: theme.textTheme.bodyLarge),
                  const SizedBox(width: 12),
                  if (_loading)
                    Text(
                      'loading...',
                      style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        _error!,
                        style: theme.textTheme.labelSmall?.copyWith(color: t.statusError),
                      ),
                    ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _loading ? null : _loadData,
                    child: Text(
                      'refresh',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _loading ? t.fgDisabled : t.accentPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(
                          title: 'skills (${_skills.length})',
                          page: _skillsPage,
                          pages: skillsPages,
                          onPrev: _skillsPage > 0
                              ? () => setState(() => _skillsPage -= 1)
                              : null,
                          onNext: _skillsPage + 1 < skillsPages
                              ? () => setState(() => _skillsPage += 1)
                              : null,
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            children: skillsPageRows.map(_skillRow).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 0.5, color: t.border),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(
                          title: 'cron (${_cronJobs.length})',
                          page: _cronPage,
                          pages: cronPages,
                          onPrev: _cronPage > 0
                              ? () => setState(() => _cronPage -= 1)
                              : null,
                          onNext: _cronPage + 1 < cronPages
                              ? () => setState(() => _cronPage += 1)
                              : null,
                        ),
                        Expanded(
                          child: _cronJobs.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    'no cron jobs configured',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: t.fgPlaceholder,
                                    ),
                                  ),
                                )
                              : ListView(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  children: cronPageRows.map(_cronRow).toList(),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required String title,
    required int page,
    required int pages,
    required VoidCallback? onPrev,
    required VoidCallback? onNext,
  }) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary)),
          const Spacer(),
          GestureDetector(
            onTap: onPrev,
            child: Text(
              'prev',
              style: theme.textTheme.labelSmall?.copyWith(
                color: onPrev == null ? t.fgDisabled : t.accentPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${page + 1}/$pages',
            style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onNext,
            child: Text(
              'next',
              style: theme.textTheme.labelSmall?.copyWith(
                color: onNext == null ? t.fgDisabled : t.accentPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skillRow(Map<String, dynamic> row) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final ready = row['eligible'] == true;
    final name = (row['name'] ?? 'unknown').toString();
    final desc = (row['description'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${ready ? 'ready' : 'missing'}  $name',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ready ? t.accentPrimary : t.fgMuted,
            ),
          ),
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Text(
                desc,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: t.fgTertiary,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _cronRow(Map<String, dynamic> row) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final id = (row['id'] ?? '(job)').toString();
    final schedule = (row['schedule'] ?? '-').toString();
    final command = (row['command'] ?? row['task'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        '$id  $schedule  $command',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: t.fgTertiary,
          fontSize: 12,
        ),
      ),
    );
  }
}
