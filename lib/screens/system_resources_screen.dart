import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

class SystemResourcesScreen extends ConsumerStatefulWidget {
  const SystemResourcesScreen({super.key});

  @override
  ConsumerState<SystemResourcesScreen> createState() =>
      _SystemResourcesScreenState();
}

class _SystemResourcesScreenState extends ConsumerState<SystemResourcesScreen> {
  SystemStorageDetails _storage = SystemStorageDetails.empty;
  bool _isLoadingStorage = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStorage());
  }

  Future<void> _loadStorage() async {
    if (!mounted) return;
    setState(() => _isLoadingStorage = true);
    final storage = await ref
        .read(appStateProvider)
        .fetchSystemStorageDetails(context: context);
    if (!mounted) return;
    setState(() {
      _storage = storage;
      _isLoadingStorage = false;
    });
  }

  double _fixedPointPercent(dynamic value) {
    if (value is! num) return 0;
    return ((value / 65536) * 100).clamp(0, 100).toDouble();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 1 : 1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(gb >= 10 ? 1 : 2)} GB';
  }

  String _releaseText(Map<String, dynamic>? boardInfo) {
    final release = boardInfo?['release'];
    if (release is Map) {
      final description = release['description']?.toString();
      final revision = release['revision']?.toString();
      return [
        if (description != null && description.isNotEmpty) description,
        if (revision != null && revision.isNotEmpty) revision,
      ].join(' ');
    }
    return boardInfo?['release']?.toString() ?? '-';
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final dashboardData = appState.dashboardData;
    final sysInfo = dashboardData?['sysInfo'] as Map<String, dynamic>?;
    final boardInfo = dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final memory = sysInfo?['memory'] as Map?;
    final load = sysInfo?['load'] as List<dynamic>?;
    final conntrack = dashboardData?['conntrack'] as Map?;

    final totalMem = _asInt(memory?['total']);
    final freeMem = _asInt(memory?['free']);
    final bufferedMem = _asInt(memory?['buffered']);
    final cachedMem = _asInt(memory?['cached']);
    final cacheBytes = cachedMem + bufferedMem;
    final usedMem = (totalMem - freeMem - cacheBytes)
        .clamp(0, totalMem)
        .toInt();
    final cpuPercent = _fixedPointPercent(
      load?.isNotEmpty == true ? load![0] : 0,
    );
    final connCount = _asInt(conntrack?['count']);
    final connMax = _asInt(conntrack?['max']);
    final connProgress = connMax > 0 ? connCount / connMax : 0.0;

    return Scaffold(
      appBar: const LuciAppBar(title: 'System Resources', showBack: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([appState.fetchDashboardData(), _loadStorage()]);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.22,
                children: [
                  _MetricTile(
                    icon: Icons.memory_rounded,
                    color: const Color(0xFF2563EB),
                    title: 'CPU Load',
                    value: '${cpuPercent.round()}%',
                    suffix: '/ 100%',
                  ),
                  _MetricTile(
                    icon: Icons.inventory_2_rounded,
                    color: const Color(0xFFA855F7),
                    title: 'RAM Usage',
                    value: _formatBytes(usedMem),
                    suffix: 'Used',
                  ),
                  _MetricTile(
                    icon: Icons.sync_rounded,
                    color: const Color(0xFFF59E0B),
                    title: 'RAM Cache',
                    value: _formatBytes(cacheBytes),
                    suffix: 'Cached',
                  ),
                  _MetricTile(
                    icon: Icons.account_tree_rounded,
                    color: const Color(0xFF10B981),
                    title: 'Connections',
                    value: connCount.toString(),
                    suffix: '/ ${connMax > 0 ? connMax : 0}',
                    badge: connProgress < 0.75 ? 'Good' : 'High',
                  ),
                  _MetricTile(
                    icon: Icons.storage_rounded,
                    color: const Color(0xFF2563EB),
                    title: 'User Storage',
                    value: _isLoadingStorage
                        ? 'Loading'
                        : _formatBytes(_storage.userFreeBytes),
                    suffix: _storage.userTotalBytes > 0
                        ? 'Free of ${_formatBytes(_storage.userTotalBytes)}'
                        : 'Free',
                  ),
                  _MetricTile(
                    icon: Icons.developer_board_rounded,
                    color: const Color(0xFFF59E0B),
                    title: 'Temp Memory',
                    value: _isLoadingStorage
                        ? 'Loading'
                        : _formatBytes(_storage.tempFreeBytes),
                    suffix: _storage.tempTotalBytes > 0
                        ? 'Free of ${_formatBytes(_storage.tempTotalBytes)}'
                        : 'Free',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SystemInfoPanel(
                release: _releaseText(boardInfo),
                kernel: boardInfo?['kernel']?.toString() ?? '-',
                model: boardInfo?['model']?.toString() ?? '-',
                architecture:
                    boardInfo?['system']?.toString() ??
                    boardInfo?['architecture']?.toString() ??
                    '-',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String suffix;
  final String? badge;

  const _MetricTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.suffix,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF22C55E),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const Spacer(),
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 5,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  height: 1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  suffix,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SystemInfoPanel extends StatelessWidget {
  final String release;
  final String kernel;
  final String model;
  final String architecture;

  const _SystemInfoPanel({
    required this.release,
    required this.kernel,
    required this.model,
    required this.architecture,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF18AEEA).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF18AEEA),
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'System Info',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.42,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.32),
              ),
            ),
            child: Text(
              release,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.18,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _InfoRow(label: 'Kernel', value: kernel),
                _InfoRow(label: 'Model', value: model),
                _InfoRow(
                  label: 'Architecture',
                  value: architecture,
                  showDivider: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool showDivider;

  const _InfoRow({
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.28),
                ),
              )
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    height: 1.25,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
