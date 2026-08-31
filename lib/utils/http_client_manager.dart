import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'logger.dart';

String _certificateFingerprint(X509Certificate cert) {
  return sha256.convert(cert.der).toString();
}

String _normalizePinHost(String host) {
  return host.startsWith('[') && host.endsWith(']')
      ? host.substring(1, host.length - 1)
      : host;
}

(String, int)? _parsePinKey(String key) {
  if (key.startsWith('[')) {
    final close = key.indexOf(']');
    if (close == -1 || close + 2 > key.length) return null;
    final port = int.tryParse(key.substring(close + 2));
    if (port == null) return null;
    return (_normalizePinHost(key.substring(1, close)), port);
  }

  final match = RegExp(r'^(.+):(\d+)$').firstMatch(key);
  if (match == null) return null;
  return (_normalizePinHost(match.group(1)!), int.parse(match.group(2)!));
}

String _pinKey(String host, int port) => '[${_normalizePinHost(host)}]:$port';

/// HTTP client manager with cached Dio clients and certificate pinning.
class HttpClientManager {
  static final HttpClientManager _instance = HttpClientManager._internal();
  factory HttpClientManager() => _instance;

  HttpClientManager._internal() {
    _pinsLoaded = _serializePinMutation(_loadAcceptedCertificates);
  }

  final Map<String, Dio> _clients = {};
  final Map<String, String> _acceptedCertFingerprints = {};
  static const String _acceptedCertsKey = 'accepted_certificates';

  bool _pinsMutated = false;
  late final Future<void> _pinsLoaded;
  Future<void> _pinMutationQueue = Future<void>.value();
  int _pinGeneration = 0;

  Future<T> _serializePinMutation<T>(Future<T> Function() action) {
    final op = _pinMutationQueue.then((_) => action());
    _pinMutationQueue = op.then((_) {}, onError: (_) {});
    return op;
  }

  Dio getClient(String hostWithPort, bool useHttps, {BuildContext? context}) {
    final key = '$hostWithPort-$useHttps';
    final existing = _clients[key];
    if (existing != null) return existing;

    final client = _createSecureClient(useHttps);
    _clients[key] = client;
    return client;
  }

  String _extractHostname(String hostWithPort) {
    if (hostWithPort.startsWith('[')) {
      final endBracket = hostWithPort.indexOf(']');
      if (endBracket != -1) {
        return hostWithPort.substring(0, endBracket + 1);
      }
    }
    if (':'.allMatches(hostWithPort).length > 1) {
      return hostWithPort;
    }
    final colonIndex = hostWithPort.lastIndexOf(':');
    if (colonIndex != -1) {
      final portPart = hostWithPort.substring(colonIndex + 1);
      if (portPart.isNotEmpty && int.tryParse(portPart) != null) {
        return hostWithPort.substring(0, colonIndex);
      }
    }
    return hostWithPort;
  }

  int _effectivePort(String hostWithPort, bool useHttps) {
    if (hostWithPort.startsWith('[')) {
      final endBracket = hostWithPort.indexOf(']');
      if (endBracket != -1 && endBracket + 1 < hostWithPort.length) {
        return int.tryParse(hostWithPort.substring(endBracket + 2)) ??
            (useHttps ? 443 : 80);
      }
    }
    if (':'.allMatches(hostWithPort).length == 1) {
      final port = int.tryParse(
        hostWithPort.substring(hostWithPort.lastIndexOf(':') + 1),
      );
      if (port != null) return port;
    }
    return useHttps ? 443 : 80;
  }

  (String, bool) _parseClientKey(String key) {
    final separator = key.lastIndexOf('-');
    if (separator == -1) return (key, false);
    final flag = key.substring(separator + 1);
    if (flag != 'true' && flag != 'false') return (key, false);
    return (key.substring(0, separator), flag == 'true');
  }

  bool _keyMatchesHost(String key, String host, bool useHttps) {
    final (keyHost, keyUseHttps) = _parseClientKey(key);
    if (keyUseHttps != useHttps) return false;
    return _normalizePinHost(_extractHostname(keyHost)) ==
            _normalizePinHost(_extractHostname(host)) &&
        _effectivePort(keyHost, keyUseHttps) == _effectivePort(host, useHttps);
  }

  void _closeAndRemoveClients(bool Function(String key) matches) {
    final keysToRemove = _clients.keys.where(matches).toList();
    for (final key in keysToRemove) {
      final dio = _clients.remove(key);
      final adapter = dio?.httpClientAdapter;
      if (adapter is IOHttpClientAdapter) {
        adapter.close(force: true);
      }
    }
  }

  Dio _createSecureClient(bool useHttps) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        followRedirects: true,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) {
          Logger.error(
            'HTTP ${e.requestOptions.method} ${e.requestOptions.uri} failed',
            e,
            e.stackTrace,
          );
          handler.next(e);
        },
      ),
    );

    if (useHttps) {
      final adapter = IOHttpClientAdapter();
      adapter.createHttpClient = () {
        final httpClient = HttpClient();
        httpClient.connectionTimeout = const Duration(seconds: 10);
        httpClient.badCertificateCallback = (cert, certHost, port) {
          final expected = _acceptedCertFingerprints[_pinKey(certHost, port)];
          return expected != null && expected == _certificateFingerprint(cert);
        };
        return httpClient;
      };
      dio.httpClientAdapter = adapter;
    }

    return dio;
  }

  Future<void> _loadAcceptedCertificates() async {
    try {
      final storage = const FlutterSecureStorage();
      final certsJson = await storage.read(key: _acceptedCertsKey);
      if (_pinsMutated || certsJson == null) return;

      final certs = Map<String, dynamic>.from(jsonDecode(certsJson));
      var migrated = false;
      for (final entry in certs.entries) {
        final value = entry.value;
        if (value is! String || value.isEmpty) continue;
        final parsed = _parsePinKey(entry.key);
        if (parsed == null) continue;
        final canonical = _pinKey(parsed.$1, parsed.$2);
        if (_pinsMutated) return;
        _acceptedCertFingerprints.putIfAbsent(canonical, () => value);
        if (canonical != entry.key) migrated = true;
      }

      if (migrated && !_pinsMutated) await _saveAcceptedCertificates();
    } catch (e) {
      Logger.warning('Failed to load accepted certificates: $e');
    }
  }

  Future<void> _saveAcceptedCertificates() async {
    try {
      final storage = const FlutterSecureStorage();
      await storage.write(
        key: _acceptedCertsKey,
        value: jsonEncode(_acceptedCertFingerprints),
      );
    } catch (e) {
      Logger.warning('Failed to save accepted certificates: $e');
    }
  }

  void disposeClient(String host, bool useHttps) {
    _closeAndRemoveClients((key) => _keyMatchesHost(key, host, useHttps));
  }

  void disposeAll() {
    _closeAndRemoveClients((_) => true);
  }

  Future<void> clearAcceptedCertificates() {
    return _serializePinMutation(() async {
      _pinsMutated = true;
      _pinGeneration++;
      _acceptedCertFingerprints.clear();
      _closeAndRemoveClients((_) => true);

      try {
        final storage = const FlutterSecureStorage();
        await storage.delete(key: _acceptedCertsKey);
      } catch (e) {
        Logger.warning('Failed to delete accepted certificates: $e');
      }
    });
  }

  Future<void> clearCertificatesForHost(String host) {
    return _serializePinMutation(() async {
      _pinsMutated = true;
      _pinGeneration++;
      final hostname = _normalizePinHost(_extractHostname(host));
      _acceptedCertFingerprints.removeWhere((key, value) {
        final parsed = _parsePinKey(key);
        return parsed != null && _normalizePinHost(parsed.$1) == hostname;
      });
      _closeAndRemoveClients(
        (key) =>
            _normalizePinHost(_extractHostname(_parseClientKey(key).$1)) ==
            hostname,
      );
      await _saveAcceptedCertificates();
    });
  }

  Future<bool> promptForCertificateAcceptance({
    required BuildContext context,
    required String hostWithPort,
    required bool useHttps,
  }) async {
    if (!useHttps) return true;
    if (!context.mounted) return false;
    await _pinsLoaded;

    final host = _extractHostname(hostWithPort);
    final port = _effectivePort(hostWithPort, useHttps);
    X509Certificate? presentedCert;
    final testClient = HttpClient();
    testClient.connectionTimeout = const Duration(seconds: 5);
    testClient.badCertificateCallback = (cert, certHost, certPort) {
      presentedCert ??= cert;
      return true;
    };

    try {
      final uri = Uri(
        scheme: 'https',
        host: _normalizePinHost(host),
        port: port == 443 ? null : port,
      );
      final request = await testClient.getUrl(uri);
      request.followRedirects = false;
      await request.close();

      if (presentedCert == null) return true;

      final certKey = _pinKey(host, port);
      final fingerprint = _certificateFingerprint(presentedCert!);
      if (_acceptedCertFingerprints[certKey] == fingerprint) return true;

      if (!context.mounted) return false;
      final generation = _pinGeneration;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(dialogContext).colorScheme.error,
            size: 32,
          ),
          title: const Text('Certificate Warning'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The certificate for $host is not trusted by your device. Only proceed if you trust this router.',
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      dialogContext,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        dialogContext,
                      ).colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Certificate Details',
                        style: Theme.of(dialogContext).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildCertDetail('Subject', presentedCert!.subject),
                      _buildCertDetail('Issuer', presentedCert!.issuer),
                      _buildCertDetail(
                        'Valid From',
                        presentedCert!.startValidity.toLocal().toString().split(
                          '.',
                        )[0],
                      ),
                      _buildCertDetail(
                        'Valid Until',
                        presentedCert!.endValidity.toLocal().toString().split(
                          '.',
                        )[0],
                      ),
                      _buildCertDetail('SHA-256', fingerprint),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              child: const Text('Accept Risk'),
            ),
          ],
        ),
      );

      if (accepted == true) {
        if (generation != _pinGeneration) {
          Logger.info('Certificate acceptance discarded after pin reset');
          return false;
        }
        await _serializePinMutation(() async {
          _pinsMutated = true;
          _pinGeneration++;
          _acceptedCertFingerprints[certKey] = fingerprint;
          await _saveAcceptedCertificates();
        });
        return true;
      }
    } catch (e) {
      if (e is! HandshakeException) {
        Logger.warning('Certificate probe failed: $e');
      }
    } finally {
      testClient.close();
    }

    return false;
  }

  Widget _buildCertDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
