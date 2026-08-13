import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/services/router_service.dart';
import 'package:luci_mobile/services/throughput_service.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/models/dashboard_preferences.dart';
import 'package:luci_mobile/services/interfaces/auth_service_interface.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/service_factory.dart';
import 'package:luci_mobile/config/app_config.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';
import 'package:luci_mobile/utils/logger.dart';

class PingMonitorSettings {
  final String target;
  final int thresholdMs;

  const PingMonitorSettings({required this.target, required this.thresholdMs});
}

class DnsMonitorSettings {
  final String hostname;

  const DnsMonitorSettings({required this.hostname});
}

class PingMonitorSample {
  final DateTime timestamp;
  final String target;
  final String status;
  final double? latencyMs;
  final String message;

  const PingMonitorSample({
    required this.timestamp,
    required this.target,
    required this.status,
    required this.latencyMs,
    required this.message,
  });

  bool get isOk => status.toUpperCase() == 'OK' && latencyMs != null;

  static PingMonitorSample? fromLine(String line) {
    final parts = line.split('|');
    if (parts.length < 5) return null;

    final timestamp = DateTime.tryParse(parts[0]);
    if (timestamp == null) return null;

    final latencyText = parts[3];
    return PingMonitorSample(
      timestamp: timestamp,
      target: parts[1],
      status: parts[2],
      latencyMs: latencyText == 'N/A' ? null : double.tryParse(latencyText),
      message: parts.sublist(4).join('|'),
    );
  }
}

class SpeedtestMonitorSettings {
  final bool enabled;
  final DateTime? runDate;
  final int runHour;
  final int runMinute;

  const SpeedtestMonitorSettings({
    required this.enabled,
    required this.runDate,
    required this.runHour,
    required this.runMinute,
  });
}

class MonthlyUsageSettings {
  final int monthStartDay;
  final String interfaceName;

  const MonthlyUsageSettings({
    required this.monthStartDay,
    required this.interfaceName,
  });
}

class SystemStorageDetails {
  final int userTotalBytes;
  final int userFreeBytes;
  final int tempTotalBytes;
  final int tempFreeBytes;

  const SystemStorageDetails({
    required this.userTotalBytes,
    required this.userFreeBytes,
    required this.tempTotalBytes,
    required this.tempFreeBytes,
  });

  static const empty = SystemStorageDetails(
    userTotalBytes: 0,
    userFreeBytes: 0,
    tempTotalBytes: 0,
    tempFreeBytes: 0,
  );
}

class NetifyFlow {
  final DateTime timestamp;
  final String deviceMac;
  final String localIp;
  final String localPort;
  final String destination;
  final String application;
  final String protocol;
  final String destinationIp;
  final String destinationPort;
  final String interfaceName;
  final int downloadedBytes;
  final int uploadedBytes;
  final int totalBytes;
  final String countryCode;
  final String region;
  final String direction;
  final String rawJson;

  const NetifyFlow({
    required this.timestamp,
    required this.deviceMac,
    required this.localIp,
    required this.localPort,
    required this.destination,
    required this.application,
    required this.protocol,
    required this.destinationIp,
    required this.destinationPort,
    required this.interfaceName,
    required this.downloadedBytes,
    required this.uploadedBytes,
    required this.totalBytes,
    required this.countryCode,
    required this.region,
    required this.direction,
    required this.rawJson,
  });

  static NetifyFlow? fromJsonLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map || decoded['type'] != 'flow') return null;
      final flow = decoded['flow'];
      if (flow is! Map) return null;

      final timestamp = _parseNetifyTimestamp(
        flow['last_seen_at'] ?? flow['first_seen_at'] ?? decoded['timeinsert'],
      );
      final sni = _firstString([
        _nestedString(flow, ['ssl', 'client_sni']),
        flow['client_sni'],
        _nestedString(flow, ['tls', 'client_sni']),
        flow['tls_client_sni'],
      ]);
      final destination = _firstString([
        sni,
        flow['host_server_name'],
        flow['fqdn'],
        flow['dns_host_name'],
        flow['other_ip'],
        'Unknown',
      ]);
      final application = _firstString([
        flow['detected_application_name'],
        flow['detected_app_name'],
        destination,
      ]);
      final destinationIp = _firstString([flow['other_ip'], '-']);
      final downloaded = _firstInt([
        flow['other_bytes'],
        flow['download_bytes'],
        flow['server_bytes'],
      ]);
      final uploaded = _firstInt([
        flow['local_bytes'],
        flow['upload_bytes'],
        flow['client_bytes'],
      ]);
      final total = _firstInt([flow['total_bytes'], downloaded + uploaded]);

      return NetifyFlow(
        timestamp: timestamp,
        deviceMac: _normalizeMac(flow['local_mac']),
        localIp: _firstString([flow['local_ip'], '-']),
        localPort: _firstString([flow['local_port'], '']),
        destination: destination.isNotEmpty ? destination : destinationIp,
        application: application,
        protocol: _firstString([flow['detected_protocol_name'], 'N/A']),
        destinationIp: destinationIp,
        destinationPort: _firstString([flow['other_port'], '0']),
        interfaceName: _firstString([
          decoded['interface'],
          flow['interface'],
          flow['local_interface'],
          '-',
        ]),
        downloadedBytes: downloaded,
        uploadedBytes: uploaded,
        totalBytes: total,
        countryCode: _firstString([
          flow['other_country_code'],
          flow['country_code'],
          flow['country'],
          '',
        ]).toUpperCase(),
        region: _firstString([
          flow['other_country_name'],
          flow['country_name'],
          flow['region'],
          '',
        ]),
        direction: _firstString([flow['direction'], 'Outbound']),
        rawJson: line,
      );
    } catch (_) {
      return null;
    }
  }

  static NetifyFlow? fromConnectionFlowRow(String line) {
    final parts = line.split('|');
    if (parts.length < 7) return null;

    final timestampSeconds = int.tryParse(parts[1]);
    final timestamp = timestampSeconds == null
        ? DateTime.now().toUtc()
        : DateTime.fromMillisecondsSinceEpoch(
            timestampSeconds * 1000,
            isUtc: true,
          );
    final source = parts[3].trim();
    final destination = parts[4].trim();
    final destinationParts = _splitEndpoint(destination);
    final transferBytes = _parseTransferBytes(parts[5]);

    return NetifyFlow(
      timestamp: timestamp,
      deviceMac: '',
      localIp: source.isEmpty ? '-' : source,
      localPort: '',
      destination: destinationParts.$1.isEmpty ? '-' : destinationParts.$1,
      application: destinationParts.$1.isEmpty ? '-' : destinationParts.$1,
      protocol: parts[2].trim().isEmpty ? 'N/A' : parts[2].trim(),
      destinationIp: destinationParts.$1.isEmpty ? '-' : destinationParts.$1,
      destinationPort: destinationParts.$2,
      interfaceName: '-',
      downloadedBytes: transferBytes,
      uploadedBytes: 0,
      totalBytes: transferBytes,
      countryCode: '',
      region: '',
      direction: 'Outbound',
      rawJson: line,
    );
  }

  static DateTime _parseNetifyTimestamp(dynamic value) {
    final numeric = value is num ? value.toDouble() : double.tryParse('$value');
    if (numeric != null && numeric > 0) {
      final milliseconds = numeric > 1000000000000
          ? numeric.round()
          : (numeric * 1000).round();
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    return DateTime.now().toUtc();
  }

  static dynamic _nestedString(Map flow, List<String> path) {
    dynamic current = flow;
    for (final key in path) {
      if (current is! Map) return null;
      current = current[key];
    }
    return current;
  }

  static String _firstString(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static int _firstInt(List<dynamic> values) {
    for (final value in values) {
      final parsed = value is num ? value.round() : int.tryParse('$value');
      if (parsed != null && parsed >= 0) return parsed;
    }
    return 0;
  }

  static (String, String) _splitEndpoint(String endpoint) {
    final trimmed = endpoint.trim();
    final match = RegExp(
      r'^((?:\d{1,3}\.){3}\d{1,3}):(\d+)$',
    ).firstMatch(trimmed);
    if (match == null) return (trimmed, '');
    return (match.group(1) ?? trimmed, match.group(2) ?? '');
  }

  static int _parseTransferBytes(String transfer) {
    final match = RegExp(r'^(\d+)').firstMatch(transfer.trim());
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  static String _normalizeMac(dynamic value) {
    if (value is List) {
      for (final entry in value) {
        final parsed = _normalizeMac(entry);
        if (parsed.isNotEmpty) return parsed;
      }
      return '';
    }
    final text = value?.toString().trim().toUpperCase() ?? '';
    if (text.isEmpty) return '';
    return text.split(RegExp(r'[\s,]+')).first.replaceAll('-', ':');
  }
}

class AppState extends ChangeNotifier {
  static AppState? _instance;

  late final SecureStorageService _secureStorageService;
  IApiService? _apiService;
  IAuthService? _authService;
  RouterService? _routerService;
  ThroughputService? _throughputService;
  final HttpClientManager _httpClientManager = HttpClientManager();

  // Reviewer mode state
  bool _reviewerModeEnabled = false;
  bool get reviewerModeEnabled => _reviewerModeEnabled;

  bool _isLoading = false;
  String? _errorMessage;

  Map<String, dynamic>? _dashboardData;
  bool _isDashboardLoading = false;
  String? _dashboardError;

  Timer? _throughputTimer;
  Timer? _systemInfoTimer;
  Timer? _pollingTimer;
  int _pollAttempts = 0;
  static const int _maxPollAttempts =
      40; // Max 40 attempts = ~5 minutes with backoff

  // Add rebooting state
  bool _isRebooting = false;
  bool get isRebooting => _isRebooting;

  // Theme mode state
  ThemeMode _themeMode = ThemeMode.system;
  static const String _themeModeKey = 'themeMode';

  // Clients view mode (aggregate across routers)
  bool _clientsAggregateAllRouters = true;
  static const String _clientsAggregateKey = 'clients_aggregate_all';
  bool get clientsAggregateAllRouters => _clientsAggregateAllRouters;

  // Dashboard preferences state
  DashboardPreferences _dashboardPreferences = DashboardPreferences();
  DashboardPreferences get dashboardPreferences => _dashboardPreferences;

  List<model.Router> get routers => _routerService?.routers ?? [];
  model.Router? get selectedRouter => _routerService?.selectedRouter;

  VoidCallback? onRouterBackOnline;

  // Add requestedTab for programmatic tab switching
  int? requestedTab;
  String? requestedInterfaceToScroll;

  void requestTab(int index, {String? interfaceToScroll}) {
    requestedTab = index;
    requestedInterfaceToScroll = interfaceToScroll;
    notifyListeners();
  }

  AppState._() {
    _initialize();
  }

  static AppState get instance {
    return _instance ??= AppState._();
  }

  Future<void> _initialize() async {
    await _loadReviewerMode();
    _initializeServices();
    await _loadThemeMode();
    await loadRouters(); // Load routers on app start (sets selectedRouter)
    await _migrateGlobalDashboardPreferencesIfNeeded(); // Proactively migrate legacy prefs
    await _loadClientsViewMode();
    await loadDashboardPreferences(); // Load prefs scoped to selected router
  }

  /// One-time migration: if a global 'dashboard_preferences' exists,
  /// copy it to each router-specific key that doesn't already have prefs.
  Future<void> _migrateGlobalDashboardPreferencesIfNeeded() async {
    try {
      final globalKey = 'dashboard_preferences';
      final globalJson = await _secureStorageService.readValue(globalKey);
      if (globalJson == null || globalJson.isEmpty) return;

      final routers = _routerService?.routers ?? const <model.Router>[];
      if (routers.isEmpty) return;

      // Validate JSON format before writing
      try {
        jsonDecode(globalJson);
      } catch (_) {
        return; // Not valid JSON; skip migration
      }

      for (final router in routers) {
        final key = 'dashboard_preferences:${router.id}';
        final existing = await _secureStorageService.readValue(key);
        if (existing == null || existing.isEmpty) {
          await _secureStorageService.writeValue(key, globalJson);
        }
      }

      // If all routers now have scoped prefs, remove the legacy global key
      var allHavePrefs = true;
      for (final router in routers) {
        final key = 'dashboard_preferences:${router.id}';
        final v = await _secureStorageService.readValue(key);
        if (v == null || v.isEmpty) {
          allHavePrefs = false;
          break;
        }
      }
      if (allHavePrefs) {
        await _secureStorageService.deleteValue(globalKey);
      }
    } catch (e, stack) {
      Logger.exception(
        'Failed migrating global dashboard preferences',
        e,
        stack,
      );
    }
  }

  Future<void> _loadReviewerMode() async {
    // Initialize secure storage service with default factory first
    ServiceContainer.configure(reviewerMode: false);
    _secureStorageService = ServiceContainer.instance.factory
        .createSecureStorageService();

    final stored = await _secureStorageService.readValue(
      AppConfig.reviewerModeKey,
    );
    _reviewerModeEnabled = stored == 'true';
  }

  void _initializeServices() {
    // Configure the service container based on reviewer mode
    ServiceContainer.configure(reviewerMode: _reviewerModeEnabled);

    // Create services using the factory
    final factory = ServiceContainer.instance.factory;
    _authService = factory.createAuthService();
    _apiService = factory.createApiService();
    _routerService = factory.createRouterService();
    _throughputService = factory.createThroughputService();
  }

  Future<void> setReviewerMode(bool enabled) async {
    _reviewerModeEnabled = enabled;
    await _secureStorageService.writeValue(
      AppConfig.reviewerModeKey,
      enabled.toString(),
    );
    _initializeServices();
    notifyListeners();
  }

  Future<void> _loadThemeMode() async {
    final stored = await _secureStorageService.readValue(_themeModeKey);
    if (stored == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (stored == 'light') {
      _themeMode = ThemeMode.light;
    } else if (stored == 'system') {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  ThemeMode get themeMode => _themeMode;
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _secureStorageService.writeValue(_themeModeKey, mode.name);
    notifyListeners();
  }

  Future<void> _loadClientsViewMode() async {
    final stored = await _secureStorageService.readValue(_clientsAggregateKey);
    if (stored == 'true') {
      _clientsAggregateAllRouters = true;
    } else if (stored == 'false') {
      _clientsAggregateAllRouters = false;
    }
  }

  Future<void> setClientsAggregateAllRouters(bool aggregate) async {
    _clientsAggregateAllRouters = aggregate;
    await _secureStorageService.writeValue(
      _clientsAggregateKey,
      aggregate.toString(),
    );
    notifyListeners();
  }

  Future<void> loadDashboardPreferences() async {
    try {
      // Scope preferences by selected router if available
      final routerId = _routerService?.selectedRouter?.id;
      final key = routerId != null
          ? 'dashboard_preferences:$routerId'
          : 'dashboard_preferences';

      // Try router-specific key first
      String? json = await _secureStorageService.readValue(key);
      // Backward-compat: if missing, fall back to global key
      if ((json == null || json.isEmpty) && routerId != null) {
        json = await _secureStorageService.readValue('dashboard_preferences');
      }
      if (json != null && json.isNotEmpty) {
        _dashboardPreferences = DashboardPreferences.fromJson(jsonDecode(json));
        notifyListeners();
      }
    } catch (e, stack) {
      Logger.exception('Failed to load dashboard preferences', e, stack);
      _dashboardPreferences = DashboardPreferences();
    }
  }

  Future<void> saveDashboardPreferences(DashboardPreferences prefs) async {
    try {
      _dashboardPreferences = prefs;
      final routerId = _routerService?.selectedRouter?.id;
      final key = routerId != null
          ? 'dashboard_preferences:$routerId'
          : 'dashboard_preferences';
      await _secureStorageService.writeValue(key, jsonEncode(prefs.toJson()));
      notifyListeners();
    } catch (e, stack) {
      Logger.exception('Failed to save dashboard preferences', e, stack);
      rethrow;
    }
  }

  String? get sysauth => _authService?.sysauth;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  Map<String, dynamic>? get dashboardData => _dashboardData;
  List<double> get rxHistory => _throughputService?.rxHistory ?? [];
  List<double> get txHistory => _throughputService?.txHistory ?? [];
  double get currentRxRate => _throughputService?.currentRxRate ?? 0.0;
  double get currentTxRate => _throughputService?.currentTxRate ?? 0.0;
  bool get isDashboardLoading => _isDashboardLoading;
  String? get dashboardError => _dashboardError;

  // Interface-specific throughput getters
  List<double> getRxHistoryForInterface(String interface) {
    final deviceName = _getDeviceNameForInterface(interface);
    return _throughputService?.getRxHistoryForInterface(
          deviceName ?? interface,
        ) ??
        [];
  }

  List<double> getTxHistoryForInterface(String interface) {
    final deviceName = _getDeviceNameForInterface(interface);
    return _throughputService?.getTxHistoryForInterface(
          deviceName ?? interface,
        ) ??
        [];
  }

  double getCurrentRxRateForInterface(String interface) {
    final deviceName = _getDeviceNameForInterface(interface);
    return _throughputService?.getCurrentRxRateForInterface(
          deviceName ?? interface,
        ) ??
        0.0;
  }

  double getCurrentTxRateForInterface(String interface) {
    final deviceName = _getDeviceNameForInterface(interface);
    return _throughputService?.getCurrentTxRateForInterface(
          deviceName ?? interface,
        ) ??
        0.0;
  }

  Future<void> loadRouters() async {
    await _routerService?.loadRouters();
    notifyListeners();
  }

  Future<void> addRouter(model.Router router) async {
    await _routerService?.addRouter(router);
    notifyListeners();
  }

  Future<void> removeRouter(String id) async {
    if (_routerService == null) return;

    // Get the router before removing to clear its certificates
    final router = _routerService!.routers.firstWhere(
      (r) => r.id == id,
      orElse: () => throw Exception('Router not found'),
    );

    // Clear certificates for this specific router
    await _httpClientManager.clearCertificatesForHost(router.ipAddress);

    final needsSwitch = await _routerService!.removeRouter(id);
    if (needsSwitch && _routerService!.routers.isNotEmpty) {
      await selectRouter(_routerService!.routers.first.id);
    } else if (_routerService!.selectedRouter == null) {
      _dashboardData = null;
      notifyListeners();
    } else {
      notifyListeners();
    }
  }

  Future<void> selectRouter(String id, {BuildContext? context}) async {
    if (_routerService == null || _routerService!.routers.isEmpty) return;

    final found = _routerService!.selectRouter(id);
    if (found == null) return;

    _isLoading = true;
    _dashboardError = null;

    // Clear throughput data when switching routers to prevent mixing data from different routers
    _cancelThroughputTimer();

    // Determine a safe context before any awaits
    final safeContext = context?.mounted == true
        ? context
        : null; // ignore: use_build_context_synchronously

    // Load router-scoped dashboard preferences immediately on selection
    await loadDashboardPreferences();

    notifyListeners();
    // ignore: use_build_context_synchronously
    final loginSuccess = await login(
      found.ipAddress,
      found.username,
      found.password,
      found.useHttps,
      fromRouter: true,
      context: safeContext, // ignore: use_build_context_synchronously
    );
    if (loginSuccess) {
      await fetchDashboardData();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateRouter(model.Router router) async {
    await _routerService?.updateRouter(router);
    notifyListeners();
  }

  Future<bool> login(
    String ip,
    String user,
    String pass,
    bool useHttps, {
    bool fromRouter = false,
    BuildContext? context,
  }) async {
    _isLoading = true;
    _errorMessage = null;

    // Clear throughput data when logging in to prevent mixing data from different sessions
    _cancelThroughputTimer();

    notifyListeners();

    try {
      await _authService!.login(ip, user, pass, useHttps, context: context);

      // Check if authentication was successful
      if (_authService!.isAuthenticated) {
        // Get the actual protocol used (might be different due to redirect)
        final actualUseHttps = _authService!.useHttps;

        if (!fromRouter) {
          // If not from router selection, add or update router with detected protocol
          if (_routerService != null) {
            final router = _routerService!.createRouter(
              ip,
              user,
              pass,
              actualUseHttps, // Use the detected protocol
            );
            final idx = _routerService!.routers.indexWhere(
              (r) => r.id == router.id,
            );
            if (idx == -1) {
              await addRouter(router);
            } else {
              await updateRouter(router);
            }
          }
        } else if (actualUseHttps != useHttps && _routerService != null) {
          // If we're logging in from a saved router and the protocol changed, update it
          final router = _routerService!.selectedRouter;
          if (router != null) {
            final updatedRouter = router.copyWith(useHttps: actualUseHttps);
            await updateRouter(updatedRouter);
            Logger.info(
              'Updated router protocol from ${useHttps ? "HTTPS" : "HTTP"} to ${actualUseHttps ? "HTTPS" : "HTTP"}',
            );
          }
        }
        await fetchDashboardData();
        _startThroughputTimer();
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage =
            'Login Failed: Invalid credentials or host unreachable.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'An error occurred: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void logout() {
    _authService?.logout().then((_) {});
    _dashboardData = null;
    _dashboardError = null;
    _cancelThroughputTimer();
    // Optionally, do not clear routers or selectedRouter
    notifyListeners();
  }

  Future<void> retryDashboardConnection({BuildContext? context}) async {
    final router = _routerService?.selectedRouter;
    if (router == null || _authService == null) {
      await fetchDashboardData();
      return;
    }

    _isDashboardLoading = true;
    _dashboardError = null;
    _cancelThroughputTimer();
    _httpClientManager.disposeClient(router.ipAddress, router.useHttps);
    notifyListeners();

    try {
      final safeContext = context?.mounted == true ? context : null;
      final loginSuccess = await _authService!.tryAutoLogin(
        router.ipAddress,
        router.username,
        router.password,
        router.useHttps,
        context: safeContext,
      );

      if (!loginSuccess || _authService?.sysauth == null) {
        _dashboardError =
            'Failed to reconnect. Please check your router credentials and network connection.';
        _dashboardData = null;
        return;
      }

      final actualUseHttps = _authService!.useHttps;
      if (actualUseHttps != router.useHttps) {
        await updateRouter(router.copyWith(useHttps: actualUseHttps));
      }

      await fetchDashboardData();
    } catch (e) {
      _dashboardError = 'Failed to reconnect: $e';
      _dashboardData = null;
    } finally {
      _isDashboardLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchDashboardData() async {
    if (_reviewerModeEnabled) {
      // For reviewer mode, return mock data immediately
      _isDashboardLoading = true;
      _dashboardError = null;
      notifyListeners();

      await Future.delayed(
        const Duration(milliseconds: 500),
      ); // Simulate network delay

      try {
        final results = await Future.wait([
          _apiService!.callSimple('system', 'board', {}),
          _apiService!.callSimple('system', 'info', {}),
          _apiService!.callSimple('network', 'device', {}),
          _apiService!.callSimple('network.interface', 'dump', {}),
          _apiService!.callSimple('wireless', 'devices', {}),
          _apiService!.callSimple('luci-rpc', 'getDHCPLeases', {}),
          _apiService!.callSimple('uci', 'get', {'config': 'wireless'}),
        ]);

        final interfaceDump = results[3][1] as Map<String, dynamic>;
        final rawDhcpData = results[5][1] as Map<String, dynamic>;
        final processedDhcpData = _processDhcpLeases(rawDhcpData);
        final associatedMacs = await _apiService!.fetchAssociatedStations();

        _dashboardData = {
          'boardInfo': results[0][1],
          'sysInfo': results[1][1],
          'networkDevices': results[2][1],
          'interfaceDump': interfaceDump,
          'wireless': results[4][1],
          'dhcpLeases': processedDhcpData,
          'uciWirelessConfig': results[6][1],
          'wan': _extractWanData(interfaceDump),
          'wireguard': <String, dynamic>{}, // Empty for reviewer mode
          'conntrack': {'count': 142, 'max': 1000},
          'pingSamples': await fetchPingMonitorSamples(limit: 144),
          'netifyFlowCount': 315188,
          'deviceCount': _countRouterDevices(processedDhcpData, associatedMacs),
          '_lastUpdated':
              DateTime.now().millisecondsSinceEpoch, // Force UI updates
        };

        // Update throughput data with mock network data for reviewer mode
        if (_throughputService != null) {
          final networkData = results[2][1] as Map<String, dynamic>?;
          final wanDeviceNames = {
            'eth0',
            'wlan0',
            'br-lan',
          }; // Mock all devices

          // Check if we should track specific interface
          final prefs = _dashboardPreferences;
          String? specificInterface;
          if (!prefs.showAllThroughput &&
              prefs.primaryThroughputInterface != null) {
            // Map interface name to actual device name
            specificInterface = _getDeviceNameForInterface(
              prefs.primaryThroughputInterface!,
            );
          }

          _throughputService!.updateThroughput(
            networkData,
            wanDeviceNames,
            specificInterface: specificInterface,
          );
        }

        // Start throughput timer for reviewer mode
        _startThroughputTimer();
        _startSystemInfoTimer();

        // Schedule an immediate throughput update to get initial data faster
        Future.delayed(const Duration(milliseconds: 100), () {
          _updateThroughputOnly();
        });

        _isDashboardLoading = false;
        notifyListeners();
      } catch (e) {
        _dashboardError = 'Failed to fetch dashboard data: $e';
        _isDashboardLoading = false;
        notifyListeners();
      }
      return;
    }

    if (_routerService?.selectedRouter == null ||
        _authService?.sysauth == null) {
      return;
    }

    // If already loading, don't start another request (but this shouldn't prevent pull-to-refresh)
    // We'll let the new request proceed and the loading state will be handled properly
    final ip = _routerService!.selectedRouter!.ipAddress;
    final useHttps = _routerService!.selectedRouter!.useHttps;

    _isDashboardLoading = true;
    _dashboardError = null;
    notifyListeners();

    try {
      // Perform all API calls in parallel
      Future<dynamic> callOptionalRpc({
        required String object,
        required String method,
        Map<String, dynamic>? params,
      }) async {
        try {
          return await _apiService!.call(
            ip,
            _authService!.sysauth!,
            useHttps,
            object: object,
            method: method,
            params: params,
          );
        } catch (e, stack) {
          Logger.warning('Optional RPC $object.$method failed: $e');
          Logger.debug('Optional RPC $object.$method stack: $stack');
          return null;
        }
      }

      final wirelessFuture = callOptionalRpc(
        object: 'luci-rpc',
        method: 'getWirelessDevices',
        params: {},
      );

      // UCI wireless config is optional — wired-only routers may not have it
      final uciWirelessFuture = callOptionalRpc(
        object: 'uci',
        method: 'get',
        params: {'config': 'wireless'},
      );

      final conntrackFuture = _fetchConntrackData(ip, useHttps);
      final pingSamplesFuture = fetchPingMonitorSamples(limit: 144);
      final netifyFlowCountFuture = fetchNetifyFlowCount();
      final associatedMacsFuture = _apiService!
          .fetchAllAssociatedWirelessMacsWithContext(
            ipAddress: ip,
            sysauth: _authService!.sysauth!,
            useHttps: useHttps,
          )
          .catchError((e, stack) {
            Logger.warning('Optional associated station fetch failed: $e');
            Logger.debug('Optional associated station fetch stack: $stack');
            return <String, Set<String>>{};
          });

      final results = await Future.wait([
        _apiService!.call(
          ip,
          _authService!.sysauth!,
          useHttps,
          object: 'system',
          method: 'board',
          params: {},
        ),
        _apiService!.call(
          ip,
          _authService!.sysauth!,
          useHttps,
          object: 'system',
          method: 'info',
          params: {},
        ),
        _apiService!.call(
          ip,
          _authService!.sysauth!,
          useHttps,
          object: 'luci-rpc',
          method: 'getNetworkDevices',
          params: {},
        ),
        _apiService!.call(
          ip,
          _authService!.sysauth!,
          useHttps,
          object: 'network.interface',
          method: 'dump',
          params: {},
        ),
        _apiService!.call(
          ip,
          _authService!.sysauth!,
          useHttps,
          object: 'luci-rpc',
          method: 'getDHCPLeases',
          params: {},
        ),
      ]);

      // Helper to safely extract data and handle errors from LuCI's [status, data] responses
      dynamic getData(dynamic result) {
        if (result is List && result.length > 1) {
          if (result[0] == 0) {
            return result[1]; // Success
          } else {
            // Throw an exception with the error message from the API
            final errorMessage = result[1] is String
                ? result[1]
                : 'Unknown API Error';
            throw Exception(errorMessage);
          }
        }
        // Handle cases where the result is not in the expected format
        return result;
      }

      dynamic getOptionalData(dynamic result, String label) {
        try {
          return getData(result);
        } catch (e) {
          Logger.warning('Optional RPC $label returned error: $e');
          return null;
        }
      }

      final boardInfoData = getData(results[0]);
      final sysInfoData = getData(results[1]);
      final networkData = getData(results[2]) as Map<String, dynamic>?;
      final interfaceDump = getData(results[3]) as Map<String, dynamic>?;
      final dhcpLeases = getData(results[4]) as Map<String, dynamic>?;

      // Await optional wireless futures in parallel (won't throw — wired-only routers are fine)
      final optionalResults = await Future.wait([
        wirelessFuture,
        uciWirelessFuture,
        conntrackFuture,
        pingSamplesFuture,
        netifyFlowCountFuture,
        associatedMacsFuture,
      ]);
      final wirelessRaw = optionalResults[0];
      final uciWirelessRaw = optionalResults[1];
      final conntrackData = optionalResults[2] as Map<String, int>;
      final pingSamples = optionalResults[3] as List<PingMonitorSample>;
      final netifyFlowCount = optionalResults[4] as int;
      final associatedMacs = optionalResults[5] as Map<String, Set<String>>;

      Map<String, dynamic>? wirelessData;
      if (wirelessRaw != null) {
        final parsedWireless = getOptionalData(
          wirelessRaw,
          'luci-rpc.getWirelessDevices',
        );
        if (parsedWireless is Map<String, dynamic>) {
          wirelessData = parsedWireless;
        }
      }

      dynamic uciWirelessConfig;
      if (uciWirelessRaw != null) {
        uciWirelessConfig = getOptionalData(uciWirelessRaw, 'uci.get wireless');
      }

      // Fetch WireGuard peer information for WireGuard interfaces
      final wireguardData = <String, dynamic>{};
      if (interfaceDump != null && interfaceDump['interface'] is List) {
        // Check if there are any WireGuard interfaces
        final hasWireGuardInterfaces = interfaceDump['interface'].any((
          interface,
        ) {
          if (interface is Map<String, dynamic>) {
            final proto = interface['proto'] as String?;
            return proto == 'wireguard';
          }
          return false;
        });

        if (hasWireGuardInterfaces) {
          // Fetch all WireGuard data at once
          final allWireGuardData = await _apiService!.fetchWireGuardPeers(
            ipAddress: ip,
            sysauth: _authService!.sysauth!,
            useHttps: useHttps,
            interface: '', // Empty string to get all interfaces
          );

          if (allWireGuardData != null) {
            // The new endpoint returns data for all interfaces
            // We need to extract data for each WireGuard interface
            for (final interface in interfaceDump['interface']) {
              if (interface is Map<String, dynamic>) {
                final ifname = interface['interface'] as String?;
                final proto = interface['proto'] as String?;
                if (proto == 'wireguard' && ifname != null) {
                  // Look for this interface in the WireGuard data
                  final interfaceData = allWireGuardData[ifname];

                  if (interfaceData != null) {
                    wireguardData[ifname] = interfaceData;
                  }
                }
              }
            }
          }
        }
      }

      // Throughput calculation - collect ALL interface devices
      final wanDeviceNames = <String>{};
      if (interfaceDump != null && interfaceDump['interface'] is List) {
        for (final interface in interfaceDump['interface']) {
          if (interface is Map<String, dynamic>) {
            final ifname = interface['interface'] as String?;
            // Skip only loopback interface
            if (ifname != null && ifname != 'loopback' && ifname != 'lo') {
              final device = interface['device'] as String?;
              final l3Device = interface['l3_device'] as String?;
              if (device != null) {
                wanDeviceNames.add(device);
              }
              if (l3Device != null && l3Device != device) {
                wanDeviceNames.add(l3Device);
              }
            }
          }
        }
      }

      // Update throughput data using the service
      // Check if we should track specific interface
      final prefs = _dashboardPreferences;
      String? specificInterface;
      if (!prefs.showAllThroughput &&
          prefs.primaryThroughputInterface != null) {
        // Map interface name to actual device name
        specificInterface = _getDeviceNameForInterface(
          prefs.primaryThroughputInterface!,
        );
      }

      _throughputService?.updateThroughput(
        networkData,
        wanDeviceNames,
        specificInterface: specificInterface,
      );

      _dashboardData = {
        'boardInfo': boardInfoData,
        'sysInfo': sysInfoData,
        'networkDevices': networkData,
        'interfaceDump': interfaceDump,
        'wireless': wirelessData ?? <String, dynamic>{},
        'dhcpLeases': dhcpLeases,
        'wan': _extractWanData(interfaceDump),
        'uciWirelessConfig': uciWirelessConfig,
        'wireguard': wireguardData,
        'conntrack': conntrackData,
        'pingSamples': pingSamples,
        'netifyFlowCount': netifyFlowCount,
        'deviceCount': _countRouterDevices(dhcpLeases, associatedMacs),
        '_lastUpdated':
            DateTime.now().millisecondsSinceEpoch, // Force UI updates
      };

      // Hybrid approach: update lastKnownHostname for the selected router
      final boardInfo = _dashboardData?['boardInfo'] as Map<String, dynamic>?;
      final hostname = boardInfo?['hostname']?.toString();
      if (hostname != null && hostname.isNotEmpty) {
        await _routerService?.updateSelectedRouterHostname(hostname);
      }

      // Ensure throughput timer is running
      _startThroughputTimer();
      _startSystemInfoTimer();

      // Schedule an immediate throughput update to get initial data faster
      Future.delayed(const Duration(milliseconds: 100), () {
        _updateThroughputOnly();
      });
    } catch (e) {
      final errorMessage = e.toString();
      if (errorMessage.contains('Access denied')) {
        _dashboardError = 'Access Denied: Check RPC permissions for this user.';
      } else {
        _dashboardError = 'Failed to fetch dashboard data: $e';
      }
      // Log error with stack trace for debugging
      // print('Dashboard fetch error: $e\n$stack');
      // Clear dashboard data when there's an error so we don't show stale data
      _dashboardData = null;
    } finally {
      _isDashboardLoading = false;
      notifyListeners();
    }
  }

  Map<String, dynamic> _processDhcpLeases(Map<String, dynamic> rawDhcpData) {
    final stdout = rawDhcpData['stdout'] as String? ?? '';
    final leases = <Map<String, dynamic>>[];

    for (final line in stdout.split('\n')) {
      if (line.trim().isEmpty) continue;

      final parts = line.trim().split(' ');
      if (parts.length >= 5) {
        // Format: timestamp mac_address ip_address hostname client_id
        final timestamp = int.tryParse(parts[0]) ?? 0;
        final macAddress = parts[1];
        final ipAddress = parts[2];
        final hostname = parts[3];

        leases.add({
          'expires': timestamp,
          'macaddr': macAddress,
          'ipaddr': ipAddress,
          'hostname': hostname,
          'activetime': 0, // Default for mock data
          'leasetime': timestamp,
        });
      }
    }

    return {'dhcp_leases': leases};
  }

  Map<String, int> _parseConntrackData(dynamic rawData) {
    final raw = switch (rawData) {
      {'stdout': final stdout} => stdout?.toString() ?? '',
      {'data': final data} => data?.toString() ?? '',
      _ => rawData?.toString() ?? '',
    };
    final values = RegExp(r'\d+')
        .allMatches(raw)
        .map((match) => int.tryParse(match.group(0) ?? ''))
        .whereType<int>()
        .toList();

    return {
      'count': values.isNotEmpty ? values[0] : 0,
      'max': values.length > 1 && values[1] > 0 ? values[1] : 1000,
    };
  }

  int? _parseProcInt(String value) {
    return int.tryParse(value.trim().split(RegExp(r'\s+')).firstOrNull ?? '');
  }

  int _countRouterDevices(
    Map<String, dynamic>? dhcpLeases,
    Map<String, Set<String>> associatedMacs,
  ) {
    final macs = <String>{};
    final leases = dhcpLeases?['dhcp_leases'] as List<dynamic>? ?? const [];

    for (final lease in leases) {
      if (lease is Map) {
        final mac = lease['macaddr']?.toString();
        if (mac != null && mac.isNotEmpty) {
          macs.add(mac.toUpperCase().replaceAll('-', ':'));
        }
      }
    }

    for (final stations in associatedMacs.values) {
      for (final mac in stations) {
        if (mac.isNotEmpty) {
          macs.add(mac.toUpperCase().replaceAll('-', ':'));
        }
      }
    }

    return macs.length;
  }

  Future<Map<String, int>> _fetchConntrackData(String ip, bool useHttps) async {
    if (_authService?.sysauth == null) {
      return {'count': 0, 'max': 1000};
    }

    try {
      Future<int?> readCounter(String path) async {
        final result = await _apiService!.call(
          ip,
          _authService!.sysauth!,
          useHttps,
          object: 'file',
          method: 'read',
          params: {'path': path},
        );
        return _parseProcInt(_commandOutput(result));
      }

      final count =
          await readCounter('/proc/sys/net/netfilter/nf_conntrack_count') ??
          await readCounter('/proc/sys/net/ipv4/netfilter/ip_conntrack_count');
      final max =
          await readCounter('/proc/sys/net/netfilter/nf_conntrack_max') ??
          await readCounter('/proc/sys/net/ipv4/netfilter/ip_conntrack_max');

      if (count != null || max != null) {
        return {
          'count': count ?? 0,
          'max': max != null && max > 0 ? max : 1000,
        };
      }

      final fallback = await _apiService!.systemExec(
        ip,
        _authService!.sysauth!,
        useHttps,
        command:
            'cat /proc/sys/net/netfilter/nf_conntrack_count /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || cat /proc/sys/net/ipv4/netfilter/ip_conntrack_count /proc/sys/net/ipv4/netfilter/ip_conntrack_max 2>/dev/null',
      );

      if (fallback is List && fallback.length > 1 && fallback[0] == 0) {
        return _parseConntrackData(fallback[1]);
      }
      return _parseConntrackData(fallback);
    } catch (e, stack) {
      Logger.warning('Optional system.exec conntrack failed: $e');
      Logger.debug('Optional system.exec conntrack stack: $stack');
      return {'count': 0, 'max': 1000};
    }
  }

  Future<SystemStorageDetails> fetchSystemStorageDetails({
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) {
      return const SystemStorageDetails(
        userTotalBytes: 56 * 1024 * 1024,
        userFreeBytes: 56 * 1024 * 1024,
        tempTotalBytes: 117 * 1024 * 1024,
        tempFreeBytes: 116 * 1024 * 1024,
      );
    }

    final router = _routerService?.selectedRouter;
    final sysauth = _authService?.sysauth;
    if (router == null || sysauth == null || _apiService == null) {
      return SystemStorageDetails.empty;
    }

    try {
      final result = await _apiService!.call(
        router.ipAddress,
        sysauth,
        router.useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/bin/sh',
          'params': [
            '-c',
            'df -kP /overlay /tmp / 2>/dev/null || df -kP 2>/dev/null',
          ],
        },
        context: context,
      );
      return _parseSystemStorageDetails(_commandOutput(result));
    } catch (e, stack) {
      Logger.warning('Optional system storage fetch failed: $e');
      Logger.debug('Optional system storage stack: $stack');
      return SystemStorageDetails.empty;
    }
  }

  SystemStorageDetails _parseSystemStorageDetails(String output) {
    ({int total, int free})? user;
    ({int total, int free})? temp;

    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('Filesystem')) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 6) continue;

      final totalKb = int.tryParse(parts[1]);
      final freeKb = int.tryParse(parts[3]);
      if (totalKb == null || freeKb == null) continue;

      final mount = parts.last;
      final values = (total: totalKb * 1024, free: freeKb * 1024);
      if (mount == '/tmp') {
        temp = values;
      } else if (mount == '/overlay' || mount == '/') {
        user ??= values;
      }
    }

    return SystemStorageDetails(
      userTotalBytes: user?.total ?? 0,
      userFreeBytes: user?.free ?? 0,
      tempTotalBytes: temp?.total ?? 0,
      tempFreeBytes: temp?.free ?? 0,
    );
  }

  String _sqliteCommand(String dbExpression, String sql) {
    final escapedSql = sql.replaceAll('"', r'\"').replaceAll(r'$', r'\$');
    return 'db="$dbExpression"; '
        'statement="PRAGMA busy_timeout=3000; $escapedSql"; '
        'if command -v sqlite3 >/dev/null 2>&1; then sqlite3 -batch -noheader -separator "|" "\$db" "\$statement"; '
        'elif command -v sqlite3-cli >/dev/null 2>&1; then sqlite3-cli -batch -noheader -separator "|" "\$db" "\$statement"; '
        'else echo "sqlite3 not installed" >&2; exit 127; fi';
  }

  String _connectionFlowsDbExpression() {
    return r'$(uci -q get openwalla.connection_flows.db_path 2>/dev/null || echo /tmp/openwalla-connection-flows.sqlite)';
  }

  String _netifyDbExpression() {
    return r'$(uci -q get openwalla.collector.db_path 2>/dev/null || echo /tmp/openwalla-netify.sqlite)';
  }

  Future<String> _sqliteQueryOutput({
    required String dbExpression,
    required String sql,
    BuildContext? context,
  }) async {
    final router = _routerService?.selectedRouter;
    final sysauth = _authService?.sysauth;
    if (router == null || sysauth == null || _apiService == null) return '';

    final result = await _apiService!.call(
      router.ipAddress,
      sysauth,
      router.useHttps,
      object: 'file',
      method: 'exec',
      params: {
        'command': '/bin/sh',
        'params': ['-c', _sqliteCommand(dbExpression, sql)],
      },
      context: context,
    );
    return _commandOutput(result);
  }

  String _connectionFlowWhereClause(String? protocolFilter) {
    switch (protocolFilter?.toUpperCase()) {
      case 'HTTP':
        return "WHERE protocol = 'HTTP' OR destination LIKE '%:80'";
      case 'HTTPS':
        return "WHERE protocol = 'HTTPS' OR destination LIKE '%:443'";
      case 'DNS':
        return "WHERE protocol = 'DNS' OR destination LIKE '%:53'";
      default:
        return '';
    }
  }

  String _netifyRawWhereClause(String? protocolFilter) {
    switch (protocolFilter?.toUpperCase()) {
      case 'HTTP':
        return 'WHERE upper(json) LIKE \'%"DETECTED_PROTOCOL_NAME"%:%"HTTP"%\'';
      case 'HTTPS':
        return 'WHERE upper(json) LIKE \'%"DETECTED_PROTOCOL_NAME"%:%"HTTP/S"%\'';
      case 'DNS':
        return 'WHERE upper(json) LIKE \'%"DETECTED_PROTOCOL_NAME"%:%"DNS"%\'';
      default:
        return '';
    }
  }

  Future<int> fetchNetifyFlowCount({
    String? protocolFilter,
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) return 315188;

    final router = _routerService?.selectedRouter;
    final sysauth = _authService?.sysauth;
    if (router == null || sysauth == null || _apiService == null) return 0;

    try {
      final output = await _sqliteQueryOutput(
        dbExpression: _netifyDbExpression(),
        sql:
            'SELECT COUNT(*) FROM flow_raw ${_netifyRawWhereClause(protocolFilter)};',
        context: context,
      );
      final netifyCount = _parseSqliteCount(output);
      if (netifyCount > 0) return netifyCount;
      return await _fetchConnectionFlowCount(protocolFilter: protocolFilter);
    } catch (e, stack) {
      Logger.warning('Optional Netify raw flow count fetch failed: $e');
      Logger.debug('Optional Netify raw flow count stack: $stack');
      return await _fetchConnectionFlowCount(protocolFilter: protocolFilter);
    }
  }

  Future<int> _fetchConnectionFlowCount({
    String? protocolFilter,
    BuildContext? context,
  }) async {
    try {
      final output = await _sqliteQueryOutput(
        dbExpression: _connectionFlowsDbExpression(),
        sql:
            'SELECT COUNT(*) FROM connection_flows ${_connectionFlowWhereClause(protocolFilter)};',
        context: context,
      );
      return _parseSqliteCount(output);
    } catch (e, stack) {
      Logger.warning('Optional connection flow count fetch failed: $e');
      Logger.debug('Optional connection flow count stack: $stack');
      return 0;
    }
  }

  int _parseSqliteCount(String output) {
    final countText = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => RegExp(r'^\d+$').hasMatch(line))
        .lastOrNull;
    return int.tryParse(countText ?? '') ?? 0;
  }

  Future<List<NetifyFlow>> fetchNetifyFlows({
    int limit = 50,
    int offset = 0,
    String? protocolFilter,
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) {
      final now = DateTime.now().toUtc();
      final mockFlows = List<NetifyFlow>.generate(20, (index) {
        final hosts = [
          'aws-iot.wyzecam.com',
          'm3-us.iotbing.com',
          'api.eu.amplitude.com',
          'connectivitycheck.gstatic.com',
          'unifi',
        ];
        return NetifyFlow(
          timestamp: now.subtract(Duration(minutes: index * 4)),
          deviceMac: index.isEven ? 'D0:3F:27:81:6C:17' : 'AA:12:44:9B:2D:10',
          localIp: index.isEven ? '10.0.200.225' : '10.0.0.32',
          localPort: '${33399 + index}',
          destination: hosts[index % hosts.length],
          application: hosts[index % hosts.length],
          protocol: index % 3 == 0 ? 'HTTP/S' : 'HTTP',
          destinationIp: index % 3 == 0 ? '54.69.167.88' : '142.250.72.14',
          destinationPort: index % 3 == 0 ? '8883' : '443',
          interfaceName: 'wan',
          downloadedBytes: 31 + (index * 420),
          uploadedBytes: 31 + (index * 120),
          totalBytes: 62 + (index * 540),
          countryCode: index % 3 == 0 ? 'US' : '',
          region: index % 3 == 0 ? 'United States' : '',
          direction: 'Outbound',
          rawJson: '{}',
        );
      });
      final normalized = protocolFilter?.toUpperCase();
      if (normalized == null || normalized.isEmpty) return mockFlows;
      return mockFlows
          .where(
            (flow) =>
                flow.protocol.toUpperCase().contains(normalized) ||
                flow.destinationPort ==
                    switch (normalized) {
                      'HTTP' => '80',
                      'HTTPS' => '443',
                      'DNS' => '53',
                      _ => '',
                    },
          )
          .toList();
    }

    final safeLimit = limit.clamp(1, 500).toInt();
    final safeOffset = offset < 0 ? 0 : offset;
    final netifyFlows = await _fetchNetifyRawFlows(
      limit: safeLimit,
      offset: safeOffset,
      protocolFilter: protocolFilter,
      context: context,
    );
    if (netifyFlows.isNotEmpty) return netifyFlows;
    return await _fetchConnectionFlows(
      limit: safeLimit,
      offset: safeOffset,
      protocolFilter: protocolFilter,
    );
  }

  Future<List<NetifyFlow>> _fetchConnectionFlows({
    required int limit,
    required int offset,
    String? protocolFilter,
    BuildContext? context,
  }) async {
    try {
      final output = await _sqliteQueryOutput(
        dbExpression: _connectionFlowsDbExpression(),
        sql:
            'SELECT id,timeinsert,protocol,source,destination,transfer,status FROM connection_flows ${_connectionFlowWhereClause(protocolFilter)} ORDER BY id DESC LIMIT $limit OFFSET $offset;',
        context: context,
      );
      return output
          .split('\n')
          .map((line) => NetifyFlow.fromConnectionFlowRow(line.trim()))
          .whereType<NetifyFlow>()
          .toList();
    } catch (e, stack) {
      Logger.warning('Optional connection flows fetch failed: $e');
      Logger.debug('Optional connection flows stack: $stack');
      return const [];
    }
  }

  Future<List<NetifyFlow>> _fetchNetifyRawFlows({
    required int limit,
    required int offset,
    String? protocolFilter,
    BuildContext? context,
  }) async {
    final router = _routerService?.selectedRouter;
    final sysauth = _authService?.sysauth;
    if (router == null || sysauth == null || _apiService == null) {
      return const [];
    }

    try {
      final output = await _sqliteQueryOutput(
        dbExpression: _netifyDbExpression(),
        sql:
            'SELECT json FROM flow_raw ${_netifyRawWhereClause(protocolFilter)} ORDER BY id DESC LIMIT $limit OFFSET $offset;',
        context: context,
      );
      return output
          .split('\n')
          .map((line) => NetifyFlow.fromJsonLine(line.trim()))
          .whereType<NetifyFlow>()
          .toList();
    } catch (e, stack) {
      Logger.warning('Optional Netify raw flows fetch failed: $e');
      Logger.debug('Optional Netify raw flows stack: $stack');
      return const [];
    }
  }

  String _systemExecOutput(dynamic result) {
    return _commandOutput(result);
  }

  String _commandOutput(dynamic result) {
    if (result is List && result.length > 1 && result[0] == 0) {
      return _commandOutput(result[1]);
    }
    if (result is Map) {
      final stdout = result['stdout'] ?? result['data'] ?? result['output'];
      if (stdout != null) return stdout.toString();
    }
    if (result is List && result.length > 1 && result[0] == 0) {
      return result[1]?.toString() ?? '';
    }
    return result?.toString() ?? '';
  }

  dynamic _extractRpcData(dynamic result) {
    if (result is List && result.length > 1) {
      return result[0] == 0 ? result[1] : null;
    }
    return result;
  }

  Future<Map?> _fetchOpenwallaUciValues({BuildContext? context}) async {
    final router = _routerService?.selectedRouter;
    final sysauth = _authService?.sysauth;
    if (router == null || sysauth == null || _apiService == null) {
      return null;
    }

    final result = await _apiService!.call(
      router.ipAddress,
      sysauth,
      router.useHttps,
      object: 'uci',
      method: 'get',
      params: {'config': 'openwalla'},
      context: context,
    );
    final data = _extractRpcData(result);
    return data is Map ? data['values'] as Map? : null;
  }

  Future<PingMonitorSettings> fetchPingMonitorSettings({
    BuildContext? context,
  }) async {
    const defaults = PingMonitorSettings(target: '1.1.1.1', thresholdMs: 100);
    if (_reviewerModeEnabled) return defaults;

    final router = _routerService?.selectedRouter;
    final sysauth = _authService?.sysauth;
    if (router == null || sysauth == null || _apiService == null) {
      return defaults;
    }

    try {
      final values = await _fetchOpenwallaUciValues(context: context);
      final ping = values is Map ? values['ping_monitor'] : null;

      if (ping is Map) {
        final target = ping['target']?.toString();
        final threshold = int.tryParse(ping['threshold']?.toString() ?? '');
        return PingMonitorSettings(
          target: target?.isNotEmpty == true ? target! : defaults.target,
          thresholdMs: threshold ?? defaults.thresholdMs,
        );
      }
    } catch (e, stack) {
      Logger.warning('Failed to fetch ping monitor settings: $e');
      Logger.debug('Ping monitor settings stack: $stack');
    }

    return defaults;
  }

  Future<void> savePingMonitorSettings(
    PingMonitorSettings settings, {
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) return;

    final router = _routerService?.selectedRouter;
    final sysauth = _authService?.sysauth;
    if (router == null || sysauth == null || _apiService == null) {
      throw Exception('Router is not connected');
    }

    await _apiService!.uciSet(
      router.ipAddress,
      sysauth,
      router.useHttps,
      config: 'openwalla',
      section: 'ping_monitor',
      values: {
        'target': settings.target,
        'threshold': settings.thresholdMs.toString(),
      },
      context: context,
    );
    await _apiService!.uciCommit(
      router.ipAddress,
      sysauth,
      router.useHttps,
      config: 'openwalla',
    );
    await _apiService!.systemExec(
      router.ipAddress,
      sysauth,
      router.useHttps,
      command:
          '/etc/init.d/openwalla-ping-monitor restart >/dev/null 2>&1 || true',
    );
  }

  Future<DnsMonitorSettings> fetchDnsMonitorSettings({
    BuildContext? context,
  }) async {
    const defaults = DnsMonitorSettings(hostname: 'openwrt.org');
    if (_reviewerModeEnabled) return defaults;

    try {
      final values = await _fetchOpenwallaUciValues(context: context);
      final dns = values is Map ? values['dns_monitor'] : null;
      if (dns is Map) {
        final target = dns['target']?.toString();
        return DnsMonitorSettings(
          hostname: target?.isNotEmpty == true ? target! : defaults.hostname,
        );
      }
    } catch (e, stack) {
      Logger.warning('Failed to fetch DNS monitor settings: $e');
      Logger.debug('DNS monitor settings stack: $stack');
    }

    return defaults;
  }

  Future<void> saveDnsMonitorSettings(
    DnsMonitorSettings settings, {
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) return;

    final router = _routerService?.selectedRouter;
    final sysauth = _authService?.sysauth;
    if (router == null || sysauth == null || _apiService == null) {
      throw Exception('Router is not connected');
    }

    await _apiService!.uciSet(
      router.ipAddress,
      sysauth,
      router.useHttps,
      config: 'openwalla',
      section: 'dns_monitor',
      values: {'target': settings.hostname},
      context: context,
    );
    await _apiService!.uciCommit(
      router.ipAddress,
      sysauth,
      router.useHttps,
      config: 'openwalla',
    );
    await _apiService!.systemExec(
      router.ipAddress,
      sysauth,
      router.useHttps,
      command:
          '/etc/init.d/openwalla-dns-monitor restart >/dev/null 2>&1 || true',
    );
  }

  Future<List<PingMonitorSample>> fetchPingMonitorSamples({
    int limit = 144,
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) {
      final now = DateTime.now().toUtc();
      return List<PingMonitorSample>.generate(12, (index) {
        final latency = 18.0 + ((index * 7) % 12);
        return PingMonitorSample(
          timestamp: now.subtract(Duration(minutes: (11 - index) * 5)),
          target: '1.1.1.1',
          status: 'OK',
          latencyMs: latency,
          message: 'reply',
        );
      });
    }

    final router = _routerService?.selectedRouter;
    final sysauth = _authService?.sysauth;
    if (router == null || sysauth == null || _apiService == null) {
      return const [];
    }

    try {
      final safeLimit = limit.clamp(1, 2000).toInt();
      final result = await _apiService!.systemExec(
        router.ipAddress,
        sysauth,
        router.useHttps,
        command:
            r'file="$(uci -q get openwalla.ping_monitor.output_file 2>/dev/null || echo /tmp/openwalla-ping-monitor.txt)"; '
            'tail -n $safeLimit "\$file" 2>/dev/null || true',
        context: context,
      );
      final output = _systemExecOutput(result);
      return output
          .split('\n')
          .map((line) => PingMonitorSample.fromLine(line.trim()))
          .whereType<PingMonitorSample>()
          .toList();
    } catch (e, stack) {
      Logger.warning('Optional ping monitor samples fetch failed: $e');
      Logger.debug('Optional ping monitor samples stack: $stack');
      return const [];
    }
  }

  Future<SpeedtestMonitorSettings> fetchSpeedtestMonitorSettings({
    BuildContext? context,
  }) async {
    final defaults = SpeedtestMonitorSettings(
      enabled: true,
      runDate: DateTime.now(),
      runHour: 3,
      runMinute: 15,
    );
    if (_reviewerModeEnabled) return defaults;

    try {
      final values = await _fetchOpenwallaUciValues(context: context);
      final speedtest = values is Map ? values['speedtest_monitor'] : null;
      if (speedtest is Map) {
        final enabled = speedtest['enabled']?.toString() != '0';
        final runHour =
            int.tryParse(speedtest['run_hour']?.toString() ?? '') ??
            defaults.runHour;
        final runMinute =
            int.tryParse(speedtest['run_minute']?.toString() ?? '') ??
            defaults.runMinute;
        final runDate = DateTime.tryParse(
          speedtest['run_date']?.toString() ?? '',
        );
        return SpeedtestMonitorSettings(
          enabled: enabled,
          runDate: runDate ?? defaults.runDate,
          runHour: runHour.clamp(0, 23),
          runMinute: runMinute.clamp(0, 59),
        );
      }
    } catch (e, stack) {
      Logger.warning('Failed to fetch speedtest monitor settings: $e');
      Logger.debug('Speedtest settings stack: $stack');
    }

    return defaults;
  }

  Future<void> saveSpeedtestMonitorSettings(
    SpeedtestMonitorSettings settings, {
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) return;

    final router = _routerService?.selectedRouter;
    final sysauth = _authService?.sysauth;
    if (router == null || sysauth == null || _apiService == null) {
      throw Exception('Router is not connected');
    }

    final runDate = settings.runDate;
    await _apiService!.uciSet(
      router.ipAddress,
      sysauth,
      router.useHttps,
      config: 'openwalla',
      section: 'speedtest_monitor',
      values: {
        'enabled': settings.enabled ? '1' : '0',
        'run_hour': settings.runHour.clamp(0, 23).toString(),
        'run_minute': settings.runMinute.clamp(0, 59).toString(),
        if (runDate != null)
          'run_date':
              '${runDate.year.toString().padLeft(4, '0')}-${runDate.month.toString().padLeft(2, '0')}-${runDate.day.toString().padLeft(2, '0')}',
      },
      context: context,
    );
    await _apiService!.uciCommit(
      router.ipAddress,
      sysauth,
      router.useHttps,
      config: 'openwalla',
    );
    await _apiService!.systemExec(
      router.ipAddress,
      sysauth,
      router.useHttps,
      command:
          r'MARKER="# OPENWALLA_SPEEDTEST_MONITOR"; CRON="/etc/crontabs/root"; TMP="/tmp/.openwalla_cron_app.$$"; HOUR="$(uci -q get openwalla.speedtest_monitor.run_hour 2>/dev/null || echo 3)"; MINUTE="$(uci -q get openwalla.speedtest_monitor.run_minute 2>/dev/null || echo 15)"; ENABLED="$(uci -q get openwalla.speedtest_monitor.enabled 2>/dev/null || echo 1)"; case "$HOUR" in ""|*[!0-9]*) HOUR=3 ;; esac; case "$MINUTE" in ""|*[!0-9]*) MINUTE=15 ;; esac; [ "$HOUR" -gt 23 ] && HOUR=3; [ "$MINUTE" -gt 59 ] && MINUTE=15; if [ -f "$CRON" ]; then grep -v "$MARKER" "$CRON" >"$TMP" 2>/dev/null || : >"$TMP"; else : >"$TMP"; fi; if [ "$ENABLED" = "1" ]; then echo "$MINUTE $HOUR * * * /usr/bin/openwalla-speedtest-monitor --once >/tmp/openwalla-speedtest-monitor.last.log 2>&1 $MARKER" >>"$TMP"; fi; mv "$TMP" "$CRON"; /etc/init.d/cron reload >/dev/null 2>&1 || /etc/init.d/cron restart >/dev/null 2>&1 || true',
    );
  }

  Future<MonthlyUsageSettings> fetchMonthlyUsageSettings({
    BuildContext? context,
  }) async {
    const defaults = MonthlyUsageSettings(
      monthStartDay: 1,
      interfaceName: 'br-lan',
    );
    if (_reviewerModeEnabled) return defaults;

    try {
      final values = await _fetchOpenwallaUciValues(context: context);
      final dashboard = values is Map ? values['dashboard'] : null;
      if (dashboard is Map) {
        final monthStartDay =
            int.tryParse(dashboard['month_start_day']?.toString() ?? '') ??
            defaults.monthStartDay;
        final interfaceName = dashboard['vnstat_interface']?.toString();
        return MonthlyUsageSettings(
          monthStartDay: monthStartDay.clamp(1, 31),
          interfaceName: interfaceName?.isNotEmpty == true
              ? interfaceName!
              : defaults.interfaceName,
        );
      }
    } catch (e, stack) {
      Logger.warning('Failed to fetch monthly usage settings: $e');
      Logger.debug('Monthly usage settings stack: $stack');
    }

    return defaults;
  }

  Future<void> saveMonthlyUsageSettings(
    MonthlyUsageSettings settings, {
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) return;

    final router = _routerService?.selectedRouter;
    final sysauth = _authService?.sysauth;
    if (router == null || sysauth == null || _apiService == null) {
      throw Exception('Router is not connected');
    }

    await _apiService!.uciSet(
      router.ipAddress,
      sysauth,
      router.useHttps,
      config: 'openwalla',
      section: 'dashboard',
      values: {
        'month_start_day': settings.monthStartDay.clamp(1, 31).toString(),
        'vnstat_interface': settings.interfaceName,
      },
      context: context,
    );
    await _apiService!.uciCommit(
      router.ipAddress,
      sysauth,
      router.useHttps,
      config: 'openwalla',
    );
  }

  List<String> dashboardInterfaceNames() {
    final interfaces =
        _dashboardData?['interfaceDump']?['interface'] as List<dynamic>?;
    final names = interfaces
        ?.whereType<Map<String, dynamic>>()
        .map((interface) => interface['interface']?.toString())
        .whereType<String>()
        .where((name) => name != 'loopback' && name != 'lo')
        .toSet()
        .toList();

    if (names == null || names.isEmpty) {
      return const ['br-lan', 'wan', 'eth0', 'eth1'];
    }
    names.sort();
    return names;
  }

  Map<String, dynamic>? _extractWanData(Map<String, dynamic>? interfaceDump) {
    if (interfaceDump == null || interfaceDump['interface'] == null) {
      return null;
    }
    try {
      for (var interface in interfaceDump['interface']) {
        if (interface['route'] is List) {
          for (var route in interface['route']) {
            if (route is Map &&
                route['target'] == '0.0.0.0' &&
                route['mask'] == 0) {
              return interface;
            }
          }
        }
      }
    } catch (e) {
      // print('WAN data extraction error: $e');
      return null;
    }
    return null;
  }

  String? _getDeviceNameForInterface(String interfaceName) {
    // Handle wireless format: "SSID (deviceName)"
    if (interfaceName.contains('(')) {
      final match = RegExp(r'\(([^)]+)\)').firstMatch(interfaceName);
      return match?.group(1);
    }

    // Map interface names to their actual device names from interface dump
    final interfaceDump =
        _dashboardData?['interfaceDump'] as Map<String, dynamic>?;
    if (interfaceDump != null && interfaceDump['interface'] is List) {
      for (final interface in interfaceDump['interface']) {
        if (interface is Map<String, dynamic>) {
          final ifname = interface['interface'] as String?;
          if (ifname == interfaceName) {
            // Return the device or l3_device field
            return (interface['device'] ?? interface['l3_device']) as String?;
          }
        }
      }
    }

    // If not found in interface dump, check if it's already a device name
    // (e.g., eth0, br-lan, wlan0)
    return interfaceName;
  }

  void _startThroughputTimer() {
    _throughputTimer?.cancel();
    // Don't start timer if we're rebooting
    if (_isRebooting) {
      return;
    }
    _throughputTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _updateThroughputOnly();
    });
  }

  void _startSystemInfoTimer() {
    _systemInfoTimer?.cancel();
    if (_isRebooting) {
      return;
    }
    _systemInfoTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateSystemInfoOnly();
    });
  }

  Future<void> _updateSystemInfoOnly() async {
    if (_isRebooting || _dashboardData == null) {
      return;
    }

    if (_reviewerModeEnabled) {
      try {
        final result = await _apiService!.callSimple('system', 'info', {});
        if (result is List && result.length > 1 && result[0] == 0) {
          _dashboardData = {
            ...?_dashboardData,
            'sysInfo': result[1],
            '_lastUpdated': DateTime.now().millisecondsSinceEpoch,
          };
          notifyListeners();
        }
      } catch (e) {
        Logger.debug('Reviewer system info refresh failed: $e');
      }
      return;
    }

    if (_routerService?.selectedRouter == null ||
        _authService?.sysauth == null) {
      return;
    }

    final ip = _routerService!.selectedRouter!.ipAddress;
    final useHttps = _routerService!.selectedRouter!.useHttps;

    try {
      final conntrackFuture = _fetchConntrackData(ip, useHttps);
      final result = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'system',
        method: 'info',
        params: {},
      );

      if (result is List && result.length > 1 && result[0] == 0) {
        final conntrackData = await conntrackFuture;
        _dashboardData = {
          ...?_dashboardData,
          'sysInfo': result[1],
          'conntrack': conntrackData,
          '_lastUpdated': DateTime.now().millisecondsSinceEpoch,
        };
        notifyListeners();
      }
    } catch (e) {
      Logger.debug('System info refresh failed: $e');
    }
  }

  /// Updates only throughput data without refetching the entire dashboard
  Future<void> _updateThroughputOnly() async {
    // Don't try to update throughput during reboot
    if (_isRebooting) {
      return;
    }

    if (_reviewerModeEnabled) {
      // For reviewer mode, get network devices data only
      try {
        final result = await _apiService!.callSimple('network', 'device', {});
        final networkData = result[1] as Map<String, dynamic>?;
        final wanDeviceNames = {'eth0'}; // Mock WAN device

        // Check if we should track specific interface
        final prefs = _dashboardPreferences;
        String? specificInterface;
        if (!prefs.showAllThroughput &&
            prefs.primaryThroughputInterface != null) {
          // Extract device name from interface ID (format: "SSID (deviceName)" or just "deviceName")
          final interfaceId = prefs.primaryThroughputInterface!;
          if (interfaceId.contains('(')) {
            // Wireless format: "SSID (deviceName)"
            final match = RegExp(r'\(([^)]+)\)').firstMatch(interfaceId);
            specificInterface = match?.group(1);
          } else {
            // Wired format: just device name
            specificInterface = interfaceId;
          }
        }

        _throughputService?.updateThroughput(
          networkData,
          wanDeviceNames,
          specificInterface: specificInterface,
        );
        notifyListeners();
      } catch (e) {
        // Don't log throughput update errors as they're non-critical
      }
      return;
    }

    if (_routerService?.selectedRouter == null ||
        _authService?.sysauth == null) {
      return;
    }

    final ip = _routerService!.selectedRouter!.ipAddress;
    final useHttps = _routerService!.selectedRouter!.useHttps;

    try {
      // Only fetch network devices for throughput calculation
      final result = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'luci-rpc',
        method: 'getNetworkDevices',
        params: {},
      );

      if (result is List && result.length > 1 && result[0] == 0) {
        final networkData = result[1] as Map<String, dynamic>?;

        // Get ALL device names from cached dashboard data (except loopback)
        final wanDeviceNames = <String>{};
        final interfaceDump =
            _dashboardData?['interfaceDump'] as Map<String, dynamic>?;
        if (interfaceDump != null && interfaceDump['interface'] is List) {
          for (final interface in interfaceDump['interface']) {
            if (interface is Map<String, dynamic>) {
              final ifname = interface['interface'] as String?;
              final device = interface['device'] as String?;
              final l3Device = interface['l3_device'] as String?;
              // Include all interfaces except loopback
              if (ifname != null && ifname != 'loopback' && ifname != 'lo') {
                if (device != null) wanDeviceNames.add(device);
                if (l3Device != null && l3Device != device) {
                  wanDeviceNames.add(l3Device);
                }
              }
            }
          }
        }

        // Check if we should track specific interface
        final prefs = _dashboardPreferences;
        String? specificInterface;
        if (!prefs.showAllThroughput &&
            prefs.primaryThroughputInterface != null) {
          // Extract device name from interface ID (format: "SSID (deviceName)" or just "deviceName")
          final interfaceId = prefs.primaryThroughputInterface!;
          if (interfaceId.contains('(')) {
            // Wireless format: "SSID (deviceName)"
            final match = RegExp(r'\(([^)]+)\)').firstMatch(interfaceId);
            specificInterface = match?.group(1);
          } else {
            // Wired format: just device name
            specificInterface = interfaceId;
          }
        }

        _throughputService?.updateThroughput(
          networkData,
          wanDeviceNames,
          specificInterface: specificInterface,
        );
        notifyListeners();
      }
    } catch (e) {
      // Don't log throughput update errors as they're non-critical
    }
  }

  void _cancelThroughputTimer() {
    _throughputTimer?.cancel();
    _systemInfoTimer?.cancel();
    _throughputService?.clear();
  }

  Future<bool> reboot({BuildContext? context}) async {
    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    // Cancel throughput timer before starting reboot to prevent "client closed" errors
    _cancelThroughputTimer();

    _isRebooting = true;
    notifyListeners();

    try {
      final result = await _apiService!.reboot(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        context: context,
      );
      // Wait 30 seconds before starting to poll for router availability
      // Some routers take longer to reboot
      Future.delayed(const Duration(seconds: 30), () {
        _pollRouterAvailability();
      });
      return result;
    } catch (e) {
      _isRebooting = false;
      notifyListeners();
      return false;
    }
  }

  void _pollRouterAvailability() {
    // Reset poll attempts
    _pollAttempts = 0;
    _pollingTimer?.cancel();

    // Start polling with exponential backoff
    _scheduleNextPoll();
  }

  void _scheduleNextPoll() {
    if (_pollAttempts >= _maxPollAttempts) {
      // Max attempts reached, stop polling
      _isRebooting = false;
      notifyListeners();
      // print('[Reboot] Timeout: Router did not come back online after $_maxPollAttempts attempts');

      // Show a user-friendly message
      if (onRouterBackOnline != null) {
        // Reuse the callback to show timeout message
        onRouterBackOnline!();
      }
      return;
    }

    // Calculate delay with exponential backoff: 3s, 3s, 5s, 8s, 12s, 18s, then 20s intervals
    int delaySeconds;
    if (_pollAttempts < 2) {
      delaySeconds = 3;
    } else if (_pollAttempts < 4) {
      delaySeconds = 5;
    } else if (_pollAttempts < 6) {
      delaySeconds = 8;
    } else if (_pollAttempts < 8) {
      delaySeconds = 12;
    } else if (_pollAttempts < 10) {
      delaySeconds = 18;
    } else {
      delaySeconds = 20; // Cap at 20 seconds for remaining attempts
    }

    _pollingTimer = Timer(Duration(seconds: delaySeconds), () async {
      _pollAttempts++;
      final available = await _pingRouter();

      if (available) {
        // Router is back online
        _pollingTimer?.cancel();
        _pollingTimer = null;
        _isRebooting = false;
        _pollAttempts = 0;
        notifyListeners();

        // Notify UI that router is back online
        if (onRouterBackOnline != null) {
          onRouterBackOnline!();
        }

        // Force relogin
        if (_routerService?.selectedRouter != null) {
          await login(
            _routerService!.selectedRouter!.ipAddress,
            _routerService!.selectedRouter!.username,
            _routerService!.selectedRouter!.password,
            _routerService!.selectedRouter!.useHttps,
          );
        }
      } else {
        // Schedule next poll
        _scheduleNextPoll();
      }
    });
  }

  Future<bool> _pingRouter() async {
    if (_authService?.ipAddress == null) return false;

    // Clear cached HTTP clients for this host to avoid stale connections
    if (_pollAttempts == 0) {
      _httpClientManager.disposeClient(
        _authService!.ipAddress!,
        _authService!.useHttps,
      );
    }

    // Try multiple endpoints in order
    final scheme = _authService!.useHttps ? 'https' : 'http';
    final endpoints = [
      '/', // Root
      '/cgi-bin/luci/', // LuCI login page
      '/cgi-bin/luci/admin', // Admin page
    ];

    for (final endpoint in endpoints) {
      try {
        final url = '$scheme://${_authService!.ipAddress}$endpoint';

        // Create a fresh Dio client for pinging to avoid certificate/connection issues
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
            sendTimeout: const Duration(seconds: 5),
            followRedirects: false,
            validateStatus: (code) => code != null && code >= 200 && code < 500,
          ),
        );

        if (_authService!.useHttps) {
          final adapter = IOHttpClientAdapter();
          adapter.createHttpClient = () {
            final httpClient = HttpClient();
            httpClient.connectionTimeout = const Duration(seconds: 5);
            // Accept any cert for ping only
            httpClient.badCertificateCallback = (cert, host, port) => true;
            return httpClient;
          };
          dio.httpClientAdapter = adapter;
        }

        // print('[Ping] Attempt $_pollAttempts: Checking $url');
        final response = await dio.get(url);
        // print('[Ping] Response from $endpoint: ${response.statusCode}');

        // Accept various status codes as "alive"
        final isAlive =
            response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 500;

        if (isAlive) {
          if (_pollAttempts > 5) {
            // If we've been polling for a while and get a response,
            // wait a bit more to ensure services are fully started
            await Future.delayed(const Duration(seconds: 5));
          }
          return true;
        }
      } catch (e) {
        // Try next endpoint
        if (endpoint == endpoints.last) {
          // print('[Ping] All endpoints failed on attempt $_pollAttempts');
          // print('[Ping] Last error: ${e.toString()}');

          if (e is SocketException) {
            // print('[Ping] Socket error: ${e.message}, OS Error: ${e.osError}');
          } else if (e is HandshakeException) {
            // print('[Ping] SSL handshake error - router may still be starting');
          }
        }
      }
    }

    return false;
  }

  Future<bool> checkRouterAvailability() async {
    if (_reviewerModeEnabled || _authService?.ipAddress == null) {
      return _reviewerModeEnabled;
    }
    return await _authService!.checkRouterAvailability(
      _authService!.ipAddress!,
      _authService!.useHttps,
    );
  }

  Future<bool> setWirelessRadioState(
    String device,
    bool enabled, {
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) {
      // Simulate operation for reviewer mode
      await Future.delayed(const Duration(milliseconds: 500));
      await fetchDashboardData();
      return true;
    }

    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    try {
      // 1. Set the disabled state
      await _apiService!.uciSet(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        section: device,
        values: {'disabled': enabled ? '0' : '1'},
        context: context,
      );

      // 2. Commit the changes
      await _apiService!.uciCommit(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        context: context?.mounted == true ? context : null,
      );

      // 3. Reload wifi to apply changes
      await _apiService!.systemExec(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        command: 'wifi reload',
        context: context?.mounted == true ? context : null,
      );

      // Refresh dashboard data to reflect the change
      await fetchDashboardData();

      return true;
    } catch (e) {
      _dashboardError = 'Failed to toggle Wi-Fi: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> tryAutoLogin({BuildContext? context}) async {
    if (_reviewerModeEnabled) {
      return await _authService!.tryAutoLogin(
        null,
        null,
        null,
        null,
        context: context,
      );
    }
    return await _authService?.tryAutoLogin(
          null,
          null,
          null,
          null,
          context: context,
        ) ??
        false;
  }

  /// Fetch all associated wireless MAC addresses from all wireless interfaces
  Future<Set<String>> fetchAllAssociatedWirelessMacs() async {
    if (_reviewerModeEnabled) {
      // Use the interface method for mock/reviewer mode
      final stationsMap = await _apiService!.fetchAssociatedStations();
      final macs = <String>{};
      stationsMap.forEach((_, stations) {
        macs.addAll(stations.map((m) => m.toLowerCase()));
      });
      return macs;
    } else {
      // Use the context-aware method for real API calls
      if (_routerService?.selectedRouter == null ||
          _authService?.sysauth == null) {
        return {};
      }

      final ip = _routerService!.selectedRouter!.ipAddress;
      final useHttps = _routerService!.selectedRouter!.useHttps;

      final stationsMap = await _apiService!
          .fetchAllAssociatedWirelessMacsWithContext(
            ipAddress: ip,
            sysauth: _authService!.sysauth!,
            useHttps: useHttps,
          );
      final macs = <String>{};
      stationsMap.forEach((_, stations) {
        macs.addAll(stations.map((m) => m.toLowerCase()));
      });
      return macs;
    }
  }

  @override
  void dispose() {
    _throughputTimer?.cancel();
    _systemInfoTimer?.cancel();
    _pollingTimer?.cancel();
    _pollAttempts = 0;
    _isRebooting = false;
    super.dispose();
  }

  /// Aggregates DHCP leases across all configured routers and classifies clients
  /// as wireless if their MAC appears in any router's associated stations list.
  Future<List<Client>> fetchAggregatedClients() async {
    try {
      // Build a union of wireless MACs across all routers
      final wirelessMacs = await fetchAllAssociatedWirelessMacsAggregated();
      final normalizedWireless = wirelessMacs
          .map((m) => m.toUpperCase().replaceAll('-', ':'))
          .toSet();

      // Aggregate leases across routers
      final leases = await fetchAggregatedDhcpLeases();

      // Convert to Client models with connection type
      final clients = <String, Client>{}; // key by normalized MAC
      for (final lease in leases) {
        final client = Client.fromLease(lease);
        final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
        final isWireless = normalizedWireless.contains(macNorm);
        // If confirmed wireless by assoclist, mark wireless; otherwise keep heuristic
        final enriched = isWireless
            ? client.copyWith(connectionType: ConnectionType.wireless)
            : client;
        // Prefer entries that have more info (hostname length as heuristic)
        if (!clients.containsKey(macNorm) ||
            (enriched.hostname.isNotEmpty &&
                enriched.hostname.length >
                    (clients[macNorm]?.hostname.length ?? 0))) {
          clients[macNorm] = enriched;
        }
      }

      // Add wireless stations not in DHCP leases (AP-mode fallback)
      for (final mac in normalizedWireless) {
        if (!clients.containsKey(mac)) {
          clients[mac] = Client.fromWirelessStation(mac);
        }
      }

      // Sort: wireless > wired > unknown, then by hostname
      final list = clients.values.toList();
      list.sort((a, b) {
        int typeOrder(ConnectionType t) {
          switch (t) {
            case ConnectionType.wireless:
              return 0;
            case ConnectionType.wired:
              return 1;
            default:
              return 2;
          }
        }

        final cmpType = typeOrder(
          a.connectionType,
        ).compareTo(typeOrder(b.connectionType));
        if (cmpType != 0) return cmpType;
        return a.hostname.toLowerCase().compareTo(b.hostname.toLowerCase());
      });
      return list;
    } catch (e, stack) {
      Logger.exception('Failed to aggregate clients', e, stack);
      return [];
    }
  }

  /// Returns clients for the currently selected router only
  Future<List<Client>> fetchClientsForSelectedRouter() async {
    try {
      if (_reviewerModeEnabled) {
        final stationsMap = await _apiService!.fetchAssociatedStations();
        final macs = <String>{};
        stationsMap.forEach((_, stations) {
          macs.addAll(stations.map((m) => m.toLowerCase()));
        });
        final result = await _apiService!.callSimple(
          'luci-rpc',
          'getDHCPLeases',
          {},
        );
        final leases = <Map<String, dynamic>>[];
        if (result is List && result.length > 1 && result[0] == 0) {
          final data = result[1] as Map<String, dynamic>;
          leases.addAll(
            (data['dhcp_leases'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>(),
          );
        }
        // Normalize wireless MACs for consistent lookup
        final normalizedMacs = macs
            .map((m) => m.toUpperCase().replaceAll('-', ':'))
            .toSet();
        final clientMap = <String, Client>{};
        for (final l in leases) {
          final c = Client.fromLease(l);
          final macNorm = c.macAddress.toUpperCase().replaceAll('-', ':');
          final isWireless = normalizedMacs.contains(macNorm);
          clientMap[macNorm] = isWireless
              ? c.copyWith(connectionType: ConnectionType.wireless)
              : c;
        }
        // Add wireless stations not in DHCP leases (AP-mode fallback)
        for (final mac in normalizedMacs) {
          if (!clientMap.containsKey(mac)) {
            clientMap[mac] = Client.fromWirelessStation(mac);
          }
        }
        final reviewerClients = clientMap.values.toList();
        reviewerClients.sort((a, b) {
          int typeOrder(ConnectionType t) {
            switch (t) {
              case ConnectionType.wireless:
                return 0;
              case ConnectionType.wired:
                return 1;
              default:
                return 2;
            }
          }

          final cmpType = typeOrder(
            a.connectionType,
          ).compareTo(typeOrder(b.connectionType));
          if (cmpType != 0) return cmpType;
          return a.hostname.toLowerCase().compareTo(b.hostname.toLowerCase());
        });
        return reviewerClients;
      }

      if (_routerService?.selectedRouter == null ||
          _authService?.sysauth == null) {
        return [];
      }
      final router = _routerService!.selectedRouter!;

      // Get wireless MACs for this router
      final stationsMap = await _apiService!
          .fetchAllAssociatedWirelessMacsWithContext(
            ipAddress: router.ipAddress,
            sysauth: _authService!.sysauth!,
            useHttps: router.useHttps,
          );
      final wireless = <String>{};
      stationsMap.forEach(
        (_, s) => wireless.addAll(s.map((m) => m.toLowerCase())),
      );

      // Get DHCP leases for this router
      final callRes = await _apiService!.call(
        router.ipAddress,
        _authService!.sysauth!,
        router.useHttps,
        object: 'luci-rpc',
        method: 'getDHCPLeases',
        params: {},
      );
      final leases = <Map<String, dynamic>>[];
      if (callRes is List && callRes.length > 1 && callRes[0] == 0) {
        final data = callRes[1] as Map<String, dynamic>;
        leases.addAll(
          (data['dhcp_leases'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>(),
        );
      }

      // Normalize wireless MACs for consistent lookup
      final normalizedWireless = wireless
          .map((m) => m.toUpperCase().replaceAll('-', ':'))
          .toSet();

      final clientMap = <String, Client>{};
      for (final l in leases) {
        final c = Client.fromLease(l);
        final macNorm = c.macAddress.toUpperCase().replaceAll('-', ':');
        final isWireless = normalizedWireless.contains(macNorm);
        clientMap[macNorm] = isWireless
            ? c.copyWith(connectionType: ConnectionType.wireless)
            : c;
      }

      // Add wireless stations not in DHCP leases (AP-mode fallback)
      for (final mac in normalizedWireless) {
        if (!clientMap.containsKey(mac)) {
          clientMap[mac] = Client.fromWirelessStation(mac);
        }
      }

      final clients = clientMap.values.toList();

      // Sort similar to aggregated
      clients.sort((a, b) {
        int typeOrder(ConnectionType t) {
          switch (t) {
            case ConnectionType.wireless:
              return 0;
            case ConnectionType.wired:
              return 1;
            default:
              return 2;
          }
        }

        final cmpType = typeOrder(
          a.connectionType,
        ).compareTo(typeOrder(b.connectionType));
        if (cmpType != 0) return cmpType;
        return a.hostname.toLowerCase().compareTo(b.hostname.toLowerCase());
      });
      return clients;
    } catch (e, stack) {
      Logger.exception('Failed to fetch clients for selected router', e, stack);
      return [];
    }
  }

  /// Returns a union set of associated wireless MAC addresses across all routers
  Future<Set<String>> fetchAllAssociatedWirelessMacsAggregated() async {
    try {
      if (_reviewerModeEnabled) {
        final stationsMap = await _apiService!.fetchAssociatedStations();
        final macs = <String>{};
        stationsMap.forEach((_, stations) {
          macs.addAll(stations.map((m) => m.toLowerCase()));
        });
        return macs;
      }

      final routers = _routerService?.routers ?? const <model.Router>[];
      if (routers.isEmpty) return {};

      final tasks = routers.map((r) async {
        try {
          if (_apiService is RealApiService) {
            final real = _apiService as RealApiService;
            final res = await real.loginWithProtocolDetection(
              r.ipAddress,
              r.username,
              r.password,
              r.useHttps,
            );
            if (res.token == null) return <String>{};
            final map = await _apiService!
                .fetchAllAssociatedWirelessMacsWithContext(
                  ipAddress: r.ipAddress,
                  sysauth: res.token!,
                  useHttps: res.actualUseHttps,
                );
            final set = <String>{};
            map.forEach((_, stations) {
              set.addAll(stations.map((m) => m.toLowerCase()));
            });
            return set;
          }
        } catch (e) {
          // Skip router on failure
        }
        return <String>{};
      }).toList();

      final results = await Future.wait(tasks);
      return results.fold<Set<String>>(<String>{}, (acc, s) => acc..addAll(s));
    } catch (e, stack) {
      Logger.exception('Failed to aggregate wireless MACs', e, stack);
      return {};
    }
  }

  /// Returns a combined list of DHCP lease maps from all routers
  Future<List<Map<String, dynamic>>> fetchAggregatedDhcpLeases() async {
    try {
      if (_reviewerModeEnabled) {
        // Use mock data
        final result = await _apiService!.callSimple(
          'luci-rpc',
          'getDHCPLeases',
          {},
        );
        if (result is List && result.length > 1 && result[0] == 0) {
          final data = result[1] as Map<String, dynamic>;
          final leases = (data['dhcp_leases'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          return leases;
        }
        return [];
      }

      final routers = _routerService?.routers ?? const <model.Router>[];
      if (routers.isEmpty) return [];

      final tasks = routers.map((r) async {
        try {
          if (_apiService is RealApiService) {
            final real = _apiService as RealApiService;
            final res = await real.loginWithProtocolDetection(
              r.ipAddress,
              r.username,
              r.password,
              r.useHttps,
            );
            if (res.token == null) return <Map<String, dynamic>>[];
            final callRes = await _apiService!.call(
              r.ipAddress,
              res.token!,
              res.actualUseHttps,
              object: 'luci-rpc',
              method: 'getDHCPLeases',
              params: {},
            );
            if (callRes is List && callRes.length > 1 && callRes[0] == 0) {
              final data = callRes[1] as Map<String, dynamic>;
              final leases = (data['dhcp_leases'] as List<dynamic>? ?? [])
                  .cast<Map<String, dynamic>>();
              return leases;
            }
          }
        } catch (e) {
          // Skip router on failure
        }
        return <Map<String, dynamic>>[];
      }).toList();

      final results = await Future.wait(tasks);
      // Deduplicate by MAC + IP
      final seen = <String, Map<String, dynamic>>{};
      for (final list in results) {
        for (final lease in list) {
          final mac = (lease['macaddr']?.toString() ?? '').toUpperCase();
          final ip = lease['ipaddr']?.toString() ?? '';
          final key = '$mac|$ip';
          if (!seen.containsKey(key)) {
            seen[key] = lease;
          }
        }
      }
      return seen.values.toList();
    } catch (e, stack) {
      Logger.exception('Failed to aggregate DHCP leases', e, stack);
      return [];
    }
  }
}
