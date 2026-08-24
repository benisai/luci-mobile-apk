import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  Future<List<OpenwallaServiceStatus>>? _servicesFuture;
  String? _busyService;

  @override
  void initState() {
    super.initState();
    _servicesFuture = _loadServices();
  }

  Future<List<OpenwallaServiceStatus>> _loadServices() {
    return ref.read(appStateProvider).fetchOpenwallaServices(context: context);
  }

  Future<void> _refresh() async {
    setState(() => _servicesFuture = _loadServices());
    await _servicesFuture;
  }

  Future<void> _toggleService(
    OpenwallaServiceStatus service,
    bool enabled,
  ) async {
    setState(() => _busyService = service.name);
    try {
      await ref
          .read(appStateProvider)
          .setOpenwallaServiceEnabled(service.name, enabled, context: context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${service.label} ${enabled ? 'enabled' : 'disabled'}.',
          ),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update ${service.label}: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyService = null);
    }
  }

  Future<void> _restartService(OpenwallaServiceStatus service) async {
    setState(() => _busyService = service.name);
    try {
      await ref
          .read(appStateProvider)
          .restartOpenwallaService(service.name, context: context);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${service.label} restarted.')));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to restart ${service.label}: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyService = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Services',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Refresh services',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<OpenwallaServiceStatus>>(
        future: _servicesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LuciLoadingWidget();
          }

          final services = snapshot.data ?? const <OpenwallaServiceStatus>[];
          if (snapshot.hasError) {
            return _ServicesEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Unable to load services',
              message: snapshot.error.toString(),
              onRefresh: _refresh,
            );
          }
          if (services.isEmpty) {
            return _ServicesEmptyState(
              icon: Icons.miscellaneous_services_rounded,
              title: 'No services found',
              message: 'Pull down to refresh the router service list.',
              onRefresh: _refresh,
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: services.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final service = services[index];
                return _ServiceCard(
                  service: service,
                  isBusy: _busyService == service.name,
                  onToggle: service.installed
                      ? (enabled) => _toggleService(service, enabled)
                      : null,
                  onRestart: service.installed && _busyService == null
                      ? () => _restartService(service)
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final OpenwallaServiceStatus service;
  final bool isBusy;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onRestart;

  const _ServiceCard({
    required this.service,
    required this.isBusy,
    required this.onToggle,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = !service.installed
        ? colorScheme.onSurfaceVariant
        : service.running
        ? const Color(0xFF20CF70)
        : const Color(0xFFFF4D4F);
    final statusLabel = !service.installed
        ? 'Missing'
        : service.running
        ? 'Running'
        : 'Stopped';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.miscellaneous_services_rounded,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          service.label,
                          style: LuciTextStyles.cardTitle(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _StatusPill(label: statusLabel, color: statusColor),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    service.name,
                    style: LuciTextStyles.cardSubtitle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (service.statusText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      service.statusText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isBusy)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              IconButton(
                tooltip: 'Restart',
                icon: const Icon(Icons.restart_alt_rounded),
                onPressed: onRestart,
              ),
              Switch.adaptive(value: service.enabled, onChanged: onToggle),
            ],
          ],
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
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ServicesEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function() onRefresh;

  const _ServicesEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          Icon(icon, size: 56, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
