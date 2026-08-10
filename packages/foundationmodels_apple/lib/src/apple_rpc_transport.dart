import 'dart:async';

import 'package:flutter/services.dart';
import 'package:foundationmodels_platform_interface/foundationmodels_platform_interface.dart';

/// Channel names — single MethodChannel + single EventChannel (ADR-0001 §6).
const String kMethodChannelName = 'foundationmodels/rpc';
const String kEventChannelName = 'foundationmodels/streams';

/// The single MethodChannel operation: its argument is the daemon-shaped
/// envelope `{"id": "rpc_...", "method": "foundationmodels.<op>", "params": {...}}`.
const String kInvokeMethod = 'invoke';

/// [FoundationModelsTransport] implementation backed by Flutter platform
/// channels, bridging to `FoundationModelsBridge.shared` in the Swift core.
///
/// Wire contract (ADR-0001 §7):
/// - Unary success resolves with the bare JSON-RPC `result` map.
/// - Failure surfaces as a typed [FoundationModelsException] via
///   `FoundationModelsException.fromError(...)` — the stable machine `code`
///   in `error.data` (e.g. CONTEXT_OVERFLOW), not the numeric JSON-RPC code,
///   is the mapping contract. [FmTransportError] is reserved for malformed
///   channel traffic (no stable code to map).
/// - [streamEvents] is the *global*, raw EventChannel stream; demultiplexing
///   by `requestId` happens in `package:foundationmodels`, not here.
class MethodChannelFoundationModels extends FoundationModelsTransport {
  MethodChannelFoundationModels({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel(kMethodChannelName),
       _eventChannel = eventChannel ?? const EventChannel(kEventChannelName);

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Stream<Map<String, Object?>>? _streamEvents;

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> envelope) async {
    final Object? raw;
    try {
      raw = await _methodChannel.invokeMethod<Object?>(kInvokeMethod, envelope);
    } on PlatformException catch (error) {
      throw _convertPlatformException(error);
    } on MissingPluginException catch (error) {
      // No native side registered (unsupported platform / headless test):
      // fail typed, never silently (ADR-0001 §7.3).
      throw UnsupportedPlatformException(
        message: error.message ?? 'foundationmodels_apple is not registered',
      );
    }
    if (raw is Map) return _deepCastMap(raw);
    throw FmTransportError(
      message:
          'Malformed channel reply: expected a result map, '
          'got ${raw.runtimeType}',
    );
  }

  /// Global stream of raw daemon-shaped events.
  ///
  /// Backed by `EventChannel.receiveBroadcastStream()`; this getter caches a
  /// single mapped instance, so all consumers share one underlying native
  /// subscription. Cancelling it triggers `onCancel` on the native side,
  /// which implicitly cancels every active native generation (the analogue
  /// of the daemon's client-EOF semantics, ADR-0001 §10). The API package
  /// keeps exactly one listener and fans events out to per-request
  /// `StreamController`s.
  @override
  Stream<Map<String, Object?>> get streamEvents {
    return _streamEvents ??= _eventChannel.receiveBroadcastStream().map(
      (event) => event is Map
          ? _deepCastMap(event)
          : const <String, Object?>{
              'type': 'error',
              'code': 'UNKNOWN_MODEL_ERROR',
              'message': 'Malformed stream event payload',
            },
    );
  }

  /// Converts a channel failure into a typed exception.
  ///
  /// The Swift side replies with `FlutterError(code: "<jsonRpcCode>"`,
  /// `message: ...`, `details: errorData`); `errorData.code` — the stable
  /// machine string — is what maps to the typed exception (ADR-0001 §7.3).
  FoundationModelsException _convertPlatformException(PlatformException error) {
    final details = error.details;
    final errorData = details is Map
        ? _deepCastMap(details)
        : const <String, Object?>{};
    return FoundationModelsException.fromError(
      code: errorData['code'] as String?,
      message: error.message ?? 'Unknown native error',
      data: errorData,
    );
  }

  /// Deep-casts `StandardMessageCodec` output (`Map<Object?, Object?>` /
  /// `List<Object?>`) into `Map<String, Object?>` / `List<Object?>`.
  static Map<String, Object?> _deepCastMap(Map<Object?, Object?> value) {
    return value.map(
      (key, entry) => MapEntry(key.toString(), _deepCast(entry)),
    );
  }

  static Object? _deepCast(Object? value) {
    if (value is Map) return _deepCastMap(value);
    if (value is List) return value.map(_deepCast).toList();
    return value;
  }
}
