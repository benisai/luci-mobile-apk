import 'package:flutter/material.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

class FlowsScreen extends StatefulWidget {
  const FlowsScreen({super.key});

  @override
  State<FlowsScreen> createState() => _FlowsScreenState();
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
}

class _FlowsScreenState extends State<FlowsScreen> {
  static const Color _cyan = Color(0xFF18AEEA);
  static const Color _red = Color(0xFFFF4D4F);

  int _selectedTab = 2;

  final List<_FlowItem> _flows = const [
    _FlowItem(
      time: '11:38 PM',
      destination: 'unifi',
      country: 'Unknown',
      blocked: false,
      deviceName: 'WYZE_Living_Room',
      deviceGroup: 'IOT',
      deviceIp: '10.0.200.225',
      devicePort: 'TCP 33399',
      macAddress: 'D0:3F:27:81:6C:17',
      vendor: 'Wyze Labs Inc',
      destinationIp: '10.0.0.1',
      destinationPort: 'TCP 443',
      destinationService: 'HTTPS',
      region: 'Local',
      timestamp: 'Aug 12, 2026 at 11:38 PM',
      direction: 'Outbound',
      outboundInterface: 'Spectrum',
      flowCount: '1',
      duration: '34s 950ms',
      downloaded: '31 B',
      uploaded: '31 B',
    ),
    _FlowItem(
      time: '11:38 PM',
      destination: 'aws-iot.wyzecam.com',
      country: 'US',
      blocked: false,
      deviceName: 'WYZE_Living_Room',
      deviceGroup: 'IOT',
      deviceIp: '10.0.200.225',
      devicePort: 'TCP 33399',
      macAddress: 'D0:3F:27:81:6C:17',
      vendor: 'Wyze Labs Inc',
      destinationIp: '54.69.167.88',
      destinationPort: 'TCP 8883',
      destinationService: 'Secure MQTT',
      region: 'United States',
      timestamp: 'Aug 12, 2026 at 11:38 PM',
      direction: 'Outbound',
      outboundInterface: 'Spectrum',
      flowCount: '1',
      duration: '34s 950ms',
      downloaded: '31 B',
      uploaded: '31 B',
    ),
    _FlowItem(
      time: '11:38 PM',
      destination: 'm3-us.iotbing.com',
      country: 'US',
      blocked: false,
      deviceName: 'Garage Camera',
      deviceGroup: 'IOT',
      deviceIp: '10.0.200.44',
      devicePort: 'TCP 42418',
      macAddress: '48:E1:E9:2A:1C:90',
      vendor: 'Generic Camera',
      destinationIp: '34.120.22.19',
      destinationPort: 'TCP 443',
      destinationService: 'HTTPS',
      region: 'United States',
      timestamp: 'Aug 12, 2026 at 11:38 PM',
      direction: 'Outbound',
      outboundInterface: 'Spectrum',
      flowCount: '3',
      duration: '1m 08s',
      downloaded: '4.8 KB',
      uploaded: '1.2 KB',
    ),
    _FlowItem(
      time: '11:38 PM',
      destination: 'api.eu.amplitude.com',
      country: 'DE',
      blocked: false,
      deviceName: 'Pixel 9',
      deviceGroup: 'Personal',
      deviceIp: '10.0.0.32',
      devicePort: 'TCP 51552',
      macAddress: 'AA:12:44:9B:2D:10',
      vendor: 'Google',
      destinationIp: '18.198.12.4',
      destinationPort: 'TCP 443',
      destinationService: 'HTTPS',
      region: 'Germany',
      timestamp: 'Aug 12, 2026 at 11:38 PM',
      direction: 'Outbound',
      outboundInterface: 'Spectrum',
      flowCount: '2',
      duration: '12s 110ms',
      downloaded: '9.2 KB',
      uploaded: '2.7 KB',
    ),
    _FlowItem(
      time: '11:38 PM',
      destination: '20.15.200.1',
      country: 'US',
      blocked: true,
      deviceName: 'Laptop',
      deviceGroup: 'Default',
      deviceIp: '10.0.0.18',
      devicePort: 'TCP 49821',
      macAddress: 'F4:D4:88:1B:8A:21',
      vendor: 'Apple',
      destinationIp: '20.15.200.1',
      destinationPort: 'TCP 443',
      destinationService: 'HTTPS',
      region: 'United States',
      timestamp: 'Aug 12, 2026 at 11:38 PM',
      direction: 'Outbound',
      outboundInterface: 'Spectrum',
      flowCount: '1',
      duration: '4s 012ms',
      downloaded: '0 B',
      uploaded: '0 B',
    ),
  ];

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
        child: ListView(
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
              '0',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                height: 0.95,
              ),
            ),
            const SizedBox(height: 22),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Upload')),
                ButtonSegment(value: 1, label: Text('Download')),
                ButtonSegment(value: 2, label: Text('History')),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (selection) {
                setState(() => _selectedTab = selection.first);
              },
              showSelectedIcon: false,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'Exclude',
                'Gaming',
                'Social',
                'Video',
                'VPN',
              ].map((label) => _FilterChip(label: label)).toList(),
            ),
            const SizedBox(height: 14),
            _FlowListCard(flows: _flows, onTapFlow: _showFlowDetails),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;

  const _FilterChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return OutlinedButton(
      onPressed: () {},
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        minimumSize: Size.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
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
