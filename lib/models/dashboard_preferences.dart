enum DashboardFlowMode { detailed, simple }

class DashboardPreferences {
  final Set<String> enabledWirelessInterfaces;
  final Set<String> enabledWiredInterfaces;
  final String? primaryThroughputInterface;
  final bool showAllThroughput;
  final bool showNetworkPerformanceCard;
  final bool showFlowsCard;
  final bool showUsageCard;
  final bool showMonthlyUsageCard;
  final DashboardFlowMode flowMode;

  DashboardPreferences({
    Set<String>? enabledWirelessInterfaces,
    Set<String>? enabledWiredInterfaces,
    this.primaryThroughputInterface,
    this.showAllThroughput = true,
    this.showNetworkPerformanceCard = false,
    this.showFlowsCard = false,
    this.showUsageCard = false,
    this.showMonthlyUsageCard = false,
    this.flowMode = DashboardFlowMode.detailed,
  }) : enabledWirelessInterfaces = enabledWirelessInterfaces ?? {},
       enabledWiredInterfaces = enabledWiredInterfaces ?? {};

  DashboardPreferences copyWith({
    Set<String>? enabledWirelessInterfaces,
    Set<String>? enabledWiredInterfaces,
    String? primaryThroughputInterface,
    bool? showAllThroughput,
    bool? showNetworkPerformanceCard,
    bool? showFlowsCard,
    bool? showUsageCard,
    bool? showMonthlyUsageCard,
    DashboardFlowMode? flowMode,
  }) {
    return DashboardPreferences(
      enabledWirelessInterfaces:
          enabledWirelessInterfaces ?? this.enabledWirelessInterfaces,
      enabledWiredInterfaces:
          enabledWiredInterfaces ?? this.enabledWiredInterfaces,
      primaryThroughputInterface:
          primaryThroughputInterface ?? this.primaryThroughputInterface,
      showAllThroughput: showAllThroughput ?? this.showAllThroughput,
      showNetworkPerformanceCard:
          showNetworkPerformanceCard ?? this.showNetworkPerformanceCard,
      showFlowsCard: showFlowsCard ?? this.showFlowsCard,
      showUsageCard: showUsageCard ?? this.showUsageCard,
      showMonthlyUsageCard: showMonthlyUsageCard ?? this.showMonthlyUsageCard,
      flowMode: flowMode ?? this.flowMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabledWirelessInterfaces': enabledWirelessInterfaces.toList(),
    'enabledWiredInterfaces': enabledWiredInterfaces.toList(),
    'primaryThroughputInterface': primaryThroughputInterface,
    'showAllThroughput': showAllThroughput,
    'showNetworkPerformanceCard': showNetworkPerformanceCard,
    'showFlowsCard': showFlowsCard,
    'showUsageCard': showUsageCard,
    'showMonthlyUsageCard': showMonthlyUsageCard,
    'flowMode': flowMode.name,
  };

  factory DashboardPreferences.fromJson(Map<String, dynamic> json) {
    return DashboardPreferences(
      enabledWirelessInterfaces: Set<String>.from(
        json['enabledWirelessInterfaces'] ?? [],
      ),
      enabledWiredInterfaces: Set<String>.from(
        json['enabledWiredInterfaces'] ?? [],
      ),
      primaryThroughputInterface: json['primaryThroughputInterface'],
      showAllThroughput: json['showAllThroughput'] ?? true,
      showNetworkPerformanceCard: json['showNetworkPerformanceCard'] ?? false,
      showFlowsCard: json['showFlowsCard'] ?? false,
      showUsageCard: json['showUsageCard'] ?? false,
      showMonthlyUsageCard: json['showMonthlyUsageCard'] ?? false,
      flowMode: DashboardFlowMode.values.firstWhere(
        (mode) => mode.name == json['flowMode']?.toString(),
        orElse: () => DashboardFlowMode.detailed,
      ),
    );
  }

  static DashboardPreferences get defaultPreferences => DashboardPreferences();
}
