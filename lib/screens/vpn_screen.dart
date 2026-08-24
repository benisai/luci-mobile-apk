import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

enum _VpnPanel { server, client }

class VpnScreen extends ConsumerStatefulWidget {
  const VpnScreen({super.key});

  @override
  ConsumerState<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends ConsumerState<VpnScreen> {
  _VpnPanel _panel = _VpnPanel.server;
  WireGuardServerSettings _settings = WireGuardServerSettings.defaults;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  final _portController = TextEditingController(text: '51820');
  final _vpnAddressController = TextEditingController(text: '10.8.0.1/24');
  final _internalIpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _portController.dispose();
    _vpnAddressController.dispose();
    _internalIpController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final settings = await ref
          .read(appStateProvider)
          .fetchWireGuardServerSettings(context: context);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _portController.text = settings.listenPort.toString();
        _vpnAddressController.text = settings.vpnAddress;
        _internalIpController.text = settings.internalIpAddress;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load WireGuard server settings.';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveServer() async {
    final port = int.tryParse(_portController.text.trim());
    final vpnAddress = _vpnAddressController.text.trim();
    final internalIp = _internalIpController.text.trim();

    if (port == null || port < 1 || port > 65535) {
      _showSnack('Enter a UDP port between 1 and 65535.');
      return;
    }
    if (!_looksLikeCidr(vpnAddress)) {
      _showSnack('Enter the VPN address as CIDR, like 10.8.0.1/24.');
      return;
    }
    if (internalIp.isNotEmpty && !_looksLikeIpv4(internalIp)) {
      _showSnack('Enter a valid internal IPv4 address or leave it blank.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final updated = WireGuardServerSettings(
        installed: _settings.installed,
        configured: _settings.configured,
        enabled: _settings.enabled,
        interfaceName: _settings.interfaceName,
        listenPort: port,
        vpnAddress: vpnAddress,
        internalIpAddress: internalIp,
        publicKey: _settings.publicKey,
      );
      await ref
          .read(appStateProvider)
          .saveWireGuardServerSettings(updated, context: context);
      if (!mounted) return;
      _showSnack('WireGuard server settings saved.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to save WireGuard server: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool _looksLikeIpv4(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      final number = int.tryParse(part);
      return number != null && number >= 0 && number <= 255;
    });
  }

  bool _looksLikeCidr(String value) {
    final parts = value.split('/');
    if (parts.length != 2 || !_looksLikeIpv4(parts[0])) return false;
    final prefix = int.tryParse(parts[1]);
    return prefix != null && prefix >= 1 && prefix <= 32;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _updateEnabled(bool enabled) {
    setState(() {
      _settings = WireGuardServerSettings(
        installed: _settings.installed,
        configured: _settings.configured,
        enabled: enabled,
        interfaceName: _settings.interfaceName,
        listenPort: _settings.listenPort,
        vpnAddress: _settings.vpnAddress,
        internalIpAddress: _settings.internalIpAddress,
        publicKey: _settings.publicKey,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const LuciAppBar(title: 'VPN', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                'WireGuard VPN',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Configure WireGuard server access on this router.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<_VpnPanel>(
                segments: const [
                  ButtonSegment(
                    value: _VpnPanel.server,
                    label: Text('Server'),
                    icon: Icon(Icons.dns_rounded),
                  ),
                  ButtonSegment(
                    value: _VpnPanel.client,
                    label: Text('Client'),
                    icon: Icon(Icons.vpn_lock_rounded),
                  ),
                ],
                selected: {_panel},
                onSelectionChanged: (selection) {
                  setState(() => _panel = selection.first);
                },
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _VpnPanelCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_error!, style: TextStyle(color: colorScheme.error)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (_panel == _VpnPanel.server)
                _buildServerPanel()
              else
                _buildClientPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    return _VpnPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'WireGuard Server',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              _StatusPill(
                label: _settings.configured ? 'Configured' : 'Not configured',
                color: _settings.configured
                    ? const Color(0xFF20CF70)
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!_settings.installed)
            _WarningBox(
              message:
                  'wireguard-tools is not installed. Install it from Router Setup or opkg before saving.',
            ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable Server'),
            subtitle: Text(_settings.interfaceName),
            value: _settings.enabled,
            onChanged: _isSaving ? null : _updateEnabled,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: 'Listen Port',
              helperText: 'The UDP port exposed on WAN.',
              prefixIcon: Icon(Icons.settings_ethernet_rounded),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            enabled: !_isSaving,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _internalIpController,
            decoration: const InputDecoration(
              labelText: 'Internal IP Address',
              helperText: 'Defaults to the WAN IPv4 address for this router.',
              prefixIcon: Icon(Icons.router_rounded),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            enabled: !_isSaving,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _vpnAddressController,
            decoration: const InputDecoration(
              labelText: 'VPN Address',
              helperText: 'Server tunnel address, for example 10.8.0.1/24.',
              prefixIcon: Icon(Icons.vpn_key_rounded),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.text,
            enabled: !_isSaving,
          ),
          const SizedBox(height: 14),
          _DetailRow(label: 'Firewall rule', value: 'owrt_wireguard_server'),
          _DetailRow(label: 'Public key', value: _settings.publicKey),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _saveServer,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_isSaving ? 'Saving' : 'Save Server'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientPanel() {
    return const _VpnPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WireGuard Client',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 8),
          Text('Client mode will be added next.'),
        ],
      ),
    );
  }
}

class _VpnPanelCard extends StatelessWidget {
  final Widget child;

  const _VpnPanelCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: child,
    );
  }
}

class _WarningBox extends StatelessWidget {
  final String message;

  const _WarningBox({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colorScheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 98,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
