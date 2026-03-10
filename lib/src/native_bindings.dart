import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

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

  _FfiUnixconnBinding._() : _library = _openLibrary();

  static final _FfiUnixconnBinding _instance = _FfiUnixconnBinding._();

  final DynamicLibrary _library;

  late final _InitializeDart _initialize =
      _library.lookupFunction<_InitializeNative, _InitializeDart>(
          'unixconn_initialize_dart_api');
  late final _StartProxyDart _startProxy =
      _library.lookupFunction<_StartProxyNative, _StartProxyDart>(
          'unixconn_start_proxy');
  late final _StopProxyDart _stopProxy = _library
      .lookupFunction<_StopProxyNative, _StopProxyDart>('unixconn_stop_proxy');
  late final _FreeStringDart _freeString =
      _library.lookupFunction<_FreeStringNative, _FreeStringDart>(
          'unixconn_free_string');

  bool _initialized = false;

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libunixconn_proxy.so');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError(
      'unixconn only supports Android, iOS, and macOS.',
    );
  }

  @override
  void ensureInitialized() {
    if (_initialized) {
      return;
    }
    final int result = _initialize(NativeApi.initializeApiDLData);
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

    return _invoke<int>(
      operation: 'startProxy',
      expectedNonNegative: true,
      callback: (errorCode, errorMessage) {
        final Pointer<Utf8> pathPointer = socketPath.toNativeUtf8();
        try {
          return _startProxy(
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
    _invoke<int>(
      operation: 'stopProxy',
      callback: (errorCode, errorMessage) {
        return _stopProxy(handle, errorCode, errorMessage);
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
        _freeString(messagePointer);
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
