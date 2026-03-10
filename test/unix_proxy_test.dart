import 'dart:isolate';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unixconn/unixconn.dart';

void main() {
  test(
      'UnixProxy.start delegates to the native binding and close is idempotent',
      () async {
    final _FakeBinding binding = _FakeBinding();
    final _SequencedSocketConnector socketConnector =
        _SequencedSocketConnector.success();

    final UnixProxy proxy = await UnixProxy.start(
      socketPath: '/tmp/unixconn.sock',
      clientTimeout: const Duration(seconds: 3),
      binding: binding,
      readinessConnector: socketConnector,
    );

    expect(proxy.handle, 41);
    expect(proxy.socketPath, '/tmp/unixconn.sock');
    expect(binding.startedSocketPath, '/tmp/unixconn.sock');
    expect(binding.startedTimeout, const Duration(seconds: 3));
    expect(binding.startedTracePort, isNull);
    expect(socketConnector.attempts, 1);

    proxy.close();
    proxy.close();

    expect(binding.stoppedHandles, <int>[41]);
  });

  test('UnixProxy.start forwards native trace events to the Dart callback',
      () async {
    final _FakeBinding binding = _FakeBinding();
    final List<UnixProxyTraceEvent> events = <UnixProxyTraceEvent>[];
    final _SequencedSocketConnector socketConnector =
        _SequencedSocketConnector.success();

    final UnixProxy proxy = await UnixProxy.start(
      socketPath: '/tmp/unixconn.sock',
      onTrace: events.add,
      binding: binding,
      readinessConnector: socketConnector,
    );

    expect(binding.startedTracePort, isNotNull);

    binding.emitTrace('''
{
  "requestId": 7,
  "method": "GET",
  "url": "https://example.com",
  "startedAt": "2026-03-09T12:00:00Z",
  "finishedAt": "2026-03-09T12:00:01Z",
  "totalDurationMicros": 1000000,
  "reusedConn": false,
  "dnsDurationMicros": 1200,
  "connectDurationMicros": 3400,
  "remoteIp": "93.184.216.34",
  "tlsDurationMicros": 5600,
  "tls": {
    "version": 772,
    "versionName": "TLS 1.3",
    "cipherSuite": 4865,
    "cipherSuiteName": "TLS_AES_128_GCM_SHA256",
    "serverName": "example.com",
    "negotiatedProtocol": "h2",
    "negotiatedProtocolIsMutual": true,
    "didResume": false,
    "handshakeComplete": true,
    "peerCertificates": [
      {
        "subject": "CN=example.com",
        "issuer": "CN=Example CA",
        "serialNumber": "1234",
        "dnsNames": ["example.com"],
        "emailAddresses": ["ops@example.com"],
        "ipAddresses": ["93.184.216.34"],
        "uris": ["spiffe://example/service"],
        "notBefore": "2026-03-01T00:00:00Z",
        "notAfter": "2027-03-01T00:00:00Z",
        "sha256Fingerprint": "abc123"
      }
    ]
  },
  "requestSentAt": "2026-03-09T12:00:00.100Z",
  "requestBytes": 128,
  "firstResponseByteAt": "2026-03-09T12:00:00.300Z",
  "responseBytes": 512,
  "statusCode": 200
}
''');
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    final UnixProxyTraceEvent event = events.single;
    expect(event.requestId, 7);
    expect(event.method, 'GET');
    expect(event.url, 'https://example.com');
    expect(event.startedAt, DateTime.parse('2026-03-09T12:00:00Z'));
    expect(event.finishedAt, DateTime.parse('2026-03-09T12:00:01Z'));
    expect(event.totalDuration, const Duration(seconds: 1));
    expect(event.reusedConn, isFalse);
    expect(event.dnsDuration, const Duration(microseconds: 1200));
    expect(event.connectDuration, const Duration(microseconds: 3400));
    expect(event.remoteIp, '93.184.216.34');
    expect(event.tlsDuration, const Duration(microseconds: 5600));
    expect(event.requestSentAt, DateTime.parse('2026-03-09T12:00:00.100Z'));
    expect(event.requestBytes, 128);
    expect(
      event.firstResponseByteAt,
      DateTime.parse('2026-03-09T12:00:00.300Z'),
    );
    expect(event.responseBytes, 512);
    expect(event.statusCode, 200);
    expect(event.errorPhase, isNull);
    expect(event.error, isNull);
    expect(event.rawData['requestId'], 7);

    final UnixProxyTlsInfo tls = event.tls!;
    expect(tls.version, 772);
    expect(tls.versionName, 'TLS 1.3');
    expect(tls.cipherSuite, 4865);
    expect(tls.cipherSuiteName, 'TLS_AES_128_GCM_SHA256');
    expect(tls.serverName, 'example.com');
    expect(tls.negotiatedProtocol, 'h2');
    expect(tls.negotiatedProtocolIsMutual, isTrue);
    expect(tls.didResume, isFalse);
    expect(tls.handshakeComplete, isTrue);
    expect(tls.peerCertificates, hasLength(1));

    final UnixProxyPeerCertificateInfo certificate =
        tls.peerCertificates.single;
    expect(certificate.subject, 'CN=example.com');
    expect(certificate.issuer, 'CN=Example CA');
    expect(certificate.serialNumber, '1234');
    expect(certificate.dnsNames, <String>['example.com']);
    expect(certificate.emailAddresses, <String>['ops@example.com']);
    expect(certificate.ipAddresses, <String>['93.184.216.34']);
    expect(certificate.uris, <String>['spiffe://example/service']);
    expect(certificate.notBefore, DateTime.parse('2026-03-01T00:00:00Z'));
    expect(certificate.notAfter, DateTime.parse('2027-03-01T00:00:00Z'));
    expect(certificate.sha256Fingerprint, 'abc123');

    proxy.close();
  });

  test('UnixProxy.start waits until the socket becomes connectable', () async {
    final _FakeBinding binding = _FakeBinding();
    final _SequencedSocketConnector socketConnector = _SequencedSocketConnector(
      <Object?>[
        const SocketException('not ready'),
        const SocketException('still not ready'),
        _FakeSocket(),
      ],
    );

    final UnixProxy proxy = await UnixProxy.start(
      socketPath: '/tmp/unixconn.sock',
      binding: binding,
      readyTimeout: const Duration(milliseconds: 200),
      readinessConnector: socketConnector,
    );

    expect(socketConnector.attempts, 3);
    expect(socketConnector.lastSocketPath, '/tmp/unixconn.sock');
    proxy.close();
  });

  test('UnixProxy.start closes the proxy if readiness never succeeds',
      () async {
    final _FakeBinding binding = _FakeBinding();
    final _SequencedSocketConnector socketConnector = _SequencedSocketConnector(
      <Object?>[
        const SocketException('not ready'),
      ],
    );

    await expectLater(
      () => UnixProxy.start(
        socketPath: '/tmp/unixconn.sock',
        binding: binding,
        readyTimeout: const Duration(milliseconds: 40),
        readinessConnector: socketConnector,
      ),
      throwsStateError,
    );

    expect(binding.stoppedHandles, <int>[41]);
  });
}

final class _FakeBinding implements UnixconnBinding {
  String? startedSocketPath;
  Duration? startedTimeout;
  SendPort? startedTracePort;
  final List<int> stoppedHandles = <int>[];

  @override
  void ensureInitialized() {}

  @override
  int startProxy({
    required String socketPath,
    Duration? clientTimeout,
    SendPort? tracePort,
  }) {
    startedSocketPath = socketPath;
    startedTimeout = clientTimeout;
    startedTracePort = tracePort;
    return 41;
  }

  @override
  void stopProxy(int handle) {
    stoppedHandles.add(handle);
  }

  void emitTrace(String payload) {
    startedTracePort?.send(payload);
  }
}

final class _SequencedSocketConnector implements UnixSocketConnector {
  _SequencedSocketConnector(this._outcomes);

  factory _SequencedSocketConnector.success() {
    return _SequencedSocketConnector(<Object?>[_FakeSocket()]);
  }

  final List<Object?> _outcomes;
  int attempts = 0;
  String? lastSocketPath;

  @override
  Future<ConnectionTask<Socket>> startConnect({
    required String socketPath,
    Duration? timeout,
  }) async {
    lastSocketPath = socketPath;
    final int index =
        attempts < _outcomes.length ? attempts : _outcomes.length - 1;
    attempts++;
    final Object? outcome = _outcomes[index];
    if (outcome is Socket) {
      return ConnectionTask.fromSocket(
        Future<Socket>.value(outcome),
        () {},
      );
    }
    if (outcome is Error) {
      throw outcome;
    }
    if (outcome is Exception) {
      throw outcome;
    }
    throw StateError('Unsupported connector outcome: $outcome');
  }
}

final class _FakeSocket implements Socket {
  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
