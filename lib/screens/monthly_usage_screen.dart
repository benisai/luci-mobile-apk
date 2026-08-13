import 'package:flutter/material.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

class MonthlyUsageScreen extends StatelessWidget {
  final String interfaceName;

  const MonthlyUsageScreen({super.key, required this.interfaceName});

  static const Color _cyan = Color(0xFF18AEEA);
  static const Color _orange = Color(0xFFF27C24);

  int _daysInMonth(DateTime date) {
    final nextMonth = DateTime(date.year, date.month + 1);
    return nextMonth.subtract(const Duration(days: 1)).day;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final totalDays = _daysInMonth(now);
    final daysLeft = totalDays - now.day;

    return Scaffold(
      appBar: LuciAppBar(title: '$interfaceName Monthly Usage', showBack: true),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            _MonthlySummaryCard(
              interfaceName: interfaceName,
              daysLeft: daysLeft,
            ),
            const SizedBox(height: 14),
            _DailyUsageChartCard(
              interfaceName: interfaceName,
              totalDays: totalDays,
            ),
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

class _MonthlySummaryCard extends StatelessWidget {
  final String interfaceName;
  final int daysLeft;

  const _MonthlySummaryCard({
    required this.interfaceName,
    required this.daysLeft,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _OpenwallaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$interfaceName Monthly Usage',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '0 MB',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  height: 0.95,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '$daysLeft days left',
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
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: 0,
              minHeight: 16,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation<Color>(
                MonthlyUsageScreen._cyan,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyUsageChartCard extends StatelessWidget {
  final String interfaceName;
  final int totalDays;

  const _DailyUsageChartCard({
    required this.interfaceName,
    required this.totalDays,
  });

  List<double> _placeholderValues() {
    return List<double>.generate(totalDays, (index) {
      final wave = ((index * 7) % 17) / 17;
      final spike = index == totalDays - 4 || index == totalDays - 2
          ? 0.95
          : 0.0;
      return spike > 0
          ? spike
          : (0.08 + wave * 0.46).clamp(0.06, 0.72).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final values = _placeholderValues();

    return _OpenwallaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Usage Per Day',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 260,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _UsageAxis(),
                const SizedBox(width: 12),
                Expanded(child: _DailyBars(values: values)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageAxis extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final labels = ['500 MB', '375 MB', '250 MB', '125 MB', '0 B'];

    return SizedBox(
      width: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: labels
            .map(
              (label) => Text(
                label,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color.withValues(alpha: 0.76),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DailyBars extends StatelessWidget {
  final List<double> values;

  const _DailyBars({required this.values});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelEvery = values.length > 28 ? 5 : 4;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(values.length, (index) {
        final height = 204 * values[index].clamp(0, 1).toDouble();
        final day = index + 1;
        final showLabel =
            day == 1 || day == values.length || day % labelEvery == 0;

        return Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: 210,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 7,
                    height: height < 3 ? 3 : height,
                    decoration: BoxDecoration(
                      color: index.isOdd
                          ? MonthlyUsageScreen._orange
                          : MonthlyUsageScreen._cyan,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                showLabel ? day.toString() : '',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
                maxLines: 1,
              ),
            ],
          ),
        );
      }),
    );
  }
}
