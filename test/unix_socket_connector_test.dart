import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unixconn/unixconn.dart';

void main() {
  test('PlatformUnixSocketConnector uses the iOS connector when requested',
      () async {
    final _FakeSocket socket = _FakeSocket();
    var invokedPath = '';

    final PlatformUnixSocketConnector connector = PlatformUnixSocketConnector(
      useIosImplementation: true,
      iosStartConnect: (String path) async {
        invokedPath = path;
        return ConnectionTask.fromSocket(
          Future<Socket>.value(socket),
          () {},
        );
      },
    );

    final ConnectionTask<Socket> task =
        await connector.startConnect(socketPath: '/tmp/ios.sock');

    expect(invokedPath, '/tmp/ios.sock');
    expect(await task.socket, same(socket));
  });

  test('PlatformUnixSocketConnector uses dart:io unix sockets elsewhere',
      () async {
    final Directory tempDir =
        await Directory.systemTemp.createTemp('unixconn_connector_');
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

    final Future<Socket> acceptedFuture = server.first;
    final PlatformUnixSocketConnector connector =
        PlatformUnixSocketConnector(useIosImplementation: false);

    final ConnectionTask<Socket> task = await connector.startConnect(
      socketPath: socketPath,
      timeout: const Duration(seconds: 2),
    );
    final Socket client = await task.socket;
    final Socket accepted = await acceptedFuture;

    client.write('ping');

    expect(utf8.decode(await accepted.first), 'ping');

    await client.close();
    await accepted.close();
  });
}

final class _FakeSocket implements Socket {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
