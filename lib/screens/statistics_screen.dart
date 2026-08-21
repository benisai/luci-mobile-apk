import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/monthly_usage_screen.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_refresh_components.dart';

enum _StatsUsageRange { minute, hour, day, week }

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  static const Color _cyan = Color(0xFF18AEEA);
  static const Color _orange = Color(0xFFF27C24);
  static const Color _border = Color(0xFF313C52);
  static const double _radius = 8;

  _StatsUsageRange _usageRange = _StatsUsageRange.day;
  Future<MonthlyUsageSettings>? _monthlyUsageSettingsFuture;
  final Map<String, Future<List<VnstatUsageSample>>> _usageFutures = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appStateProvider).fetchDashboardData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);

    if (appState.isDashboardLoading && appState.dashboardData == null) {
      return const Scaffold(
        appBar: LuciAppBar(title: 'Statistics'),
        body: LuciLoadingWidget(),
      );
    }

    return Scaffold(
      appBar: const LuciAppBar(title: 'Statistics'),
      body: SafeArea(
        bottom: false,
        child: LuciPullToRefresh(
          onRefresh: () async {
            _usageFutures.clear();
            _monthlyUsageSettingsFuture = null;
            await appState.fetchDashboardData();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              FutureBuilder<MonthlyUsageSettings>(
                future: _monthlyUsageSettings(),
                builder: (context, snapshot) {
                  final interfaceName =
                      (snapshot.data?.interfaceName.isNotEmpty ?? false)
                      ? snapshot.data!.interfaceName
                      : _primaryUsageInterfaceName(appState);
                  return Column(
                    children: [
                      _buildMonthlyUsageCard(interfaceName),
                      const SizedBox(height: 12),
                      _buildUsageCard(interfaceName),
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

  Future<MonthlyUsageSettings> _monthlyUsageSettings() {
    return _monthlyUsageSettingsFuture ??= ref
        .read(appStateProvider)
        .fetchMonthlyUsageSettings();
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

  Widget _card({required Widget child, VoidCallback? onTap}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(
          color: isDark
              ? _border
              : colorScheme.outlineVariant.withValues(alpha: 0.62),
        ),
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildUsageCard(String interfaceName) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titleRow('$interfaceName Daily Usage', trailing: _rangePicker()),
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
            future: _usageFuture(_usageRange, interfaceName),
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

  Widget _buildMonthlyUsageCard(String interfaceName) {
    return _card(
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
          _titleRow('$interfaceName Monthly Usage', trailing: _subtleArrow()),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FutureBuilder<List<VnstatUsageSample>>(
                future: _monthlyUsageFuture(interfaceName),
                builder: (context, snapshot) {
                  final summary = _monthlySummary(snapshot.data ?? const []);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatUsageTotal(summary.totalBytes),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                              height: 0.95,
                            ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '${summary.daysLeft} days left',
                          style: _mutedTextStyle(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 22),
          FutureBuilder<List<VnstatUsageSample>>(
            future: _monthlyUsageFuture(interfaceName),
            builder: (context, snapshot) {
              final summary = _monthlySummary(snapshot.data ?? const []);
              return _progressBar(summary.progress);
            },
          ),
        ],
      ),
    );
  }

  Future<List<VnstatUsageSample>> _monthlyUsageFuture(String interfaceName) {
    final key = '$interfaceName:monthly-summary';
    return _usageFutures.putIfAbsent(
      key,
      () => ref
          .read(appStateProvider)
          .fetchVnstatUsageSamples(
            period: 'daily',
            interfaceName: interfaceName,
            limit: 45,
          ),
    );
  }

  Future<List<VnstatUsageSample>> _usageFuture(
    _StatsUsageRange range,
    String interfaceName,
  ) {
    final period = switch (range) {
      _StatsUsageRange.minute => '5min',
      _StatsUsageRange.hour => 'hourly',
      _StatsUsageRange.day => 'hourly',
      _StatsUsageRange.week => 'daily',
    };
    final limit = switch (range) {
      _StatsUsageRange.minute => 12,
      _StatsUsageRange.hour => 12,
      _StatsUsageRange.day => 24,
      _StatsUsageRange.week => 7,
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

  String _usageRangeLabel(_StatsUsageRange range) {
    return switch (range) {
      _StatsUsageRange.minute => 'Minute',
      _StatsUsageRange.hour => 'Hour',
      _StatsUsageRange.day => 'Day',
      _StatsUsageRange.week => 'Week',
    };
  }

  String _usageSubtitle(_StatsUsageRange range) {
    return switch (range) {
      _StatsUsageRange.minute => 'Last 60 minutes',
      _StatsUsageRange.hour => 'Last 12 hours',
      _StatsUsageRange.day => 'Last 24 hours',
      _StatsUsageRange.week => 'Last 7 days',
    };
  }

  Widget _rangePicker() {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<_StatsUsageRange>(
      initialValue: _usageRange,
      onSelected: (range) => setState(() => _usageRange = range),
      itemBuilder: (context) => _StatsUsageRange.values
          .map(
            (range) => PopupMenuItem<_StatsUsageRange>(
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
  _usageSamplesForRange(
    _StatsUsageRange range,
    List<VnstatUsageSample> samples,
  ) {
    final now = DateTime.now();
    return switch (range) {
      _StatsUsageRange.minute => _timeBuckets(
        samples,
        count: 12,
        bucket: const Duration(minutes: 5),
        anchor: DateTime(
          now.year,
          now.month,
          now.day,
          now.hour,
          now.minute - (now.minute % 5),
        ),
        labelFor: (slot, index, lastIndex) =>
            index == lastIndex ? 'Now' : _timeLabel(slot),
      ),
      _StatsUsageRange.hour => _timeBuckets(
        samples,
        count: 12,
        bucket: const Duration(hours: 1),
        anchor: DateTime(now.year, now.month, now.day, now.hour),
        labelFor: (slot, index, lastIndex) =>
            index == lastIndex ? 'Now' : _hourLabel(slot),
      ),
      _StatsUsageRange.day => _timeBuckets(
        samples,
        count: 24,
        bucket: const Duration(hours: 1),
        anchor: DateTime(now.year, now.month, now.day, now.hour),
        labelFor: (slot, index, lastIndex) =>
            index == lastIndex ? 'Now' : _hourLabel(slot),
      ),
      _StatsUsageRange.week => _timeBuckets(
        samples,
        count: 7,
        bucket: const Duration(days: 1),
        anchor: DateTime(now.year, now.month, now.day),
        labelFor: (slot, index, lastIndex) =>
            index == lastIndex ? 'Today' : _weekdayShort(slot.weekday),
      ),
    };
  }

  List<({String label, int downloadBytes, int uploadBytes, bool hasData})>
  _timeBuckets(
    List<VnstatUsageSample> samples, {
    required int count,
    required Duration bucket,
    required DateTime anchor,
    required String Function(DateTime slot, int index, int lastIndex) labelFor,
  }) {
    return List.generate(count, (index) {
      final slot = anchor.subtract(bucket * (count - 1 - index));
      final slotEnd = slot.add(bucket);
      final matches = samples.where((sample) {
        final time = sample.timestamp.toLocal();
        return !time.isBefore(slot) && time.isBefore(slotEnd);
      }).toList();
      return (
        label: labelFor(slot, index, count - 1),
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
    });
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
        .fold<int>(0, max);
    final maxY = _niceMax(maxValue);
    final labelIndexes = _bottomLabelIndexes(samples.length);
    final hasAnyData = samples.any((sample) => sample.hasData);

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
                          return Text(
                            _formatUsageTotal(value.round()),
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.74),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
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
                  lineBarsData: [
                    _lineBar(samples, _cyan, (sample) => sample.downloadBytes),
                    _lineBar(samples, _orange, (sample) => sample.uploadBytes),
                  ],
                ),
              ),
              if (!hasAnyData)
                Text('No usage data yet', style: _mutedTextStyle()),
            ],
          ),
        ),
      ],
    );
  }

  LineChartBarData _lineBar(
    List<({String label, int downloadBytes, int uploadBytes, bool hasData})>
    samples,
    Color color,
    int Function(
      ({String label, int downloadBytes, int uploadBytes, bool hasData}) sample,
    )
    selector,
  ) {
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

  Widget _titleRow(String title, {Widget? trailing}) {
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

  Widget _subtleArrow() {
    return Icon(
      Icons.chevron_right_rounded,
      size: 24,
      color: Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
    );
  }

  Widget _progressBar(double value) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        minHeight: 16,
        value: value.clamp(0, 1),
        backgroundColor: colorScheme.surfaceContainerHighest,
        valueColor: const AlwaysStoppedAnimation<Color>(_cyan),
      ),
    );
  }

  Widget _usageTotalSummary(int downloadBytes, int uploadBytes) {
    final total = downloadBytes + uploadBytes;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Total ${_formatUsageTotal(total)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
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
              style: _mutedTextStyle(),
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
        _legendItem('Download', _cyan),
        const SizedBox(width: 18),
        _legendItem('Upload', _orange),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: _mutedTextStyle()),
      ],
    );
  }

  TextStyle? _mutedTextStyle() {
    return Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );
  }

  double _niceMax(int maxBytes) {
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

  Set<int> _bottomLabelIndexes(int length) {
    if (length <= 1) return {0};
    return {0, (length / 3).floor(), ((length * 2) / 3).floor(), length - 1};
  }

  ({int totalBytes, int daysLeft, double progress}) _monthlySummary(
    List<VnstatUsageSample> samples,
  ) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final daysInMonth = end.difference(start).inDays;
    final totalBytes = samples
        .where((sample) {
          final time = sample.timestamp.toLocal();
          return !time.isBefore(start) && time.isBefore(end);
        })
        .fold<int>(
          0,
          (sum, sample) => sum + sample.downloadBytes + sample.uploadBytes,
        );

    return (
      totalBytes: totalBytes,
      daysLeft: max(0, daysInMonth - now.day),
      progress: daysInMonth <= 0 ? 0 : now.day / daysInMonth,
    );
  }

  String _timeLabel(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _hourLabel(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour $suffix';
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
}
