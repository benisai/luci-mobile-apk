import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

enum _NotificationMenuAction { archiveAll, deleteAll }

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<OpenwallaNotification> _notifications = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNotifications());
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final appState = ref.read(appStateProvider);
    final notifications = await appState.fetchNotifications(context: context);
    await appState.refreshNotificationCount();
    if (!mounted) return;
    setState(() {
      _notifications = notifications;
      _isLoading = false;
    });
  }

  Future<void> _archiveOne(OpenwallaNotification notification) async {
    await ref
        .read(appStateProvider)
        .archiveNotification(notification.id, context: context);
    await _loadNotifications();
  }

  Future<void> _archiveAll() async {
    await ref.read(appStateProvider).archiveAllNotifications(context: context);
    await _loadNotifications();
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all notifications?'),
        content: const Text(
          'This will remove all active and archived notifications.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(appStateProvider).deleteAllNotifications(context: context);
    await _loadNotifications();
  }

  Future<void> _handleMenuAction(_NotificationMenuAction action) async {
    switch (action) {
      case _NotificationMenuAction.archiveAll:
        await _archiveAll();
      case _NotificationMenuAction.deleteAll:
        await _deleteAll();
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
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
    final month = months[(local.month - 1).clamp(0, 11)];
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month ${local.day.toString().padLeft(2, '0')}, ${local.hour}:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasNotifications = _notifications.isNotEmpty;

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Notifications',
        showBack: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<_NotificationMenuAction>(
              enabled: hasNotifications,
              onSelected: _handleMenuAction,
              icon: Icon(
                Icons.more_horiz_rounded,
                color: hasNotifications
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
              ),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _NotificationMenuAction.archiveAll,
                  child: Text('Archive All'),
                ),
                PopupMenuItem(
                  value: _NotificationMenuAction.deleteAll,
                  child: Text('Delete All'),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadNotifications,
          child: _isLoading
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  children: const [
                    SizedBox(height: 180),
                    Center(child: CircularProgressIndicator()),
                  ],
                )
              : _notifications.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  children: [
                    SizedBox(
                      height: 260,
                      child: Center(
                        child: Text(
                          'No active notifications',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  itemBuilder: (context, index) => _NotificationCard(
                    notification: _notifications[index],
                    timestamp: _formatTimestamp(
                      _notifications[index].timestamp,
                    ),
                    onArchive: () => _archiveOne(_notifications[index]),
                  ),
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 14),
                  itemCount: _notifications.length,
                ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final OpenwallaNotification notification;
  final String timestamp;
  final VoidCallback onArchive;

  const _NotificationCard({
    required this.notification,
    required this.timestamp,
    required this.onArchive,
  });

  Color _notificationColor() {
    final app = notification.app.toLowerCase();
    final message = notification.message.toLowerCase();
    if (message.contains('outage') || message.contains('failed')) {
      return const Color(0xFFFF424B);
    }
    if (app.contains('ping') || message.contains('threshold')) {
      return const Color(0xFFEAB308);
    }
    if (app.contains('quarantine') || message.contains('new device')) {
      return const Color(0xFF20CF70);
    }
    return const Color(0xFF18AEEA);
  }

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
      padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            color: _notificationColor(),
            size: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.app.isEmpty ? 'openwalla' : notification.app,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  notification.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  timestamp,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Archive',
            onPressed: onArchive,
            icon: Icon(Icons.close_rounded, color: colorScheme.onSurface),
          ),
        ],
      ),
    );
  }
}
