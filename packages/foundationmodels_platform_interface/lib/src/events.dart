/// Typed stream events of the FoundationModels protocol (v2).
///
/// Events arrive on the multiplexed event channel as `Map`s and are parsed
/// with [FmStreamEvent.fromMap]. Every event carries [FmStreamEvent.requestId];
/// [FmStreamEvent.sessionId] and [FmStreamEvent.traceId] are included when
/// the native side has them available.
///
/// Stable event types: `run_started`, `message_start`, `text_delta`,
/// `structured_delta`, `tool_call_start`, `tool_call_delta`,
/// `tool_call_result`, `message_end`, `done`, `error`.
library;

import 'errors.dart';

/// Base type of every streaming generation event.
sealed class FmStreamEvent {
  /// Creates an event correlated to [requestId].
  const FmStreamEvent({required this.requestId, this.sessionId, this.traceId});

  /// Correlation id of the generation request (`rpc_...`).
  final String requestId;

  /// Session the generation belongs to, when available.
  final String? sessionId;

  /// Distributed trace id, when available.
  final String? traceId;

  /// Stable wire type of this event (e.g. `text_delta`).
  String get type;

  /// Parses a wire map into a typed event.
  ///
  /// Throws [FormatException] when `type` or `requestId` is missing or the
  /// `type` is not one of the stable protocol event types.
  static FmStreamEvent fromMap(Map<String, Object?> map) {
    final type = map['type'] as String?;
    final requestId = map['requestId'] as String?;
    if (type == null) {
      throw FormatException('Stream event is missing "type".', map);
    }
    if (requestId == null) {
      throw FormatException(
        'Stream event of type "$type" is missing "requestId".',
        map,
      );
    }
    final sessionId = map['sessionId'] as String?;
    final traceId = map['traceId'] as String?;

    switch (type) {
      case 'run_started':
        return RunStarted(
          requestId: requestId,
          sessionId: sessionId,
          traceId: traceId,
        );
      case 'message_start':
        return MessageStart(
          requestId: requestId,
          sessionId: sessionId,
          traceId: traceId,
        );
      // Core host emits type "delta" with "text"; daemon/plugin may emit
      // "text_delta" with "delta". Accept both (parity honesty, no silent drop).
      case 'text_delta':
      case 'delta':
        return TextDelta(
          requestId: requestId,
          sessionId: sessionId,
          traceId: traceId,
          delta: map['delta'] as String? ?? map['text'] as String? ?? '',
        );
      case 'structured_delta':
        return StructuredDelta(
          requestId: requestId,
          sessionId: sessionId,
          traceId: traceId,
          delta: map['delta'] as String? ?? map['text'] as String? ?? '',
        );
      case 'tool_call_start':
        return ToolCallStart(
          requestId: requestId,
          sessionId: sessionId,
          traceId: traceId,
          toolCallId: map['toolCallId'] as String?,
          toolName: map['toolName'] as String?,
        );
      case 'tool_call_delta':
        return ToolCallDelta(
          requestId: requestId,
          sessionId: sessionId,
          traceId: traceId,
          toolCallId: map['toolCallId'] as String?,
          // Core may ship complete args under "arguments"; text fragments under delta/text.
          delta: map['delta'] as String? ??
              map['text'] as String? ??
              (map['arguments'] != null ? map['arguments'].toString() : ''),
        );
      case 'tool_call_result':
        return ToolCallResult(
          requestId: requestId,
          sessionId: sessionId,
          traceId: traceId,
          toolCallId: map['toolCallId'] as String?,
          // Core emits "output"; protocol docs also use "result".
          result: map['result'] ?? map['output'],
        );
      case 'tool_call_request':
        return ToolCallRequest(
          requestId: requestId,
          sessionId: sessionId,
          traceId: traceId,
          toolCallId: map['toolCallId'] as String?,
          toolName: map['toolName'] as String?,
          arguments: _asStringKeyedMap(map['arguments']),
        );
      case 'message_end':
        return MessageEnd(
          requestId: requestId,
          sessionId: sessionId,
          traceId: traceId,
        );
      case 'done':
        return StreamDone(
          requestId: requestId,
          sessionId: sessionId,
          traceId: traceId,
          usage: map['usage'] as Map<String, Object?>?,
        );
      // Core sometimes emits a final "result" envelope before "done". Treat as
      // a terminal text snapshot via TextDelta when output/content is present;
      // otherwise ignore by mapping to MessageEnd so parsers do not throw.
      case 'result':
        final out = map['output'] as String? ??
            map['content'] as String? ??
            map['text'] as String?;
        if (out != null && out.isNotEmpty) {
          return TextDelta(
            requestId: requestId,
            sessionId: sessionId,
            traceId: traceId,
            delta: out,
          );
        }
        return MessageEnd(
          requestId: requestId,
          sessionId: sessionId,
          traceId: traceId,
        );
      case 'error':
        return StreamError(
          requestId: requestId,
          sessionId: sessionId,
          traceId: traceId,
          code: map['code'] as String?,
          message: map['message'] as String? ?? 'Stream error',
          data: map['data'] as Map<String, Object?>?,
        );
      default:
        throw FormatException('Unknown stream event type "$type".', map);
    }
  }

  @override
  String toString() => '$runtimeType(requestId: $requestId, '
      'sessionId: $sessionId, traceId: $traceId)';
}

/// `run_started` — the generation run has begun.
final class RunStarted extends FmStreamEvent {
  /// Creates the event.
  const RunStarted({
    required super.requestId,
    super.sessionId,
    super.traceId,
  });

  @override
  String get type => 'run_started';
}

/// `message_start` — the model started emitting a message.
final class MessageStart extends FmStreamEvent {
  /// Creates the event.
  const MessageStart({
    required super.requestId,
    super.sessionId,
    super.traceId,
  });

  @override
  String get type => 'message_start';
}

/// `text_delta` — an incremental fragment of plain-text output.
final class TextDelta extends FmStreamEvent {
  /// Creates the event carrying the text [delta].
  const TextDelta({
    required super.requestId,
    super.sessionId,
    super.traceId,
    required this.delta,
  });

  /// Incremental text fragment; concatenate to rebuild the full message.
  final String delta;

  @override
  String get type => 'text_delta';

  @override
  String toString() => 'TextDelta(requestId: $requestId, delta: $delta)';
}

/// `structured_delta` — an incremental fragment of guided (JSON) output.
final class StructuredDelta extends FmStreamEvent {
  /// Creates the event carrying the serialized JSON [delta].
  const StructuredDelta({
    required super.requestId,
    super.sessionId,
    super.traceId,
    required this.delta,
  });

  /// Incremental fragment of the serialized structured output.
  final String delta;

  @override
  String get type => 'structured_delta';

  @override
  String toString() =>
      'StructuredDelta(requestId: $requestId, delta: $delta)';
}

/// `tool_call_start` — the model started a tool call mid-stream.
final class ToolCallStart extends FmStreamEvent {
  /// Creates the event.
  const ToolCallStart({
    required super.requestId,
    super.sessionId,
    super.traceId,
    this.toolCallId,
    this.toolName,
  });

  /// Correlation id of the tool call, when present.
  final String? toolCallId;

  /// Name of the invoked tool, when present.
  final String? toolName;

  @override
  String get type => 'tool_call_start';
}

/// `tool_call_delta` — incremental arguments of an in-flight tool call.
final class ToolCallDelta extends FmStreamEvent {
  /// Creates the event.
  const ToolCallDelta({
    required super.requestId,
    super.sessionId,
    super.traceId,
    this.toolCallId,
    required this.delta,
  });

  /// Correlation id of the tool call, when present.
  final String? toolCallId;

  /// Incremental fragment of the serialized tool arguments.
  final String delta;

  @override
  String get type => 'tool_call_delta';
}

/// `tool_call_result` — a (native or client) tool call produced a result.
final class ToolCallResult extends FmStreamEvent {
  /// Creates the event.
  const ToolCallResult({
    required super.requestId,
    super.sessionId,
    super.traceId,
    this.toolCallId,
    this.result,
  });

  /// Correlation id of the tool call, when present.
  final String? toolCallId;

  /// Tool result payload (structure is tool-defined).
  final Object? result;

  @override
  String get type => 'tool_call_result';
}

/// `tool_call_request` — complete tool call ready for host execution (duplex).
///
/// Emitted once arguments are complete. Hosts run the registered callback and
/// reply via `foundationmodels.tools.result` with the same [toolCallId].
final class ToolCallRequest extends FmStreamEvent {
  /// Creates the event.
  const ToolCallRequest({
    required super.requestId,
    super.sessionId,
    super.traceId,
    this.toolCallId,
    this.toolName,
    this.arguments = const {},
  });

  /// Correlation id of the tool call, when present.
  final String? toolCallId;

  /// Name of the invoked tool, when present.
  final String? toolName;

  /// Fully decoded tool arguments (empty map when absent).
  final Map<String, Object?> arguments;

  @override
  String get type => 'tool_call_request';
}

/// `message_end` — the model finished emitting the message.
final class MessageEnd extends FmStreamEvent {
  /// Creates the event.
  const MessageEnd({
    required super.requestId,
    super.sessionId,
    super.traceId,
  });

  @override
  String get type => 'message_end';
}

/// `done` — terminal event: the generation completed successfully.
final class StreamDone extends FmStreamEvent {
  /// Creates the event, optionally with token [usage] for the whole stream.
  const StreamDone({
    required super.requestId,
    super.sessionId,
    super.traceId,
    this.usage,
  });

  /// Raw usage payload for the completed generation, when reported.
  final Map<String, Object?>? usage;

  @override
  String get type => 'done';
}

/// `error` — terminal event: the generation failed.
///
/// Convert to a typed exception with [toException], which applies the
/// stable `error.data.code` contract via [FoundationModelsException.fromError].
final class StreamError extends FmStreamEvent {
  /// Creates the event.
  const StreamError({
    required super.requestId,
    super.sessionId,
    super.traceId,
    required this.code,
    required this.message,
    this.data,
  });

  /// Stable machine-readable error code (`error.data.code`).
  final String? code;

  /// Human-readable error message.
  final String message;

  /// Structured error payload (`error.data`).
  final Map<String, Object?>? data;

  /// Maps this event to the typed exception matching [code].
  FoundationModelsException toException() =>
      FoundationModelsException.fromError(
        code: code,
        message: message,
        data: data,
      );

  @override
  String get type => 'error';

  @override
  String toString() =>
      'StreamError(requestId: $requestId, code: $code, message: $message)';
}

Map<String, Object?> _asStringKeyedMap(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is Map) {
    return {
      for (final e in raw.entries) e.key.toString(): e.value,
    };
  }
  return const {};
}
