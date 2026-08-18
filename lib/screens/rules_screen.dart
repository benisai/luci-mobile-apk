import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key});

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen> {
  List<OpenwrtFirewallRule> _rules = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRules());
  }

  Future<void> _loadRules() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final appState = ref.read(appStateProvider);
      final rules = await appState.fetchFirewallRules(context: context);
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _isLoading = false;
      });
      await appState.refreshDashboardSummaryCounts();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load firewall rules.';
        _isLoading = false;
      });
    }
  }

  String _formatCount(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final remaining = text.length - i;
      buffer.write(text[i]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const LuciAppBar(title: 'Rules', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadRules,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text(
                'Firewall Rules',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatCount(_rules.length),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                ),
              ),
              const SizedBox(height: 18),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 44),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _RulesEmptyCard(message: _error!, action: _loadRules)
              else if (_rules.isEmpty)
                _RulesEmptyCard(
                  message: 'No firewall rules found.',
                  action: _loadRules,
                )
              else
                ..._rules.map((rule) => _RuleCard(rule: rule)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RulesEmptyCard extends StatelessWidget {
  final String message;
  final VoidCallback action;

  const _RulesEmptyCard({required this.message, required this.action});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 28),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: action,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final OpenwrtFirewallRule rule;

  const _RuleCard({required this.rule});

  Color _targetColor(BuildContext context) {
    final action = rule.action.toUpperCase();
    if (action == 'ACCEPT') return const Color(0xFF20CF70);
    if (action == 'REJECT' || action == 'DROP') {
      return Theme.of(context).colorScheme.error;
    }
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final targetColor = _targetColor(context);
    final backgroundColor = rule.isBlocked
        ? colorScheme.error.withValues(alpha: 0.045)
        : colorScheme.surface;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: rule.isOpenwallaRule
              ? colorScheme.primary.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rule.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              _RuleBadge(label: rule.action, color: targetColor),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (rule.isOpenwallaRule)
                _RuleBadge(
                  label: 'Openwalla',
                  color: colorScheme.primary,
                  filled: false,
                ),
              _RuleBadge(
                label: rule.enabled ? 'Enabled' : 'Disabled',
                color: rule.enabled
                    ? const Color(0xFF20CF70)
                    : colorScheme.onSurfaceVariant,
                filled: false,
              ),
              _RuleBadge(label: rule.protocol, color: colorScheme.secondary),
            ],
          ),
          const SizedBox(height: 12),
          _RuleDetailGrid(rule: rule),
        ],
      ),
    );
  }
}

class _RuleBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;

  const _RuleBadge({
    required this.label,
    required this.color,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _RuleDetailGrid extends StatelessWidget {
  final OpenwrtFirewallRule rule;

  const _RuleDetailGrid({required this.rule});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RuleDetailRow(label: 'Source', value: rule.source),
        _RuleDetailRow(label: 'Source IP', value: rule.sourceIp),
        _RuleDetailRow(label: 'Destination', value: rule.destination),
        _RuleDetailRow(label: 'Port', value: rule.port),
        _RuleDetailRow(label: 'Section', value: rule.section),
      ],
    );
  }
}

class _RuleDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _RuleDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
