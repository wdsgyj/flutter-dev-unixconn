import 'dart:convert';
import 'dart:io';

const int _darwinSockaddrUnPathLimit = 103;
int _nextSocketSequence =
    DateTime.now().microsecondsSinceEpoch.remainder(0x100000);

/// Creates a unix socket path inside a process-accessible temp directory.
///
/// Using [Directory.systemTemp] keeps the socket under the app sandbox on iOS.
/// On Darwin, `/private/var/...` is normalized to `/var/...` to stay within
/// `sockaddr_un.sun_path` limits. When the absolute temp path is still too
/// long, the process current directory is switched to that temp directory and a
/// short relative socket name is returned instead.
String createSandboxedUnixSocketPath({
  String prefix = 'unixconn',
  Directory? directory,
}) {
  final Directory resolvedDirectory = directory ?? Directory.systemTemp;
  final String directoryPath =
      _normalizeDarwinSocketDirectoryPath(resolvedDirectory.path);
  final String safePrefix = _sanitizePrefix(prefix);
  final String token = _nextSocketToken();
  final String absoluteName = _buildSocketName(
    prefix: safePrefix,
    token: token,
    maxLength: _availableSocketNameLength(directoryPath),
  );
  final String absolutePath = '$directoryPath/$absoluteName';
  if (_fitsDarwinUnixSocketPath(absolutePath)) {
    return absolutePath;
  }

  _switchCurrentDirectoryForRelativeSocket(resolvedDirectory);
  return _buildSocketName(
    prefix: safePrefix,
    token: token,
    maxLength: _darwinSockaddrUnPathLimit,
  );
}

String _sanitizePrefix(String value) {
  final String normalized =
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_').replaceAll(
            RegExp(r'_+'),
            '_',
          );
  final String trimmed = normalized.replaceAll(RegExp(r'^_+|_+$'), '');
  if (trimmed.isEmpty) {
    throw ArgumentError.value(
      value,
      'prefix',
      'The socket path prefix must contain at least one valid character.',
    );
  }
  return trimmed;
}

String _normalizeDarwinSocketDirectoryPath(String value) {
  final String normalized = value.endsWith('/') && value.length > 1
      ? value.substring(0, value.length - 1)
      : value;
  if (normalized.startsWith('/private/var/')) {
    return normalized.substring('/private'.length);
  }
  return normalized;
}

int _availableSocketNameLength(String directoryPath) {
  return _darwinSockaddrUnPathLimit - utf8.encode(directoryPath).length - 1;
}

String _buildSocketName({
  required String prefix,
  required String token,
  required int maxLength,
}) {
  if (maxLength <= 0) {
    return token;
  }
  if (maxLength <= token.length) {
    return token.substring(0, maxLength);
  }

  final int maxPrefixLength = maxLength - token.length - 1;
  if (maxPrefixLength <= 0) {
    return token;
  }

  final String trimmedPrefix = prefix.length > maxPrefixLength
      ? prefix.substring(0, maxPrefixLength)
      : prefix;
  return '${trimmedPrefix}_$token';
}

bool _fitsDarwinUnixSocketPath(String value) {
  return utf8.encode(value).length <= _darwinSockaddrUnPathLimit;
}

void _switchCurrentDirectoryForRelativeSocket(Directory directory) {
  if (Directory.current.path == directory.path) {
    return;
  }
  Directory.current = directory.path;
}

String _nextSocketToken() {
  final int current = _nextSocketSequence;
  _nextSocketSequence = (_nextSocketSequence + 1) & 0xFFFFF;
  final String pidToken = (pid & 0xFFF).toRadixString(36);
  final String sequenceToken = current.toRadixString(36).padLeft(4, '0');
  return 'u$pidToken$sequenceToken';
}
