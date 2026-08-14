import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';
import 'package:luci_mobile/widgets/luci_refresh_components.dart';
import 'package:luci_mobile/widgets/luci_animation_system.dart';

class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen>
    with SingleTickerProviderStateMixin {
  String _searchQuery = '';
  final Set<int> _expandedClientIndices = {};
  late AnimationController _controller;
  late TextEditingController _searchController;
  bool _aggregateAllRouters = true;
  Future<List<Client>>? _clientsFuture;
  String? _lastSelectedRouterId;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _searchController = TextEditingController();
    _searchController.addListener(() {
      if (_searchQuery != _searchController.text) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
    // Initialize toggle from persisted state
    final initState = ref.read(appStateProvider);
    _aggregateAllRouters = initState.clientsAggregateAllRouters;
    _lastSelectedRouterId = initState.selectedRouter?.id;
    _computeClientsFuture();
  }

  void _computeClientsFuture() {
    final appState = ref.read(appStateProvider);
    _clientsFuture = _aggregateAllRouters
        ? appState.fetchAggregatedClients()
        : appState.fetchClientsForSelectedRouter();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final watchedAppState = ref.watch(appStateProvider);
    // Recompute future only when selected router changes
    Future<List<Client>>? future = _clientsFuture;
    final currentId = watchedAppState.selectedRouter?.id;
    if (currentId != _lastSelectedRouterId) {
      _lastSelectedRouterId = currentId;
      _computeClientsFuture();
      future = _clientsFuture;
    }
    return FutureBuilder<List<Client>>(
      future: future,
      builder: (context, snapshot) {
        final aggregatedClients = snapshot.data ?? [];
        return Scaffold(
          body: Stack(
            children: [
              LuciPullToRefresh(
                onRefresh: () async {
                  // Trigger a refresh by re-fetching dashboard data for selected router
                  await ref.read(appStateProvider).fetchDashboardData();
                  setState(() {
                    _computeClientsFuture();
                  });
                },
                child: Builder(
                  builder: (context) {
                    final appState = ref.watch(appStateProvider);
                    final isLoading =
                        snapshot.connectionState == ConnectionState.waiting &&
                        (aggregatedClients.isEmpty);
                    final dashboardError = appState.dashboardError;

                    if (isLoading) {
                      return SafeArea(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: LuciSpacing.md,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: LuciSpacing.lg),
                              LuciSkeleton(
                                width: 230,
                                height: 34,
                                borderRadius: BorderRadius.circular(
                                  LuciSpacing.sm,
                                ),
                              ),
                              SizedBox(height: LuciSpacing.sm),
                              LuciSkeleton(
                                width: 210,
                                height: 18,
                                borderRadius: BorderRadius.circular(
                                  LuciSpacing.xs,
                                ),
                              ),
                              SizedBox(height: LuciSpacing.lg),
                              LuciSkeleton(
                                width: double.infinity,
                                height: 56,
                                borderRadius: BorderRadius.circular(
                                  LuciSpacing.sm,
                                ),
                              ),
                              SizedBox(height: LuciSpacing.md),
                              Row(
                                children: List.generate(
                                  3,
                                  (index) => Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        right: index == 2 ? 0 : LuciSpacing.md,
                                      ),
                                      child: AspectRatio(
                                        aspectRatio: 1,
                                        child: LuciSkeleton(
                                          width: double.infinity,
                                          height: double.infinity,
                                          borderRadius: BorderRadius.circular(
                                            LuciSpacing.sm,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: LuciSpacing.md),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: 6,
                                  separatorBuilder: (context, index) =>
                                      SizedBox(height: LuciSpacing.sm),
                                  itemBuilder: (context, index) =>
                                      LuciListItemSkeleton(
                                        showLeading: true,
                                        showTrailing: true,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    if (dashboardError != null && aggregatedClients.isEmpty) {
                      return LuciErrorDisplay(
                        title: 'Failed to Load Clients',
                        message:
                            'Could not connect to the router. Please check your network connection and the router\'s IP address.',
                        actionLabel: 'Retry',
                        onAction: () => ref
                            .read(appStateProvider)
                            .retryDashboardConnection(context: context),
                        icon: Icons.wifi_off_rounded,
                      );
                    }

                    final clients = aggregatedClients;
                    final blockedCount = clients
                        .where((client) => client.isBlocked)
                        .length;
                    final onlineCount = clients.length - blockedCount;
                    const offlineCount = 0;

                    final filteredClients = clients.where((client) {
                      final query = _searchQuery.toLowerCase();
                      return client.hostname.toLowerCase().contains(query) ||
                          client.ipAddress.toLowerCase().contains(query) ||
                          client.macAddress.toLowerCase().contains(query) ||
                          (client.vendor != null &&
                              client.vendor!.toLowerCase().contains(query)) ||
                          (client.dnsName != null &&
                              client.dnsName!.toLowerCase().contains(query));
                    }).toList();

                    return Column(
                      children: [
                        SafeArea(
                          bottom: false,
                          child: _buildClientsHeader(
                            context,
                            onlineCount: onlineCount,
                            blockedCount: blockedCount,
                            offlineCount: offlineCount,
                          ),
                        ),
                        Expanded(
                          child: filteredClients.isEmpty
                              ? LuciEmptyState(
                                  title: _searchQuery.isEmpty
                                      ? 'No Active Clients Found'
                                      : 'No Matching Clients',
                                  message: _searchQuery.isEmpty
                                      ? 'No clients are currently connected to the router. Pull down to refresh the list.'
                                      : 'No clients match your search criteria. Try a different search term.',
                                  icon: Icons.people_outline,
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  separatorBuilder: (context, idx) =>
                                      const SizedBox(height: 4),
                                  itemCount: filteredClients.length,
                                  itemBuilder: (context, index) {
                                    final client = filteredClients[index];
                                    final isExpanded = _expandedClientIndices
                                        .contains(index);

                                    return LuciSlideTransition(
                                      direction: LuciSlideDirection.up,
                                      delay: Duration(milliseconds: index * 50),
                                      distance: 30,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16.0,
                                          vertical: 8.0,
                                        ),
                                        child: _UnifiedClientCard(
                                          client: client,
                                          isExpanded: isExpanded,
                                          onTap: () {
                                            setState(() {
                                              if (isExpanded) {
                                                _expandedClientIndices.remove(
                                                  index,
                                                );
                                              } else {
                                                _expandedClientIndices.add(
                                                  index,
                                                );
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String normalizeMac(String mac) => mac.toUpperCase().replaceAll('-', ':');

  Widget _buildClientsHeader(
    BuildContext context, {
    required int onlineCount,
    required int blockedCount,
    required int offlineCount,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchField(context),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildClientStatCard(
                  context,
                  icon: Icons.wifi_rounded,
                  count: onlineCount,
                  label: 'Online',
                  color: const Color(0xFF22C55E),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildClientStatCard(
                  context,
                  icon: Icons.block_rounded,
                  count: blockedCount,
                  label: 'Blocked',
                  color: const Color(0xFFFF4D5A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildClientStatCard(
                  context,
                  icon: Icons.cloud_off_outlined,
                  count: offlineCount,
                  label: 'Offline',
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextField(
      autofocus: false,
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search by name, IP, or MAC',
        prefixIcon: const Icon(Icons.search_rounded, size: 28),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                  });
                },
                tooltip: 'Clear search',
              )
            : null,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.7),
            width: 1.4,
          ),
        ),
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }

  Widget _buildClientStatCard(
    BuildContext context, {
    required IconData icon,
    required int count,
    required String label,
    required Color color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return AspectRatio(
      aspectRatio: 1.08,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                count.toString(),
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                height: 1.05,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _UnifiedClientCard extends StatefulWidget {
  final Client client;
  final bool isExpanded;
  final VoidCallback onTap;

  const _UnifiedClientCard({
    required this.client,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<_UnifiedClientCard> createState() => _UnifiedClientCardState();
}

class _UnifiedClientCardState extends State<_UnifiedClientCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    if (widget.isExpanded) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_UnifiedClientCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isBlocked = widget.client.isBlocked;
    final borderColor = isBlocked
        ? const Color(0xFFFF4D5A).withValues(alpha: 0.45)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.10);

    return Card(
      elevation: widget.isExpanded ? 6 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
        side: BorderSide(color: borderColor, width: isBlocked ? 1.3 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      color: isBlocked
          ? colorScheme.errorContainer.withValues(alpha: 0.08)
          : null,
      child: AnimatedScale(
        scale: widget.isExpanded ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: Column(
          children: [
            InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(18.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8.0),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.13,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: AnimatedScale(
                            scale: widget.isExpanded ? 1.1 : 1.0,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.elasticOut,
                            child: Icon(
                              Icons.person_outline,
                              color: colorScheme.primary,
                              size: 22,
                              semanticLabel: 'Client icon',
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Tooltip(
                            message:
                                widget.client.connectionType ==
                                    ConnectionType.unknown
                                ? 'Unknown connection type'
                                : 'Client is online',
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: widget.client.isBlocked
                                    ? const Color(0xFFFF4D5A)
                                    : widget.client.connectionType ==
                                              ConnectionType.wireless ||
                                          widget.client.connectionType ==
                                              ConnectionType.wired
                                    ? Colors.green
                                    : Colors.amber,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorScheme.surface,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.client.hostname,
                            style: LuciTextStyles.cardTitle(context),
                            semanticsLabel:
                                'Client hostname: ${widget.client.hostname}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: LuciSpacing.xs),
                          Container(
                            margin: const EdgeInsets.only(right: 32),
                            child: Divider(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.10),
                              thickness: 1,
                              height: 8,
                            ),
                          ),
                          Text(
                            _buildMinimalClientSubtitle(widget.client),
                            style: LuciTextStyles.cardSubtitle(context),
                            semanticsLabel:
                                'Client details: ${_buildMinimalClientSubtitle(widget.client)}',
                          ),
                          if (widget.client.vendor != null &&
                              widget.client.vendor!.isNotEmpty)
                            Text(
                              widget.client.vendor!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              semanticsLabel: 'Vendor: ${widget.client.vendor}',
                            ),
                        ],
                      ),
                    ),
                    if (widget.client.isBlocked)
                      _buildBlockedChip(context)
                    else
                      _buildConnectionTypeChip(
                        context,
                        widget.client.connectionType,
                      ),
                    const SizedBox(width: 8),
                    Icon(
                      widget.isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: colorScheme.onSurfaceVariant,
                      size: 26,
                      semanticLabel: widget.isExpanded
                          ? 'Collapse details'
                          : 'Expand details',
                    ),
                  ],
                ),
              ),
            ),
            if (widget.isExpanded)
              Column(
                children: [
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildClientDetails(context, widget.client),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionTypeChip(BuildContext context, ConnectionType type) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    String label;
    IconData icon;
    Color bgColor;
    Color fgColor;

    switch (type) {
      case ConnectionType.wireless:
        label = 'Wi-Fi';
        icon = Icons.wifi;
        bgColor = colorScheme.primaryContainer;
        fgColor = colorScheme.onPrimaryContainer;
        break;
      case ConnectionType.wired:
        label = 'Wired';
        icon = Icons.settings_ethernet;
        bgColor = colorScheme.secondaryContainer;
        fgColor = colorScheme.onSecondaryContainer;
        break;
      default:
        label = 'Unknown';
        icon = Icons.devices_other_outlined;
        bgColor = colorScheme.surfaceContainerHighest;
        fgColor = colorScheme.onSurfaceVariant;
        break;
    }

    return Chip(
      label: Text(label),
      avatar: Icon(icon, size: 16, color: fgColor),
      backgroundColor: bgColor,
      labelStyle: theme.textTheme.labelSmall?.copyWith(color: fgColor),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildBlockedChip(BuildContext context) {
    return Chip(
      label: const Text('Blocked'),
      avatar: const Icon(Icons.block_rounded, size: 16),
      backgroundColor: Theme.of(
        context,
      ).colorScheme.errorContainer.withValues(alpha: 0.62),
      labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onErrorContainer,
        fontWeight: FontWeight.w800,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildClientDetails(BuildContext context, Client client) {
    final theme = Theme.of(context);

    Widget detailRow(
      String title,
      String value, {
      Color? valueColor,
      VoidCallback? onTap,
      String? semanticsLabel,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LuciSpacing.md,
            vertical: LuciSpacing.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: LuciTextStyles.detailLabel(context),
                semanticsLabel: title,
              ),
              Row(
                children: [
                  Text(
                    value,
                    style: valueColor != null
                        ? LuciTextStyles.detailValue(
                            context,
                          ).copyWith(color: valueColor)
                        : LuciTextStyles.detailValue(context),
                    semanticsLabel: semanticsLabel ?? value,
                  ),
                  if (onTap != null)
                    GestureDetector(
                      onTap: onTap,
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8.0),
                        child: Icon(
                          Icons.copy_all_outlined,
                          size: 16,
                          semanticLabel: 'Copy',
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

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.18,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      child: Column(
        children: [
          if (client.isBlocked) ...[
            detailRow(
              'Quarantine',
              'Blocked from LAN and Internet',
              valueColor: theme.colorScheme.error,
              semanticsLabel: 'Quarantine: blocked from LAN and Internet',
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],
          detailRow(
            'IP Address',
            client.ipAddress,
            onTap: () =>
                _copyToClipboard(context, client.ipAddress, 'IP Address'),
            semanticsLabel: 'IP Address: ${client.ipAddress}',
          ),
          if (client.ipv6Addresses != null && client.ipv6Addresses!.isNotEmpty)
            ...client.ipv6Addresses!.map(
              (ipv6) => detailRow(
                'IPv6 Address',
                ipv6,
                onTap: () => _copyToClipboard(context, ipv6, 'IPv6 Address'),
                semanticsLabel: 'IPv6 Address: $ipv6',
              ),
            ),
          detailRow(
            'MAC Address',
            client.macAddress,
            onTap: () =>
                _copyToClipboard(context, client.macAddress, 'MAC Address'),
            semanticsLabel: 'MAC Address: ${client.macAddress}',
          ),
          if (client.vendor != null && client.vendor!.isNotEmpty)
            detailRow(
              'Vendor',
              client.vendor!,
              semanticsLabel: 'Vendor: ${client.vendor}',
            ),
          if (client.dnsName != null && client.dnsName!.isNotEmpty)
            detailRow(
              'DNS Name',
              client.dnsName!,
              semanticsLabel: 'DNS Name: ${client.dnsName}',
            ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          const SizedBox(height: 8),
          detailRow(
            'Lease Time Remaining',
            client.formattedLeaseTime,
            valueColor: client.formattedLeaseTime == 'Expired'
                ? theme.colorScheme.error
                : null,
            semanticsLabel:
                'Lease Time Remaining: ${client.formattedLeaseTime}',
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _buildMinimalClientSubtitle(Client client) {
    final v4 = client.ipAddress;
    final v6s = client.ipv6Addresses ?? [];
    final v6 = v6s.isNotEmpty ? v6s.first : null;
    String? shown;
    int extra = 0;
    if (v4 != 'N/A') {
      shown = v4;
      if (v6 != null) extra++;
    } else if (v6 != null) {
      shown = v6;
    }
    if (shown == null) return '';
    if (extra > 0) {
      return '$shown  +$extra';
    } else {
      return shown;
    }
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
