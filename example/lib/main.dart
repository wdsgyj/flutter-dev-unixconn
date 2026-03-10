import 'package:flutter/material.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    const String sample = '''
final socketPath = createSandboxedUnixSocketPath();
final tracesByRequestId = <int, UnixProxyTraceEvent>{};

final proxy = await UnixProxy.start(
  socketPath: socketPath,
  clientTimeout: Duration(seconds: 10),
  onTrace: (event) {
    tracesByRequestId[event.requestId] = event;
    print(event.requestId);
    print(event.method);
    print(event.url);
    print(event.statusCode);
    print(event.tls?.peerCertificates.first.sha256Fingerprint);
  },
);

final client = HttpClient()
  ..findProxy = (_) => 'DIRECT'
  ..connectionFactory = ignoringProxySettings(
    createUnixProxyConnectionFactory(
      socketPath: proxy.socketPath,
    ),
  );

final uri = Uri.parse('https://example.com');
final request = await client.getUrl(uri);
request.headers.set('X-Forwarded-Proto', uri.scheme);
final response = await request.close();
''';

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('unixconn example')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: SelectableText(sample),
        ),
      ),
    );
  }
}
