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

## Apple FFI registration

On iOS and macOS, `unixconn` no longer resolves FFI entry points by exported
symbol name. The native plugin returns the raw C function addresses over the
plugin channel, and Dart binds them with `Pointer.fromAddress(...).asFunction()`.
Host apps should not need extra Podfile linker configuration just to preserve
FFI symbols.

Apple bootstrap currently depends on the main isolate's Flutter messenger. If
you use the default binding, initialize it on the main isolate before the first
`UnixProxy.start(...)`:

```dart
WidgetsFlutterBinding.ensureInitialized();
await UnixconnBindings.ensureInitialized();
```

Direct background-isolate startup is not supported on iOS/macOS. If you need
that later, bootstrap the native API on the main isolate first and then design
your own address-table handoff to the background isolate.
