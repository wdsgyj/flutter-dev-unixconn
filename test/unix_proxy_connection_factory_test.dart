import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unixconn/unixconn.dart';

void main() {
  test('proxyHeadersFor only accepts http and https', () {
    expect(
      proxyHeadersFor(Uri.parse('https://example.com')),
      <String, String>{'X-Forwarded-Proto': 'https'},
    );
    expect(
      proxyHeadersFor(Uri.parse('http://example.com')),
      <String, String>{'X-Forwarded-Proto': 'http'},
    );
    expect(
      () => proxyHeadersFor(Uri.parse('ws://example.com')),
      throwsArgumentError,
    );
  });

  test('createUnixProxyConnectionFactory delegates to the socket connector',
      () async {
    final _FakeSocketConnector socketConnector = _FakeSocketConnector();

    final UnixProxyConnectionFactory connectionFactory =
        createUnixProxyConnectionFactory(
      socketPath: '/tmp/proxy.sock',
      socketConnector: socketConnector,
    );

    final ConnectionTask<Socket> task = await connectionFactory(
      Uri.parse('https://example.com'),
      null,
      null,
    );

    expect(socketConnector.lastSocketPath, '/tmp/proxy.sock');
    expect(await task.socket, same(socketConnector.socket));
  });

  test('createUnixProxyConnectionFactory rejects outbound HTTP proxies', () {
    final UnixProxyConnectionFactory connectionFactory =
        createUnixProxyConnectionFactory(
      socketPath: '/tmp/proxy.sock',
      socketConnector: _FakeSocketConnector(),
    );

    expect(
      () => connectionFactory(
        Uri.parse('https://example.com'),
        'proxy.example.com',
        3128,
      ),
      throwsStateError,
    );
  });

  test('ignoringProxySettings discards proxyHost and proxyPort', () async {
    final _FakeSocketConnector socketConnector = _FakeSocketConnector();
    final UnixProxyConnectionFactory connectionFactory = ignoringProxySettings(
      createUnixProxyConnectionFactory(
        socketPath: '/tmp/proxy.sock',
        socketConnector: socketConnector,
      ),
    );

    final ConnectionTask<Socket> task = await connectionFactory(
      Uri.parse('https://example.com'),
      'proxy.example.com',
      3128,
    );

    expect(socketConnector.lastSocketPath, '/tmp/proxy.sock');
    expect(await task.socket, same(socketConnector.socket));
  });

  test(
      'factory-produced sockets can be assigned to HttpClient.connectionFactory',
      () async {
    final Directory tempDir =
        await Directory.systemTemp.createTemp('unixconn_factory_');
    final String socketPath = '${tempDir.path}/proxy.sock';
    final ServerSocket server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );

    addTearDown(() async {
      await server.close();
      if (await File(socketPath).exists()) {
        await File(socketPath).delete();
      }
      await tempDir.delete(recursive: true);
    });

    final UnixProxyConnectionFactory connectionFactory =
        createUnixProxyConnectionFactory(socketPath: socketPath);
    final HttpClient client = HttpClient();
    client.findProxy = ((_) => 'DIRECT');
    client.connectionFactory = connectionFactory;

    final Future<Socket> acceptedFuture = server.first;
    final ConnectionTask<Socket> task =
        await connectionFactory(Uri.parse('https://example.com'), null, null);
    final Socket clientSocket = await task.socket;
    final Socket accepted = await acceptedFuture;

    clientSocket.add(utf8.encode('ping'));
    await clientSocket.flush();

    expect(utf8.decode(await accepted.first), 'ping');

    await clientSocket.close();
    await accepted.close();
    client.close(force: true);
  });
}

final class _FakeSocketConnector implements UnixSocketConnector {
  String? lastSocketPath;
  final _FakeSocket socket = _FakeSocket();

  @override
  Future<ConnectionTask<Socket>> startConnect({
    required String socketPath,
    Duration? timeout,
  }) async {
    lastSocketPath = socketPath;
    return ConnectionTask.fromSocket(
      Future<Socket>.value(socket),
      () {},
    );
  }
}

final class _FakeSocket implements Socket {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
