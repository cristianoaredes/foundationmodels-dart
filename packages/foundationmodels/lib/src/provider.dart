/// Provider abstraction between the public runtime and a backend (native
/// transport or the deterministic mock).
library;

import 'package:foundationmodels_platform_interface/foundationmodels_platform_interface.dart';

import 'options.dart';
import 'schema.dart';
import 'tools.dart';

/// A single generation request, normalized by the runtime.
class FmRequest {
  /// Creates a request.
  const FmRequest({
    required this.id,
    required this.input,
    this.sessionId,
    this.sessionInstructions,
    this.instructions,
    this.options = GenerationOptions.defaults,
    this.schema,
    this.schemaMode = SchemaMode.output,
    this.model = 'apple.system',
    this.tools = const [],
    this.autoExecuteTools = true,
  });

  /// Unique correlation id (`rpc_...`). Doubles as the streaming
  /// `generationId` used by cancellation.
  final String id;

  /// User input text. Never concatenated into instructions by the runtime.
  final String input;

  /// Session this request belongs to, when any.
  final String? sessionId;

  /// Instructions used to **materialize** the native session on its first
  /// request (`null` afterwards — first request wins, per upstream).
  final String? sessionInstructions;

  /// Request-scoped instructions (trusted channel only — never interpolated
  /// with user input by the runtime).
  final String? instructions;

  /// Validated generation options.
  final GenerationOptions options;

  /// Guided-generation schema, when structured output is requested.
  final FmSchema? schema;

  /// How [schema] is serialized (fail-fast vs. sanitized).
  final SchemaMode schemaMode;

  /// Target model id (default `apple.system`).
  final String model;

  /// Request-scoped tools (never persisted on the session). Callback tools
  /// require streaming; enforced by the runtime before the provider call.
  final List<FmTool> tools;

  /// When `true` (default), the runtime executes callback tools on each
  /// [ToolCallRequest] and submits `foundationmodels.tools.result`.
  ///
  /// Set `false` when an external owner (e.g. `FmAgent` / `FmToolRouter` with
  /// HITL) is the sole executor — tools still travel on the wire and events
  /// still yield, but the runtime will not call `submitToolResult`.
  final bool autoExecuteTools;

  /// Names of tools that require a streaming generation path.
  List<String> get callbackToolNames => [
        for (final t in tools)
          if (t.requiresStreaming) t.name,
      ];
}

/// The result of a unary generation.
class FmResponse {
  /// Creates a response.
  const FmResponse({
    required this.requestId,
    this.text,
    this.structured,
    this.usage,
    this.traceId,
  });

  /// Correlation id of the request that produced this response.
  final String requestId;

  /// Plain-text output (when no schema was requested).
  final String? text;

  /// Structured output decoded from guided generation (when a schema was
  /// requested). Typically a `Map<String, Object?>`.
  final Object? structured;

  /// Token usage. Beware [Usage.estimated]: mock values are always
  /// estimates, never measurements.
  final Usage? usage;

  /// Distributed trace id, when reported.
  final String? traceId;
}

/// Input for a token-count pre-flight check.
class FmCountTokensRequest {
  /// Creates the request.
  const FmCountTokensRequest({
    required this.input,
    this.instructions,
    this.schema,
    this.model = 'apple.system',
  });

  /// User input text.
  final String input;

  /// Instructions that would accompany the generation.
  final String? instructions;

  /// Response schema that would accompany the generation.
  final FmSchema? schema;

  /// Target model id.
  final String model;
}

/// A backend for the FoundationModels runtime.
///
/// Implementations: `MockProvider` (deterministic, offline, CI-friendly) and
/// `TransportProvider` (JSON-RPC envelope over [FoundationModelsTransport]).
abstract class FmProvider {
  /// Stable identifier of this provider (e.g. `mock`, `apple-transport`).
  String get id;

  /// Availability report (see [AvailabilityReport]).
  Future<AvailabilityReport> availability();

  /// Capability descriptor used for feature-detect.
  Future<Map<String, Object?>> capabilities();

  /// Token accounting for a prospective request.
  Future<TokenCount> countTokens(FmCountTokensRequest request);

  /// Unary generation.
  ///
  /// Throws typed [FoundationModelsException] subtypes on failure.
  Future<FmResponse> respond(FmRequest request);

  /// Streaming generation. Emits typed [FmStreamEvent]s; terminates with
  /// [StreamDone] on success or [StreamError] on failure.
  Stream<FmStreamEvent> stream(FmRequest request);

  /// Cooperatively cancels the streaming generation [requestId].
  ///
  /// Sends `foundationmodels.generation.cancel` with
  /// `generationId == requestId` on real transports. Idempotent.
  Future<void> cancelGeneration(String requestId);

  /// Changes the instructions of a native session, preserving its transcript
  /// (`foundationmodels.sessions.transition`).
  Future<void> transitionSession({required String sessionId, String? instructions});

  /// Disposes a native session and drops its transcript
  /// (`foundationmodels.sessions.dispose`).
  Future<void> disposeSession(String sessionId);

  /// Health probe (`foundationmodels.health`). Default: empty map.
  Future<Map<String, Object?>> health() async => const {};

  /// Pre-warms a model/session (`foundationmodels.sessions.prewarm`).
  Future<Map<String, Object?>> prewarm({
    String? sessionId,
    String? model,
  }) async =>
      const {'warmed': false};

  /// Vision OCR (`foundationmodels.vision.ocr`).
  Future<Map<String, Object?>> visionOcr(Map<String, Object?> params) async {
    throw const UnsupportedOperationException(
      message: 'visionOcr is not implemented by this provider.',
      capability: 'vision.ocr',
    );
  }

  /// Vision barcode (`foundationmodels.vision.barcode`).
  Future<Map<String, Object?>> visionBarcode(Map<String, Object?> params) async {
    throw const UnsupportedOperationException(
      message: 'visionBarcode is not implemented by this provider.',
      capability: 'vision.barcode',
    );
  }

  /// Feedback attachment (`foundationmodels.feedback.logAttachment`).
  Future<Map<String, Object?>> logFeedbackAttachment(
    Map<String, Object?> params,
  ) async {
    throw const UnsupportedOperationException(
      message: 'logFeedbackAttachment is not implemented by this provider.',
      capability: 'feedback',
    );
  }

  /// Duplex tool result (`foundationmodels.tools.result`).
  Future<Map<String, Object?>> submitToolResult(
    Map<String, Object?> params,
  ) async {
    throw const UnsupportedOperationException(
      message: 'submitToolResult is not implemented by this provider.',
      capability: 'tools',
    );
  }
}
