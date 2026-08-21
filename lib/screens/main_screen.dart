import 'package:flutter/material.dart';
import 'package:luci_mobile/screens/dashboard_screen.dart';
import 'package:luci_mobile/screens/more_screen.dart';
import 'package:luci_mobile/screens/statistics_screen.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/widgets/luci_navigation_enhancements.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int? initialTab;

  const MainScreen({super.key, this.initialTab});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null) {
      _selectedIndex = widget.initialTab!.clamp(0, 2);
    }
  }

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle initial tab changes
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      _selectedIndex = widget.initialTab!.clamp(0, 2);
    }
  }

  List<Widget> get _widgetOptions => [
    const DashboardScreen(),
    const StatisticsScreen(),
    const MoreScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen for requestedTab in AppState
    final appState = ref.watch(appStateProvider);
    if (appState.requestedTab != null &&
        appState.requestedTab != _selectedIndex) {
      // Store the values before the callback to avoid null reference issues
      final requestedTab = appState.requestedTab!;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedIndex = requestedTab.clamp(0, 2);
        });
        appState.requestedTab = null;
        appState.requestedInterfaceToScroll = null;
      });
    }
    return Scaffold(
      body: Center(
        child: LuciTabTransition(
          transitionKey: 'tab_$_selectedIndex',
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final isRebooting = ref.watch(
            appStateProvider.select((state) => state.isRebooting),
          );
          Color? getTabColor(int index) =>
              (isRebooting && index != 2) ? Colors.grey.withAlpha(128) : null;
          double getTabOpacity(int index) =>
              (isRebooting && index != 2) ? 0.5 : 1.0;
          return NavigationBar(
            onDestinationSelected: (index) {
              if (isRebooting && index != 2) return; // Only allow 'More' tab
              _onItemTapped(index);
            },
            selectedIndex: _selectedIndex,
            destinations: [
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(0),
                  child: Icon(Icons.dashboard, color: getTabColor(0)),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(0),
                  child: Icon(Icons.dashboard_outlined, color: getTabColor(0)),
                ),
                label: 'Dashboard',
              ),
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(1),
                  child: Icon(Icons.bar_chart_rounded, color: getTabColor(1)),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(1),
                  child: Icon(Icons.bar_chart_outlined, color: getTabColor(1)),
                ),
                label: 'Statistics',
              ),
              NavigationDestination(
                selectedIcon: Opacity(
                  opacity: getTabOpacity(2),
                  child: Icon(Icons.more_horiz),
                ),
                icon: Opacity(
                  opacity: getTabOpacity(2),
                  child: Icon(Icons.more_horiz_outlined),
                ),
                label: 'More',
              ),
            ],
          );
        },
      ),
    );
  }
}
