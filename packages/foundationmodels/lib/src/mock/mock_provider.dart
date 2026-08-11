/// Deterministic offline mock provider — the CI-friendly backend.
///
/// Design (verbatim constraints from the upstream mock semantics):
/// - **Deterministic**: answers are derived from a hash of (seed, input,
///   labels/schema), never from wall-clock or random sources.
/// - **Offline**: no network, no filesystem, no environment reads.
/// - **Explicitly estimated**: every [Usage] reports `estimated: true` —
///   never silently treat mock numbers as measurements.
library;

import 'dart:async';
import 'dart:convert';

import 'package:foundationmodels_platform_interface/foundationmodels_platform_interface.dart';

import '../provider.dart';
import '../schema.dart';
import '../tools.dart';

/// A deterministic, offline [FmProvider] for tests and local development.
///
/// Returned by [createFoundationModels] when no providers are given.
class MockProvider implements FmProvider {
  /// Creates a mock provider with an optional [seed] (default `0`) and
  /// simulated streaming [chunkDelay] (default `Duration.zero`).
  const MockProvider({this.seed = 0, this.chunkDelay = Duration.zero});

  /// Determinism seed mixed into every hash.
  final int seed;

  /// Artificial delay between streaming chunks (tests only).
  final Duration chunkDelay;

  static const String _model = 'apple.system';

  /// Request ids cancelled via [cancelGeneration] while a mock stream is
  /// in flight. Shared across instances so `const MockProvider(...)` still
  /// observes cooperative cancel (U6 contract on the offline path).
  static final Set<String> _cancelledRequestIds = <String>{};

  int _hash(String input) {
    var hash = seed;
    for (final unit in input.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  Usage _estimate(String input, String output) => Usage(
        inputTokens: (input.length / 4).ceil(),
        outputTokens: (output.length / 4).ceil(),
        estimated: true, // always: mock numbers are estimates, never measurements.
      );

  @override
  String get id => 'mock';

  @override
  Future<AvailabilityReport> availability() async => const AvailabilityReport(
        available: true,
        features: {
          'streaming': true,
          'guidedGeneration': true,
          'countTokens': true,
          'multimodal': false,
          'vision': false,
          'feedback': false,
          // Static + scripted callback duplex; native tools stay false.
          'tools': true,
          'nativeTools': false,
        },
      );

  @override
  Future<Map<String, Object?>> capabilities() async => const {
        'provider': 'mock',
        'model': _model,
        'features': {
          'streaming': true,
          'guidedGeneration': true,
          'countTokens': true,
          'multimodal': false,
          'vision': false,
          'feedback': false,
          'tools': true,
          'nativeTools': false,
        },
      };

  @override
  Future<TokenCount> countTokens(FmCountTokensRequest request) async {
    final input = (request.input.length / 4).ceil();
    final instructions = ((request.instructions?.length ?? 0) / 4).ceil();
    final schema = request.schema == null
        ? 0
        : (jsonEncode(request.schema!.toJson()).length / 4).ceil();
    const window = 4096;
    final total = input + instructions + schema;
    return TokenCount(
      input: input,
      instructions: instructions,
      tool: 0,
      schema: schema,
      total: total,
      contextWindow: window,
      remaining: window - total,
      estimated: true,
    );
  }

  @override
  Future<FmResponse> respond(FmRequest request) async {
    request.options.validate();
    // Callback tools must never reach here — runtime enforces stream-only.
    final schema = request.schema;
    if (schema != null) {
      final structured = _structuredFor(schema, request);
      final output = jsonEncode(structured);
      return FmResponse(
        requestId: request.id,
        structured: structured,
        usage: _estimate(request.input, output),
        traceId: 'trace_mock_${_hash(request.input).toRadixString(16)}',
      );
    }
    // Static tools: echo staticOutput deterministically into the text path.
    final staticTools = [
      for (final t in request.tools)
        if (t.kind == FmToolKind.staticOutput) t,
    ];
    if (staticTools.isNotEmpty) {
      final parts = [
        for (final t in staticTools)
          '${t.name}=${jsonEncode(t.staticOutput)}',
      ];
      final text = 'static_tools: ${parts.join('; ')}';
      return FmResponse(
        requestId: request.id,
        text: text,
        usage: _estimate(request.input, text),
        traceId: 'trace_mock_${_hash(request.input).toRadixString(16)}',
      );
    }
    final text = _textFor(request.input);
    return FmResponse(
      requestId: request.id,
      text: text,
      usage: _estimate(request.input, text),
      traceId: 'trace_mock_${_hash(request.input).toRadixString(16)}',
    );
  }

  bool _wasCancelled(String requestId) =>
      _cancelledRequestIds.remove(requestId);

  StreamError _cancelledEvent({
    required String requestId,
    String? sessionId,
    String? traceId,
  }) =>
      StreamError(
        requestId: requestId,
        sessionId: sessionId,
        traceId: traceId,
        code: 'GENERATION_CANCELLED',
        message: 'Generation $requestId was cancelled before completion.',
        data: const {'code': 'GENERATION_CANCELLED'},
      );

  @override
  Stream<FmStreamEvent> stream(FmRequest request) async* {
    request.options.validate();
    final schema = request.schema;
    final sessionId = request.sessionId;
    final traceId = 'trace_mock_${_hash(request.input).toRadixString(16)}';
    // Clear a stale cancel mark from a prior generation with the same id.
    _cancelledRequestIds.remove(request.id);

    yield RunStarted(
      requestId: request.id,
      sessionId: sessionId,
      traceId: traceId,
    );
    yield MessageStart(
      requestId: request.id,
      sessionId: sessionId,
      traceId: traceId,
    );

    // Scripted duplex: for each callback tool, emit a complete tool_call
    // lifecycle so the runtime can execute the host callback + tools.result.
    final callbackTools = [
      for (final t in request.tools)
        if (t.kind == FmToolKind.callback) t,
    ];
    for (var i = 0; i < callbackTools.length; i++) {
      final tool = callbackTools[i];
      final toolCallId = 'tc_mock_${request.id}_$i';
      if (_wasCancelled(request.id)) {
        yield _cancelledEvent(
          requestId: request.id,
          sessionId: sessionId,
          traceId: traceId,
        );
        return;
      }
      yield ToolCallStart(
        requestId: request.id,
        sessionId: sessionId,
        traceId: traceId,
        toolCallId: toolCallId,
        toolName: tool.name,
      );
      // Complete arguments on tool_call_request (daemon shape).
      yield ToolCallRequest(
        requestId: request.id,
        sessionId: sessionId,
        traceId: traceId,
        toolCallId: toolCallId,
        toolName: tool.name,
        arguments: {
          'input': request.input,
          'tool': tool.name,
        },
      );
      // Brief yield point so the runtime can run the callback + submitToolResult.
      if (chunkDelay > Duration.zero) {
        await Future<void>.delayed(chunkDelay);
      } else {
        await Future<void>.delayed(Duration.zero);
      }
    }

    // Static tools on the stream path: surface their outputs as text deltas.
    final staticTools = [
      for (final t in request.tools)
        if (t.kind == FmToolKind.staticOutput) t,
    ];
    final content = schema != null
        ? jsonEncode(_structuredFor(schema, request))
        : staticTools.isNotEmpty
            ? 'static_tools: ${[
                for (final t in staticTools)
                  '${t.name}=${jsonEncode(t.staticOutput)}',
              ].join('; ')}'
            : callbackTools.isNotEmpty
                ? 'after_tools: ${_textFor(request.input)}'
                : _textFor(request.input);

    if (schema != null) {
      for (final chunk in _chunks(content)) {
        if (_wasCancelled(request.id)) {
          yield _cancelledEvent(
            requestId: request.id,
            sessionId: sessionId,
            traceId: traceId,
          );
          return;
        }
        if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
        if (_wasCancelled(request.id)) {
          yield _cancelledEvent(
            requestId: request.id,
            sessionId: sessionId,
            traceId: traceId,
          );
          return;
        }
        yield StructuredDelta(
          requestId: request.id,
          sessionId: sessionId,
          traceId: traceId,
          delta: chunk,
        );
      }
    } else {
      for (final chunk in _chunks(content)) {
        if (_wasCancelled(request.id)) {
          yield _cancelledEvent(
            requestId: request.id,
            sessionId: sessionId,
            traceId: traceId,
          );
          return;
        }
        if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
        if (_wasCancelled(request.id)) {
          yield _cancelledEvent(
            requestId: request.id,
            sessionId: sessionId,
            traceId: traceId,
          );
          return;
        }
        yield TextDelta(
          requestId: request.id,
          sessionId: sessionId,
          traceId: traceId,
          delta: chunk,
        );
      }
    }

    if (_wasCancelled(request.id)) {
      yield _cancelledEvent(
        requestId: request.id,
        sessionId: sessionId,
        traceId: traceId,
      );
      return;
    }

    yield MessageEnd(
      requestId: request.id,
      sessionId: sessionId,
      traceId: traceId,
    );
    yield StreamDone(
      requestId: request.id,
      sessionId: sessionId,
      traceId: traceId,
      usage: _estimate(request.input, 'mock').toMap(),
    );
  }

  @override
  Future<void> cancelGeneration(String requestId) async {
    // Mark the id so an in-flight mock stream terminates with
    // GENERATION_CANCELLED. Idempotent: repeated cancels are no-ops.
    _cancelledRequestIds.add(requestId);
  }

  @override
  Future<void> transitionSession({
    required String sessionId,
    String? instructions,
  }) async {
    // No-op: the mock keeps no transcripts.
  }

  @override
  Future<void> disposeSession(String sessionId) async {
    // No-op: the mock keeps no transcripts.
  }

  @override
  Future<Map<String, Object?>> health() async => const {
        'provider': 'mock',
        'ok': true,
        'stub': false,
        'transport': 'offline-mock',
      };

  @override
  Future<Map<String, Object?>> prewarm({
    String? sessionId,
    String? model,
  }) async =>
      {
        'warmed': true,
        'provider': 'mock',
        if (sessionId != null) 'sessionId': sessionId,
        'model': model ?? _model,
      };

  @override
  Future<Map<String, Object?>> visionOcr(Map<String, Object?> params) async {
    // Honest mock: no real OCR. Surfaces the stable unavailable code so
    // consumers can feature-detect without inventing text from an image.
    throw const VisionOcrUnavailableException(
      message: 'Mock provider does not perform OCR.',
    );
  }

  @override
  Future<Map<String, Object?>> visionBarcode(Map<String, Object?> params) async {
    throw const VisionBarcodeUnavailableException(
      message: 'Mock provider does not scan barcodes.',
    );
  }

  @override
  Future<Map<String, Object?>> logFeedbackAttachment(
    Map<String, Object?> params,
  ) async {
    // Accept and ack offline — feedback is best-effort telemetry.
    return {
      'ok': true,
      'provider': 'mock',
      'generationId': params['generationId'],
      'recorded': true,
    };
  }

  /// Accepted tool results (duplex) for observability/tests.
  static final List<Map<String, Object?>> submittedToolResults =
      <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> submitToolResult(
    Map<String, Object?> params,
  ) async {
    // Duplex path: runtime submits after executing the host callback.
    // Accept and record — the mock generation does not block on results.
    submittedToolResults.add(Map<String, Object?>.from(params));
    return {
      'ok': true,
      'accepted': true,
      'toolCallId': params['toolCallId'],
      'provider': 'mock',
    };
  }

  // ---------------------------------------------------------------------------

  String _textFor(String input) {
    final responses = [
      'Understood.',
      'Here is a concise answer.',
      'On-device processing keeps your data private.',
      'Deterministic mock response.',
    ];
    return '${responses[_hash(input) % responses.length]} '
        '(echo: ${_truncate(input, 48)})';
  }

  String _truncate(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';

  Iterable<String> _chunks(String output) sync* {
    const size = 12;
    for (var i = 0; i < output.length; i += size) {
      final end = (i + size > output.length) ? output.length : i + size;
      yield output.substring(i, end);
    }
  }

  Object? _structuredFor(FmSchema schema, FmRequest request) {
    final json = schema.toJson(mode: request.schemaMode);
    return _valueFor(json, request.input);
  }

  Object? _valueFor(Map<String, Object?> schema, String input) {
    switch (schema['type']) {
      case 'object':
        final properties =
            (schema['properties'] as Map?)?.cast<String, Object?>() ?? const {};
        final required =
            (schema['required'] as List?)?.whereType<String>().toSet() ??
                properties.keys.toSet();
        return {
          for (final entry in properties.entries)
            if (required.contains(entry.key))
              entry.key: entry.value is Map<String, Object?>
                  ? _valueFor(entry.value! as Map<String, Object?>, input)
                  : null,
        };
      case 'array':
        final items = schema['items'];
        final min = (schema['minItems'] as num?)?.toInt() ?? 1;
        final item = items is Map<String, Object?>
            ? _valueFor(items, input)
            : 'item';
        return List.filled(min < 1 ? 1 : min, item);
      case 'string':
        final enumValues = schema['enum'];
        if (enumValues is List && enumValues.isNotEmpty) {
          // Deterministic label pick — the primitive the mock exists for.
          return enumValues[_hash(input) % enumValues.length];
        }
        return 'mock:${_truncate(input, 32)}';
      case 'number':
        return (_hash(input) % 1000) / 10.0;
      case 'integer':
        return _hash(input) % 100;
      case 'boolean':
        return _hash(input).isEven;
      case null:
        final ref = schema['\$ref'];
        if (ref is String) return 'mock-ref:$ref';
        return null;
      default:
        return null;
    }
  }
}
