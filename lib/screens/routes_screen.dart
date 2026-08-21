import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({super.key});

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen> {
  List<OpenwrtStaticRoute> _routes = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoutes());
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final routes = await ref
          .read(appStateProvider)
          .fetchStaticRoutes(context: context);
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load static routes.';
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddRouteSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _AddRouteSheet(),
    );
    if (saved == true) await _loadRoutes();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Routes',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Add route',
            onPressed: _showAddRouteSheet,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadRoutes,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Static IPv4 Routes',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _showAddRouteSheet,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _RouteEmptyCard(message: _error!, onRefresh: _loadRoutes)
              else if (_routes.isEmpty)
                _RouteEmptyCard(
                  message: 'No static routes found.',
                  onRefresh: _loadRoutes,
                )
              else
                ..._routes.map((route) => _RouteCard(route: route)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final OpenwrtStaticRoute route;

  const _RouteCard({required this.route});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final gateway = route.gateway.isEmpty ? 'parent gateway' : route.gateway;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.route_rounded,
                color: route.enabled
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  route.target,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                route.routeType,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _RouteMeta(
                  label: 'Interface',
                  value: route.interfaceName,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RouteMeta(label: 'Gateway', value: gateway),
              ),
              const SizedBox(width: 12),
              _RouteMeta(label: 'Metric', value: route.metric),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteMeta extends StatelessWidget {
  final String label;
  final String value;

  const _RouteMeta({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value.isEmpty ? '-' : value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _RouteEmptyCard extends StatelessWidget {
  final String message;
  final VoidCallback onRefresh;

  const _RouteEmptyCard({required this.message, required this.onRefresh});

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
          Text(message, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class _AddRouteSheet extends ConsumerStatefulWidget {
  const _AddRouteSheet();

  @override
  ConsumerState<_AddRouteSheet> createState() => _AddRouteSheetState();
}

class _AddRouteSheetState extends ConsumerState<_AddRouteSheet> {
  final _targetController = TextEditingController();
  final _gatewayController = TextEditingController();
  final _metricController = TextEditingController();
  var _interfaceName = 'lan';
  var _routeType = 'unicast';
  var _interfaces = const ['lan', 'wan'];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final names = ref.read(appStateProvider).dashboardInterfaceNames();
    _interfaces = names.isEmpty ? _interfaces : names;
    _interfaceName = _interfaces.first;
  }

  @override
  void dispose() {
    _targetController.dispose();
    _gatewayController.dispose();
    _metricController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final target = _targetController.text.trim();
    if (target.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await ref
          .read(appStateProvider)
          .addStaticRoute(
            interfaceName: _interfaceName,
            routeType: _routeType,
            target: target,
            gateway: _gatewayController.text,
            metric: _metricController.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add route: $e')));
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Route',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _interfaceName,
              decoration: const InputDecoration(labelText: 'Interface'),
              items: _interfaces
                  .map(
                    (name) => DropdownMenuItem(value: name, child: Text(name)),
                  )
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (value) => setState(
                      () => _interfaceName = value ?? _interfaceName,
                    ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _routeType,
              decoration: const InputDecoration(labelText: 'Route type'),
              items: const ['unicast', 'blackhole', 'unreachable', 'prohibit']
                  .map(
                    (type) => DropdownMenuItem(value: type, child: Text(type)),
                  )
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (value) => setState(() => _routeType = value ?? _routeType),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetController,
              enabled: !_isSaving,
              decoration: const InputDecoration(
                labelText: 'Target',
                hintText: '0.0.0.0/0',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gatewayController,
              enabled: !_isSaving,
              decoration: const InputDecoration(
                labelText: 'Gateway',
                hintText: '192.168.0.1',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _metricController,
              enabled: !_isSaving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Metric'),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Dismiss'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
