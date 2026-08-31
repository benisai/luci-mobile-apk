import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Router fallback address', () {
    test('activeAddress returns primary when index is 0', () {
      final router = model.Router(
        id: 'test-root',
        ipAddress: '192.168.8.1',
        username: 'root',
        password: 'pass',
        useHttps: false,
        alternateAddress: 'router.tail.ts.net',
        alternateUseHttps: true,
        activeAddressIndex: 0,
      );

      expect(router.activeAddress, '192.168.8.1');
      expect(router.activeUseHttps, false);
      expect(router.inactiveAddress, 'router.tail.ts.net');
      expect(router.inactiveUseHttps, true);
    });

    test('activeAddress returns alternate when index is 1', () {
      final router = model.Router(
        id: 'test-root',
        ipAddress: '192.168.8.1',
        username: 'root',
        password: 'pass',
        useHttps: false,
        alternateAddress: 'router.tail.ts.net',
        alternateUseHttps: true,
        activeAddressIndex: 1,
      );

      expect(router.activeAddress, 'router.tail.ts.net');
      expect(router.activeUseHttps, true);
      expect(router.inactiveAddress, '192.168.8.1');
      expect(router.inactiveUseHttps, false);
    });

    test('copyWith can clear fallback data', () {
      final router = model.Router(
        id: 'test-root',
        ipAddress: '192.168.8.1',
        username: 'root',
        password: 'pass',
        useHttps: false,
        alternateAddress: 'router.tail.ts.net',
        alternateUseHttps: true,
        activeAddressIndex: 1,
      );

      final updated = router.copyWith(clearAlternate: true);

      expect(updated.alternateAddress, isNull);
      expect(updated.alternateUseHttps, isNull);
      expect(updated.activeAddressIndex, 0);
      expect(updated.activeAddress, '192.168.8.1');
    });

    test(
      'auth does not assume HTTP when fallback protocol is missing',
      () async {
        final api = _FailingLoginApi();
        final result = await RealAuthService(api).loginWithFallback(
          activeAddress: 'primary',
          activeHttps: true,
          activeIndex: 0,
          fallbackAddress: 'fallback',
          username: 'root',
          password: 'pass',
        );

        expect(result.success, isFalse);
        expect(api.addresses, ['primary']);
      },
    );
  });
}

class _FailingLoginApi extends RealApiService {
  final addresses = <String>[];

  @override
  Future<LoginResult> loginWithProtocolDetection(
    String ipAddress,
    String username,
    String password,
    bool initialUseHttps, {
    BuildContext? context,
  }) async {
    addresses.add(ipAddress);
    return LoginResult(token: null, actualUseHttps: initialUseHttps);
  }
}
