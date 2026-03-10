import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:unixconn/unixconn.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iOS proxy request and trace events remain stable across repeated rounds',
    (WidgetTester tester) async {
      final HttpServer upstream =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(upstream.close);

      upstream.listen((HttpRequest request) async {
        final String body = await utf8.decodeStream(request);
        final Map<String, Object?> payload = <String, Object?>{
          'method': request.method,
          'path': request.uri.path,
          'query': request.uri.queryParameters,
          'body': body,
          'headerScheme': request.headers.value('x-forwarded-proto'),
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(payload));
        await request.response.close();
      });

      const int sessionCount = 3;
      const int requestsPerSession = 4;

      for (int session = 0; session < sessionCount; session++) {
        final _TraceCollector traceCollector = _TraceCollector();
        final Set<int> seenRequestIds = <int>{};
        final String socketPath =
            createSandboxedUnixSocketPath(prefix: 'unx_$session');
        final File socketFile = File(socketPath);
        if (await socketFile.exists()) {
          await socketFile.delete();
        }

        final UnixProxy proxy = await UnixProxy.start(
          socketPath: socketPath,
          clientTimeout: const Duration(seconds: 5),
          onTrace: traceCollector.add,
        );
        addTearDown(() async {
          proxy.close();
          if (await socketFile.exists()) {
            await socketFile.delete();
          }
        });

        final UnixProxyConnectionFactory connectionFactory =
            createUnixProxyConnectionFactory(socketPath: socketPath);
        final HttpClient client = HttpClient();
        client.findProxy = ((_) => 'DIRECT');
        client.connectionFactory = connectionFactory;

        try {
          for (int round = 0; round < requestsPerSession; round++) {
            final Uri uri = Uri.parse(
              'http://127.0.0.1:${upstream.port}/echo?session=$session&round=$round',
            );
            final String requestBody = 'payload-$session-$round';

            final HttpClientRequest request = await client.postUrl(uri);
            request.headers.set('X-Forwarded-Proto', uri.scheme);
            request.write(requestBody);

            final HttpClientResponse response = await request.close();
            final String responseBody = await utf8.decodeStream(response);
            final Map<String, Object?> decoded =
                jsonDecode(responseBody) as Map<String, Object?>;

            expect(response.statusCode, HttpStatus.ok);
            expect(decoded['method'], 'POST');
            expect(decoded['path'], '/echo');
            expect(
              decoded['query'],
              <String, Object?>{
                'session': '$session',
                'round': '$round',
              },
            );
            expect(decoded['body'], requestBody);
            expect(decoded['headerScheme'], 'http');

            final UnixProxyTraceEvent event = await traceCollector.waitForCount(
              round + 1,
            );

            expect(event.requestId, greaterThan(0));
            expect(seenRequestIds.add(event.requestId), isTrue);
            expect(event.method, 'POST');
            expect(event.url, _traceUrlFor(uri));
            expect(event.startedAt.isAfter(event.finishedAt), isFalse);
            expect(
              event.totalDuration,
              greaterThanOrEqualTo(Duration.zero),
            );
            expect(event.requestSentAt, isNotNull);
            expect(event.requestBytes, greaterThan(0));
            expect(event.firstResponseByteAt, isNotNull);
            expect(event.responseBytes, greaterThan(0));
            expect(event.statusCode, HttpStatus.ok);
            expect(event.errorPhase, anyOf(isNull, isEmpty));
            expect(event.error, anyOf(isNull, isEmpty));
            expect(event.tls, isNull);
          }

          final UnixProxyTraceEvent lastEvent =
              await traceCollector.waitForCount(
            requestsPerSession,
          );
          expect(lastEvent.statusCode, HttpStatus.ok);
          expect(traceCollector.events, hasLength(requestsPerSession));
        } finally {
          client.close(force: true);
          proxy.close();
          if (await socketFile.exists()) {
            await socketFile.delete();
          }
        }
      }
    },
    skip: !Platform.isIOS,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

String _traceUrlFor(Uri uri) {
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.port,
    path: uri.path,
  ).toString();
}

final class _TraceCollector {
  final List<UnixProxyTraceEvent> events = <UnixProxyTraceEvent>[];

  void add(UnixProxyTraceEvent event) {
    events.add(event);
  }

  Future<UnixProxyTraceEvent> waitForCount(
    int expectedCount, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (events.length >= expectedCount) {
        return events[expectedCount - 1];
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    throw StateError('Timed out waiting for $expectedCount trace events.');
  }
}
