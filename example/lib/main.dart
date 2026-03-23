import 'package:flutter/material.dart';
import 'package:mmkv/mmkv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MMKV.initialize();
  final MMKV mmkv = MMKV.defaultMMKV();
  const String key = 'unixconn_mmkv_probe';
  const String value = 'ready';
  mmkv.encodeString(key, value);

  runApp(ExampleApp(mmkvProbe: mmkv.decodeString(key) ?? 'missing'));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({required this.mmkvProbe, super.key});

  final String mmkvProbe;

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
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('MMKV probe: $mmkvProbe'),
              const SizedBox(height: 16),
              const Expanded(
                  child: SingleChildScrollView(child: SelectableText(sample))),
            ],
          ),
        ),
      ),
    );
  }
}
