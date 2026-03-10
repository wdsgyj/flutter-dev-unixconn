import 'dart:io';

import 'unix_socket_connector.dart';

typedef UnixProxyConnectionFactory = Future<ConnectionTask<Socket>> Function(
  Uri url,
  String? proxyHost,
  int? proxyPort,
);

UnixProxyConnectionFactory ignoringProxySettings(
  UnixProxyConnectionFactory inner,
) {
  return (Uri url, String? _, int? __) {
    return inner(url, null, null);
  };
}

Map<String, String> proxyHeadersFor(Uri url) {
  final String scheme = url.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw ArgumentError.value(
      url,
      'url',
      'unixproxy-go only supports http and https targets.',
    );
  }
  return <String, String>{'X-Forwarded-Proto': scheme};
}

UnixProxyConnectionFactory createUnixProxyConnectionFactory({
  required String socketPath,
  UnixSocketConnector? socketConnector,
}) {
  final UnixSocketConnector resolvedConnector =
      socketConnector ?? PlatformUnixSocketConnector();

  return (Uri _, String? proxyHost, int? proxyPort) {
    if (proxyHost != null || proxyPort != null) {
      throw StateError(
        'The unix proxy connection factory does not support outbound HTTP proxies.',
      );
    }
    return resolvedConnector.startConnect(socketPath: socketPath);
  };
}
