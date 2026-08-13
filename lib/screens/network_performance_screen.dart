import 'package:flutter/material.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

class NetworkPerformanceScreen extends StatelessWidget {
  const NetworkPerformanceScreen({super.key});

  static const Color _cyan = Color(0xFF18AEEA);
  static const Color _orange = Color(0xFFF27C24);
  static const Color _green = Color(0xFF20CF70);
  static const Color _yellow = Color(0xFFEAB308);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Network Performance', showBack: true),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: const [
            _NetworkTimelineCard(),
            SizedBox(height: 14),
            _RecentEventsCard(),
            SizedBox(height: 14),
            _PingTestCard(),
            SizedBox(height: 14),
            _SpeedTestCard(),
          ],
        ),
      ),
    );
  }
}

class _OpenwallaPanel extends StatelessWidget {
  final Widget child;

  const _OpenwallaPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }
}

class _NetworkTimelineCard extends StatelessWidget {
  const _NetworkTimelineCard();

  String _formatHour(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final labels = List<String>.generate(7, (index) {
      if (index == 6) return 'Now';
      return _formatHour(now.subtract(Duration(hours: 12 - (index * 2))));
    });

    return _OpenwallaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Network Timeline'),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '0ms',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  height: 0.95,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'Latency',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: List.generate(6, (index) {
              final isLast = index == 5;
              return Expanded(
                child: Container(
                  height: 12,
                  margin: EdgeInsets.only(right: isLast ? 0 : 2),
                  decoration: BoxDecoration(
                    color: index == 4
                        ? NetworkPerformanceScreen._yellow
                        : NetworkPerformanceScreen._green,
                    borderRadius: BorderRadius.horizontal(
                      left: index == 0 ? const Radius.circular(6) : Radius.zero,
                      right: isLast ? const Radius.circular(6) : Radius.zero,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labels
                .map(
                  (label) => Flexible(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _RecentEventsCard extends StatelessWidget {
  const _RecentEventsCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final events = [
      ('internet_monitor', 'No recent latency events', 'Pending data source'),
      (
        'speedtest',
        'Speed test history will appear here',
        'Pending data source',
      ),
      (
        'ping_monitor',
        'Ping test history will appear here',
        'Pending data source',
      ),
    ];

    return _OpenwallaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Recent Events'),
          const SizedBox(height: 14),
          ...events.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.circle_rounded,
                    size: 9,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.$1,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          event.$2,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          event.$3,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.68,
                                ),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PingTestCard extends StatelessWidget {
  const _PingTestCard();

  String _formatTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final labels = List<String>.generate(12, (index) {
      return _formatTime(now.subtract(Duration(minutes: (11 - index) * 5)));
    });

    return _ChartPanel(
      title: 'Ping Test',
      value: '0ms',
      label: 'Average latency',
      bars: const [
        0.18,
        0.22,
        0.2,
        0.28,
        0.24,
        0.3,
        0.26,
        0.22,
        0.32,
        0.25,
        0.2,
        0.18,
      ],
      color: NetworkPerformanceScreen._green,
      secondaryColor: NetworkPerformanceScreen._yellow,
      labels: labels,
    );
  }
}

class _SpeedTestCard extends StatelessWidget {
  const _SpeedTestCard();

  String _formatDay(DateTime time) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[time.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final labels = List<String>.generate(7, (index) {
      return _formatDay(now.subtract(Duration(days: 6 - index)));
    });

    return _ChartPanel(
      title: 'Speed Test',
      value: '0 Mbps',
      label: 'Latest result',
      bars: const [0.2, 0.38, 0.34, 0.52, 0.44, 0.6, 0.48],
      color: NetworkPerformanceScreen._cyan,
      secondaryColor: NetworkPerformanceScreen._orange,
      labels: labels,
    );
  }
}

class _ChartPanel extends StatelessWidget {
  final String title;
  final String value;
  final String label;
  final List<double> bars;
  final Color color;
  final Color secondaryColor;
  final List<String> labels;

  const _ChartPanel({
    required this.title,
    required this.value,
    required this.label,
    required this.bars,
    required this.color,
    required this.secondaryColor,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _OpenwallaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  height: 0.95,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(bars.length, (index) {
                final height = 112 * bars[index].clamp(0, 1).toDouble();
                return Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 12,
                      height: height < 3 ? 3 : height,
                      decoration: BoxDecoration(
                        color: index == bars.length - 2
                            ? secondaryColor
                            : color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(labels.length, (index) {
              final label = labels[index];
              return Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
