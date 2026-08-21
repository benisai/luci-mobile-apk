import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/screens/monthly_usage_screen.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_refresh_components.dart';

enum _StatsUsageRange { day, week }

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
                      _buildUsageCard(interfaceName),
                      const SizedBox(height: 12),
                      _buildMonthlyUsageCard(interfaceName),
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
                child: Text('26 days left', style: _mutedTextStyle()),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _progressBar(0),
        ],
      ),
    );
  }

  Future<List<VnstatUsageSample>> _usageFuture(
    _StatsUsageRange range,
    String interfaceName,
  ) {
    final period = range == _StatsUsageRange.day ? 'daily' : 'daily';
    final limit = range == _StatsUsageRange.day ? 14 : 60;
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
      _StatsUsageRange.day => 'Day',
      _StatsUsageRange.week => 'Week',
    };
  }

  String _usageSubtitle(_StatsUsageRange range) {
    return switch (range) {
      _StatsUsageRange.day => 'Last 14 days',
      _StatsUsageRange.week => 'Last 8 weeks',
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
    if (range == _StatsUsageRange.week) {
      return List.generate(8, (index) {
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
      });
    }

    return List.generate(14, (index) {
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
