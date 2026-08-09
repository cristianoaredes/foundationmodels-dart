/// Provider that speaks the protocol v2 envelope over a
/// [FoundationModelsTransport] — the path used by the real
/// `foundationmodels_apple` plugin (and by contract tests with fakes).
library;

import 'dart:async';

import 'package:foundationmodels_platform_interface/foundationmodels_platform_interface.dart';

import 'provider.dart';

/// [FmProvider] over a [FoundationModelsTransport].
///
/// - Unary calls are sent as `{"id", "method", "params"}` envelopes; the
///   resolved map is the JSON-RPC `result`.
/// - [FmTransportError] failures are mapped to typed exceptions via
///   [FoundationModelsException.fromError] using the stable
///   `error.data.code` string.
/// - [stream] sends `foundationmodels.sessions.stream`, then demultiplexes
///   [FoundationModelsTransport.streamEvents] by `requestId` until `done` or
///   `error`.
class TransportProvider implements FmProvider {
  /// Creates a provider over [transport].
  const TransportProvider(this._transport);

  final FoundationModelsTransport _transport;

  @override
  String get id => 'apple-transport';

  Never _rethrowTyped(FmTransportError error) {
    throw FoundationModelsException.fromError(
      code: error.data?['code'] as String?,
      message: error.message,
      data: error.data,
    );
  }

  Future<Map<String, Object?>> _call(
    String method,
    Map<String, Object?> params, {
    String? requestId,
  }) async {
    try {
      return await _transport.invoke({
        'id': requestId ?? 'rpc_${method.hashCode.toRadixString(16)}',
        'method': method,
        'params': params,
      });
    } on FmTransportError catch (error) {
      _rethrowTyped(error);
    }
  }

  Map<String, Object?> _requestParams(FmRequest request) {
    return {
      if (request.sessionId != null) 'sessionId': request.sessionId,
      if (request.sessionInstructions != null)
        'instructions': request.sessionInstructions,
      if (request.instructions != null && request.sessionId == null)
        'instructions': request.instructions,
      'model': request.model,
      'input': [
        {'type': 'text', 'text': request.input},
      ],
      'options': request.options.toJson(),
      if (request.schema != null)
        'responseFormat': {
          'type': 'json_schema',
          'schema': request.schema!.toJson(mode: request.schemaMode),
        },
    };
  }

  FmResponse _toResponse(String requestId, Map<String, Object?> result) {
    return FmResponse(
      requestId: requestId,
      text: result['content'] as String?,
      structured: result['structuredContent'],
      usage: result['usage'] is Map<String, Object?>
          ? Usage.fromMap(result['usage']! as Map<String, Object?>)
          : null,
      traceId: result['traceId'] as String?,
    );
  }

  @override
  Future<AvailabilityReport> availability() async =>
      AvailabilityReport.fromMap(await _call(FmMethods.availability, const {}));

  @override
  Future<Map<String, Object?>> capabilities() =>
      _call(FmMethods.capabilities, const {});

  @override
  Future<TokenCount> countTokens(FmCountTokensRequest request) async {
    final result = await _call(FmMethods.countTokens, {
      'model': request.model,
      'input': [
        {'type': 'text', 'text': request.input},
      ],
      if (request.instructions != null) 'instructions': request.instructions,
      if (request.schema != null) 'schema': request.schema!.toJson(),
    });
    return TokenCount.fromMap(result);
  }

  @override
  Future<FmResponse> respond(FmRequest request) async {
    final result = await _call(
      FmMethods.sessionRespond,
      _requestParams(request),
      requestId: request.id,
    );
    return _toResponse(request.id, result);
  }

  @override
  Stream<FmStreamEvent> stream(FmRequest request) {
    final controller = StreamController<FmStreamEvent>();
    StreamSubscription<Map<String, Object?>>? subscription;
    // Guards the terminal path: `close()` also triggers `onCancel`, so the
    // implicit-cancel cleanup must run only for genuine mid-stream
    // abandonment (and must never await `close()`, which would deadlock).
    var settled = false;

    void settle() {
      settled = true;
      unawaited(subscription?.cancel());
      unawaited(controller.close());
    }

    controller.onListen = () async {
      try {
        subscription = _transport.streamEvents.listen(
          (raw) {
            if (raw['requestId'] != request.id) return;
            final event = FmStreamEvent.fromMap(raw);
            if (!controller.isClosed) controller.add(event);
            if (event is StreamDone || event is StreamError) {
              settle();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
            settle();
          },
        );
        // The invoke resolves with the stream-start acknowledgement.
        await _call(
          FmMethods.sessionStream,
          _requestParams(request),
          requestId: request.id,
        );
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
        settled = true;
        await subscription?.cancel();
        await controller.close();
      }
    };
    controller.onCancel = () {
      if (settled) return; // normal terminal path already cleaned up.
      settled = true;
      // Abandoning the subscription is an implicit cancel.
      unawaited(cancelGeneration(request.id));
      unawaited(subscription?.cancel());
    };
    return controller.stream;
  }

  @override
  Future<void> cancelGeneration(String requestId) async {
    try {
      await _transport.invoke({
        'id': '${requestId}_cancel',
        'method': FmMethods.generationCancel,
        'params': {'generationId': requestId},
      });
    } on FmTransportError catch (error) {
      _rethrowTyped(error);
    }
  }

  @override
  Future<void> transitionSession({
    required String sessionId,
    String? instructions,
  }) =>
      _call(FmMethods.sessionTransition, {
        'sessionId': sessionId,
        if (instructions != null) 'instructions': instructions,
      }).then((_) {});

  @override
  Future<void> disposeSession(String sessionId) =>
      _call(FmMethods.sessionDispose, {'sessionId': sessionId}).then((_) {});
}
