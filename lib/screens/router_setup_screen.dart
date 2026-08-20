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
  bool _showDetails = false;
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
        _showDetails = true;
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
            const SizedBox(height: 18),
            _SetupPermissionCard(
              isInstalling: _isInstalling,
              onRunSetup: _runSetup,
              onCopyCommand: _copyCommand,
              onToggleDetails: () => setState(() => _showDetails = true),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: () => setState(() => _showDetails = !_showDetails),
                icon: Icon(
                  _showDetails
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
                label: Text(_showDetails ? 'Hide Details' : 'Show Details'),
              ),
            ),
            if (_showDetails) ...[
              const SizedBox(height: 8),
              _CommandPreview(command: command),
            ],
            if (_showDetails && _lastOutput != null) ...[
              const SizedBox(height: 16),
              _OutputPreview(output: _lastOutput!),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetupPermissionCard extends StatelessWidget {
  final bool isInstalling;
  final VoidCallback onRunSetup;
  final VoidCallback onCopyCommand;
  final VoidCallback onToggleDetails;

  const _SetupPermissionCard({
    required this.isInstalling,
    required this.onRunSetup,
    required this.onCopyCommand,
    required this.onToggleDetails,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const actionBlue = Color(0xFF2563EB);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: actionBlue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: actionBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Router access required',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Openwalla needs permission to install the selected helper scripts on your router.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest.withValues(
                  alpha: 0.42,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.18),
                ),
              ),
              child: const Column(
                children: [
                  _PermissionLine(
                    icon: Icons.monitor_heart_outlined,
                    text:
                        'Install monitoring, usage, and notification helpers.',
                  ),
                  SizedBox(height: 10),
                  _PermissionLine(
                    icon: Icons.account_tree_outlined,
                    text: 'Enable selected flow collection mode.',
                  ),
                  SizedBox(height: 10),
                  _PermissionLine(
                    icon: Icons.security_outlined,
                    text: 'Initialize firewall and quarantine helpers.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                Text(
                  'Want to inspect the SSH fallback?',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton(
                  onPressed: onToggleDetails,
                  child: const Text('Show details'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: FilledButton.icon(
                onPressed: isInstalling ? null : onRunSetup,
                icon: isInstalling
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_user_outlined),
                label: Text(isInstalling ? 'Installing' : 'Run From App'),
                style: FilledButton.styleFrom(
                  backgroundColor: actionBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: isInstalling ? null : onCopyCommand,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy SSH Command'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PermissionLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const actionBlue = Color(0xFF2563EB);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: actionBlue, size: 17),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
              height: 1.28,
            ),
          ),
        ),
      ],
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
