import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_animation_system.dart';
import 'package:luci_mobile/models/dashboard_preferences.dart';
import 'package:luci_mobile/screens/flows_screen.dart';
import 'package:luci_mobile/screens/monthly_usage_screen.dart';
import 'package:luci_mobile/screens/network_performance_screen.dart';
import 'package:luci_mobile/screens/notifications_screen.dart';
import 'package:luci_mobile/screens/rules_screen.dart';
import 'package:luci_mobile/screens/simple_flows_screen.dart';
import 'package:luci_mobile/screens/system_resources_screen.dart';
import 'package:luci_mobile/models/router.dart' as model;

enum _UsageRange { minute, hour, day, week }

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  static const Color _openwallaCyan = Color(0xFF18AEEA);
  static const Color _openwallaOrange = Color(0xFFF27C24);
  static const Color _openwallaGreen = Color(0xFF20CF70);
  static const Color _openwallaCardBorder = Color(0xFF313C52);
  static const double _openwallaRadius = 8;
  _UsageRange _usageRange = _UsageRange.day;
  final Map<String, Future<List<VnstatUsageSample>>> _usageFutures = {};
  Future<MonthlyUsageSettings>? _monthlyUsageSettingsFuture;
  Timer? _summaryRefreshTimer;
  bool _summaryRefreshInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appStateProvider).fetchDashboardData();
      _startSummaryRefreshTimer();
    });
  }

  @override
  void dispose() {
    _summaryRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startSummaryRefreshTimer();
      _refreshSummaryCounts();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _summaryRefreshTimer?.cancel();
      _summaryRefreshTimer = null;
    }
  }

  void _startSummaryRefreshTimer() {
    _summaryRefreshTimer?.cancel();
    _summaryRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshSummaryCounts();
    });
  }

  Future<void> _refreshSummaryCounts() async {
    if (!mounted || _summaryRefreshInFlight) return;
    _summaryRefreshInFlight = true;
    try {
      await ref
          .read(appStateProvider)
          .refreshDashboardSummaryCounts(context: context);
    } finally {
      _summaryRefreshInFlight = false;
    }
  }

  double _scaledLoadPercent(List<dynamic>? load, int index) {
    if (load == null || load.isEmpty) return 0;
    final safeIndex = index < load.length ? index : 0;
    final value = load[safeIndex];
    if (value is! num) return 0;
    return ((value / 65536) * 100).clamp(0, 100).toDouble();
  }

  double _legacyCpuLoadPercent(Map<String, dynamic>? sysInfo) {
    final load = sysInfo?['load'] as List<dynamic>?;
    return _scaledLoadPercent(load, 0);
  }

  double _legacyMemoryPercent(Map<String, dynamic>? sysInfo) {
    final memory = sysInfo?['memory'];
    if (memory is! Map) return 0;

    final totalMem = memory['total'] as int? ?? 0;
    final freeMem = memory['free'] as int? ?? 0;
    final bufferedMem = memory['buffered'] as int? ?? 0;
    final usedMem = totalMem - freeMem - bufferedMem;

    return totalMem > 0
        ? (usedMem / totalMem * 100).clamp(0, 100).toDouble()
        : 0.0;
  }

  Widget _buildOpenwallaCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? _openwallaCardBorder
        : colorScheme.outlineVariant.withValues(alpha: 0.62);

    return Container(
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(_openwallaRadius),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildOpenwallaCardHeader({
    required IconData icon,
    required String title,
    Color? color,
    Widget? trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = color ?? colorScheme.primary;

    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(_openwallaRadius),
          ),
          child: Icon(icon, size: 17, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildDashboardSummaryCards(AppState appState) {
    final deviceCount = appState.dashboardData?['deviceCount'];
    final notificationCount = appState.dashboardData?['notificationCount'];
    final rulesCount = appState.dashboardData?['rulesCount'];

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDashboardSummaryCard(
                label: 'Devices',
                count: (deviceCount is int ? deviceCount : 0).toString(),
                icon: Icons.devices_rounded,
                color: _openwallaCyan,
                onTap: () => ref.read(appStateProvider).requestTab(1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildDashboardSummaryCard(
                label: 'Notifications',
                count: (notificationCount is int ? notificationCount : 0)
                    .toString(),
                icon: Icons.notifications_rounded,
                color: _openwallaOrange,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const NotificationsScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildDashboardSummaryCard(
                label: 'Rules',
                count: (rulesCount is int ? rulesCount : 0).toString(),
                icon: Icons.rule_rounded,
                color: _openwallaGreen,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const RulesScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDashboardSummaryCard({
    required String label,
    required String count,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildOpenwallaCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(
            count,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardFlowsCard(AppState appState) {
    final colorScheme = Theme.of(context).colorScheme;
    const flowColor = Color(0xFF8B5CF6);
    final flowSummary = appState.dashboardData?['flowSummary'];
    final flowMode = appState.dashboardPreferences.flowMode;
    final provider = flowSummary is OpenwallaFlowSummary
        ? flowSummary.provider
        : appState.dashboardData?['flowProvider'];
    if (provider == OpenwallaFlowProvider.none) {
      return const SizedBox.shrink();
    }
    final flowCount = flowSummary is OpenwallaFlowSummary
        ? flowSummary.count
        : appState.dashboardData?['netifyFlowCount'] as int? ?? 0;
    final title = flowMode == DashboardFlowMode.simple
        ? 'Simple Flow'
        : 'Detailed Flow';
    final sourceLabel = flowMode == DashboardFlowMode.simple
        ? 'Conntrack'
        : 'Netify';

    return _buildOpenwallaCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => flowMode == DashboardFlowMode.simple
                ? const SimpleFlowsScreen()
                : const FlowsScreen(),
          ),
        );
      },
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: flowColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(_openwallaRadius),
            ),
            child: const Icon(
              Icons.account_tree_rounded,
              color: flowColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatCompactCount(flowCount),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                            height: 1,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        sourceLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  bool _hasDashboardFlowsCard(AppState appState) {
    final flowSummary = appState.dashboardData?['flowSummary'];
    final provider = flowSummary is OpenwallaFlowSummary
        ? flowSummary.provider
        : appState.dashboardData?['flowProvider'];
    return provider != OpenwallaFlowProvider.none;
  }

  String _formatTimelineHour(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour $suffix';
  }

  String _formatCompactCount(int value) {
    if (value < 1000) return value.toString();
    if (value < 1000000) {
      final thousands = value / 1000;
      return '${thousands.toStringAsFixed(thousands >= 10 ? 0 : 1)}K';
    }
    final millions = value / 1000000;
    return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}M';
  }

  List<PingMonitorSample> _pingSamples(AppState appState) {
    final rawSamples = appState.dashboardData?['pingSamples'];
    if (rawSamples is List<PingMonitorSample>) return rawSamples;
    return const [];
  }

  String _formatLatencyValue(double? latencyMs) {
    if (latencyMs == null) return 'No data';
    if (latencyMs >= 100) return '${latencyMs.toStringAsFixed(0)}ms';
    return '${latencyMs.toStringAsFixed(1)}ms';
  }

  List<_PingHourBucket> _pingHourBuckets(List<PingMonitorSample> samples) {
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

  Color _pingBucketColor(_PingHourBucket bucket) {
    if (!bucket.hasSamples) {
      return Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.28);
    }
    if (bucket.hasOnlyFailures) return Theme.of(context).colorScheme.error;
    final latency = bucket.averageLatencyMs ?? 0;
    if (latency >= 100) return const Color(0xFFEAB308);
    return _openwallaGreen;
  }

  String _pingBucketTooltip(
    _PingHourBucket bucket,
    String startLabel,
    String endLabel,
  ) {
    if (!bucket.hasSamples) {
      return '$startLabel - $endLabel\nNo ping data';
    }
    final latency = bucket.averageLatencyMs == null
        ? 'No replies'
        : _formatLatencyValue(bucket.averageLatencyMs);
    return '$startLabel - $endLabel\n'
        'Average latency: $latency\n'
        'Samples: ${bucket.sampleCount}\n'
        'Failures: ${bucket.failureCount}';
  }

  Widget _buildNetworkPerformanceCard({required AppState appState}) {
    final colorScheme = Theme.of(context).colorScheme;
    final samples = _pingSamples(appState);
    final buckets = _pingHourBuckets(samples);
    final averageLatency = NetworkPerformanceScreen.averageLatestPingLatency(
      samples,
    );
    final now = DateTime.now();
    final currentHour = DateTime(now.year, now.month, now.day, now.hour);
    final labels = List<String>.generate(7, (index) {
      if (index == 6) return 'Now';
      return _formatTimelineHour(
        currentHour.subtract(Duration(hours: 5 - index)),
      );
    });

    return _buildOpenwallaCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const NetworkPerformanceScreen(),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Network Performance',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              _subtleCardArrow(),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatLatencyValue(averageLatency),
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
                  message: _pingBucketTooltip(
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
                      color: _pingBucketColor(bucket),
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

  Widget _buildTitleWithTimestamp(String title, AppState appState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildRealtimeThroughputCard(AppState appState) {
    final prefs = appState.dashboardPreferences;

    // Determine which throughput data to use
    List<double> rxHistory;
    List<double> txHistory;
    double currentRxRate;
    double currentTxRate;
    String throughputLabel = '';

    if (!prefs.showAllThroughput && prefs.primaryThroughputInterface != null) {
      // Use specific interface throughput
      final interface = prefs.primaryThroughputInterface!;
      rxHistory = appState.getRxHistoryForInterface(interface);
      txHistory = appState.getTxHistoryForInterface(interface);
      currentRxRate = appState.getCurrentRxRateForInterface(interface);
      currentTxRate = appState.getCurrentTxRateForInterface(interface);
      throughputLabel = ' - $interface';
    } else {
      // Use combined throughput
      rxHistory = appState.rxHistory;
      txHistory = appState.txHistory;
      currentRxRate = appState.currentRxRate;
      currentTxRate = appState.currentTxRate;
    }

    // Show loading state if we don't have any throughput data yet
    final hasValidData =
        rxHistory.isNotEmpty ||
        txHistory.isNotEmpty ||
        currentRxRate > 0 ||
        currentTxRate > 0; // Show data as soon as we have any throughput info
    // Only show switching state if we're loading AND no dashboard data is available (true router switch)
    final isSwitchingRouter =
        appState.isLoading && appState.dashboardData == null;

    final card = _buildOpenwallaCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOpenwallaCardHeader(
            icon: Icons.show_chart_rounded,
            title: 'Live Traffic',
            color: _openwallaCyan,
            trailing: throughputLabel.isNotEmpty
                ? Text(
                    throughputLabel.replaceFirst(' - ', ''),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSpeedIndicator(
                  Icons.arrow_downward,
                  _openwallaCyan,
                  '',
                  isSwitchingRouter ? 0.0 : currentRxRate,
                ),
                _buildSpeedIndicator(
                  Icons.arrow_upward,
                  _openwallaOrange,
                  '',
                  isSwitchingRouter ? 0.0 : currentTxRate,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                top: 16.0,
              ), // Add space above the chart
              child: AnimatedSwitcher(
                duration: const Duration(
                  milliseconds: 600,
                ), // Smoother transition
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, 0.2),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
                  );
                },
                child: hasValidData && !isSwitchingRouter
                    ? LineChart(
                        key: ValueKey('chart_${appState.selectedRouter?.id}'),
                        LineChartData(
                          gridData: FlGridData(show: false),
                          titlesData: FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              fitInsideVertically: true,
                              getTooltipColor: (LineBarSpot spot) => Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.9),
                              tooltipBorderRadius: BorderRadius.circular(8),
                              tooltipPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              getTooltipItems:
                                  (List<LineBarSpot> touchedSpots) {
                                    return touchedSpots.map((barSpot) {
                                      final flSpot = barSpot;
                                      final Color color =
                                          flSpot.bar.gradient?.colors.first ??
                                          flSpot.bar.color ??
                                          Colors.white;

                                      return LineTooltipItem(
                                        _formatSpeed(flSpot.y),
                                        TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w900,
                                        ),
                                        textAlign: TextAlign.left,
                                      );
                                    }).toList();
                                  },
                            ),
                          ),
                          lineBarsData: [
                            _buildLineChartBarData(rxHistory, [
                              _openwallaCyan,
                              _openwallaCyan.withValues(alpha: 0.7),
                            ]),
                            _buildLineChartBarData(txHistory, [
                              _openwallaOrange,
                              _openwallaOrange.withValues(alpha: 0.72),
                            ]),
                          ],
                        ),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeInOut,
                      )
                    : Center(
                        key: ValueKey('loading_${appState.selectedRouter?.id}'),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.trending_up,
                              size: 48,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isSwitchingRouter
                                  ? 'Switching router...'
                                  : 'Collecting throughput data...',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.8),
                                  ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );

    // Always return the card without fixed height - let parent control sizing
    return card;
  }

  Widget _buildSpeedIndicator(
    IconData icon,
    Color color,
    String label,
    double speed,
  ) {
    // Show 0 if we don't have valid throughput data yet
    final displaySpeed = speed.isNaN || speed.isInfinite || speed < 0
        ? 0.0
        : speed;
    final speedText = AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Text(
        _formatSpeed(displaySpeed),
        key: ValueKey(displaySpeed),
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        if (label.isNotEmpty)
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                speedText,
              ],
            ),
          )
        else
          Flexible(child: speedText),
      ],
    );
  }

  LineChartBarData _buildLineChartBarData(
    List<double> data,
    List<Color> gradientColors,
  ) {
    // Handle single data point case - show a flat line at that value
    if (data.length == 1) {
      return LineChartBarData(
        spots: [
          FlSpot(0, data[0]),
          FlSpot(1, data[0]), // Duplicate the point to create a flat line
        ],
        isCurved: false, // Don't curve a flat line
        gradient: LinearGradient(colors: gradientColors),
        barWidth: 3,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, barData, index) {
            return FlDotCirclePainter(
              radius: 3,
              color: gradientColors.first,
              strokeWidth: 0,
            );
          },
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            colors: gradientColors
                .map((color) => color.withValues(alpha: 0.1))
                .toList(),
          ),
        ),
      );
    }

    // Don't show chart data if we don't have any data points
    if (data.isEmpty) {
      return LineChartBarData(
        spots: [],
        isCurved: true,
        gradient: LinearGradient(colors: gradientColors),
        barWidth: 3,
        isStrokeCapRound: true,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );
    }

    return LineChartBarData(
      spots: data
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value))
          .toList(),
      isCurved: true,
      gradient: LinearGradient(colors: gradientColors),
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: gradientColors
              .map((color) => color.withValues(alpha: 0.3))
              .toList(),
        ),
      ),
    );
  }

  String _formatSpeed(double bytesPerSecond) {
    // Handle edge cases
    if (bytesPerSecond.isNaN ||
        bytesPerSecond.isInfinite ||
        bytesPerSecond < 0) {
      return '0 bps';
    }

    final bitsPerSecond = bytesPerSecond * 8;
    if (bitsPerSecond < 1_000) return '${bitsPerSecond.toStringAsFixed(0)} bps';
    if (bitsPerSecond < 1_000_000) {
      return '${(bitsPerSecond / 1_000).toStringAsFixed(1)} Kbps';
    }
    return '${(bitsPerSecond / 1_000_000).toStringAsFixed(2)} Mbps';
  }

  Widget _buildSystemGauge({
    required String label,
    required double percent,
    required Color color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayValue = percent.round().clamp(0, 100);

    return SizedBox(
      width: 82,
      height: 82,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 78,
            height: 78,
            child: CircularProgressIndicator(
              value: displayValue / 100,
              strokeWidth: 8,
              strokeCap: StrokeCap.round,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$displayValue%',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSystemGaugeColumn({
    required String label,
    required double percent,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSystemGauge(label: label, percent: percent, color: color),
        ],
      ),
    );
  }

  Widget _buildSystemGaugeRow({
    required double cpuPercent,
    required double memoryPercent,
    required double loadPercent,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSystemGaugeColumn(
          label: 'CPU',
          percent: cpuPercent,
          color: _openwallaGreen,
        ),
        _buildSystemGaugeColumn(
          label: 'Mem',
          percent: memoryPercent,
          color: _openwallaCyan,
        ),
        _buildSystemGaugeColumn(
          label: 'Load',
          percent: loadPercent,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _buildSystemVitalsCard(AppState appState) {
    final sysInfo = appState.dashboardData?['sysInfo'] as Map<String, dynamic>?;

    final cpuLoad = sysInfo?['load'] as List<dynamic>?;
    final cpuPercent = _legacyCpuLoadPercent(sysInfo);
    final memoryPercent = _legacyMemoryPercent(sysInfo);
    final loadPercent = _scaledLoadPercent(cpuLoad, 1);

    return _buildOpenwallaCard(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const SystemResourcesScreen(),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'System Resources',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              _subtleCardArrow(),
            ],
          ),
          const SizedBox(height: 18),
          _buildSystemGaugeRow(
            cpuPercent: cpuPercent,
            memoryPercent: memoryPercent,
            loadPercent: loadPercent,
          ),
        ],
      ),
    );
  }

  String _primaryUsageInterfaceName(AppState appState) {
    final interfaces =
        appState.dashboardData?['interfaceDump']?['interface']
            as List<dynamic>?;
    if (interfaces == null) return 'br-lan';

    final names = interfaces
        .whereType<Map<String, dynamic>>()
        .map((interface) => interface['interface']?.toString())
        .whereType<String>()
        .where((name) => name != 'loopback' && name != 'lo')
        .toList();

    return names.firstWhere(
      (name) => name == 'br-lan',
      orElse: () => names.isNotEmpty ? names.first : 'br-lan',
    );
  }

  ({int count, int max}) _conntrackValues(AppState appState) {
    final conntrack = appState.dashboardData?['conntrack'];
    if (conntrack is! Map) return (count: 0, max: 1000);

    final count = conntrack['count'];
    final max = conntrack['max'];
    return (
      count: count is int ? count : int.tryParse(count?.toString() ?? '') ?? 0,
      max: max is int ? max : int.tryParse(max?.toString() ?? '') ?? 1000,
    );
  }

  Widget _buildDashboardBottomCards(AppState appState) {
    final preferences = appState.dashboardPreferences;
    final fallbackInterface = _primaryUsageInterfaceName(appState);
    _monthlyUsageSettingsFuture ??= ref
        .read(appStateProvider)
        .fetchMonthlyUsageSettings();

    return FutureBuilder<MonthlyUsageSettings>(
      future: _monthlyUsageSettingsFuture,
      builder: (context, snapshot) {
        final configuredInterface = snapshot.data?.interfaceName;
        final interfaceName = configuredInterface?.isNotEmpty == true
            ? configuredInterface!
            : fallbackInterface;
        final cards = <Widget>[
          if (preferences.showUsageCard) _buildUsageCard(interfaceName),
          if (preferences.showMonthlyUsageCard)
            _buildMonthlyUsageCard(interfaceName),
          _buildConntrackCard(appState),
        ];

        return Column(
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              if (index > 0) const SizedBox(height: 12),
              cards[index],
            ],
          ],
        );
      },
    );
  }

  Widget _buildUsageCard(String interfaceName) {
    final usageFuture = _usageFuture(_usageRange, interfaceName);

    return _buildOpenwallaCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _metricCardTitle(
            '$interfaceName Usage',
            trailing: _usageRangePicker(),
          ),
          const SizedBox(height: 8),
          Text(
            _usageSubtitle(_usageRange),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),
          FutureBuilder<List<VnstatUsageSample>>(
            future: usageFuture,
            builder: (context, snapshot) {
              final samples = _usageSamplesForRange(
                _usageRange,
                snapshot.data ?? const [],
              );
              return _usageLineGraph(samples);
            },
          ),
          const SizedBox(height: 18),
          _usageLegend(),
        ],
      ),
    );
  }

  Future<List<VnstatUsageSample>> _usageFuture(
    _UsageRange range,
    String interfaceName,
  ) {
    final period = _usageVnstatPeriod(range);
    final limit = switch (range) {
      _UsageRange.minute => 24,
      _UsageRange.hour => 24,
      _UsageRange.day => 14,
      _UsageRange.week => 60,
    };
    final key = '$interfaceName:$period:$limit';
    return _usageFutures.putIfAbsent(
      key,
      () => ref
          .read(appStateProvider)
          .fetchVnstatUsageSamples(
            period: period,
            interfaceName: interfaceName,
            limit: limit,
          ),
    );
  }

  String _usageVnstatPeriod(_UsageRange range) {
    return switch (range) {
      _UsageRange.minute => '5min',
      _UsageRange.hour => 'hourly',
      _UsageRange.day => 'daily',
      _UsageRange.week => 'daily',
    };
  }

  String _usageRangeLabel(_UsageRange range) {
    return switch (range) {
      _UsageRange.minute => 'Minute',
      _UsageRange.hour => 'Hour',
      _UsageRange.day => 'Day',
      _UsageRange.week => 'Week',
    };
  }

  String _usageSubtitle(_UsageRange range) {
    return switch (range) {
      _UsageRange.minute => 'Last 2 hours, 5 minute intervals',
      _UsageRange.hour => 'Last 24 hours',
      _UsageRange.day => 'Last 14 days',
      _UsageRange.week => 'Last 8 weeks',
    };
  }

  Widget _usageRangePicker() {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<_UsageRange>(
      initialValue: _usageRange,
      onSelected: (range) => setState(() => _usageRange = range),
      itemBuilder: (context) => _UsageRange.values
          .map(
            (range) => PopupMenuItem<_UsageRange>(
              value: range,
              child: Text(_usageRangeLabel(range)),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _usageRangeLabel(_usageRange),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  List<({String label, int downloadBytes, int uploadBytes, bool hasData})>
  _usageSamplesForRange(_UsageRange range, List<VnstatUsageSample> samples) {
    final now = DateTime.now();

    return switch (range) {
      _UsageRange.minute => List.generate(24, (index) {
        final slot = DateTime(
          now.year,
          now.month,
          now.day,
          now.hour,
          (now.minute ~/ 5) * 5,
        ).subtract(Duration(minutes: (23 - index) * 5));
        final slotEnd = slot.add(const Duration(minutes: 5));
        final matches = samples.where((sample) {
          final time = sample.timestamp.toLocal();
          return !time.isBefore(slot) && time.isBefore(slotEnd);
        }).toList();
        final download = matches.fold<int>(
          0,
          (sum, sample) => sum + sample.downloadBytes,
        );
        final upload = matches.fold<int>(
          0,
          (sum, sample) => sum + sample.uploadBytes,
        );
        return (
          label: '${slot.hour}:${slot.minute.toString().padLeft(2, '0')}',
          downloadBytes: download,
          uploadBytes: upload,
          hasData: matches.isNotEmpty,
        );
      }),
      _UsageRange.hour => List.generate(24, (index) {
        final slot = DateTime(
          now.year,
          now.month,
          now.day,
          now.hour,
        ).subtract(Duration(hours: 23 - index));
        final slotEnd = slot.add(const Duration(hours: 1));
        final matches = samples.where((sample) {
          final time = sample.timestamp.toLocal();
          return !time.isBefore(slot) && time.isBefore(slotEnd);
        }).toList();
        return (
          label: index == 23 ? 'Now' : '${slot.hour}:00',
          downloadBytes: matches.fold<int>(
            0,
            (sum, sample) => sum + sample.downloadBytes,
          ),
          uploadBytes: matches.fold<int>(
            0,
            (sum, sample) => sum + sample.uploadBytes,
          ),
          hasData: matches.isNotEmpty,
        );
      }),
      _UsageRange.day => List.generate(14, (index) {
        final day = now.subtract(Duration(days: 13 - index));
        final slot = DateTime(day.year, day.month, day.day);
        final slotEnd = slot.add(const Duration(days: 1));
        final matches = samples.where((sample) {
          final time = sample.timestamp.toLocal();
          return !time.isBefore(slot) && time.isBefore(slotEnd);
        }).toList();
        return (
          label: index == 13 ? 'Today' : _weekdayShort(day.weekday),
          downloadBytes: matches.fold<int>(
            0,
            (sum, sample) => sum + sample.downloadBytes,
          ),
          uploadBytes: matches.fold<int>(
            0,
            (sum, sample) => sum + sample.uploadBytes,
          ),
          hasData: matches.isNotEmpty,
        );
      }),
      _UsageRange.week => List.generate(8, (index) {
        final end = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: (7 - index) * 7));
        final start = end.subtract(const Duration(days: 6));
        final slotEnd = end.add(const Duration(days: 1));
        final matches = samples.where((sample) {
          final time = sample.timestamp.toLocal();
          return !time.isBefore(start) && time.isBefore(slotEnd);
        }).toList();
        return (
          label: index == 7 ? 'This Week' : 'W-${7 - index}',
          downloadBytes: matches.fold<int>(
            0,
            (sum, sample) => sum + sample.downloadBytes,
          ),
          uploadBytes: matches.fold<int>(
            0,
            (sum, sample) => sum + sample.uploadBytes,
          ),
          hasData: matches.isNotEmpty,
        );
      }),
    };
  }

  String _weekdayShort(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[(weekday - 1).clamp(0, 6)];
  }

  String _formatUsageTotal(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
    final gb = mb / 1024;
    if (gb >= 100) return '${gb.toStringAsFixed(0)} GB';
    if (gb >= 10) return '${gb.toStringAsFixed(1)} GB';
    return '${gb.toStringAsFixed(2)} GB';
  }

  Widget _usageLineGraph(
    List<({String label, int downloadBytes, int uploadBytes, bool hasData})>
    samples,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalDownload = samples.fold<int>(
      0,
      (sum, sample) => sum + sample.downloadBytes,
    );
    final totalUpload = samples.fold<int>(
      0,
      (sum, sample) => sum + sample.uploadBytes,
    );
    final maxValue = samples
        .expand((sample) => [sample.downloadBytes, sample.uploadBytes])
        .fold<int>(0, (max, value) => value > max ? value : max);
    final maxY = _niceUsageMax(maxValue);
    final hasAnyData = samples.any((sample) => sample.hasData);
    final labelIndexes = _usageBottomLabelIndexes(samples.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _usageTotalSummary(totalDownload, totalUpload),
        const SizedBox(height: 12),
        SizedBox(
          height: 188,
          child: Stack(
            alignment: Alignment.center,
            children: [
              LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (samples.length - 1)
                      .clamp(1, samples.length)
                      .toDouble(),
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.22),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        interval: maxY / 4,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              _formatUsageAxisValue(value),
                              textAlign: TextAlign.right,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.74),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0,
                                  ),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.round();
                          if (!labelIndexes.contains(index) ||
                              index < 0 ||
                              index >= samples.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              samples[index].label,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: index == samples.length - 1
                                        ? colorScheme.onSurface
                                        : colorScheme.onSurfaceVariant,
                                    fontWeight: index == samples.length - 1
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipColor: (_) =>
                          colorScheme.surface.withValues(alpha: 0.96),
                      tooltipBorderRadius: BorderRadius.circular(8),
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      getTooltipItems: (spots) => spots.map((spot) {
                        final index = spot.x.round().clamp(
                          0,
                          samples.length - 1,
                        );
                        final sample = samples[index];
                        final total = sample.downloadBytes + sample.uploadBytes;
                        final label = spot.barIndex == 0
                            ? 'Download'
                            : 'Upload';
                        final value = spot.barIndex == 0
                            ? sample.downloadBytes
                            : sample.uploadBytes;
                        final color = spot.barIndex == 0
                            ? _openwallaCyan
                            : _openwallaOrange;
                        return LineTooltipItem(
                          '${sample.label}\n'
                          '$label ${_formatUsageTotal(value)}\n'
                          'Total ${_formatUsageTotal(total)}',
                          TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  lineBarsData: [
                    _usageLineChartBar(
                      samples: samples,
                      color: _openwallaCyan,
                      selector: (sample) => sample.downloadBytes,
                    ),
                    _usageLineChartBar(
                      samples: samples,
                      color: _openwallaOrange,
                      selector: (sample) => sample.uploadBytes,
                    ),
                  ],
                ),
              ),
              if (!hasAnyData)
                Text(
                  'No usage data yet',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  LineChartBarData _usageLineChartBar({
    required List<
      ({String label, int downloadBytes, int uploadBytes, bool hasData})
    >
    samples,
    required Color color,
    required int Function(
      ({String label, int downloadBytes, int uploadBytes, bool hasData}) sample,
    )
    selector,
  }) {
    return LineChartBarData(
      spots: List.generate(samples.length, (index) {
        final sample = samples[index];
        return FlSpot(
          index.toDouble(),
          sample.hasData ? selector(sample).toDouble() : 0,
        );
      }),
      isCurved: true,
      curveSmoothness: 0.28,
      color: color,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.12),
      ),
    );
  }

  double _niceUsageMax(int maxBytes) {
    if (maxBytes <= 0) return 1024;
    final units = <int>[
      1024,
      10 * 1024,
      100 * 1024,
      1024 * 1024,
      10 * 1024 * 1024,
      100 * 1024 * 1024,
      1024 * 1024 * 1024,
      10 * 1024 * 1024 * 1024,
      100 * 1024 * 1024 * 1024,
    ];
    for (final unit in units) {
      if (maxBytes <= unit) return unit.toDouble();
    }
    return maxBytes * 1.15;
  }

  String _formatUsageAxisValue(double bytes) {
    if (bytes <= 0) return '';
    return _formatUsageTotal(bytes.round());
  }

  Set<int> _usageBottomLabelIndexes(int length) {
    if (length <= 1) return {0};
    return {0, (length / 3).floor(), ((length * 2) / 3).floor(), length - 1};
  }

  Widget _usageTotalSummary(int downloadBytes, int uploadBytes) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = downloadBytes + uploadBytes;

    return Row(
      children: [
        Expanded(
          child: Text(
            'Total ${_formatUsageTotal(total)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              'Down ${_formatUsageTotal(downloadBytes)}  Up ${_formatUsageTotal(uploadBytes)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _usageLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _usageLegendItem('Download', _openwallaCyan),
        const SizedBox(width: 18),
        _usageLegendItem('Upload', _openwallaOrange),
      ],
    );
  }

  Widget _usageLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: _metricMutedTextStyle()),
      ],
    );
  }

  Widget _buildMonthlyUsageCard(String interfaceName) {
    return _buildOpenwallaCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                MonthlyUsageScreen(interfaceName: interfaceName),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _metricCardTitle(
            '$interfaceName Monthly Usage',
            trailing: _subtleCardArrow(),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '0 MB',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  height: 0.95,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('26 days left', style: _metricMutedTextStyle()),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _metricProgressBar(value: 0),
        ],
      ),
    );
  }

  Widget _buildConntrackCard(AppState appState) {
    final values = _conntrackValues(appState);
    final max = values.max <= 0 ? 1000 : values.max;
    final progress = (values.count / max).clamp(0.0, 1.0);

    return _buildOpenwallaCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _metricCardTitle(
            'Conntrack',
            trailing: Text(
              '${values.count} / $max connections',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 16),
          _metricProgressBar(value: progress, fillColor: _openwallaCyan),
        ],
      ),
    );
  }

  Widget _metricCardTitle(String title, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }

  Widget _subtleCardArrow() {
    final colorScheme = Theme.of(context).colorScheme;

    return Icon(
      Icons.arrow_forward_ios_rounded,
      size: 16,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.74),
    );
  }

  TextStyle? _metricMutedTextStyle() {
    return Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );
  }

  Widget _metricProgressBar({required double value, Color? fillColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 16,
        backgroundColor: colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(
          fillColor ?? colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final List<model.Router> routers = appState.routers;
    final model.Router? selected = appState.selectedRouter;
    final boardInfo =
        appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final hostname = boardInfo?['hostname']?.toString();
    final headerText = (hostname != null && hostname.isNotEmpty)
        ? hostname
        : (selected?.ipAddress ?? 'Loading...');
    return Scaffold(
      appBar: LuciAppBar(
        centerTitle: true,
        title: null, // Always use titleWidget now
        titleWidget: routers.length > 1
            ? Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 1.1,
                    ),
                  ),
                  constraints: const BoxConstraints(minHeight: 36),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final selectedId = await showModalBottomSheet<String>(
                          context: context,
                          isScrollControlled: false,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surface,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(_openwallaRadius),
                            ),
                          ),
                          builder: (context) {
                            return SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  left: 8,
                                  right: 8,
                                  bottom: 8,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Center(
                                      child: Container(
                                        width: 40,
                                        height: 4,
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.outlineVariant,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12.0,
                                        vertical: 4,
                                      ),
                                      child: Center(
                                        child: Text(
                                          'Select Router',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                    const Divider(height: 16),
                                    ...routers.map((r) {
                                      final isSelected = r.id == selected?.id;
                                      String routerTitle;
                                      bool isStale = false;
                                      if (isSelected && boardInfo != null) {
                                        final hostname = boardInfo['hostname']
                                            ?.toString();
                                        routerTitle =
                                            (hostname != null &&
                                                hostname.isNotEmpty)
                                            ? hostname
                                            : (r.lastKnownHostname ??
                                                  r.ipAddress);
                                      } else if (r.lastKnownHostname != null &&
                                          r.lastKnownHostname!.isNotEmpty) {
                                        routerTitle = r.lastKnownHostname!;
                                        isStale = true;
                                      } else {
                                        routerTitle = r.ipAddress;
                                      }
                                      return ListTile(
                                        leading: Icon(
                                          Icons.router,
                                          color: isSelected
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                        ),
                                        title: Tooltip(
                                          message: isStale
                                              ? 'Last known hostname (may be out of date)'
                                              : '',
                                          child: Text(
                                            routerTitle,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: isStale
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant
                                                            .withValues(
                                                              alpha: 0.7,
                                                            )
                                                      : Theme.of(
                                                          context,
                                                        ).colorScheme.onSurface,
                                                ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        subtitle: Text(
                                          r.ipAddress,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                        trailing: isSelected
                                            ? Icon(
                                                Icons.check_circle,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              )
                                            : null,
                                        selected: isSelected,
                                        selectedTileColor: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.07),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        onTap: () =>
                                            Navigator.of(context).pop(r.id),
                                      );
                                    }),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                        if (selectedId != null &&
                            selectedId != selected?.id &&
                            context.mounted) {
                          await appState.selectRouter(
                            selectedId,
                            context: context,
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: 16.0,
                          right: 8.0,
                          top: 4.0,
                          bottom: 4.0,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              headerText,
                              style:
                                  Theme.of(
                                    context,
                                  ).appBarTheme.titleTextStyle ??
                                  Theme.of(
                                    context,
                                  ).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).appBarTheme.titleTextStyle?.color,
                                  ),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 20,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : _buildTitleWithTimestamp(headerText, appState),
      ),
      body: Stack(children: [_buildBody(appState)]),
    );
  }

  Widget _buildBody(AppState appState) {
    if (appState.dashboardError != null) {
      return LuciErrorDisplay(
        title: 'Connection Failed',
        message:
            'Unable to connect to the router. Please check your network connection and router settings.',
        actionLabel: 'Retry Connection',
        onAction: () => appState.retryDashboardConnection(context: context),
        icon: Icons.wifi_off_rounded,
      );
    }

    if (appState.isDashboardLoading && appState.dashboardData == null) {
      return const LuciLoadingWidget();
    }

    if (appState.dashboardData == null) {
      return LuciEmptyState(
        title: 'No Data Available',
        message:
            'Unable to fetch dashboard data. Pull down to refresh or tap the button below.',
        icon: Icons.dashboard_outlined,
        actionLabel: 'Fetch Data',
        onAction: () => appState.fetchDashboardData(),
      );
    }

    return RefreshIndicator(
      onRefresh: () => appState.fetchDashboardData(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape =
              MediaQuery.of(context).orientation == Orientation.landscape;

          // Split layout handling to avoid Expanded widget conflicts with staggered animations
          if (isLandscape) {
            final preferences = appState.dashboardPreferences;
            final hasFlowsCard =
                preferences.showFlowsCard && _hasDashboardFlowsCard(appState);
            final landscapeContent = [
              const SizedBox(height: 16),
              _buildDashboardSummaryCards(appState),
              if (preferences.showNetworkPerformanceCard) ...[
                const SizedBox(height: 12),
                _buildNetworkPerformanceCard(appState: appState),
              ],
              const SizedBox(height: 12),
              _buildSystemVitalsCard(appState),
              const SizedBox(height: 12),
              SizedBox(
                height: 240,
                child: _buildRealtimeThroughputCard(appState),
              ),
              if (hasFlowsCard) ...[
                const SizedBox(height: 12),
                _buildDashboardFlowsCard(appState),
              ],
              const SizedBox(height: 12),
              _buildDashboardBottomCards(appState),
              const SizedBox(height: 12),
              // Extra padding to ensure scroll behavior for RefreshIndicator
              const SizedBox(height: 100),
            ];

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: LuciStaggeredAnimation(
                  staggerDelay: const Duration(milliseconds: 50),
                  children: landscapeContent,
                ),
              ),
            );
          } else {
            // Portrait mode: let content scroll naturally so cards never get
            // squeezed into a height that causes internal overflows.
            return LayoutBuilder(
              builder: (context, constraints) {
                final preferences = appState.dashboardPreferences;
                final hasFlowsCard =
                    preferences.showFlowsCard &&
                    _hasDashboardFlowsCard(appState);
                return RefreshIndicator(
                  onRefresh: () => appState.fetchDashboardData(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              _buildDashboardSummaryCards(appState),
                              if (preferences.showNetworkPerformanceCard) ...[
                                const SizedBox(height: 12),
                                _buildNetworkPerformanceCard(
                                  appState: appState,
                                ),
                              ],
                              const SizedBox(height: 12),
                              _buildSystemVitalsCard(appState),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 220,
                                child: _buildRealtimeThroughputCard(appState),
                              ),
                              if (hasFlowsCard) ...[
                                const SizedBox(height: 12),
                                _buildDashboardFlowsCard(appState),
                              ],
                              const SizedBox(height: 12),
                              _buildDashboardBottomCards(appState),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }
        },
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
