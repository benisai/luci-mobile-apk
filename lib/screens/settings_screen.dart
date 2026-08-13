import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/screens/dashboard_settings_list_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSettingsCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: colorScheme.onPrimaryContainer, size: 24),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
    );
  }

  void _openSettingsPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => page));
  }

  void _showReviewerModeResetDialog(BuildContext context, WidgetRef ref) {
    final appState = ref.read(appStateProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Reviewer Mode?'),
        content: const Text(
          'This will disable reviewer mode and return to normal authentication. '
          'You will need to log in with real router credentials.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await appState.setReviewerMode(false);
              appState.logout();
              if (context.mounted) {
                unawaited(
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/login', (route) => false),
                );
              }
            },
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Settings', showBack: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        children: [
          Builder(
            builder: (context) {
              final appState = ref.watch(appStateProvider);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(context, 'Theme'),
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: RadioGroup<ThemeMode>(
                      groupValue: appState.themeMode,
                      onChanged: (mode) {
                        if (mode != null) appState.setThemeMode(mode);
                      },
                      child: const Column(
                        children: [
                          RadioListTile<ThemeMode>(
                            title: Text('System Default'),
                            value: ThemeMode.system,
                          ),
                          RadioListTile<ThemeMode>(
                            title: Text('Light'),
                            value: ThemeMode.light,
                          ),
                          RadioListTile<ThemeMode>(
                            title: Text('Dark'),
                            value: ThemeMode.dark,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 32),
                  _buildSectionTitle(context, 'Dashboard'),
                  _buildSettingsCard(
                    context: context,
                    icon: Icons.dashboard_customize,
                    title: 'Customize Dashboard',
                    subtitle:
                        'Configure interface visibility and throughput monitoring',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              const DashboardSettingsListScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 32),
                  _buildSectionTitle(context, 'Monitoring'),
                  _buildSettingsCard(
                    context: context,
                    icon: Icons.network_ping_rounded,
                    title: 'Ping Settings',
                    subtitle:
                        'Configure latency monitoring and alert thresholds',
                    onTap: () =>
                        _openSettingsPage(context, const _PingSettingsScreen()),
                  ),
                  _buildSettingsCard(
                    context: context,
                    icon: Icons.speed_rounded,
                    title: 'Speedtest Settings',
                    subtitle: 'Configure scheduled speed tests',
                    onTap: () => _openSettingsPage(
                      context,
                      const _SpeedtestSettingsScreen(),
                    ),
                  ),
                  _buildSettingsCard(
                    context: context,
                    icon: Icons.bar_chart_rounded,
                    title: 'Monthly Usage',
                    subtitle: 'Configure monthly usage tracking',
                    onTap: () => _openSettingsPage(
                      context,
                      const _MonthlyUsageSettingsScreen(),
                    ),
                  ),
                  if (appState.reviewerModeEnabled) ...[
                    const Divider(height: 32),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        'Reviewer Mode',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.info_outline,
                        color: Colors.orange,
                      ),
                      title: const Text('Reviewer Mode Active'),
                      subtitle: Text(
                        'Mock data is being used for demonstration',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: FilledButton.icon(
                        onPressed: () =>
                            _showReviewerModeResetDialog(context, ref),
                        icon: const Icon(Icons.exit_to_app),
                        label: const Text('Exit Reviewer Mode'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onError,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PingSettingsScreen extends ConsumerStatefulWidget {
  const _PingSettingsScreen();

  @override
  ConsumerState<_PingSettingsScreen> createState() =>
      _PingSettingsScreenState();
}

class _PingSettingsScreenState extends ConsumerState<_PingSettingsScreen> {
  final _targetController = TextEditingController(text: '1.1.1.1');
  final _thresholdController = TextEditingController(text: '100');
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  @override
  void dispose() {
    _targetController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final appState = ref.read(appStateProvider);
    final settings = await appState.fetchPingMonitorSettings(context: context);
    if (!mounted) return;

    _targetController.text = settings.target;
    _thresholdController.text = settings.thresholdMs.toString();
    setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    final target = _targetController.text.trim();
    final threshold = int.tryParse(_thresholdController.text.trim());

    if (target.isEmpty || threshold == null || threshold <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a target and a threshold greater than 0ms.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .savePingMonitorSettings(
            PingMonitorSettings(target: target, thresholdMs: threshold),
            context: context,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ping monitor settings saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save ping settings: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Ping Settings', showBack: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SettingsFormCard(
                  children: [
                    TextField(
                      controller: _targetController,
                      decoration: const InputDecoration(
                        labelText: 'Target',
                        hintText: '1.1.1.1',
                        prefixIcon: Icon(Icons.public_rounded),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      enabled: !_isSaving,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _thresholdController,
                      decoration: const InputDecoration(
                        labelText: 'Alert Threshold',
                        suffixText: 'ms',
                        prefixIcon: Icon(Icons.notifications_active_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !_isSaving,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveSettings,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(_isSaving ? 'Saving' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _SpeedtestSettingsScreen extends ConsumerStatefulWidget {
  const _SpeedtestSettingsScreen();

  @override
  ConsumerState<_SpeedtestSettingsScreen> createState() =>
      _SpeedtestSettingsScreenState();
}

class _SpeedtestSettingsScreenState
    extends ConsumerState<_SpeedtestSettingsScreen> {
  bool _enabled = true;
  bool _isLoading = true;
  bool _isSaving = false;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = const TimeOfDay(hour: 3, minute: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final settings = await ref
        .read(appStateProvider)
        .fetchSpeedtestMonitorSettings(context: context);
    if (!mounted) return;

    setState(() {
      _enabled = settings.enabled;
      _selectedDate = settings.runDate ?? DateTime.now();
      _selectedTime = TimeOfDay(
        hour: settings.runHour,
        minute: settings.runMinute,
      );
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .saveSpeedtestMonitorSettings(
            SpeedtestMonitorSettings(
              enabled: _enabled,
              runDate: _selectedDate,
              runHour: _selectedTime.hour,
              runMinute: _selectedTime.minute,
            ),
            context: context,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speedtest settings saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save speedtest settings: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _selectDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (pickedDate != null && mounted) {
      setState(() => _selectedDate = pickedDate);
    }
  }

  Future<void> _selectTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );

    if (pickedTime != null && mounted) {
      setState(() => _selectedTime = pickedTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Speedtest Settings', showBack: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SettingsFormCard(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Scheduled Speedtest'),
                      subtitle: Text(_enabled ? 'Enabled' : 'Disabled'),
                      value: _enabled,
                      onChanged: _isSaving
                          ? null
                          : (value) => setState(() => _enabled = value),
                    ),
                    const Divider(height: 24),
                    _PickerTile(
                      icon: Icons.calendar_month_rounded,
                      title: 'Date',
                      value: _formatDate(_selectedDate),
                      onTap: _isSaving ? null : _selectDate,
                    ),
                    _PickerTile(
                      icon: Icons.schedule_rounded,
                      title: 'Time',
                      value: _selectedTime.format(context),
                      onTap: _isSaving ? null : _selectTime,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveSettings,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(_isSaving ? 'Saving' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _MonthlyUsageSettingsScreen extends ConsumerStatefulWidget {
  const _MonthlyUsageSettingsScreen();

  @override
  ConsumerState<_MonthlyUsageSettingsScreen> createState() =>
      _MonthlyUsageSettingsScreenState();
}

class _MonthlyUsageSettingsScreenState
    extends ConsumerState<_MonthlyUsageSettingsScreen> {
  static const _defaultInterface = 'br-lan';
  var _interfaces = const ['br-lan', 'wan', 'eth0', 'eth1'];
  DateTime _startDate = DateTime.now();
  String _selectedInterface = _defaultInterface;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final appState = ref.read(appStateProvider);
    final settings = await appState.fetchMonthlyUsageSettings(context: context);
    final interfaces = appState.dashboardInterfaceNames();
    if (!mounted) return;

    setState(() {
      _interfaces = interfaces.contains(settings.interfaceName)
          ? interfaces
          : [...interfaces, settings.interfaceName];
      _selectedInterface = settings.interfaceName;
      final now = DateTime.now();
      final safeDay = settings.monthStartDay.clamp(1, 28);
      _startDate = DateTime(now.year, now.month, safeDay);
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .saveMonthlyUsageSettings(
            MonthlyUsageSettings(
              monthStartDay: _startDate.day,
              interfaceName: _selectedInterface,
            ),
            context: context,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Monthly usage settings saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save monthly usage settings: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _selectStartDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 1),
    );

    if (pickedDate != null && mounted) {
      setState(() => _startDate = pickedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Monthly Usage', showBack: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SettingsFormCard(
                  children: [
                    _PickerTile(
                      icon: Icons.event_available_rounded,
                      title: 'Start Date',
                      value: _formatDate(_startDate),
                      onTap: _isSaving ? null : _selectStartDate,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedInterface,
                      decoration: const InputDecoration(
                        labelText: 'Interface',
                        prefixIcon: Icon(Icons.settings_ethernet_rounded),
                        border: OutlineInputBorder(),
                      ),
                      items: _interfaces
                          .map(
                            (interface) => DropdownMenuItem(
                              value: interface,
                              child: Text(interface),
                            ),
                          )
                          .toList(),
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _selectedInterface = value);
                              }
                            },
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveSettings,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(_isSaving ? 'Saving' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _SettingsFormCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsFormCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  const _PickerTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: colorScheme.primary),
      title: Text(title),
      subtitle: Text(value),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
