import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/terminal_client.dart';
import '../terminal/terminal_view.dart';
import '../shell/shell_page.dart' show terminalClientProvider;

enum OnboardingStep { welcome, status, configure, catalog, terminal }

class OnboardingWizard extends ConsumerStatefulWidget {
  final VoidCallback? onComplete;
  final OnboardingStep initialStep;

  const OnboardingWizard({
    super.key,
    this.onComplete,
    this.initialStep = OnboardingStep.welcome,
  });

  @override
  ConsumerState<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends ConsumerState<OnboardingWizard> {
  late OnboardingStep _currentStep;
  final PageController _pageController = PageController();
  bool _isConnecting = false;
  String? _connectionError;
  bool _catalogLoading = false;
  String? _catalogError;
  List<Map<String, dynamic>> _skills = [];
  List<Map<String, dynamic>> _cronJobs = [];

  @override
  void initState() {
    super.initState();
    _currentStep = widget.initialStep;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectTerminal();
      if (_currentStep == OnboardingStep.catalog) {
        _loadCatalog();
      }
      _pageController.jumpToPage(_currentStep.index);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _connectTerminal() async {
    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });

    try {
      final client = ref.read(terminalClientProvider);
      await client.connect();

      await Future.delayed(const Duration(milliseconds: 500));

      if (client.isAuthenticated) {
        setState(() {
          _isConnecting = false;
        });
        client.executeCommand('doctor');
      } else {
        setState(() {
          _isConnecting = false;
          _connectionError = 'Failed to authenticate with terminal proxy';
        });
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _connectionError = 'Failed to connect: $e';
      });
    }
  }

  void _nextStep() {
    final nextIndex = _currentStep.index + 1;
    if (nextIndex < OnboardingStep.values.length) {
      final nextStep = OnboardingStep.values[nextIndex];
      setState(() {
        _currentStep = nextStep;
      });
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      if (nextStep == OnboardingStep.catalog && _skills.isEmpty && !_catalogLoading) {
        _loadCatalog();
      }
    } else {
      widget.onComplete?.call();
    }
  }

  void _previousStep() {
    final prevIndex = _currentStep.index - 1;
    if (prevIndex >= 0) {
      setState(() {
        _currentStep = OnboardingStep.values[prevIndex];
      });
      _pageController.animateToPage(
        prevIndex,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _goToStep(OnboardingStep step) {
    setState(() {
      _currentStep = step;
    });
    _pageController.animateToPage(
      step.index,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    if (step == OnboardingStep.catalog && _skills.isEmpty && !_catalogLoading) {
      _loadCatalog();
    }
  }

  Map<String, dynamic> _decodeJsonFromOutput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    try {
      final parsed = jsonDecode(trimmed);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}

    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final sliced = trimmed.substring(start, end + 1);
      final parsed = jsonDecode(sliced);
      if (parsed is Map<String, dynamic>) return parsed;
    }
    throw FormatException('No JSON object found in command output');
  }

  Future<void> _loadCatalog() async {
    final client = ref.read(terminalClientProvider);
    if (!client.isAuthenticated) {
      setState(() {
        _catalogError = 'terminal not connected';
      });
      return;
    }

    setState(() {
      _catalogLoading = true;
      _catalogError = null;
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

      final skillsObj = _decodeJsonFromOutput(skillsRaw);
      final cronObj = _decodeJsonFromOutput(cronRaw);

      final parsedSkills = ((skillsObj['skills'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      final parsedJobs = ((cronObj['jobs'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      if (!mounted) return;
      setState(() {
        _skills = parsedSkills;
        _cronJobs = parsedJobs;
        _catalogError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _catalogError = 'failed to load catalog: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _catalogLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    return Container(
      color: t.surfaceBase,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _connectionError != null
                ? _buildErrorView()
                : PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildWelcomeStep(),
                      _buildStatusStep(),
                      _buildConfigureStep(),
                      _buildCatalogStep(),
                      _buildTerminalStep(),
                    ],
                  ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            'setup',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: t.fgPrimary,
            ),
          ),
          const SizedBox(width: 16),
          ...OnboardingStep.values.map((step) {
            final isActive = step == _currentStep;
            final isPast = step.index < _currentStep.index;
            final isFuture = step.index > _currentStep.index;

            return GestureDetector(
              onTap: isFuture ? null : () => _goToStep(step),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  _getStepTitle(step),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isActive
                        ? t.accentPrimary
                        : isPast
                            ? t.fgTertiary
                            : t.fgDisabled,
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          if (_isConnecting)
            Text(
              'connecting...',
              style: theme.textTheme.labelSmall?.copyWith(
                color: t.fgTertiary,
              ),
            ),
        ],
      ),
    );
  }

  String _getStepTitle(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.welcome:
        return 'welcome';
      case OnboardingStep.status:
        return 'status';
      case OnboardingStep.configure:
        return 'configure';
      case OnboardingStep.catalog:
        return 'catalog';
      case OnboardingStep.terminal:
        return 'terminal';
    }
  }

  Widget _buildCatalogStep() {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    final ready = _skills.where((s) => s['eligible'] == true).toList();
    final missing = _skills.where((s) => s['eligible'] != true).toList();

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
                'skills + cron',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
              ),
              const SizedBox(width: 12),
              if (_catalogLoading)
                Text(
                  'loading...',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                ),
              const Spacer(),
              GestureDetector(
                onTap: _catalogLoading ? null : _loadCatalog,
                child: Text(
                  'refresh',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _catalogLoading ? t.fgDisabled : t.accentPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_catalogError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              _catalogError!,
              style: theme.textTheme.bodyMedium?.copyWith(color: t.statusError),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                'skills (${_skills.length})  ready (${ready.length})  missing (${missing.length})',
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
              ),
              const SizedBox(height: 8),
              ...ready.map((s) => _skillRow(s, true)),
              ...missing.map((s) => _skillRow(s, false)),
              const SizedBox(height: 16),
              Text(
                'cron jobs (${_cronJobs.length})',
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
              ),
              const SizedBox(height: 8),
              if (_cronJobs.isEmpty)
                Text(
                  'no cron jobs configured',
                  style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                )
              else
                ..._cronJobs.map(_cronRow),
            ],
          ),
        ),
      ],
    );
  }

  Widget _skillRow(Map<String, dynamic> skill, bool ready) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    final name = (skill['name'] ?? 'unknown').toString();
    final desc = (skill['description'] ?? '').toString();

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
              ),
            ),
        ],
      ),
    );
  }

  Widget _cronRow(Map<String, dynamic> job) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    final id = (job['id'] ?? '').toString();
    final schedule = (job['schedule'] ?? '').toString();
    final command = (job['command'] ?? job['task'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '${id.isNotEmpty ? id : '(job)'}  ${schedule.isNotEmpty ? schedule : '-'}  ${command.isNotEmpty ? command : ''}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: t.fgTertiary,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'connection error',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: t.statusError,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _connectionError!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: t.fgTertiary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _connectTerminal,
            child: Text(
              'retry',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: t.accentPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeStep() {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OpenClaw Gateway powers the agent runtime, multi-provider LLM, '
            'tool execution, sessions, memory, and governance.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: t.fgSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          _buildFeatureLine('health check', 'verify OpenClaw is running'),
          _buildFeatureLine('configuration', 'set up LLM providers and keys'),
          _buildFeatureLine('terminal', 'run OpenClaw commands from browser'),
          const SizedBox(height: 24),
          Text(
            'The wizard will connect to the OpenClaw Gateway running in Docker.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: t.fgTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureLine(String title, String description) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '- ',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: t.fgTertiary,
            ),
          ),
          Text(
            '$title  ',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: t.fgPrimary,
            ),
          ),
          Flexible(
            child: Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: t.fgTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStep() {
    return Consumer(
      builder: (context, ref, child) {
        final client = ref.watch(terminalClientProvider);

        return TerminalView(
          client: client,
          showInput: false,
          suggestedCommands: const ['status', 'doctor', 'models'],
        );
      },
    );
  }

  Widget _buildConfigureStep() {
    return Consumer(
      builder: (context, ref, child) {
        final client = ref.watch(terminalClientProvider);
        final t = ShellTokens.of(context);

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: t.border, width: 0.5),
                ),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _buildConfigLink(client, 'configure', 'configure'),
                  _buildConfigLink(client, 'web tools', 'configure --section web'),
                  _buildConfigLink(client, 'channels', 'channels login'),
                  _buildConfigLink(client, 'auto-fix', 'doctor --fix'),
                ],
              ),
            ),
            Expanded(
              child: TerminalView(
                client: client,
                showInput: true,
                suggestedCommands: const [
                  'configure --section providers',
                  'configure --section web',
                  'channels list',
                  'sessions list',
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConfigLink(TerminalProxyClient client, String label, String command) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    return GestureDetector(
      onTap: client.isExecuting ? null : () => client.executeCommand(command),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: client.isExecuting
              ? t.fgDisabled
              : t.accentPrimary,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildTerminalStep() {
    return Consumer(
      builder: (context, ref, child) {
        final client = ref.watch(terminalClientProvider);

        return TerminalView(
          client: client,
          showInput: true,
          suggestedCommands: const ['status', 'models', 'sessions list', 'logs'],
        );
      },
    );
  }

  Widget _buildFooter() {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (_currentStep.index > 0)
            GestureDetector(
              onTap: _previousStep,
              child: Text(
                'back',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: t.fgTertiary,
                ),
              ),
            ),
          const Spacer(),
          GestureDetector(
            onTap: _isConnecting ? null : _nextStep,
            child: Text(
              _currentStep == OnboardingStep.terminal ? 'done' : 'next',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _isConnecting
                    ? t.fgDisabled
                    : t.accentPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
