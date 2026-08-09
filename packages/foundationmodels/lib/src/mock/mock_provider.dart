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

import '../options.dart';
import '../provider.dart';
import '../schema.dart';

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
          'tools': false,
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
          'tools': false,
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
    final text = _textFor(request.input);
    return FmResponse(
      requestId: request.id,
      text: text,
      usage: _estimate(request.input, text),
      traceId: 'trace_mock_${_hash(request.input).toRadixString(16)}',
    );
  }

  @override
  Stream<FmStreamEvent> stream(FmRequest request) async* {
    request.options.validate();
    final schema = request.schema;
    final sessionId = request.sessionId;
    final traceId = 'trace_mock_${_hash(request.input).toRadixString(16)}';

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

    if (schema != null) {
      final output = jsonEncode(_structuredFor(schema, request));
      for (final chunk in _chunks(output)) {
        if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
        yield StructuredDelta(
          requestId: request.id,
          sessionId: sessionId,
          traceId: traceId,
          delta: chunk,
        );
      }
    } else {
      for (final chunk in _chunks(_textFor(request.input))) {
        if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
        yield TextDelta(
          requestId: request.id,
          sessionId: sessionId,
          traceId: traceId,
          delta: chunk,
        );
      }
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
    // No-op: the mock has no in-flight native work. Idempotent by design.
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
