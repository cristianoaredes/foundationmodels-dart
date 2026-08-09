/// Low-level transport contract between the Dart runtime and a native host.
///
/// The real implementation lives in `foundationmodels_apple` and is backed by
/// a single MethodChannel (`foundationmodels/rpc`) plus a single multiplexed
/// EventChannel (`foundationmodels/streams`). Tests use fakes. This package
/// ships no implementation on purpose.
library;

/// A failure raised by the transport layer itself (channel error, native
/// error envelope, codec problem).
///
/// The stable machine-readable error code — the real contract, per the
/// upstream protocol — travels inside [data] under the key `code`
/// (e.g. `{"code": "RATE_LIMITED", "resetDate": "..."}`). The numeric
/// JSON-RPC-ish [code] is informational only and must never be used to map
/// to typed exceptions.
class FmTransportError implements Exception {
  /// Creates a transport error.
  const FmTransportError({this.code, required this.message, this.data});

  /// Numeric protocol code (informational only — not the typed-error contract).
  final int? code;

  /// Human-readable message produced by the native side.
  final String message;

  /// Structured payload. Carries the stable string `code`
  /// (e.g. `APPLE_MODEL_UNAVAILABLE`) plus code-specific fields.
  final Map<String, Object?>? data;

  @override
  String toString() =>
      'FmTransportError(code: $code, message: $message, data: $data)';
}

/// Transport capable of carrying JSON-RPC-shaped envelopes to the native
/// FoundationModels core and of delivering multiplexed stream events.
///
/// Wire format of [invoke] arguments:
/// `{"id": "rpc_...", "method": "foundationmodels.sessions.respond",
///   "params": {...}}`.
///
/// On success [invoke] resolves with the JSON-RPC `result` map directly
/// (channel correlation replaces the `id` echo). On failure it throws
/// [FmTransportError] whose `data` contains the stable string error code.
abstract class FoundationModelsTransport {
  /// Sends a unary envelope and resolves with the JSON-RPC `result`.
  ///
  /// Throws [FmTransportError] when the native side reports an error.
  Future<Map<String, Object?>> invoke(Map<String, Object?> envelope);

  /// Multiplexed stream of protocol events (`text_delta`, `done`, `error`,
  /// ...) for all in-flight streaming generations.
  ///
  /// Every event carries `requestId`; consumers demultiplex by it. When
  /// available, events also carry `sessionId` and `traceId`.
  Stream<Map<String, Object?>> get streamEvents;
}
