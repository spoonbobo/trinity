import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../shell/shell_page.dart' show terminalClientProvider;

enum CatalogTab { skills, crons }

enum SkillsCategory { ready, notReady, clawhub, templates }

enum CronCategory { existing, templates }

class SkillsCronDialog extends ConsumerStatefulWidget {
  final CatalogTab initialTab;

  const SkillsCronDialog({
    super.key,
    this.initialTab = CatalogTab.skills,
  });

  @override
  ConsumerState<SkillsCronDialog> createState() => _SkillsCronDialogState();
}

class _SkillsCronDialogState extends ConsumerState<SkillsCronDialog> {
  final TextEditingController _clawhubQueryController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _installingSkill;
  bool _clawhubSearching = false;
  String? _clawhubError;
  List<Map<String, String>> _clawhubResults = [];

  CatalogTab _tab = CatalogTab.skills;
  SkillsCategory _skillsCategory = SkillsCategory.ready;
  CronCategory _cronCategory = CronCategory.existing;

  List<Map<String, dynamic>> _skills = [];
  List<Map<String, dynamic>> _cronJobs = [];

  int _skillsPage = 0;
  int _cronPage = 0;
  static const int _pageSize = 14;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _clawhubQueryController.dispose();
    super.dispose();
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

  Future<void> _installSkill(Map<String, dynamic> row) async {
    final client = ref.read(terminalClientProvider);
    final rawName = (row['slug'] ?? row['name'] ?? '').toString().trim();
    if (rawName.isEmpty) return;

    if (!client.isAuthenticated) {
      setState(() {
        _error = 'terminal proxy not connected';
      });
      return;
    }

    setState(() {
      _installingSkill = rawName;
      _error = null;
    });

    try {
      await client.executeCommandForOutput(
        'clawhub install $rawName',
        timeout: const Duration(seconds: 90),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'failed to install $rawName: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _installingSkill = null;
      });
    }
  }

  Future<void> _searchClawhub() async {
    final client = ref.read(terminalClientProvider);
    final query = _clawhubQueryController.text.trim();
    if (query.isEmpty) return;

    if (!client.isAuthenticated) {
      setState(() {
        _clawhubError = 'terminal proxy not connected';
      });
      return;
    }

    final escaped = query.replaceAll('"', '\\"');

    setState(() {
      _clawhubSearching = true;
      _clawhubError = null;
      _clawhubResults = [];
    });

    try {
      final raw = await client.executeCommandForOutput(
        'clawhub search "$escaped" --limit 20',
        timeout: const Duration(seconds: 60),
      );

      final parsed = <Map<String, String>>[];
      for (final line in raw.split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('- ')) continue;

        final withoutPrefix = trimmed.substring(2).trim();
        final scoreStart = withoutPrefix.lastIndexOf('(');
        final scoreEnd = withoutPrefix.lastIndexOf(')');

        String score = '';
        String body = withoutPrefix;
        if (scoreStart > 0 && scoreEnd > scoreStart) {
          score = withoutPrefix.substring(scoreStart + 1, scoreEnd).trim();
          body = withoutPrefix.substring(0, scoreStart).trim();
        }

        if (body.isEmpty) continue;
        final parts = body.split(RegExp(r'\s{2,}'));
        final slug = parts.isNotEmpty ? parts.first.trim() : body;
        final name = parts.length > 1 ? parts.sublist(1).join(' ').trim() : slug;
        if (slug.isEmpty) continue;

        parsed.add({'slug': slug, 'name': name, 'score': score});
      }

      if (!mounted) return;
      setState(() {
        _clawhubResults = parsed;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _clawhubError = 'search failed: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _clawhubSearching = false;
      });
    }
  }

  Future<void> _installClawhubSkill(Map<String, String> row) async {
    final client = ref.read(terminalClientProvider);
    final slug = (row['slug'] ?? '').trim();
    if (slug.isEmpty) return;

    setState(() {
      _installingSkill = slug;
      _error = null;
      _clawhubError = null;
    });

    try {
      await client.executeCommandForOutput(
        'clawhub install $slug',
        timeout: const Duration(seconds: 120),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _clawhubError = 'failed to install $slug: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _installingSkill = null;
      });
    }
  }

  List<Map<String, dynamic>> _slicePage(List<Map<String, dynamic>> rows, int page) {
    final start = page * _pageSize;
    if (start >= rows.length) return const [];
    final end = (start + _pageSize).clamp(0, rows.length);
    return rows.sublist(start, end);
  }

  bool _isTemplate(Map<String, dynamic> skill) {
    final source = (skill['source'] ?? '').toString().toLowerCase();
    final kind = (skill['kind'] ?? '').toString().toLowerCase();
    final name = (skill['name'] ?? '').toString().toLowerCase();
    return source.contains('template') ||
        kind.contains('template') ||
        name.contains('template');
  }

  List<Map<String, dynamic>> _skillsForCategory() {
    switch (_skillsCategory) {
      case SkillsCategory.ready:
        return _skills.where((s) => s['eligible'] == true && !_isTemplate(s)).toList();
      case SkillsCategory.notReady:
        return _skills.where((s) => s['eligible'] != true && !_isTemplate(s)).toList();
      case SkillsCategory.clawhub:
        return _skills.where((s) {
          final name = (s['name'] ?? '').toString().toLowerCase();
          final source = (s['source'] ?? '').toString().toLowerCase();
          return name.contains('clawhub') || source.contains('clawhub');
        }).toList();
      case SkillsCategory.templates:
        return _skills.where(_isTemplate).toList();
    }
  }

  bool _isCronTemplate(Map<String, dynamic> job) {
    final source = (job['source'] ?? '').toString().toLowerCase();
    final kind = (job['kind'] ?? '').toString().toLowerCase();
    final id = (job['id'] ?? '').toString().toLowerCase();
    final name = (job['name'] ?? '').toString().toLowerCase();
    return source.contains('template') ||
        kind.contains('template') ||
        id.contains('template') ||
        name.contains('template');
  }

  List<Map<String, dynamic>> _cronsForCategory() {
    switch (_cronCategory) {
      case CronCategory.existing:
        return _cronJobs.where((j) => !_isCronTemplate(j)).toList();
      case CronCategory.templates:
        return _cronJobs.where(_isCronTemplate).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    final categoryRows = _skillsForCategory();
    final cronCategoryRows = _cronsForCategory();
    final skillsPages = (categoryRows.length / _pageSize).ceil().clamp(1, 9999);
    final cronPages = (cronCategoryRows.length / _pageSize).ceil().clamp(1, 9999);

    final skillsPageRows = _slicePage(categoryRows, _skillsPage);
    final cronPageRows = _slicePage(cronCategoryRows, _cronPage);

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
                  _topToggle('skills', _tab == CatalogTab.skills, () {
                    setState(() {
                      _tab = CatalogTab.skills;
                      _skillsPage = 0;
                    });
                  }),
                  const SizedBox(width: 12),
                  _topToggle('crons', _tab == CatalogTab.crons, () {
                    setState(() {
                      _tab = CatalogTab.crons;
                      _cronPage = 0;
                    });
                  }),
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
                child: _tab == CatalogTab.skills
                    ? _buildSkillsView(
                        skillsPageRows: skillsPageRows,
                        pages: skillsPages,
                        totalRows: categoryRows.length,
                      )
                    : _buildCronsView(
                        cronPageRows: cronPageRows,
                        pages: cronPages,
                        totalRows: cronCategoryRows.length,
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillsView({
    required List<Map<String, dynamic>> skillsPageRows,
    required int pages,
    required int totalRows,
  }) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              _categoryToggle('ready', _skillsCategory == SkillsCategory.ready, () {
                setState(() {
                  _skillsCategory = SkillsCategory.ready;
                  _skillsPage = 0;
                });
              }),
              const SizedBox(width: 10),
              _categoryToggle('not ready', _skillsCategory == SkillsCategory.notReady, () {
                setState(() {
                  _skillsCategory = SkillsCategory.notReady;
                  _skillsPage = 0;
                });
              }),
              const SizedBox(width: 10),
              _categoryToggle('clawhub', _skillsCategory == SkillsCategory.clawhub, () {
                setState(() {
                  _skillsCategory = SkillsCategory.clawhub;
                  _skillsPage = 0;
                });
              }),
              const SizedBox(width: 10),
              _categoryToggle('templates', _skillsCategory == SkillsCategory.templates, () {
                setState(() {
                  _skillsCategory = SkillsCategory.templates;
                  _skillsPage = 0;
                });
              }),
              const Spacer(),
              Text(
                '${_skillsPage + 1}/$pages',
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
              ),
              const SizedBox(width: 10),
              _pageControl('prev', _skillsPage > 0, () {
                setState(() => _skillsPage -= 1);
              }),
              const SizedBox(width: 8),
              _pageControl('next', _skillsPage + 1 < pages, () {
                setState(() => _skillsPage += 1);
              }),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            'skills ($totalRows)',
            style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
          ),
        ),
        Expanded(
          child: _skillsCategory == SkillsCategory.clawhub
              ? _buildClawhubSearchView()
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: skillsPageRows.map(_skillRow).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildClawhubSearchView() {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _clawhubQueryController,
                  decoration: const InputDecoration(
                    hintText: 'search clawhub skills',
                  ),
                  onSubmitted: (_) => _searchClawhub(),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _clawhubSearching ? null : _searchClawhub,
                child: Text(
                  _clawhubSearching ? 'searching...' : 'search',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _clawhubSearching ? t.fgDisabled : t.accentPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_clawhubError != null)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _clawhubError!,
                style: theme.textTheme.bodyMedium?.copyWith(color: t.statusError),
              ),
            ),
          ),
        Expanded(
          child: _clawhubResults.isEmpty
              ? Center(
                  child: Text(
                    _clawhubSearching ? 'searching...' : 'search to discover skills',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: _clawhubResults.map(_clawhubRow).toList(),
                ),
        ),
      ],
    );
  }

  Widget _clawhubRow(Map<String, String> row) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final slug = (row['slug'] ?? '').trim();
    final name = (row['name'] ?? slug).trim();
    final score = (row['score'] ?? '').trim();
    final installing = _installingSkill == slug;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              score.isEmpty ? '$slug  $name' : '$slug  $name  ($score)',
              style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
            ),
          ),
          GestureDetector(
            onTap: installing ? null : () => _installClawhubSkill(row),
            child: Text(
              installing ? 'installing...' : 'install',
              style: theme.textTheme.labelSmall?.copyWith(
                color: installing ? t.fgDisabled : t.accentPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCronsView({
    required List<Map<String, dynamic>> cronPageRows,
    required int pages,
    required int totalRows,
  }) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Text(
                'cron jobs ($totalRows)',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
              ),
              const SizedBox(width: 12),
              _categoryToggle('existing', _cronCategory == CronCategory.existing, () {
                setState(() {
                  _cronCategory = CronCategory.existing;
                  _cronPage = 0;
                });
              }),
              const SizedBox(width: 10),
              _categoryToggle('templates', _cronCategory == CronCategory.templates, () {
                setState(() {
                  _cronCategory = CronCategory.templates;
                  _cronPage = 0;
                });
              }),
              const Spacer(),
              Text(
                '${_cronPage + 1}/$pages',
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
              ),
              const SizedBox(width: 10),
              _pageControl('prev', _cronPage > 0, () {
                setState(() => _cronPage -= 1);
              }),
              const SizedBox(width: 8),
              _pageControl('next', _cronPage + 1 < pages, () {
                setState(() => _cronPage += 1);
              }),
            ],
          ),
        ),
        Expanded(
          child: totalRows == 0
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'no cron jobs configured',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: cronPageRows.map(_cronRow).toList(),
                ),
        ),
      ],
    );
  }

  Widget _topToggle(String label, bool active, VoidCallback onTap) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: active ? t.accentPrimary : t.fgMuted,
        ),
      ),
    );
  }

  Widget _categoryToggle(String label, bool active, VoidCallback onTap) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: active ? t.accentPrimary : t.fgMuted,
        ),
      ),
    );
  }

  Widget _pageControl(String label, bool enabled, VoidCallback onTap) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: enabled ? t.accentPrimary : t.fgDisabled,
        ),
      ),
    );
  }

  Widget _skillRow(Map<String, dynamic> row) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final ready = row['eligible'] == true;
    final name = (row['name'] ?? 'unknown').toString();
    final desc = (row['description'] ?? '').toString();
    final canInstall = !ready;
    final installing = _installingSkill == name;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${ready ? 'ready' : 'missing'}  $name',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ready ? t.accentPrimary : t.fgMuted,
                  ),
                ),
              ),
              if (canInstall)
                GestureDetector(
                  onTap: installing ? null : () => _installSkill(row),
                  child: Text(
                    installing ? 'installing...' : 'install',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: installing ? t.fgDisabled : t.accentPrimary,
                    ),
                  ),
                ),
            ],
          ),
          if (!canInstall && _skillsCategory == SkillsCategory.templates)
            Text(
              'template',
              style: theme.textTheme.labelSmall?.copyWith(
                color: t.fgTertiary,
                fontSize: 10,
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
