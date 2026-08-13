import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

class FlowsScreen extends ConsumerStatefulWidget {
  const FlowsScreen({super.key});

  @override
  ConsumerState<FlowsScreen> createState() => _FlowsScreenState();
}

class _FlowItem {
  final String time;
  final String destination;
  final String country;
  final bool blocked;
  final String deviceName;
  final String deviceGroup;
  final String deviceIp;
  final String devicePort;
  final String macAddress;
  final String vendor;
  final String destinationIp;
  final String destinationPort;
  final String destinationService;
  final String region;
  final String timestamp;
  final String direction;
  final String outboundInterface;
  final String flowCount;
  final String duration;
  final String downloaded;
  final String uploaded;

  const _FlowItem({
    required this.time,
    required this.destination,
    required this.country,
    required this.blocked,
    required this.deviceName,
    required this.deviceGroup,
    required this.deviceIp,
    required this.devicePort,
    required this.macAddress,
    required this.vendor,
    required this.destinationIp,
    required this.destinationPort,
    required this.destinationService,
    required this.region,
    required this.timestamp,
    required this.direction,
    required this.outboundInterface,
    required this.flowCount,
    required this.duration,
    required this.downloaded,
    required this.uploaded,
  });

  factory _FlowItem.fromNetify(
    NetifyFlow flow, {
    Map<String, String> hostnameByMac = const {},
    Map<String, String> hostnameByIp = const {},
  }) {
    final time = _formatClock(flow.timestamp.toLocal());
    final timestamp = _formatDateTime(flow.timestamp.toLocal());
    final protocol = flow.protocol == 'N/A' ? 'TCP' : flow.protocol;
    final destinationPort = flow.destinationPort == '0'
        ? protocol
        : '$protocol ${flow.destinationPort}';
    final devicePort = flow.localPort.isEmpty
        ? protocol
        : '$protocol ${flow.localPort}';
    final deviceName =
        hostnameByMac[flow.deviceMac] ??
        hostnameByIp[flow.localIp] ??
        (flow.localIp == '-' ? flow.deviceMac : flow.localIp);

    return _FlowItem(
      time: time,
      destination: flow.destination,
      country: flow.countryCode.isEmpty ? '?' : flow.countryCode,
      blocked: false,
      deviceName: deviceName.isEmpty ? '-' : deviceName,
      deviceGroup: '-',
      deviceIp: flow.localIp,
      devicePort: devicePort,
      macAddress: flow.deviceMac.isEmpty ? '-' : flow.deviceMac,
      vendor: '-',
      destinationIp: flow.destinationIp,
      destinationPort: destinationPort,
      destinationService: flow.protocol,
      region: flow.region.isEmpty ? flow.countryCode : flow.region,
      timestamp: timestamp,
      direction: flow.direction,
      outboundInterface: flow.interfaceName,
      flowCount: '1',
      duration: '-',
      downloaded: _formatBytes(flow.downloadedBytes),
      uploaded: _formatBytes(flow.uploadedBytes),
    );
  }

  static String _formatClock(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  static String _formatDateTime(DateTime time) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[time.month - 1]} ${time.day}, ${time.year} at ${_formatClock(time)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)} GB';
  }
}

class _FlowsScreenState extends ConsumerState<FlowsScreen> {
  static const Color _cyan = Color(0xFF18AEEA);
  static const Color _red = Color(0xFFFF4D4F);
  static const int _pageSize = 250;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreFlows = true;
  String? _error;
  String? _selectedProtocolFilter;
  int _flowCount = 0;
  List<_FlowItem> _flows = const [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFlows());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _isLoading ||
        _isLoadingMore ||
        !_hasMoreFlows) {
      return;
    }

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _loadMoreFlows();
    }
  }

  Future<void> _loadFlows() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _hasMoreFlows = true;
      _error = null;
    });

    try {
      final appState = ref.read(appStateProvider);
      final hostnames = _hostnameMaps(appState);
      final results = await Future.wait([
        appState.fetchNetifyFlowCount(
          protocolFilter: _selectedProtocolFilter,
          context: context,
        ),
        appState.fetchNetifyFlows(
          limit: _pageSize,
          protocolFilter: _selectedProtocolFilter,
          context: context,
        ),
      ]);
      if (!mounted) return;
      final flows = results[1] as List<NetifyFlow>;
      setState(() {
        _flowCount = results[0] as int;
        _flows = _mapFlowItems(flows, hostnames);
        _hasMoreFlows = flows.length == _pageSize && _flows.length < _flowCount;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load Netify flows.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreFlows() async {
    if (!mounted || _isLoading || _isLoadingMore || !_hasMoreFlows) return;

    setState(() => _isLoadingMore = true);

    try {
      final appState = ref.read(appStateProvider);
      final hostnames = _hostnameMaps(appState);
      final flows = await appState.fetchNetifyFlows(
        limit: _pageSize,
        offset: _flows.length,
        protocolFilter: _selectedProtocolFilter,
        context: context,
      );
      if (!mounted) return;
      final items = _mapFlowItems(flows, hostnames);
      setState(() {
        _flows = [..._flows, ...items];
        _hasMoreFlows = flows.length == _pageSize && _flows.length < _flowCount;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasMoreFlows = false;
        _isLoadingMore = false;
      });
    }
  }

  List<_FlowItem> _mapFlowItems(
    List<NetifyFlow> flows,
    (Map<String, String>, Map<String, String>) hostnames,
  ) {
    return flows
        .map(
          (flow) => _FlowItem.fromNetify(
            flow,
            hostnameByMac: hostnames.$1,
            hostnameByIp: hostnames.$2,
          ),
        )
        .toList();
  }

  (Map<String, String>, Map<String, String>) _hostnameMaps(AppState appState) {
    final byMac = <String, String>{};
    final byIp = <String, String>{};
    final dhcpLeases =
        appState.dashboardData?['dhcpLeases']?['dhcp_leases']
            as List<dynamic>? ??
        const [];

    for (final lease in dhcpLeases) {
      if (lease is! Map) continue;
      final hostname = lease['hostname']?.toString().trim();
      if (hostname == null || hostname.isEmpty || hostname == '*') continue;

      final mac = lease['macaddr']?.toString().trim().toUpperCase();
      final ip = lease['ipaddr']?.toString().trim();
      if (mac != null && mac.isNotEmpty) {
        byMac[mac.replaceAll('-', ':')] = hostname;
      }
      if (ip != null && ip.isNotEmpty) {
        byIp[ip] = hostname;
      }
    }

    return (byMac, byIp);
  }

  void _toggleProtocolFilter(String protocol) {
    setState(() {
      _selectedProtocolFilter = _selectedProtocolFilter == protocol
          ? null
          : protocol;
    });
    _loadFlows();
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

  void _showFlowDetails(_FlowItem flow) {
    showDialog<void>(
      context: context,
      builder: (context) => _FlowDetailsDialog(flow: flow),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const LuciAppBar(title: 'Network Flows', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadFlows,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Row(
                children: [
                  Text(
                    'Last 24 Hours',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {},
                    child: const Text(
                      'View Blocked',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'All Flows',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatCount(_flowCount),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['HTTP', 'HTTPS', 'DNS']
                    .map(
                      (label) => _FilterChip(
                        label: label,
                        selected: _selectedProtocolFilter == label,
                        onPressed: () => _toggleProtocolFilter(label),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _FlowEmptyCard(message: _error!, action: _loadFlows)
              else if (_flows.isEmpty)
                _FlowEmptyCard(
                  message: 'No Netify flow data yet.',
                  action: _loadFlows,
                )
              else
                _FlowListCard(flows: _flows, onTapFlow: _showFlowDetails),
              if (_isLoadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (!_isLoading && _flows.isNotEmpty && !_hasMoreFlows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'End of flows',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlowEmptyCard extends StatelessWidget {
  final String message;
  final VoidCallback action;

  const _FlowEmptyCard({required this.message, required this.action});

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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = selected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: foregroundColor,
        backgroundColor: selected ? colorScheme.primary : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        minimumSize: Size.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(
          color: selected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _FlowListCard extends StatelessWidget {
  final List<_FlowItem> flows;
  final ValueChanged<_FlowItem> onTapFlow;

  const _FlowListCard({required this.flows, required this.onTapFlow});

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
      child: Column(
        children: flows
            .map((flow) => _FlowRow(flow: flow, onTap: () => onTapFlow(flow)))
            .toList(),
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  final _FlowItem flow;
  final VoidCallback onTap;

  const _FlowRow({required this.flow, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = flow.blocked
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                flow.time,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  decoration: flow.blocked ? TextDecoration.lineThrough : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 34,
              child: Text(
                flow.country,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Text(
                flow.destination,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  decoration: flow.blocked ? TextDecoration.lineThrough : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowDetailsDialog extends StatelessWidget {
  final _FlowItem flow;

  const _FlowDetailsDialog({required this.flow});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog.fullscreen(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        appBar: LuciAppBar(
          title: 'Flow Details',
          showBack: true,
          actions: [
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                  children: [
                    _DetailSection(
                      title: 'Device',
                      rows: [
                        _DetailRow(
                          label: 'Name',
                          value: flow.deviceName,
                          icon: Icons.sensors_rounded,
                          iconColor: _FlowsScreenState._cyan,
                        ),
                        _DetailRow(label: 'Group', value: flow.deviceGroup),
                        _DetailRow(label: 'IP Address', value: flow.deviceIp),
                        _DetailRow(label: 'Port', value: flow.devicePort),
                        _DetailRow(
                          label: 'MAC Address',
                          value: flow.macAddress,
                        ),
                        _DetailRow(label: 'Vendor', value: flow.vendor),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _DetailSection(
                      title: 'Destination',
                      rows: [
                        _DetailRow(
                          label: 'Name',
                          value: flow.destination,
                          showChevron: true,
                        ),
                        _DetailRow(
                          label: 'IP Address',
                          value: flow.destinationIp,
                          showChevron: true,
                        ),
                        _DetailRow(
                          label: 'Port',
                          value: flow.destinationPort,
                          helper: flow.destinationService,
                        ),
                        _DetailRow(
                          label: 'Region',
                          value: flow.region,
                          showChevron: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _DetailSection(
                      title: 'Flow Detail',
                      rows: [
                        _DetailRow(label: 'Timestamp', value: flow.timestamp),
                        _DetailRow(label: 'Direction', value: flow.direction),
                        _DetailRow(
                          label: 'Outbound Interface',
                          value: flow.outboundInterface,
                        ),
                        _DetailRow(label: 'Flow Count', value: flow.flowCount),
                        _DetailRow(label: 'Duration', value: flow.duration),
                        _DetailRow(label: 'Downloaded', value: flow.downloaded),
                        _DetailRow(label: 'Uploaded', value: flow.uploaded),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.96),
                  border: Border(
                    top: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.alt_route_rounded),
                        label: const Text('Route'),
                        style: TextButton.styleFrom(
                          foregroundColor: _FlowsScreenState._cyan,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.block_rounded),
                        label: const Text('Block'),
                        style: TextButton.styleFrom(
                          foregroundColor: _FlowsScreenState._red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<_DetailRow> rows;

  const _DetailSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.38),
            ),
          ),
          child: Column(children: rows),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  final String? helper;
  final bool showChevron;

  const _DetailRow({
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
    this.helper,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.32),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (icon != null) ...[
                Icon(icon, color: iconColor ?? colorScheme.primary, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(
                flex: 2,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showChevron) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
          if (helper != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Text(
                helper!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
