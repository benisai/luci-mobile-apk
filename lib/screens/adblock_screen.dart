import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/openwrt_feature_gate.dart';

const List<_AdblockFeedOption> _adblockFeedOptions = [
  _AdblockFeedOption('adguard', 'AdGuard', 'L, general'),
  _AdblockFeedOption('adguard_tracking', 'AdGuard Tracking', 'L, tracking'),
  _AdblockFeedOption('certpl', 'CERT Polska', 'L, phishing'),
  _AdblockFeedOption('1hosts', '1Hosts', 'VAR, compilation'),
  _AdblockFeedOption('android_tracking', 'Android Tracking', 'S, tracking'),
  _AdblockFeedOption('andryou', 'Andryou', 'L, compilation'),
  _AdblockFeedOption('anti_ad', 'Anti-AD', 'L, compilation'),
  _AdblockFeedOption('anudeep', 'Anudeep', 'M, compilation'),
  _AdblockFeedOption('bitcoin', 'Bitcoin', 'S, mining'),
  _AdblockFeedOption('cpbl', 'CPBL', 'XL, compilation'),
  _AdblockFeedOption('disconnect', 'Disconnect', 'S, general'),
  _AdblockFeedOption('doh_blocklist', 'DoH Blocklist', 'S, doh server'),
  _AdblockFeedOption('firetv_tracking', 'Fire TV Tracking', 'S, tracking'),
  _AdblockFeedOption('hagezi', 'Hagezi', 'VAR, compilation'),
  _AdblockFeedOption('hblock', 'HBlock', 'XL, compilation'),
  _AdblockFeedOption('oisd_small', 'OISD Small', 'L, general'),
  _AdblockFeedOption('phishing_army', 'Phishing Army', 'S, phishing'),
  _AdblockFeedOption('smarttv_tracking', 'Smart TV Tracking', 'S, tracking'),
  _AdblockFeedOption('stevenblack', 'StevenBlack', 'VAR, compilation'),
  _AdblockFeedOption('winspy', 'WinSpy', 'S, telemetry'),
  _AdblockFeedOption('yoyo', 'Yoyo', 'S, general'),
];

class _AdblockFeedOption {
  final String id;
  final String label;
  final String detail;

  const _AdblockFeedOption(this.id, this.label, this.detail);
}

class AdblockScreen extends ConsumerStatefulWidget {
  const AdblockScreen({super.key});

  @override
  ConsumerState<AdblockScreen> createState() => _AdblockScreenState();
}

class _AdblockScreenState extends ConsumerState<AdblockScreen> {
  OpenwrtAdblockSettings? _settings;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasStartedLoad = false;
  String? _error;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final settings = await ref
          .read(appStateProvider)
          .fetchAdblockSettings(context: context);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load AdBlock settings.';
        _isLoading = false;
      });
    }
  }

  void _update(OpenwrtAdblockSettings settings) {
    setState(() => _settings = settings);
  }

  Future<void> _save() async {
    final settings = _settings;
    if (settings == null) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(appStateProvider).saveAdblockSettings(settings);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('AdBlock settings saved.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save AdBlock: $e')));
      setState(() => _isSaving = false);
    }
  }

  Future<void> _runAction(String action) async {
    setState(() => _isSaving = true);
    try {
      await ref.read(appStateProvider).runAdblockServiceAction(action);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AdBlock $action requested.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to run AdBlock action: $e')),
      );
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = _settings;

    return Scaffold(
      appBar: const LuciAppBar(title: 'AdBlock', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                'DNS-Based AdBlock',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage OpenWrt adblock service settings and runtime actions.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 18),
              OpenwrtFeatureGate(
                feature: OpenwrtFeature.adblock,
                title: 'AdBlock is not installed',
                message:
                    'Install the OpenWrt adblock package before managing DNS blocklists and AdBlock service actions.',
                installLabel: 'Install AdBlock',
                builder: (_) => _buildInstalledContent(settings),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstalledContent(OpenwrtAdblockSettings? settings) {
    if (!_hasStartedLoad) {
      _hasStartedLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _AdblockEmptyCard(message: _error!, onRefresh: _load);
    }
    if (settings == null) return const SizedBox.shrink();
    return _AdblockEditor(
      settings: settings,
      isSaving: _isSaving,
      onChanged: _update,
      onSave: _save,
      onAction: _runAction,
    );
  }
}

class _AdblockEditor extends StatelessWidget {
  final OpenwrtAdblockSettings settings;
  final bool isSaving;
  final ValueChanged<OpenwrtAdblockSettings> onChanged;
  final VoidCallback onSave;
  final ValueChanged<String> onAction;

  const _AdblockEditor({
    required this.settings,
    required this.isSaving,
    required this.onChanged,
    required this.onSave,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = settings.installed
        ? colorScheme.primary
        : colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AdblockSectionCard(
          title: 'Feeds',
          icon: Icons.playlist_add_check_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select the blocklists AdBlock should use. Smaller default feeds are easier on low-memory routers.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _adblockFeedOptions.map((feed) {
                  final selected = settings.selectedFeeds.contains(feed.id);
                  return FilterChip(
                    selected: selected,
                    label: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(feed.label),
                        Text(
                          feed.detail,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: selected
                                    ? colorScheme.onSecondaryContainer
                                    : colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                        ),
                      ],
                    ),
                    onSelected: isSaving
                        ? null
                        : (value) {
                            final next = [...settings.selectedFeeds];
                            if (value) {
                              if (!next.contains(feed.id)) next.add(feed.id);
                            } else {
                              next.remove(feed.id);
                            }
                            onChanged(settings.copyWith(selectedFeeds: next));
                          },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _AdblockSectionCard(
          title: 'Settings',
          icon: Icons.tune_rounded,
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable SafeSearch'),
                subtitle: const Text(
                  'Apply safe search rules where supported.',
                ),
                value: settings.safeSearch,
                onChanged: isSaving
                    ? null
                    : (value) =>
                          onChanged(settings.copyWith(safeSearch: value)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: settings.triggerInterface,
                enabled: !isSaving,
                decoration: const InputDecoration(
                  labelText: 'Startup trigger interface',
                  hintText: 'wan',
                ),
                onChanged: (value) =>
                    onChanged(settings.copyWith(triggerInterface: value)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: isSaving ? null : onSave,
                icon: isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(isSaving ? 'Saving' : 'Save'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _AdblockSectionCard(
          title: 'Service Controls',
          icon: Icons.settings_power_rounded,
          initiallyExpanded: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.block_rounded, color: statusColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          settings.installed
                              ? 'AdBlock installed'
                              : 'Not installed',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          settings.serviceStatus,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable AdBlock service'),
                value: settings.enabled,
                onChanged: isSaving
                    ? null
                    : (value) => onChanged(settings.copyWith(enabled: value)),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: isSaving ? null : onSave,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save Service Settings'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ActionChipButton(
                    label: 'Start',
                    enabled: !isSaving,
                    onTap: () => onAction('start'),
                  ),
                  _ActionChipButton(
                    label: 'Stop',
                    enabled: !isSaving,
                    onTap: () => onAction('stop'),
                  ),
                  _ActionChipButton(
                    label: 'Reload',
                    enabled: !isSaving,
                    onTap: () => onAction('reload'),
                  ),
                  _ActionChipButton(
                    label: 'Restart',
                    enabled: !isSaving,
                    onTap: () => onAction('restart'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdblockSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  const _AdblockSectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.initiallyExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: initiallyExpanded
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: colorScheme.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  child,
                ],
              ),
            )
          : Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                leading: Icon(icon, color: colorScheme.primary, size: 22),
                title: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                children: [child],
              ),
            ),
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionChipButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: enabled ? onTap : null,
      avatar: const Icon(Icons.terminal_rounded, size: 18),
    );
  }
}

class _AdblockEmptyCard extends StatelessWidget {
  final String message;
  final Future<void> Function() onRefresh;

  const _AdblockEmptyCard({required this.message, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}
