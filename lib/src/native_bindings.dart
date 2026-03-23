import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

abstract interface class UnixconnBinding {
  void ensureInitialized();

  int startProxy({
    required String socketPath,
    Duration? clientTimeout,
    SendPort? tracePort,
  });

  void stopProxy(int handle);
}

final class UnixconnBindings {
  static UnixconnBinding? debugOverride;

  static UnixconnBinding get instance => debugOverride ?? _FfiUnixconnBinding();

  static Future<void> ensureInitialized() async {
    final UnixconnBinding? override = debugOverride;
    if (override != null) {
      override.ensureInitialized();
      return;
    }
    final _FfiUnixconnBinding binding = _FfiUnixconnBinding();
    await binding.ensureBootstrapInitialized();
    binding.ensureInitialized();
  }
}

final class UnixconnNativeException implements Exception {
  const UnixconnNativeException(this.operation, this.code, this.message);

  final String operation;
  final int code;
  final String message;

  @override
  String toString() =>
      'UnixconnNativeException(operation: $operation, code: $code, message: $message)';
}

typedef _StartProxyNative = Int64 Function(
  Pointer<Utf8>,
  Int32,
  Int64,
  Pointer<Int32>,
  Pointer<Pointer<Char>>,
);
typedef _StartProxyDart = int Function(
  Pointer<Utf8>,
  int,
  int,
  Pointer<Int32>,
  Pointer<Pointer<Char>>,
);

typedef _InitializeNative = IntPtr Function(Pointer<Void>);
typedef _InitializeDart = int Function(Pointer<Void>);

typedef _StopProxyNative = Int32 Function(
  Int64,
  Pointer<Int32>,
  Pointer<Pointer<Char>>,
);
typedef _StopProxyDart = int Function(
  int,
  Pointer<Int32>,
  Pointer<Pointer<Char>>,
);

typedef _FreeStringNative = Void Function(Pointer<Char>);
typedef _FreeStringDart = void Function(Pointer<Char>);

final class _FfiUnixconnBinding implements UnixconnBinding {
  factory _FfiUnixconnBinding() => _instance;

  _FfiUnixconnBinding._() {
    if (Platform.isAndroid) {
      final DynamicLibrary library =
          DynamicLibrary.open('libunixconn_proxy.so');
      _initialize = library.lookupFunction<_InitializeNative, _InitializeDart>(
        'unixconn_initialize_dart_api',
      );
      _startProxy = library.lookupFunction<_StartProxyNative, _StartProxyDart>(
        'unixconn_start_proxy',
      );
      _stopProxy = library.lookupFunction<_StopProxyNative, _StopProxyDart>(
        'unixconn_stop_proxy',
      );
      _freeString = library.lookupFunction<_FreeStringNative, _FreeStringDart>(
        'unixconn_free_string',
      );
      return;
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return;
    }
    throw UnsupportedError(
      'unixconn only supports Android, iOS, and macOS.',
    );
  }

  static final _FfiUnixconnBinding _instance = _FfiUnixconnBinding._();

  static const MethodChannel _appleBootstrapChannel = MethodChannel('unixconn');

  _InitializeDart? _initialize;
  _StartProxyDart? _startProxy;
  _StopProxyDart? _stopProxy;
  _FreeStringDart? _freeString;
  Future<void>? _bootstrapFuture;

  bool _initialized = false;

  bool get _hasFunctionTable =>
      _initialize != null &&
      _startProxy != null &&
      _stopProxy != null &&
      _freeString != null;

  Future<void> ensureBootstrapInitialized() async {
    if (Platform.isAndroid || _hasFunctionTable) {
      return;
    }
    try {
      await (_bootstrapFuture ??= _bootstrapAppleBindings());
    } catch (_) {
      _bootstrapFuture = null;
      rethrow;
    }
  }

  Future<void> _bootstrapAppleBindings() async {
    final Map<String, int>? addresses =
        await _appleBootstrapChannel.invokeMapMethod<String, int>(
      'getNativeApiAddresses',
    );
    if (addresses == null) {
      throw StateError(
        'Failed to fetch the unixconn Apple native API address table.',
      );
    }
    _initialize = Pointer<NativeFunction<_InitializeNative>>.fromAddress(
      _requireAddress(addresses, 'initializeDartApi'),
    ).asFunction<_InitializeDart>();
    _startProxy = Pointer<NativeFunction<_StartProxyNative>>.fromAddress(
      _requireAddress(addresses, 'startProxy'),
    ).asFunction<_StartProxyDart>();
    _stopProxy = Pointer<NativeFunction<_StopProxyNative>>.fromAddress(
      _requireAddress(addresses, 'stopProxy'),
    ).asFunction<_StopProxyDart>();
    _freeString = Pointer<NativeFunction<_FreeStringNative>>.fromAddress(
      _requireAddress(addresses, 'freeString'),
    ).asFunction<_FreeStringDart>();
  }

  static int _requireAddress(Map<String, int> addresses, String key) {
    final int? address = addresses[key];
    if (address == null || address == 0) {
      throw StateError('The unixconn Apple native API is missing "$key".');
    }
    return address;
  }

  static T _requireFunction<T extends Function>(T? function, String name) {
    if (function != null) {
      return function;
    }
    if (Platform.isIOS || Platform.isMacOS) {
      throw StateError(
        'unixconn Apple native API is not initialized for this isolate. '
        'Call await UnixconnBindings.ensureInitialized() on the main isolate '
        'before using the default binding.',
      );
    }
    throw StateError('The unixconn native binding for "$name" is unavailable.');
  }

  @override
  void ensureInitialized() {
    if (_initialized) {
      return;
    }
    final _InitializeDart initialize =
        _requireFunction(_initialize, 'initializeDartApi');
    final int result = initialize(NativeApi.initializeApiDLData);
    if (result != 0) {
      throw StateError(
        'Failed to initialize the native Dart API bridge: $result',
      );
    }
    _initialized = true;
  }

  @override
  int startProxy({
    required String socketPath,
    Duration? clientTimeout,
    SendPort? tracePort,
  }) {
    if (socketPath.isEmpty) {
      throw ArgumentError.value(
        socketPath,
        'socketPath',
        'The unix socket path must not be empty.',
      );
    }
    ensureInitialized();
    final _StartProxyDart startProxy =
        _requireFunction(_startProxy, 'startProxy');

    return _invoke<int>(
      operation: 'startProxy',
      expectedNonNegative: true,
      callback: (errorCode, errorMessage) {
        final Pointer<Utf8> pathPointer = socketPath.toNativeUtf8();
        try {
          return startProxy(
            pathPointer,
            clientTimeout?.inMilliseconds ?? 0,
            tracePort?.nativePort ?? 0,
            errorCode,
            errorMessage,
          );
        } finally {
          calloc.free(pathPointer);
        }
      },
    );
  }

  @override
  void stopProxy(int handle) {
    final _StopProxyDart stopProxy = _requireFunction(_stopProxy, 'stopProxy');
    _invoke<int>(
      operation: 'stopProxy',
      callback: (errorCode, errorMessage) {
        return stopProxy(handle, errorCode, errorMessage);
      },
    );
  }

  T _invoke<T extends num>({
    required String operation,
    required T Function(
      Pointer<Int32> errorCode,
      Pointer<Pointer<Char>> errorMessage,
    ) callback,
    bool expectedNonNegative = false,
  }) {
    final Pointer<Int32> errorCode = calloc<Int32>();
    final Pointer<Pointer<Char>> errorMessage = calloc<Pointer<Char>>();
    final _FreeStringDart freeString =
        _requireFunction(_freeString, 'freeString');
    try {
      final T result = callback(errorCode, errorMessage);
      final int code = errorCode.value;
      if (code != 0) {
        throw UnixconnNativeException(
          operation,
          code,
          _readMessage(errorMessage),
        );
      }
      if (expectedNonNegative && result.toInt() < 0) {
        throw UnixconnNativeException(
          operation,
          -1,
          'The native call returned an invalid handle.',
        );
      }
      return result;
    } finally {
      final Pointer<Char> messagePointer = errorMessage.value;
      if (messagePointer != nullptr) {
        freeString(messagePointer);
      }
      calloc.free(errorCode);
      calloc.free(errorMessage);
    }
  }

  String _readMessage(Pointer<Pointer<Char>> errorMessage) {
    final Pointer<Char> pointer = errorMessage.value;
    if (pointer == nullptr) {
      return 'Unknown native error.';
    }
    return pointer.cast<Utf8>().toDartString();
  }
}
