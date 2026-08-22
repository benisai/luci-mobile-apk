import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

class SshCommandResult {
  final String output;
  final int? exitCode;

  const SshCommandResult({required this.output, required this.exitCode});
}

class SshService {
  Future<SshCommandResult> runCommand({
    required String host,
    required String username,
    required String password,
    required String command,
    int port = 22,
    Duration timeout = const Duration(seconds: 18),
    void Function(String chunk)? onOutput,
  }) async {
    final target = _parseTarget(host, port);
    SSHClient? client;

    final socket = await SSHSocket.connect(
      target.host,
      target.port,
      timeout: timeout,
    );
    client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
    );

    try {
      final session = await client.execute(command);
      final output = StringBuffer();

      void append(String chunk) {
        output.write(chunk);
        onOutput?.call(chunk);
      }

      final stdoutDone = utf8.decoder
          .bind(session.stdout)
          .listen(append)
          .asFuture<void>();
      final stderrDone = utf8.decoder
          .bind(session.stderr)
          .listen(append)
          .asFuture<void>();

      await Future.wait([stdoutDone, stderrDone], eagerError: true);
      await session.done;

      final exitCode = session.exitCode;
      if (exitCode != null && exitCode != 0) {
        append('\nExit code: $exitCode');
      }

      return SshCommandResult(output: output.toString(), exitCode: exitCode);
    } finally {
      unawaited(client.close());
      unawaited(client.done.catchError((_) {}));
    }
  }

  _SshTarget _parseTarget(String rawHost, int defaultPort) {
    var value = rawHost.trim();
    if (value.isEmpty) {
      throw ArgumentError('SSH host cannot be empty');
    }

    if (value.contains('://')) {
      final uri = Uri.parse(value);
      return _SshTarget(uri.host, defaultPort);
    }

    value = value.split('/').first;
    if (value.startsWith('[')) {
      final end = value.indexOf(']');
      if (end > 0) {
        final host = value.substring(1, end);
        final portText = value.substring(end + 1);
        final parsedPort = portText.startsWith(':')
            ? int.tryParse(portText.substring(1))
            : null;
        return _SshTarget(host, parsedPort ?? defaultPort);
      }
    }

    final colonCount = ':'.allMatches(value).length;
    if (colonCount == 1) {
      final parts = value.split(':');
      final parsedPort = int.tryParse(parts[1]);
      if (parsedPort != null) {
        return _SshTarget(parts[0], parsedPort);
      }
    }

    return _SshTarget(value, defaultPort);
  }
}

class _SshTarget {
  final String host;
  final int port;

  const _SshTarget(this.host, this.port);
}
