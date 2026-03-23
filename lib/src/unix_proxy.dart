import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'native_bindings.dart';
import 'unix_socket_connector.dart';

typedef UnixProxyTraceCallback = void Function(UnixProxyTraceEvent event);

final class UnixProxyTraceEvent {
  UnixProxyTraceEvent._({
    required this.rawData,
    required this.requestId,
    required this.method,
    required this.url,
    required this.startedAt,
    required this.finishedAt,
    required this.totalDuration,
    required this.reusedConn,
    this.dnsDuration,
    this.connectDuration,
    this.remoteIp,
    this.tlsDuration,
    this.tls,
    this.requestSentAt,
    this.requestBytes,
    this.firstResponseByteAt,
    this.responseBytes,
    this.statusCode,
    this.errorPhase,
    this.error,
  });

  factory UnixProxyTraceEvent.fromJson(String encoded) {
    final Object? decoded = jsonDecode(encoded);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException(
          'Expected the native trace payload to be a JSON object.');
    }
    final Map<String, Object?> data = decoded.map<String, Object?>(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );

    return UnixProxyTraceEvent._(
      rawData: Map<String, Object?>.unmodifiable(data),
      requestId: _readRequiredInt(data, 'requestId'),
      method: _readRequiredString(data, 'method'),
      url: _readRequiredString(data, 'url'),
      startedAt: _readRequiredDateTime(data, 'startedAt'),
      finishedAt: _readRequiredDateTime(data, 'finishedAt'),
      totalDuration:
          _durationFromMicros(_readRequiredInt(data, 'totalDurationMicros')),
      reusedConn: _readRequiredBool(data, 'reusedConn'),
      dnsDuration: _readOptionalDuration(data, 'dnsDurationMicros'),
      connectDuration: _readOptionalDuration(data, 'connectDurationMicros'),
      remoteIp: _readOptionalString(data, 'remoteIp'),
      tlsDuration: _readOptionalDuration(data, 'tlsDurationMicros'),
      tls: _readOptionalObject(data, 'tls', UnixProxyTlsInfo.fromMap),
      requestSentAt: _readOptionalDateTime(data, 'requestSentAt'),
      requestBytes: _readOptionalInt(data, 'requestBytes'),
      firstResponseByteAt: _readOptionalDateTime(data, 'firstResponseByteAt'),
      responseBytes: _readOptionalInt(data, 'responseBytes'),
      statusCode: _readOptionalInt(data, 'statusCode'),
      errorPhase: _readOptionalString(data, 'errorPhase'),
      error: _readOptionalString(data, 'error'),
    );
  }

  final Map<String, Object?> rawData;

  /// Stable per-request identifier emitted by the native Go proxy.
  ///
  /// Use this as the upper-layer key for deduplication or aggregation.
  final int requestId;
  final String method;
  final String url;
  final DateTime startedAt;
  final DateTime finishedAt;
  final Duration totalDuration;
  final bool reusedConn;
  final Duration? dnsDuration;
  final Duration? connectDuration;
  final String? remoteIp;
  final Duration? tlsDuration;
  final UnixProxyTlsInfo? tls;
  final DateTime? requestSentAt;
  final int? requestBytes;
  final DateTime? firstResponseByteAt;
  final int? responseBytes;
  final int? statusCode;
  final String? errorPhase;
  final String? error;
}

final class UnixProxyTlsInfo {
  UnixProxyTlsInfo._({
    required this.version,
    required this.versionName,
    required this.cipherSuite,
    required this.cipherSuiteName,
    required this.serverName,
    required this.negotiatedProtocol,
    required this.negotiatedProtocolIsMutual,
    required this.didResume,
    required this.handshakeComplete,
    required this.peerCertificates,
  });

  factory UnixProxyTlsInfo.fromMap(Map<String, Object?> data) {
    return UnixProxyTlsInfo._(
      version: _readRequiredInt(data, 'version'),
      versionName: _readRequiredString(data, 'versionName'),
      cipherSuite: _readRequiredInt(data, 'cipherSuite'),
      cipherSuiteName: _readRequiredString(data, 'cipherSuiteName'),
      serverName: _readRequiredString(data, 'serverName'),
      negotiatedProtocol: _readRequiredString(data, 'negotiatedProtocol'),
      negotiatedProtocolIsMutual:
          _readRequiredBool(data, 'negotiatedProtocolIsMutual'),
      didResume: _readRequiredBool(data, 'didResume'),
      handshakeComplete: _readRequiredBool(data, 'handshakeComplete'),
      peerCertificates: _readObjectList(
        data,
        'peerCertificates',
        UnixProxyPeerCertificateInfo.fromMap,
      ),
    );
  }

  final int version;
  final String versionName;
  final int cipherSuite;
  final String cipherSuiteName;
  final String serverName;
  final String negotiatedProtocol;
  final bool negotiatedProtocolIsMutual;
  final bool didResume;
  final bool handshakeComplete;
  final List<UnixProxyPeerCertificateInfo> peerCertificates;
}

final class UnixProxyPeerCertificateInfo {
  UnixProxyPeerCertificateInfo._({
    required this.subject,
    required this.issuer,
    required this.serialNumber,
    required this.dnsNames,
    required this.emailAddresses,
    required this.ipAddresses,
    required this.uris,
    required this.notBefore,
    required this.notAfter,
    required this.sha256Fingerprint,
  });

  factory UnixProxyPeerCertificateInfo.fromMap(Map<String, Object?> data) {
    return UnixProxyPeerCertificateInfo._(
      subject: _readRequiredString(data, 'subject'),
      issuer: _readRequiredString(data, 'issuer'),
      serialNumber: _readRequiredString(data, 'serialNumber'),
      dnsNames: _readStringList(data, 'dnsNames'),
      emailAddresses: _readStringList(data, 'emailAddresses'),
      ipAddresses: _readStringList(data, 'ipAddresses'),
      uris: _readStringList(data, 'uris'),
      notBefore: _readRequiredDateTime(data, 'notBefore'),
      notAfter: _readRequiredDateTime(data, 'notAfter'),
      sha256Fingerprint: _readRequiredString(data, 'sha256Fingerprint'),
    );
  }

  final String subject;
  final String issuer;
  final String serialNumber;
  final List<String> dnsNames;
  final List<String> emailAddresses;
  final List<String> ipAddresses;
  final List<String> uris;
  final DateTime notBefore;
  final DateTime notAfter;
  final String sha256Fingerprint;
}

final class UnixProxy {
  UnixProxy._(
    this.handle,
    this.socketPath,
    this._binding, {
    ReceivePort? tracePort,
    StreamSubscription<dynamic>? traceSubscription,
  })  : _tracePort = tracePort,
        _traceSubscription = traceSubscription;

  final int handle;
  final String socketPath;
  final UnixconnBinding _binding;
  final ReceivePort? _tracePort;
  final StreamSubscription<dynamic>? _traceSubscription;

  bool _closed = false;

  static Future<UnixProxy> start({
    required String socketPath,
    Duration? clientTimeout,
    Duration readyTimeout = const Duration(seconds: 5),
    UnixProxyTraceCallback? onTrace,
    UnixconnBinding? binding,
    UnixSocketConnector? readinessConnector,
  }) async {
    final UnixconnBinding resolvedBinding;
    if (binding == null) {
      await UnixconnBindings.ensureInitialized();
      resolvedBinding = UnixconnBindings.instance;
    } else {
      binding.ensureInitialized();
      resolvedBinding = binding;
    }
    final UnixSocketConnector resolvedReadinessConnector =
        readinessConnector ?? PlatformUnixSocketConnector();
    ReceivePort? tracePort;
    StreamSubscription<dynamic>? traceSubscription;
    if (onTrace != null) {
      tracePort = ReceivePort();
      traceSubscription = tracePort.listen((dynamic message) {
        if (message is! String) {
          return;
        }
        onTrace(UnixProxyTraceEvent.fromJson(message));
      });
    }
    try {
      final int handle = resolvedBinding.startProxy(
        socketPath: socketPath,
        clientTimeout: clientTimeout,
        tracePort: tracePort?.sendPort,
      );
      final UnixProxy proxy = UnixProxy._(
        handle,
        socketPath,
        resolvedBinding,
        tracePort: tracePort,
        traceSubscription: traceSubscription,
      );
      try {
        await _waitForSocketReady(
          socketPath: socketPath,
          timeout: readyTimeout,
          socketConnector: resolvedReadinessConnector,
        );
      } catch (_) {
        proxy.close();
        rethrow;
      }
      return proxy;
    } catch (_) {
      tracePort?.close();
      if (traceSubscription != null) {
        unawaited(traceSubscription.cancel());
      }
      rethrow;
    }
  }

  void close() {
    if (_closed) {
      return;
    }
    _binding.stopProxy(handle);
    _tracePort?.close();
    if (_traceSubscription != null) {
      unawaited(_traceSubscription.cancel());
    }
    _closed = true;
  }
}

Future<void> _waitForSocketReady({
  required String socketPath,
  required Duration timeout,
  required UnixSocketConnector socketConnector,
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  Object? lastError;

  while (true) {
    final Duration remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      break;
    }

    final Duration attemptTimeout =
        remaining < const Duration(milliseconds: 200)
            ? remaining
            : const Duration(milliseconds: 200);
    ConnectionTask<Socket>? task;
    try {
      task = await socketConnector.startConnect(
        socketPath: socketPath,
        timeout: attemptTimeout,
      );
      final Socket socket = await task.socket.timeout(attemptTimeout);
      await socket.close();
      return;
    } catch (error) {
      lastError = error;
      task?.cancel();
    }

    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  throw StateError(
    'Timed out waiting for unix proxy to become ready at "$socketPath". '
    'Last error: $lastError',
  );
}

int _readRequiredInt(Map<String, Object?> data, String key) {
  final Object? value = data[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('Expected "$key" to be an integer.');
}

int? _readOptionalInt(Map<String, Object?> data, String key) {
  final Object? value = data[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('Expected "$key" to be an integer when present.');
}

String _readRequiredString(Map<String, Object?> data, String key) {
  final Object? value = data[key];
  if (value is String) {
    return value;
  }
  throw FormatException('Expected "$key" to be a string.');
}

String? _readOptionalString(Map<String, Object?> data, String key) {
  final Object? value = data[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value.isEmpty ? null : value;
  }
  throw FormatException('Expected "$key" to be a string when present.');
}

bool _readRequiredBool(Map<String, Object?> data, String key) {
  final Object? value = data[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected "$key" to be a bool.');
}

DateTime _readRequiredDateTime(Map<String, Object?> data, String key) {
  final Object? value = data[key];
  if (value is! String) {
    throw FormatException('Expected "$key" to be an ISO-8601 string.');
  }
  return DateTime.parse(value);
}

DateTime? _readOptionalDateTime(Map<String, Object?> data, String key) {
  final Object? value = data[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException(
      'Expected "$key" to be an ISO-8601 string when present.',
    );
  }
  return DateTime.parse(value);
}

Duration _durationFromMicros(int micros) => Duration(microseconds: micros);

Duration? _readOptionalDuration(Map<String, Object?> data, String key) {
  final int? micros = _readOptionalInt(data, key);
  if (micros == null) {
    return null;
  }
  return _durationFromMicros(micros);
}

T? _readOptionalObject<T>(
  Map<String, Object?> data,
  String key,
  T Function(Map<String, Object?> value) parser,
) {
  final Object? value = data[key];
  if (value == null) {
    return null;
  }
  if (value is! Map<Object?, Object?>) {
    throw FormatException('Expected "$key" to be an object when present.');
  }
  return parser(
    value.map<String, Object?>(
      (Object? childKey, Object? childValue) =>
          MapEntry(childKey.toString(), childValue),
    ),
  );
}

List<T> _readObjectList<T>(
  Map<String, Object?> data,
  String key,
  T Function(Map<String, Object?> value) parser,
) {
  final Object? value = data[key];
  if (value == null) {
    return <T>[];
  }
  if (value is! List<Object?>) {
    throw FormatException('Expected "$key" to be an array.');
  }
  return value.map<T>((Object? entry) {
    if (entry is! Map<Object?, Object?>) {
      throw FormatException(
        'Expected every entry in "$key" to be an object.',
      );
    }
    return parser(
      entry.map<String, Object?>(
        (Object? childKey, Object? childValue) =>
            MapEntry(childKey.toString(), childValue),
      ),
    );
  }).toList(growable: false);
}

List<String> _readStringList(Map<String, Object?> data, String key) {
  final Object? value = data[key];
  if (value == null) {
    return const <String>[];
  }
  if (value is! List<Object?>) {
    throw FormatException('Expected "$key" to be an array of strings.');
  }
  return value.map<String>((Object? entry) {
    if (entry is! String) {
      throw FormatException(
        'Expected every entry in "$key" to be a string.',
      );
    }
    return entry;
  }).toList(growable: false);
}
