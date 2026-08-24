import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/network_performance_settings_screen.dart';
import 'package:luci_mobile/screens/router_setup_screen.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

class NetworkPerformanceScreen extends ConsumerStatefulWidget {
  const NetworkPerformanceScreen({super.key});

  static const Color _cyan = Color(0xFF18AEEA);
  static const Color _orange = Color(0xFFF27C24);
  static const Color _green = Color(0xFF20CF70);
  static const Color _yellow = Color(0xFFEAB308);

  static List<PingMonitorSample> _samplesFromDashboard(AppState appState) {
    final rawSamples = appState.dashboardData?['pingSamples'];
    if (rawSamples is List<PingMonitorSample>) return rawSamples;
    return const [];
  }

  static String formatLatency(double? latencyMs) {
    if (latencyMs == null) return 'No data';
    if (latencyMs >= 100) return '${latencyMs.toStringAsFixed(0)}ms';
    return '${latencyMs.toStringAsFixed(1)}ms';
  }

  static double? averageLatestPingLatency(
    List<PingMonitorSample> samples, {
    int count = 5,
  }) {
    final latestLatencies = samples.where((sample) => sample.isOk).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final selected = latestLatencies
        .take(count)
        .map((sample) => sample.latencyMs)
        .whereType<double>()
        .toList();
    if (selected.isEmpty) return null;
    return selected.reduce((a, b) => a + b) / selected.length;
  }

  static List<_PingHourBucket> _hourBuckets(List<PingMonitorSample> samples) {
    final now = DateTime.now();
    final currentHour = DateTime(now.year, now.month, now.day, now.hour);
    return List<_PingHourBucket>.generate(6, (index) {
      final start = currentHour.subtract(Duration(hours: 5 - index));
      final end = start.add(const Duration(hours: 1));
      final bucketSamples = samples.where((sample) {
        final time = sample.timestamp.toLocal();
        return !time.isBefore(start) && time.isBefore(end);
      }).toList();
      final latencies = bucketSamples
          .where((sample) => sample.isOk)
          .map((sample) => sample.latencyMs)
          .whereType<double>()
          .toList();
      final failureCount = bucketSamples.length - latencies.length;
      final average = latencies.isEmpty
          ? null
          : latencies.reduce((a, b) => a + b) / latencies.length;
      return _PingHourBucket(
        averageLatencyMs: average,
        sampleCount: bucketSamples.length,
        failureCount: failureCount,
        hasSamples: bucketSamples.isNotEmpty,
        hasOnlyFailures: bucketSamples.isNotEmpty && latencies.isEmpty,
      );
    });
  }

  static Color _bucketColor(_PingHourBucket bucket, Color emptyColor) {
    if (!bucket.hasSamples) return emptyColor.withValues(alpha: 0.76);
    if (bucket.hasOnlyFailures) return const Color(0xFFFF424B);
    final latency = bucket.averageLatencyMs ?? 0;
    if (latency >= 100) return _yellow;
    return _green;
  }

  @override
  ConsumerState<NetworkPerformanceScreen> createState() =>
      _NetworkPerformanceScreenState();
}

class _NetworkPerformanceScreenState
    extends ConsumerState<NetworkPerformanceScreen> {
  List<PingMonitorSample>? _freshSamples;
  List<SpeedtestMonitorSample>? _speedtestSamples;
  Future<bool>? _supportFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshSamples());
  }

  Future<void> _refreshSamples() async {
    _supportFuture = null;
    final appState = ref.read(appStateProvider);
    final results = await Future.wait([
      appState.fetchPingMonitorSamples(context: mounted ? context : null),
      appState.fetchSpeedtestMonitorSamples(
        limit: 30,
        context: mounted ? context : null,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _freshSamples = results[0] as List<PingMonitorSample>;
      _speedtestSamples = results[1] as List<SpeedtestMonitorSample>;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final dashboardSamples = NetworkPerformanceScreen._samplesFromDashboard(
      appState,
    );
    final samples = _freshSamples ?? dashboardSamples;

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Network Performance',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Performance settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: _openPerformanceSettings,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refreshSamples,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            children: [
              FutureBuilder<bool>(
                future: _networkPerformanceSupport(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.data != true) {
                    return _NetworkSetupRequiredCard(
                      onPressed: _openRouterSetup,
                    );
                  }
                  return Column(
                    children: [
                      _NetworkTimelineCard(samples: samples),
                      const SizedBox(height: 14),
                      _RecentEventsCard(samples: samples),
                      const SizedBox(height: 14),
                      _PingTestCard(samples: samples),
                      const SizedBox(height: 14),
                      _SpeedTestCard(samples: _speedtestSamples ?? const []),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _networkPerformanceSupport() {
    return _supportFuture ??= ref
        .read(appStateProvider)
        .hasNetworkPerformanceSupport(context: context);
  }

  void _openRouterSetup() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const RouterSetupScreen()));
  }

  void _openPerformanceSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const NetworkPerformanceSettingsScreen(),
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

class _NetworkSetupRequiredCard extends StatelessWidget {
  final VoidCallback onPressed;

  const _NetworkSetupRequiredCard({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _OpenwallaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.network_check_rounded,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Network monitoring is not installed',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Install the Openwalla ping, DNS, and speedtest helper scripts to enable the timeline and test graphs.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.router_rounded),
            label: const Text('Open Router Setup'),
          ),
        ],
      ),
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
  final List<PingMonitorSample> samples;

  const _NetworkTimelineCard({required this.samples});

  String _formatHour(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour $suffix';
  }

  String _bucketTooltip(
    _PingHourBucket bucket,
    String startLabel,
    String endLabel,
  ) {
    if (!bucket.hasSamples) {
      return '$startLabel - $endLabel\nNo ping data';
    }
    final latency = bucket.averageLatencyMs == null
        ? 'No replies'
        : NetworkPerformanceScreen.formatLatency(bucket.averageLatencyMs);
    return '$startLabel - $endLabel\n'
        'Average latency: $latency\n'
        'Samples: ${bucket.sampleCount}\n'
        'Failures: ${bucket.failureCount}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final buckets = NetworkPerformanceScreen._hourBuckets(samples);
    final averageLatency = NetworkPerformanceScreen.averageLatestPingLatency(
      samples,
    );
    final currentHour = DateTime(now.year, now.month, now.day, now.hour);
    final labels = List<String>.generate(7, (index) {
      if (index == 6) return 'Now';
      return _formatHour(currentHour.subtract(Duration(hours: 5 - index)));
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
                NetworkPerformanceScreen.formatLatency(averageLatency),
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
            children: List.generate(buckets.length, (index) {
              final isLast = index == buckets.length - 1;
              final bucket = buckets[index];
              return Expanded(
                child: Tooltip(
                  message: _bucketTooltip(
                    bucket,
                    labels[index],
                    labels[index + 1],
                  ),
                  triggerMode: TooltipTriggerMode.tap,
                  showDuration: const Duration(seconds: 3),
                  preferBelow: false,
                  child: Container(
                    height: 12,
                    margin: EdgeInsets.only(right: isLast ? 0 : 2),
                    decoration: BoxDecoration(
                      color: NetworkPerformanceScreen._bucketColor(
                        bucket,
                        colorScheme.surfaceContainerHighest,
                      ),
                      borderRadius: BorderRadius.horizontal(
                        left: index == 0
                            ? const Radius.circular(6)
                            : Radius.zero,
                        right: isLast ? const Radius.circular(6) : Radius.zero,
                      ),
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

class _PingHourBucket {
  final double? averageLatencyMs;
  final int sampleCount;
  final int failureCount;
  final bool hasSamples;
  final bool hasOnlyFailures;

  const _PingHourBucket({
    required this.averageLatencyMs,
    required this.sampleCount,
    required this.failureCount,
    required this.hasSamples,
    required this.hasOnlyFailures,
  });
}

class _RecentEventsCard extends StatelessWidget {
  final List<PingMonitorSample> samples;

  const _RecentEventsCard({required this.samples});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final recentProblems = samples
        .where((sample) => !sample.isOk || (sample.latencyMs ?? 0) >= 100)
        .toList()
        .reversed
        .take(2)
        .toList();
    final events = recentProblems
        .map(
          (sample) => (
            'ping_monitor',
            sample.isOk
                ? 'High latency detected: ${NetworkPerformanceScreen.formatLatency(sample.latencyMs)}'
                : 'Ping outage detected: ${sample.message}',
            sample.timestamp.toLocal().toString(),
          ),
        )
        .toList();

    return _OpenwallaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Recent Events'),
          const SizedBox(height: 14),
          if (events.isEmpty)
            Text(
              'No recent events',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            )
          else
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
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.68),
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
  final List<PingMonitorSample> samples;

  const _PingTestCard({required this.samples});

  String _formatTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentSlot = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      (now.minute ~/ 5) * 5,
    );
    final slots = List<DateTime>.generate(
      12,
      (index) => currentSlot.subtract(Duration(minutes: (11 - index) * 5)),
    );
    final slotSamples = slots.map((slotStart) {
      final slotEnd = slotStart.add(const Duration(minutes: 5));
      final matches = samples.where((sample) {
        final time = sample.timestamp.toLocal();
        return !time.isBefore(slotStart) && time.isBefore(slotEnd);
      }).toList();
      if (matches.isEmpty) return null;
      return matches.last;
    }).toList();
    final labels = slots.map(_formatTime).toList();
    final validLatencies = slotSamples
        .map((sample) => sample?.latencyMs)
        .whereType<double>()
        .toList();
    final maxLatency = validLatencies.isEmpty
        ? 100.0
        : validLatencies.reduce((a, b) => a > b ? a : b).clamp(1, 1000);
    final averageLatency = NetworkPerformanceScreen.averageLatestPingLatency(
      samples,
    );
    final minLatency = validLatencies.isEmpty
        ? null
        : validLatencies.reduce((a, b) => a < b ? a : b);
    final maxLatencyValue = validLatencies.isEmpty
        ? null
        : validLatencies.reduce((a, b) => a > b ? a : b);
    final bars = slotSamples
        .map(
          (sample) => sample?.latencyMs == null
              ? 0.16
              : (sample!.latencyMs! / maxLatency).clamp(0.04, 1.0),
        )
        .toList();
    final hasData = slotSamples
        .map((sample) => sample?.latencyMs != null)
        .toList();
    final readableLabels = labels.asMap().entries.map((entry) {
      final index = entry.key;
      if (index == 0 || index == labels.length ~/ 2) return entry.value;
      if (index == labels.length - 1) return 'Now';
      return '';
    }).toList();
    final tooltips = slotSamples.asMap().entries.map((entry) {
      final sample = entry.value;
      final slotLabel = entry.key == slotSamples.length - 1
          ? 'Now'
          : labels[entry.key];
      if (sample == null) return '$slotLabel\nNo ping data';
      final latency = NetworkPerformanceScreen.formatLatency(sample.latencyMs);
      return '$slotLabel\nLatency: $latency\nStatus: ${sample.status}\nTarget: ${sample.target}';
    }).toList();

    return _ChartPanel(
      title: 'Ping Test',
      value: NetworkPerformanceScreen.formatLatency(averageLatency),
      label: 'Last 5 avg',
      bars: bars,
      hasData: hasData,
      color: NetworkPerformanceScreen._green,
      secondaryColor: NetworkPerformanceScreen._yellow,
      labels: readableLabels,
      tooltips: tooltips,
      stats: [
        (
          label: 'Min',
          value: NetworkPerformanceScreen.formatLatency(minLatency),
        ),
        (
          label: 'Avg',
          value: NetworkPerformanceScreen.formatLatency(averageLatency),
        ),
        (
          label: 'Max',
          value: NetworkPerformanceScreen.formatLatency(maxLatencyValue),
        ),
      ],
    );
  }
}

class _SpeedTestCard extends StatelessWidget {
  final List<SpeedtestMonitorSample> samples;

  const _SpeedTestCard({required this.samples});

  String _formatDay(DateTime time) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[time.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final slots = List<DateTime>.generate(
      7,
      (index) => today.subtract(Duration(days: 6 - index)),
    );
    final slotSamples = slots.map((slotStart) {
      final slotEnd = slotStart.add(const Duration(days: 1));
      final matches = samples.where((sample) {
        final time = sample.timestamp.toLocal();
        return !time.isBefore(slotStart) && time.isBefore(slotEnd);
      }).toList();
      if (matches.isEmpty) return null;
      return matches.last;
    }).toList();
    final labels = slots.map(_formatDay).toList();
    final validDownloads = slotSamples
        .map((sample) => sample?.downloadMbps)
        .whereType<double>()
        .toList();
    final maxDownload = validDownloads.isEmpty
        ? 100.0
        : validDownloads.reduce((a, b) => a > b ? a : b).clamp(1, 10000);
    final latestDownload = slotSamples.reversed
        .map((sample) => sample?.downloadMbps)
        .whereType<double>()
        .firstOrNull;
    final bars = slotSamples
        .map(
          (sample) => sample?.downloadMbps == null
              ? 0.16
              : (sample!.downloadMbps! / maxDownload).clamp(0.04, 1.0),
        )
        .toList();
    final hasData = slotSamples
        .map((sample) => sample?.downloadMbps != null)
        .toList();
    final tooltips = slotSamples.asMap().entries.map((entry) {
      final sample = entry.value;
      final label = entry.key == slotSamples.length - 1
          ? 'Today'
          : labels[entry.key];
      if (sample == null) return '$label\nNo speedtest data';
      final down = sample.downloadMbps == null
          ? 'N/A'
          : '${sample.downloadMbps!.toStringAsFixed(1)} Mbps';
      final up = sample.uploadMbps == null
          ? 'N/A'
          : '${sample.uploadMbps!.toStringAsFixed(1)} Mbps';
      return '$label\nDownload: $down\nUpload: $up\nStatus: ${sample.status}';
    }).toList();

    return _ChartPanel(
      title: 'Speed Test',
      value: latestDownload == null
          ? 'No data'
          : '${latestDownload.toStringAsFixed(0)} Mbps',
      label: 'Latest result',
      bars: bars,
      hasData: hasData,
      color: NetworkPerformanceScreen._cyan,
      secondaryColor: NetworkPerformanceScreen._orange,
      labels: labels,
      tooltips: tooltips,
    );
  }
}

class _ChartStatPill extends StatelessWidget {
  final String label;
  final String value;

  const _ChartStatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
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
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPanel extends StatelessWidget {
  final String title;
  final String value;
  final String label;
  final List<double> bars;
  final List<bool> hasData;
  final Color color;
  final Color secondaryColor;
  final List<String> labels;
  final List<String> tooltips;
  final List<({String label, String value})> stats;

  const _ChartPanel({
    required this.title,
    required this.value,
    required this.label,
    required this.bars,
    required this.hasData,
    required this.color,
    required this.secondaryColor,
    required this.labels,
    this.tooltips = const [],
    this.stats = const [],
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
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: stats
                  .map(
                    (stat) => Expanded(
                      child: _ChartStatPill(
                        label: stat.label,
                        value: stat.value,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            height: 128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(bars.length, (index) {
                final height = 112 * bars[index].clamp(0, 1).toDouble();
                final hasSample = index < hasData.length && hasData[index];
                return Expanded(
                  child: Tooltip(
                    message: index < tooltips.length
                        ? tooltips[index]
                        : labels[index],
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 3),
                    preferBelow: false,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 12,
                        height: height < 3 ? 3 : height,
                        decoration: BoxDecoration(
                          color: !hasSample
                              ? colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.28,
                                )
                              : index == bars.length - 2
                              ? secondaryColor
                              : color,
                          borderRadius: BorderRadius.circular(4),
                        ),
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
