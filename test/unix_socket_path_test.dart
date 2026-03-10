import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unixconn/unixconn.dart';

void main() {
  test('createSandboxedUnixSocketPath uses the provided directory', () {
    final String socketPath = createSandboxedUnixSocketPath(
      prefix: 'proxy',
      directory: Directory('/sandbox/tmp'),
    );

    expect(socketPath.startsWith('/sandbox/tmp/'), isTrue);
    expect(socketPath, contains('/proxy_'));
  });

  test('createSandboxedUnixSocketPath shortens Darwin temp paths', () {
    final String socketPath = createSandboxedUnixSocketPath(
      prefix: 'proxy',
      directory: Directory(
        '/private/var/mobile/Containers/Data/Application/12345678-1234-1234-1234-123456789ABC/tmp',
      ),
    );

    expect(socketPath.startsWith('/var/mobile/Containers/Data/Application/'),
        isTrue);
    expect(socketPath.length, lessThanOrEqualTo(103));
  });

  test('createSandboxedUnixSocketPath keeps the path within Darwin limits', () {
    final String socketPath = createSandboxedUnixSocketPath(
      prefix: 'very_long_prefix_that_should_be_trimmed_when_needed',
      directory: Directory(
          '/var/mobile/Containers/Data/Application/12345678-1234-1234-1234-123456789ABC/tmp'),
    );

    expect(socketPath.length, lessThanOrEqualTo(103));
    expect(socketPath.split('/').last.length, lessThanOrEqualTo(22));
  });

  test('createSandboxedUnixSocketPath falls back to a short relative filename',
      () async {
    final String originalCurrentDirectory = Directory.current.path;
    final Directory baseDir =
        await Directory.systemTemp.createTemp('unixconn_socket_path_');
    final Directory longDir = Directory(
      '${baseDir.path}/${'a' * 24}/${'b' * 24}/${'c' * 24}',
    );
    await longDir.create(recursive: true);

    try {
      final String socketPath = createSandboxedUnixSocketPath(
        prefix: 'very_long_prefix_that_will_not_fit',
        directory: longDir,
      );

      expect(socketPath.length, lessThanOrEqualTo(_darwinSocketPathLimit));
      expect(socketPath.startsWith('/'), isFalse);
      expect(socketPath.contains('/'), isFalse);
      expect(
        _normalizeCurrentPathForComparison(Directory.current.path),
        _normalizeCurrentPathForComparison(longDir.path),
      );
    } finally {
      Directory.current = originalCurrentDirectory;
      await baseDir.delete(recursive: true);
    }
  });

  test('createSandboxedUnixSocketPath rejects invalid prefixes', () {
    expect(
      () => createSandboxedUnixSocketPath(prefix: '***'),
      throwsArgumentError,
    );
  });
}

const int _darwinSocketPathLimit = 103;

String _normalizeCurrentPathForComparison(String value) {
  if (value.startsWith('/private/var/')) {
    return value.substring('/private'.length);
  }
  return value;
}
