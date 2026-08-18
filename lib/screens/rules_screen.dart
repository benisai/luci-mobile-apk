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

  Future<void> _setRuleEnabled(OpenwrtFirewallRule rule, bool enabled) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appStateProvider).setFirewallRuleEnabled(rule, enabled);
      if (!mounted) return;
      await _loadRules();
      messenger.showSnackBar(
        SnackBar(content: Text(enabled ? 'Rule enabled.' : 'Rule disabled.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update rule: $e')),
      );
    }
  }

  Future<void> _deleteRule(OpenwrtFirewallRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rule?'),
        content: Text('Delete "${rule.name}" from firewall rules?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appStateProvider).deleteFirewallRule(rule);
      if (!mounted) return;
      await _loadRules();
      messenger.showSnackBar(const SnackBar(content: Text('Rule deleted.')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete rule: $e')),
      );
    }
  }

  void _showRuleDetails(OpenwrtFirewallRule rule) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _RuleDetailsSheet(
        rule: rule,
        onToggleEnabled: (enabled) {
          Navigator.of(sheetContext).pop();
          _setRuleEnabled(rule, enabled);
        },
        onDelete: () {
          Navigator.of(sheetContext).pop();
          _deleteRule(rule);
        },
      ),
    );
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
                ..._rules.map(
                  (rule) => _RuleCard(
                    rule: rule,
                    onTap: () => _showRuleDetails(rule),
                  ),
                ),
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
  final VoidCallback onTap;

  const _RuleCard({required this.rule, required this.onTap});

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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
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
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
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

class _RuleDetailsSheet extends StatelessWidget {
  final OpenwrtFirewallRule rule;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onDelete;

  const _RuleDetailsSheet({
    required this.rule,
    required this.onToggleEnabled,
    required this.onDelete,
  });

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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rule.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _RuleBadge(label: rule.action, color: targetColor),
                _RuleBadge(
                  label: rule.enabled ? 'Enabled' : 'Disabled',
                  color: rule.enabled
                      ? const Color(0xFF20CF70)
                      : colorScheme.onSurfaceVariant,
                  filled: false,
                ),
                if (rule.isOpenwallaRule)
                  _RuleBadge(
                    label: 'Openwalla',
                    color: colorScheme.primary,
                    filled: false,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.42),
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _RuleDetailRow(label: 'Source', value: rule.source),
                  _RuleDetailRow(label: 'Source IP', value: rule.sourceIp),
                  _RuleDetailRow(label: 'Destination', value: rule.destination),
                  _RuleDetailRow(label: 'Protocol', value: rule.protocol),
                  _RuleDetailRow(label: 'Port', value: rule.port),
                  _RuleDetailRow(label: 'Action', value: rule.action),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => onToggleEnabled(!rule.enabled),
                    icon: Icon(
                      rule.enabled
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                    ),
                    label: Text(rule.enabled ? 'Disable' : 'Enable'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
