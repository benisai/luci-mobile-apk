import 'package:flutter/material.dart';
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

enum ClientFilter { online, blocked, offline }

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  String _searchQuery = '';
  ClientFilter _currentFilter = ClientFilter.online;
  late TextEditingController _searchController;
  bool _aggregateAllRouters = true;
  Future<List<Client>>? _clientsFuture;
  String? _lastSelectedRouterId;
  String? _activeClientCacheKey;
  List<Client> _visibleClients = const [];
  final Set<String> _blockingMacs = {};
  static final Map<String, List<Client>> _clientCache = {};

  @override
  void initState() {
    super.initState();
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
    final cacheKey = _clientCacheKey(appState);
    _activeClientCacheKey = cacheKey;
    _visibleClients = _clientCache[cacheKey] ?? const [];
    _clientsFuture = _loadClients(cacheKey);
  }

  String _clientCacheKey(dynamic appState) {
    if (_aggregateAllRouters) return 'aggregate';
    return appState.selectedRouter?.id?.toString() ?? 'selected:none';
  }

  Future<List<Client>> _loadClients(String cacheKey) async {
    final appState = ref.read(appStateProvider);
    final clients = _aggregateAllRouters
        ? await appState.fetchAggregatedClients()
        : await appState.fetchClientsForSelectedRouter();
    _clientCache[cacheKey] = clients;
    if (mounted && _activeClientCacheKey == cacheKey) {
      setState(() {
        _visibleClients = clients;
      });
    }
    return clients;
  }

  @override
  void dispose() {
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
        final aggregatedClients = snapshot.data ?? _visibleClients;
        return Scaffold(
          appBar: const LuciAppBar(title: 'Devices', showBack: true),
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
                    final blockedClients = clients
                        .where((client) => client.isBlocked)
                        .toList();
                    final offlineClients = clients
                        .where(
                          (client) => !client.isBlocked && client.isOffline,
                        )
                        .toList();
                    final onlineClients = clients
                        .where(
                          (client) => !client.isBlocked && !client.isOffline,
                        )
                        .toList();

                    final blockedCount = blockedClients.length;
                    final offlineCount = offlineClients.length;
                    final onlineCount = onlineClients.length;

                    final activeCategoryClients = switch (_currentFilter) {
                      ClientFilter.online => onlineClients,
                      ClientFilter.blocked => blockedClients,
                      ClientFilter.offline => offlineClients,
                    };

                    final filteredClients = activeCategoryClients.where((
                      client,
                    ) {
                      final query = _searchQuery.toLowerCase();
                      if (query.isEmpty) return true;
                      return client.hostname.toLowerCase().contains(query) ||
                          client.ipAddress.toLowerCase().contains(query) ||
                          client.macAddress.toLowerCase().contains(query) ||
                          (client.vendor != null &&
                              client.vendor!.toLowerCase().contains(query)) ||
                          (client.dnsName != null &&
                              client.dnsName!.toLowerCase().contains(query));
                    }).toList();

                    String emptyTitle;
                    String emptyMessage;
                    IconData emptyIcon;

                    if (_searchQuery.isNotEmpty) {
                      emptyTitle = 'No Matching Clients';
                      emptyMessage =
                          'No clients match your search criteria. Try a different search term.';
                      emptyIcon = Icons.search_off_rounded;
                    } else {
                      switch (_currentFilter) {
                        case ClientFilter.online:
                          emptyTitle = 'No Online Clients Found';
                          emptyMessage =
                              'No clients are currently connected to the router. Pull down to refresh the list.';
                          emptyIcon = Icons.wifi_off_rounded;
                          break;
                        case ClientFilter.blocked:
                          emptyTitle = 'No Blocked Clients';
                          emptyMessage =
                              'No devices are currently blocked from accessing the internet.';
                          emptyIcon = Icons.shield_outlined;
                          break;
                        case ClientFilter.offline:
                          emptyTitle = 'No Offline Clients';
                          emptyMessage =
                              'No offline clients found in recent device history.';
                          emptyIcon = Icons.cloud_off_outlined;
                          break;
                      }
                    }

                    return Column(
                      children: [
                        SafeArea(
                          top: false,
                          bottom: false,
                          child: _buildClientsHeader(
                            context,
                            onlineCount: onlineCount,
                            blockedCount: blockedCount,
                            offlineCount: offlineCount,
                            currentFilter: _currentFilter,
                            onFilterChanged: (filter) {
                              setState(() {
                                _currentFilter = filter;
                              });
                            },
                          ),
                        ),
                        Expanded(
                          child: filteredClients.isEmpty
                              ? LuciEmptyState(
                                  title: emptyTitle,
                                  message: emptyMessage,
                                  icon: emptyIcon,
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  separatorBuilder: (context, idx) =>
                                      const SizedBox(height: 4),
                                  itemCount: filteredClients.length,
                                  itemBuilder: (context, index) {
                                    final client = filteredClients[index];

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
                                          isBlockingActionRunning: _blockingMacs
                                              .contains(
                                                _normalizeMac(
                                                  client.macAddress,
                                                ),
                                              ),
                                          onToggleInternetBlock: (blocked) =>
                                              _setClientInternetBlocked(
                                                client,
                                                blocked,
                                              ),
                                          onOpenSettings: () =>
                                              _showDeviceSettingsSheet(client),
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
    required ClientFilter currentFilter,
    required ValueChanged<ClientFilter> onFilterChanged,
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
                  isSelected: currentFilter == ClientFilter.online,
                  onTap: () => onFilterChanged(ClientFilter.online),
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
                  isSelected: currentFilter == ClientFilter.blocked,
                  onTap: () => onFilterChanged(ClientFilter.blocked),
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
                  isSelected: currentFilter == ClientFilter.offline,
                  onTap: () => onFilterChanged(ClientFilter.offline),
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

  String _normalizeMac(String mac) =>
      mac.trim().toUpperCase().replaceAll('-', ':');

  void _applyCachedClientBlockState(String mac, bool blocked) {
    Client updateClient(Client client) {
      if (_normalizeMac(client.macAddress) != mac) return client;
      return client.copyWith(
        isBlocked: blocked,
        status: blocked ? 'blocked' : 'online',
      );
    }

    _visibleClients = _visibleClients.map(updateClient).toList();
    for (final entry in _clientCache.entries.toList()) {
      _clientCache[entry.key] = entry.value.map(updateClient).toList();
    }
  }

  Future<void> _setClientInternetBlocked(Client client, bool blocked) async {
    final mac = _normalizeMac(client.macAddress);
    if (mac.isEmpty || mac == 'N/A') return;

    setState(() {
      _blockingMacs.add(mac);
    });

    try {
      await ref
          .read(appStateProvider)
          .setClientInternetBlocked(client, blocked);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? 'Internet blocked for ${client.hostname}'
                : 'Device unblocked',
          ),
        ),
      );
      setState(() {
        _applyCachedClientBlockState(mac, blocked);
        _computeClientsFuture();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update device block: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _blockingMacs.remove(mac);
        });
      }
    }
  }

  Future<void> _showDeviceSettingsSheet(Client client) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _DeviceSettingsSheet(client: client),
    );
    if (updated == true && mounted) {
      setState(() {
        _computeClientsFuture();
      });
    }
  }

  Widget _buildClientStatCard(
    BuildContext context, {
    required IconData icon,
    required int count,
    required String label,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return AspectRatio(
      aspectRatio: 1.08,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.34,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.24),
                width: 1.0,
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, color: color, size: 22),
                    if (isSelected)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
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
        ),
      ),
    );
  }
}

class _DeviceSettingsSheet extends ConsumerStatefulWidget {
  final Client client;

  const _DeviceSettingsSheet({required this.client});

  @override
  ConsumerState<_DeviceSettingsSheet> createState() =>
      _DeviceSettingsSheetState();
}

class _DeviceSettingsSheetState extends ConsumerState<_DeviceSettingsSheet> {
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  bool _staticIpEnabled = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.client.hostname;
    _ipController.text = widget.client.staticIpAddress?.isNotEmpty == true
        ? widget.client.staticIpAddress!
        : widget.client.ipAddress == 'N/A'
        ? ''
        : widget.client.ipAddress;
    _staticIpEnabled = widget.client.staticIpAddress?.isNotEmpty == true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Device name is required.');
      return;
    }
    if (_staticIpEnabled && _ipController.text.trim().isEmpty) {
      _showError('Static IP address is required.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .saveClientDeviceSettings(
            widget.client,
            hostname: name,
            staticIpEnabled: _staticIpEnabled,
            staticIpAddress: _ipController.text.trim(),
            context: context,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to save device settings: $e');
      setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(
                      Icons.devices_other_rounded,
                      color: colorScheme.primary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Device Settings',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.client.macAddress,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _DeviceUsagePanel(client: widget.client),
              const SizedBox(height: 22),
              Text(
                'Device Name',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.edit_rounded),
                  hintText: 'Device name',
                ),
              ),
              const SizedBox(height: 18),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Static IP Address'),
                subtitle: const Text('Reserve a permanent IP for this device'),
                value: _staticIpEnabled,
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _staticIpEnabled = value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ipController,
                enabled: !_isSaving && _staticIpEnabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.lan_rounded),
                  labelText: 'IP Address',
                  hintText: '192.168.1.50',
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_isSaving ? 'Saving' : 'Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceUsagePanel extends StatelessWidget {
  final Client client;

  const _DeviceUsagePanel({required this.client});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _usageMetric(
              context,
              label: 'Download',
              value: _formatBytes(client.totalDownloadBytes),
              icon: Icons.arrow_downward_rounded,
              color: const Color(0xFF18AEEA),
            ),
          ),
          Container(
            width: 1,
            height: 44,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          Expanded(
            child: _usageMetric(
              context,
              label: 'Upload',
              value: _formatBytes(client.totalUploadBytes),
              icon: Icons.arrow_upward_rounded,
              color: const Color(0xFFF27C24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _usageMetric(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final decimals = value >= 100 || unit == 0
        ? 0
        : value >= 10
        ? 1
        : 2;
    return '${value.toStringAsFixed(decimals)} ${units[unit]}';
  }
}

class _UnifiedClientCard extends StatelessWidget {
  final Client client;
  final ValueChanged<bool> onToggleInternetBlock;
  final VoidCallback onOpenSettings;
  final bool isBlockingActionRunning;

  const _UnifiedClientCard({
    required this.client,
    required this.onToggleInternetBlock,
    required this.onOpenSettings,
    required this.isBlockingActionRunning,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isBlocked = client.isBlocked;
    final borderColor = isBlocked
        ? const Color(0xFFFF4D5A).withValues(alpha: 0.45)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.10);

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
        side: BorderSide(color: borderColor, width: isBlocked ? 1.3 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      color: isBlocked
          ? colorScheme.errorContainer.withValues(alpha: 0.08)
          : null,
      child: InkWell(
        onTap: onOpenSettings,
        borderRadius: BorderRadius.circular(18.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
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
                    child: Icon(
                      client.isBlocked
                          ? Icons.block_rounded
                          : client.isOffline
                          ? Icons.cloud_off_rounded
                          : client.connectionType == ConnectionType.wireless
                          ? Icons.wifi_rounded
                          : client.connectionType == ConnectionType.wired
                          ? Icons.settings_ethernet
                          : Icons.devices_other_rounded,
                      color: client.isBlocked
                          ? const Color(0xFFFF4D5A)
                          : client.isOffline
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.primary,
                      size: 22,
                      semanticLabel: 'Client icon',
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Tooltip(
                      message: client.isBlocked
                          ? 'Client is blocked'
                          : client.isOffline
                          ? 'Client is offline'
                          : 'Client is online',
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: client.isBlocked
                              ? const Color(0xFFFF4D5A)
                              : client.isOffline
                              ? colorScheme.onSurfaceVariant
                              : Colors.green,
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
                      client.hostname,
                      style: LuciTextStyles.cardTitle(context),
                      semanticsLabel: 'Client hostname: ${client.hostname}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: LuciSpacing.xs),
                    Container(
                      margin: const EdgeInsets.only(right: 32),
                      child: Divider(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.10,
                        ),
                        thickness: 1,
                        height: 8,
                      ),
                    ),
                    Text(
                      _buildMinimalClientSubtitle(client),
                      style: LuciTextStyles.cardSubtitle(context),
                      semanticsLabel:
                          'Client details: ${_buildMinimalClientSubtitle(client)}',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildBlockActionButton(context),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 26,
                semanticLabel: 'Open device settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockActionButton(BuildContext context) {
    final theme = Theme.of(context);
    final color = client.isBlocked
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    return OutlinedButton.icon(
      onPressed: isBlockingActionRunning
          ? null
          : () => onToggleInternetBlock(!client.isBlocked),
      icon: isBlockingActionRunning
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color.withValues(alpha: 0.9),
              ),
            )
          : Icon(
              client.isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
              size: 16,
            ),
      label: Text(
        isBlockingActionRunning
            ? 'Wait'
            : client.isBlocked
            ? 'Unblock'
            : 'Block',
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.34)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
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
}
