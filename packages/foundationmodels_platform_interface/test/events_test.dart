import 'package:foundationmodels_platform_interface/foundationmodels_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  group('FmStreamEvent.fromMap', () {
    test('parses every stable event type', () {
      const types = [
        'run_started',
        'message_start',
        'text_delta',
        'structured_delta',
        'tool_call_start',
        'tool_call_delta',
        'tool_call_result',
        'message_end',
        'done',
        'error',
      ];
      for (final type in types) {
        final event = FmStreamEvent.fromMap({
          'type': type,
          'requestId': 'rpc_1',
          'delta': 'x',
          'message': 'm',
        });
        expect(event.type, type);
        expect(event.requestId, 'rpc_1');
      }
    });

    test('carries sessionId and traceId when available', () {
      final event = FmStreamEvent.fromMap({
        'type': 'run_started',
        'requestId': 'rpc_9',
        'sessionId': 'ses_1',
        'traceId': 'trace_1',
      });
      expect(event, isA<RunStarted>());
      expect(event.sessionId, 'ses_1');
      expect(event.traceId, 'trace_1');
    });

    test('text_delta carries delta', () {
      final event = FmStreamEvent.fromMap(
          {'type': 'text_delta', 'requestId': 'r', 'delta': 'Hello'});
      expect((event as TextDelta).delta, 'Hello');
    });

    test('structured_delta carries delta', () {
      final event = FmStreamEvent.fromMap(
          {'type': 'structured_delta', 'requestId': 'r', 'delta': '{"a":1'});
      expect((event as StructuredDelta).delta, '{"a":1');
    });

    test('tool_call_start carries toolCallId and toolName', () {
      final event = FmStreamEvent.fromMap({
        'type': 'tool_call_start',
        'requestId': 'r',
        'toolCallId': 'tc_1',
        'toolName': 'get_weather',
      });
      final start = event as ToolCallStart;
      expect(start.toolCallId, 'tc_1');
      expect(start.toolName, 'get_weather');
    });

    test('tool_call_delta and tool_call_result parse', () {
      final delta = FmStreamEvent.fromMap({
        'type': 'tool_call_delta',
        'requestId': 'r',
        'toolCallId': 'tc_1',
        'delta': '{"city":',
      }) as ToolCallDelta;
      expect(delta.delta, '{"city":');
      final result = FmStreamEvent.fromMap({
        'type': 'tool_call_result',
        'requestId': 'r',
        'toolCallId': 'tc_1',
        'result': {'temp': 21},
      }) as ToolCallResult;
      expect(result.result, {'temp': 21});
    });

    test('done carries usage', () {
      final event = FmStreamEvent.fromMap({
        'type': 'done',
        'requestId': 'r',
        'usage': {'inputTokens': 5, 'outputTokens': 7, 'estimated': true},
      });
      expect((event as StreamDone).usage?['outputTokens'], 7);
    });

    test('error event maps to typed exception', () {
      final event = FmStreamEvent.fromMap({
        'type': 'error',
        'requestId': 'r',
        'code': 'GENERATION_CANCELLED',
        'message': 'cancelled by user',
      }) as StreamError;
      expect(event.toException(), isA<GenerationCancelledException>());
    });

    test('error event without code maps to generic exception', () {
      final event = FmStreamEvent.fromMap(
          {'type': 'error', 'requestId': 'r', 'message': 'mystery'});
      expect((event as StreamError).toException(),
          isA<UnknownModelException>());
    });

    test('missing requestId throws FormatException', () {
      expect(() => FmStreamEvent.fromMap({'type': 'done'}),
          throwsFormatException);
    });

    test('missing type throws FormatException', () {
      expect(() => FmStreamEvent.fromMap({'requestId': 'r'}),
          throwsFormatException);
    });

    test('unknown type throws FormatException', () {
      expect(
        () => FmStreamEvent.fromMap({'type': 'telemetry', 'requestId': 'r'}),
        throwsFormatException,
      );
    });
  });
}
