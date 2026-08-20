import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/dashboard_preferences.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

enum _SetupFlowChoice { none, simple, detailed }

class RouterSetupScreen extends ConsumerStatefulWidget {
  const RouterSetupScreen({super.key});

  @override
  ConsumerState<RouterSetupScreen> createState() => _RouterSetupScreenState();
}

class _RouterSetupScreenState extends ConsumerState<RouterSetupScreen> {
  static const _rawSetupBase =
      'https://raw.githubusercontent.com/benisai/luci-mobile-apk/main/openwrt-setup';

  bool _installMonitoring = true;
  bool _installQuarantine = false;
  bool _isInstalling = false;
  _SetupFlowChoice _flowChoice = _SetupFlowChoice.none;
  String? _lastOutput;

  List<String> get _selectedInstallers {
    final installers = <String>[];
    if (_installMonitoring) {
      installers.addAll([
        'install-usage-monitoring.sh',
        'install-ping-monitor.sh',
        'install-dns-monitor.sh',
        'install-speedtest-monitor.sh',
        'install-notifications-db.sh',
        'install-devices-collector.sh',
        'install-device-bandwidth.sh',
        'install-internet-blocking.sh',
        'install-state-sync.sh',
      ]);
    }
    switch (_flowChoice) {
      case _SetupFlowChoice.simple:
        installers.add('install-conntrack.sh');
        break;
      case _SetupFlowChoice.detailed:
        installers.add('install-netify.sh');
        break;
      case _SetupFlowChoice.none:
        break;
    }
    if (_installQuarantine) installers.add('install-quarantine.sh');
    return installers;
  }

  String get _setupCommand {
    final installers = _selectedInstallers;
    final installerFetches = installers
        .map(
          (installer) =>
              'fetch "\$OPENWALLA_RAW_BASE/standalone/$installer" "$installer"',
        )
        .join(' && ');
    final installSteps = installers
        .map((installer) => 'sh $installer')
        .join(' && ');
    if (installSteps.isEmpty) return '';

    return [
      'export OPENWALLA_RAW_BASE=$_rawSetupBase',
      'fetch() { if command -v wget >/dev/null 2>&1; then wget -qO "\$2" "\$1"; else curl -fsSL "\$1" -o "\$2"; fi; }',
      'cd /tmp',
      'rm -rf openwalla-app-setup',
      'mkdir -p openwalla-app-setup/lib openwalla-app-setup/files',
      'cd openwalla-app-setup',
      'fetch "\$OPENWALLA_RAW_BASE/standalone/lib/openwalla-standalone-common.sh" "lib/openwalla-standalone-common.sh"',
      installerFetches,
      installSteps,
    ].join(' && ');
  }

  Future<void> _copyCommand() async {
    final command = _setupCommand;
    if (command.isEmpty) {
      _showSnack('Choose at least one setup option first.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: command));
    if (!mounted) return;
    _showSnack('Router setup command copied.');
  }

  Future<void> _runSetup() async {
    final command = _setupCommand;
    if (command.isEmpty) {
      _showSnack('Choose at least one setup option first.');
      return;
    }

    setState(() {
      _isInstalling = true;
      _lastOutput = null;
    });

    try {
      final appState = ref.read(appStateProvider);
      final output = await appState.runRouterSetupCommand(
        command,
        context: context,
      );
      await _enableDashboardCardsForInstalledFeatures();
      if (!mounted) return;
      setState(() {
        _lastOutput = output.trim().isEmpty ? 'Setup finished.' : output.trim();
      });
      _showSnack('Router setup finished.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastOutput =
            'App install failed. This router may not allow setup commands until the Openwalla rpcd ACL is installed. Copy the SSH command below and run it as root.\n\n$e';
      });
      _showSnack('Router setup could not run from the app.');
    } finally {
      if (mounted) setState(() => _isInstalling = false);
    }
  }

  Future<void> _enableDashboardCardsForInstalledFeatures() async {
    final appState = ref.read(appStateProvider);
    var prefs = appState.dashboardPreferences;

    if (_installMonitoring) {
      prefs = prefs.copyWith(
        showNetworkPerformanceCard: true,
        showUsageCard: true,
        showMonthlyUsageCard: true,
      );
    }
    switch (_flowChoice) {
      case _SetupFlowChoice.simple:
        prefs = prefs.copyWith(
          showFlowsCard: true,
          flowMode: DashboardFlowMode.simple,
        );
        break;
      case _SetupFlowChoice.detailed:
        prefs = prefs.copyWith(
          showFlowsCard: true,
          flowMode: DashboardFlowMode.detailed,
        );
        break;
      case _SetupFlowChoice.none:
        break;
    }

    await appState.saveDashboardPreferences(prefs);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final command = _setupCommand;

    return Scaffold(
      appBar: const LuciAppBar(title: 'Router Setup', showBack: true),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Text(
              'Install only the Openwalla router helpers you want. Fresh routers start with these tools off in the app until setup runs.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _SetupFeatureCard(
              icon: Icons.monitor_heart_outlined,
              title: 'Monitoring Tools',
              subtitle:
                  'Ping, DNS, speedtest, vnStat/nlbwmon, notifications, devices, usage, and internet blocking helpers.',
              trailing: Switch.adaptive(
                value: _installMonitoring,
                onChanged: _isInstalling
                    ? null
                    : (value) => setState(() => _installMonitoring = value),
              ),
            ),
            const SizedBox(height: 12),
            _SetupFeatureCard(
              icon: Icons.account_tree_outlined,
              title: 'Flows',
              subtitle:
                  'Choose Netify for richer flow detail or Conntrack for wider router support.',
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SegmentedButton<_SetupFlowChoice>(
                  segments: const [
                    ButtonSegment(
                      value: _SetupFlowChoice.none,
                      label: Text('Off'),
                    ),
                    ButtonSegment(
                      value: _SetupFlowChoice.simple,
                      label: Text('Simple'),
                    ),
                    ButtonSegment(
                      value: _SetupFlowChoice.detailed,
                      label: Text('Detailed'),
                    ),
                  ],
                  selected: {_flowChoice},
                  showSelectedIcon: false,
                  onSelectionChanged: _isInstalling
                      ? null
                      : (values) => setState(() => _flowChoice = values.single),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _SetupFeatureCard(
              icon: Icons.security_outlined,
              title: 'Quarantine',
              subtitle:
                  'Install the quarantine service for blocking newly discovered devices.',
              trailing: Switch.adaptive(
                value: _installQuarantine,
                onChanged: _isInstalling
                    ? null
                    : (value) => setState(() => _installQuarantine = value),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isInstalling ? null : _copyCommand,
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy SSH Command'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isInstalling ? null : _runSetup,
                    icon: _isInstalling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(_isInstalling ? 'Installing' : 'Run From App'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _CommandPreview(command: command),
            if (_lastOutput != null) ...[
              const SizedBox(height: 16),
              _OutputPreview(output: _lastOutput!),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetupFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? child;

  const _SetupFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            if (child != null) ...[const SizedBox(height: 8), child!],
          ],
        ),
      ),
    );
  }
}

class _CommandPreview extends StatelessWidget {
  final String command;

  const _CommandPreview({required this.command});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'SSH Command',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            SelectableText(
              command.isEmpty ? 'Choose at least one setup option.' : command,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutputPreview extends StatelessWidget {
  final String output;

  const _OutputPreview({required this.output});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Setup Output',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            SelectableText(
              output,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
