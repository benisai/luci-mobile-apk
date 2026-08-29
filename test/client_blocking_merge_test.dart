import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/state/app_state.dart';

void main() {
  group('Client blocking and device DB merging', () {
    test('blocking a device preserves hostname, IP and wireless connection type', () {
      final lease = {
        'macaddr': 'AA:BB:CC:11:22:33',
        'ipaddr': '192.168.1.150',
        'hostname': 'My-MacBook-Pro',
        'vendor': 'Apple',
      };

      final client = Client.fromLease(lease).copyWith(
        connectionType: ConnectionType.wireless,
      );

      // Simulate device record created after blocking (where hostname was empty or default)
      final deviceRecords = (
        <String, OpenwallaDeviceRecord>{
          'AA:BB:CC:11:22:33': const OpenwallaDeviceRecord(
            mac: 'AA:BB:CC:11:22:33',
            ip: '',
            hostname: '',
            totalUploadBytes: 0,
            totalDownloadBytes: 0,
            staticIpAddress: '',
            quarantined: true,
            status: 'blocked',
          ),
        },
        <String, OpenwallaDeviceRecord>{},
      );

      // Enrich client with DB record
      final byMac = deviceRecords.$1;
      final record = byMac[client.macAddress];
      expect(record, isNotNull);

      final hasCustomHostname = record!.hostname.isNotEmpty &&
          record.hostname != '*' &&
          record.hostname.toLowerCase() != 'unknown';

      final enriched = client.copyWith(
        hostname: hasCustomHostname
            ? record.hostname
            : (client.hostname.isNotEmpty ? client.hostname : 'Unknown'),
        isBlocked: record.quarantined || record.status == 'blocked',
        status: record.quarantined ? 'blocked' : record.status,
      );

      expect(enriched.hostname, 'My-MacBook-Pro');
      expect(enriched.ipAddress, '192.168.1.150');
      expect(enriched.connectionType, ConnectionType.wireless);
      expect(enriched.isBlocked, isTrue);
      expect(enriched.status, 'blocked');
    });

    test('device DB record with "Unknown" does not overwrite valid DHCP hostname', () {
      final lease = {
        'macaddr': 'AA:BB:CC:44:55:66',
        'ipaddr': '192.168.1.151',
        'hostname': 'Smart-TV',
      };

      final client = Client.fromLease(lease);

      final deviceRecords = (
        <String, OpenwallaDeviceRecord>{
          'AA:BB:CC:44:55:66': const OpenwallaDeviceRecord(
            mac: 'AA:BB:CC:44:55:66',
            ip: '192.168.1.151',
            hostname: 'Unknown',
            totalUploadBytes: 0,
            totalDownloadBytes: 0,
            staticIpAddress: '',
            quarantined: true,
            status: 'blocked',
          ),
        },
        <String, OpenwallaDeviceRecord>{},
      );

      final record = deviceRecords.$1[client.macAddress]!;
      final hasCustomHostname = record.hostname.isNotEmpty &&
          record.hostname != '*' &&
          record.hostname.toLowerCase() != 'unknown';

      final enriched = client.copyWith(
        hostname: hasCustomHostname
            ? record.hostname
            : (client.hostname.isNotEmpty ? client.hostname : 'Unknown'),
        isBlocked: record.quarantined || record.status == 'blocked',
      );

      expect(enriched.hostname, 'Smart-TV');
      expect(enriched.isBlocked, isTrue);
    });

    test('device DB record with valid custom name DOES override DHCP hostname', () {
      final lease = {
        'macaddr': 'AA:BB:CC:77:88:99',
        'ipaddr': '192.168.1.152',
        'hostname': 'android-dhcp-default',
      };

      final client = Client.fromLease(lease);

      final deviceRecords = (
        <String, OpenwallaDeviceRecord>{
          'AA:BB:CC:77:88:99': const OpenwallaDeviceRecord(
            mac: 'AA:BB:CC:77:88:99',
            ip: '192.168.1.152',
            hostname: 'Living Room Tablet',
            totalUploadBytes: 1000,
            totalDownloadBytes: 2000,
            staticIpAddress: '192.168.1.152',
            quarantined: false,
            status: 'online',
          ),
        },
        <String, OpenwallaDeviceRecord>{},
      );

      final record = deviceRecords.$1[client.macAddress]!;
      final hasCustomHostname = record.hostname.isNotEmpty &&
          record.hostname != '*' &&
          record.hostname.toLowerCase() != 'unknown';

      final enriched = client.copyWith(
        hostname: hasCustomHostname
            ? record.hostname
            : (client.hostname.isNotEmpty ? client.hostname : 'Unknown'),
      );

      expect(enriched.hostname, 'Living Room Tablet');
    });
  });
}
