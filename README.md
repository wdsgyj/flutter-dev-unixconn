# unixconn

Flutter FFI plugin for starting an in-process Go unix proxy and connecting
`HttpClient` to it through a unix socket.

## Trace events

`UnixProxy.start(..., onTrace: ...)` delivers `UnixProxyTraceEvent` objects from
the Go proxy. Each event exposes `requestId`, which is the native per-request
unique ID and can be used directly as the upper-layer aggregation key.

```dart
final tracesByRequestId = <int, UnixProxyTraceEvent>{};

final proxy = await UnixProxy.start(
  socketPath: createSandboxedUnixSocketPath(),
  onTrace: (event) {
    tracesByRequestId[event.requestId] = event;
  },
);
```

## Ignoring proxy settings

If `HttpClient` passes non-null `proxyHost` / `proxyPort`, wrap the factory with
`ignoringProxySettings(...)` to discard them instead of throwing:

```dart
final client = HttpClient()
  ..connectionFactory = ignoringProxySettings(
    createUnixProxyConnectionFactory(
      socketPath: proxy.socketPath,
    ),
  );
```
