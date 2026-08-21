import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/dashboard_preferences.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

class RouterSetupScreen extends ConsumerStatefulWidget {
  const RouterSetupScreen({super.key});

  @override
  ConsumerState<RouterSetupScreen> createState() => _RouterSetupScreenState();
}

class _RouterSetupScreenState extends ConsumerState<RouterSetupScreen> {
  static const _rawSetupBase =
      'https://raw.githubusercontent.com/benisai/luci-mobile-apk/main/openwrt-setup';

  static const _standardInstaller = 'install-standard-apps.sh';
  static const _defaultScriptInstallers = [
    'install-usage-monitoring.sh',
    'install-ping-monitor.sh',
    'install-dns-monitor.sh',
    'install-speedtest-monitor.sh',
    'install-notifications-db.sh',
    'install-devices-collector.sh',
    'install-device-bandwidth.sh',
    'install-internet-blocking.sh',
    'install-state-sync.sh',
    'install-conntrack.sh',
  ];

  int _wizardStep = 0;
  bool _installAdblock = false;
  bool _installQosScripts = false;
  bool _installNetify = false;
  bool _installBanip = false;
  bool _installPbr = false;
  bool _isInstalling = false;
  bool _showDetails = false;
  String? _lastOutput;

  List<String> get _extraInstallers {
    return [
      if (_installAdblock) 'install-adblock.sh',
      if (_installQosScripts) 'install-qos-scripts.sh',
      if (_installNetify) 'install-netify.sh',
      if (_installBanip) 'install-banip.sh',
      if (_installPbr) 'install-pbr.sh',
    ];
  }

  List<String> get _selectedInstallers {
    return [
      _standardInstaller,
      ..._extraInstallers,
      ..._defaultScriptInstallers,
    ];
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
      _lastOutput =
          'Connecting to router...\nRunning Openwalla setup command...\n\nOutput will appear here when the router returns console data.';
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
        _lastOutput = output.trim().isEmpty
            ? 'Setup finished. The router did not return console output.'
            : output.trim();
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
    final prefs = appState.dashboardPreferences.copyWith(
      showNetworkPerformanceCard: true,
      showUsageCard: true,
      showMonthlyUsageCard: true,
      showFlowsCard: true,
      flowMode: _installNetify
          ? DashboardFlowMode.detailed
          : DashboardFlowMode.simple,
    );

    await appState.saveDashboardPreferences(prefs);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _nextStep() {
    if (_wizardStep < 4) setState(() => _wizardStep += 1);
  }

  void _previousStep() {
    if (_wizardStep > 0) setState(() => _wizardStep -= 1);
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
            _WizardProgress(currentStep: _wizardStep, totalSteps: 5),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey(_wizardStep),
                child: _buildWizardStep(theme, colorScheme),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (_wizardStep > 0)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isInstalling ? null : _previousStep,
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Back'),
                    ),
                  ),
                if (_wizardStep > 0) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isInstalling
                        ? null
                        : _wizardStep == 4
                        ? _runSetup
                        : _nextStep,
                    icon: _isInstalling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _wizardStep == 4
                                ? Icons.verified_user_outlined
                                : Icons.arrow_forward_rounded,
                          ),
                    label: Text(
                      _isInstalling
                          ? 'Installing'
                          : _wizardStep == 4
                          ? 'Run From App'
                          : 'Next',
                    ),
                  ),
                ),
              ],
            ),
            if (_wizardStep == 4) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: _isInstalling ? null : _copyCommand,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy SSH Command'),
                ),
              ),
            ],
            if (_wizardStep == 4) ...[
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
              if (_lastOutput != null) ...[
                const SizedBox(height: 16),
                _OutputPreview(output: _lastOutput!, isRunning: _isInstalling),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWizardStep(ThemeData theme, ColorScheme colorScheme) {
    switch (_wizardStep) {
      case 0:
        return _WizardIntroCard(
          title: 'Welcome to Openwalla Router Setup',
          subtitle:
              'This wizard installs the OpenWrt packages and Openwalla helper scripts needed for dashboard monitoring, device inventory, usage, notifications, and router controls.',
          icon: Icons.router_rounded,
        );
      case 1:
        return _SetupFeatureCard(
          icon: Icons.inventory_2_outlined,
          title: 'Installing standard OpenWrt applications',
          subtitle:
              'uhttpd-mod-ubus, nlbwmon, vnstat2, sqlite3-cli, conntrack, and qrencode.',
          child: const _InstallerList(
            items: [
              'uhttpd-mod-ubus',
              'Nlbwmon',
              'Vnstat2',
              'sqlite3-cli',
              'conntrack',
              'qrencode',
            ],
          ),
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Would you like to install extra software?',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Make a selection now. These are optional packages and can be installed later.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            _ExtraSoftwareTile(
              icon: Icons.block_rounded,
              title: 'AdBlock',
              subtitle: 'DNS-based ad and tracker blocking.',
              value: _installAdblock,
              enabled: !_isInstalling,
              onChanged: (value) => setState(() => _installAdblock = value),
            ),
            _ExtraSoftwareTile(
              icon: Icons.speed_rounded,
              title: 'qos-scripts',
              subtitle: 'QoS/SQM packages for traffic shaping.',
              value: _installQosScripts,
              enabled: !_isInstalling,
              onChanged: (value) => setState(() => _installQosScripts = value),
            ),
            _ExtraSoftwareTile(
              icon: Icons.account_tree_rounded,
              title: 'netify',
              subtitle: 'Detailed flow data when the router supports it.',
              value: _installNetify,
              enabled: !_isInstalling,
              onChanged: (value) => setState(() => _installNetify = value),
            ),
            _ExtraSoftwareTile(
              icon: Icons.shield_outlined,
              title: 'banip',
              subtitle: 'OpenWrt IP blocklist support.',
              value: _installBanip,
              enabled: !_isInstalling,
              onChanged: (value) => setState(() => _installBanip = value),
            ),
            _ExtraSoftwareTile(
              icon: Icons.alt_route_rounded,
              title: 'pbr',
              subtitle: 'Policy-based routing package support.',
              value: _installPbr,
              enabled: !_isInstalling,
              onChanged: (value) => setState(() => _installPbr = value),
            ),
          ],
        );
      case 3:
        return _SetupFeatureCard(
          icon: Icons.monitor_heart_outlined,
          title: 'Installing default Openwalla scripts',
          subtitle:
              'The app downloads only the needed installers with wget, then each installer fetches its own files.',
          child: const _InstallerList(
            items: [
              'Ping Test',
              'DNS Test',
              'Speedtest',
              'Notifications',
              'Devices',
              'Device Bandwidth',
              'Internet Blocking',
              'sync/backup',
              'Simple Conntrack Flows',
            ],
          ),
        );
      default:
        return _SetupPermissionCard(
          isInstalling: _isInstalling,
          extraSoftware: _extraInstallers.length,
          scriptCount: _defaultScriptInstallers.length,
          onToggleDetails: () => setState(() => _showDetails = true),
        );
    }
  }
}

class _SetupPermissionCard extends StatelessWidget {
  final bool isInstalling;
  final int extraSoftware;
  final int scriptCount;
  final VoidCallback onToggleDetails;

  const _SetupPermissionCard({
    required this.isInstalling,
    required this.extraSoftware,
    required this.scriptCount,
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
              'Openwalla needs permission to install the selected packages and helper scripts on your router.',
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
                    icon: Icons.inventory_2_outlined,
                    text: 'Install standard OpenWrt application packages.',
                  ),
                  SizedBox(height: 10),
                  _PermissionLine(
                    icon: Icons.extension_outlined,
                    text: 'Install selected optional software packages.',
                  ),
                  SizedBox(height: 10),
                  _PermissionLine(
                    icon: Icons.monitor_heart_outlined,
                    text: 'Install default Openwalla monitoring scripts.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Selected: $extraSoftware extra software option${extraSoftware == 1 ? '' : 's'} and $scriptCount Openwalla script installers.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
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
          ],
        ),
      ),
    );
  }
}

class _WizardProgress extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _WizardProgress({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(totalSteps, (index) {
        final active = index <= currentStep;
        return Expanded(
          child: Container(
            height: 5,
            margin: EdgeInsets.only(right: index == totalSteps - 1 ? 0 : 6),
            decoration: BoxDecoration(
              color: active
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }
}

class _WizardIntroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _WizardIntroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: colorScheme.primary, size: 28),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstallerList extends StatelessWidget {
  final List<String> items;

  const _InstallerList({required this.items});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (item) => Chip(
              avatar: Icon(
                Icons.check_circle_outline_rounded,
                size: 17,
                color: colorScheme.primary,
              ),
              label: Text(item),
            ),
          )
          .toList(),
    );
  }
}

class _ExtraSoftwareTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ExtraSoftwareTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: CheckboxListTile(
        value: value,
        onChanged: enabled ? (value) => onChanged(value ?? false) : null,
        controlAffinity: ListTileControlAffinity.trailing,
        secondary: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: colorScheme.primary),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
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
  final Widget? child;

  const _SetupFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
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
  final bool isRunning;

  const _OutputPreview({required this.output, required this.isRunning});

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
              isRunning ? 'SSH Console Running' : 'SSH Console Output',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (isRunning) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                minHeight: 3,
                borderRadius: BorderRadius.circular(999),
              ),
            ],
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
