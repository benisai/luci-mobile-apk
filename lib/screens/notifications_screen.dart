import 'package:flutter/material.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationItem {
  final String type;
  final String message;
  final String timestamp;
  final Color color;

  const _NotificationItem({
    required this.type,
    required this.message,
    required this.timestamp,
    required this.color,
  });
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<_NotificationItem> _notifications = [
    const _NotificationItem(
      type: 'internet_monitor',
      message: 'High latency detected: 20.1ms at 2025-11-05T04:31:20.952Z',
      timestamp: 'Nov 04, 2025 20:31',
      color: Color(0xFFEAB308),
    ),
    const _NotificationItem(
      type: 'new_device',
      message:
          'New device Unknown with IP 10.0.0.10 joined the network on 11/4/2025, 8:29:43 PM',
      timestamp: 'Nov 04, 2025 20:29',
      color: Color(0xFF20CF70),
    ),
  ];

  void _archiveAll() {
    setState(_notifications.clear);
  }

  void _archiveOne(int index) {
    setState(() {
      _notifications.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Notifications',
        showBack: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _notifications.isEmpty ? null : _archiveAll,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
                disabledForegroundColor: colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.45),
                backgroundColor: colorScheme.surfaceContainerLowest,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: const Text(
                'Archive All',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _notifications.isEmpty
            ? Center(
                child: Text(
                  'No notifications',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                itemBuilder: (context, index) => _NotificationCard(
                  notification: _notifications[index],
                  onArchive: () => _archiveOne(index),
                ),
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 14),
                itemCount: _notifications.length,
              ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final _NotificationItem notification;
  final VoidCallback onArchive;

  const _NotificationCard({
    required this.notification,
    required this.onArchive,
  });

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
            color: notification.color,
            size: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.type,
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
                  notification.timestamp,
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
