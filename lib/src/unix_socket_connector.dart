import 'dart:io';

import 'package:unixsock_plugin/unixsock_plugin.dart' as unixsock;

abstract interface class UnixSocketConnector {
  Future<ConnectionTask<Socket>> startConnect({
    required String socketPath,
    Duration? timeout,
  });
}

typedef IosStartConnect = Future<ConnectionTask<Socket>> Function(String path);

final class PlatformUnixSocketConnector implements UnixSocketConnector {
  PlatformUnixSocketConnector({
    bool? useIosImplementation,
    IosStartConnect? iosStartConnect,
  })  : _useIosImplementation = useIosImplementation ?? Platform.isIOS,
        _iosStartConnect = iosStartConnect ?? _defaultIosStartConnect;

  final bool _useIosImplementation;
  final IosStartConnect _iosStartConnect;

  static Future<ConnectionTask<Socket>> _defaultIosStartConnect(
    String path,
  ) {
    return unixsock.UnixSocket.startConnect(path, 0);
  }

  @override
  Future<ConnectionTask<Socket>> startConnect({
    required String socketPath,
    Duration? timeout,
  }) {
    if (_useIosImplementation) {
      return _iosStartConnect(socketPath);
    }

    final InternetAddress address = InternetAddress(
      socketPath,
      type: InternetAddressType.unix,
    );
    if (timeout == null) {
      return Socket.startConnect(address, 0);
    }
    return Future<ConnectionTask<Socket>>.value(
      ConnectionTask.fromSocket(
        Socket.connect(address, 0, timeout: timeout),
        () {},
      ),
    );
  }
}
