import 'dart:async';

import 'package:foundationmodels/foundationmodels.dart';
import 'package:foundationmodels_tools/foundationmodels_tools.dart';
import 'package:test/test.dart';

/// Fake transport that records tool results and can push stream events.
class _RecordingTransport implements FoundationModelsTransport {
  final envelopes = <Map<String, Object?>>[];
  final _events = StreamController<Map<String, Object?>>.broadcast();

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> envelope) async {
    envelopes.add(envelope);
    final method = envelope['method'] as String?;
    if (method == 'foundationmodels.availability') {
      return const {'available': true, 'features': {'streaming': true}};
    }
    if (method == 'foundationmodels.sessions.stream') {
      return const {'ok': true, 'streaming': true};
    }
    if (method == 'foundationmodels.tools.result') {
      return {'ok': true, 'accepted': true, 'params': envelope['params']};
    }
    return const {'ok': true};
  }

  @override
  Stream<Map<String, Object?>> get streamEvents => _events.stream;

  void push(Map<String, Object?> event) => _events.add(event);
}

void main() {
  test('register keeps callback tools only', () async {
    final fm = await createFoundationModels();
    final router = FmToolRouter(fm);
    router.register(FmTool.callback(
      name: 'echo',
      description: 'echo',
      inputSchema: FmSchema.object({'x': FmSchema.string()}),
      callback: (args) async => args['x'],
    ));
    router.register(FmTool.static(
      name: 'static_only',
      description: 's',
      inputSchema: FmSchema.object(const {}),
      staticOutput: 'hi',
    ));
    expect(router.tools.keys, ['echo']);
  });

  test('duplex: tool_call_request executes handler and submits result',
      () async {
    final transport = _RecordingTransport();
    final fm = await createFoundationModels(
      providers: [TransportProvider(transport)],
    );
    final router = FmToolRouter(fm);
    router.registerHandler('echo', (args) async => 'echo:${args['q']}');

    // Simulate duplex events for a known request id.
    const requestId = 'rpc_tools_1';
    await router.handleEvent(const ToolCallStart(
      requestId: requestId,
      toolCallId: 'tc_1',
      toolName: 'echo',
    ));
    await router.handleEvent(const ToolCallDelta(
      requestId: requestId,
      toolCallId: 'tc_1',
      delta: '{"q":',
    ));
    await router.handleEvent(const ToolCallDelta(
      requestId: requestId,
      toolCallId: 'tc_1',
      delta: '"hi"}',
    ));
    // Prefer complete arguments on tool_call_request (daemon shape).
    final consumed = await router.handleEvent(const ToolCallRequest(
      requestId: requestId,
      toolCallId: 'tc_1',
      toolName: 'echo',
      arguments: {'q': 'hi'},
    ));
    expect(consumed, isTrue);

    final toolEnvelopes = transport.envelopes
        .where((e) => e['method'] == 'foundationmodels.tools.result')
        .toList();
    expect(toolEnvelopes, hasLength(1));
    final params = toolEnvelopes.single['params']! as Map<String, Object?>;
    expect(params['toolCallId'], 'tc_1');
    expect(params['output'], 'echo:hi');
  });

  test('missing handler submits TOOL_CALLBACK_NOT_FOUND', () async {
    final transport = _RecordingTransport();
    final fm = await createFoundationModels(
      providers: [TransportProvider(transport)],
    );
    final router = FmToolRouter(fm);
    await router.handleEvent(const ToolCallRequest(
      requestId: 'r',
      toolCallId: 'tc_x',
      toolName: 'missing',
      arguments: {},
    ));
    final params = transport.envelopes
        .singleWhere((e) => e['method'] == 'foundationmodels.tools.result')
        ['params']! as Map<String, Object?>;
    expect((params['error']! as Map)['code'], 'TOOL_CALLBACK_NOT_FOUND');
  });

  test('FmTool.callback requiresStreaming; static does not', () {
    final cb = FmTool.callback(
      name: 'c',
      description: 'd',
      inputSchema: FmSchema.object(const {}),
      callback: (_) async => null,
    );
    final st = FmTool.static(
      name: 's',
      description: 'd',
      inputSchema: FmSchema.object(const {}),
      staticOutput: 1,
    );
    expect(cb.requiresStreaming, isTrue);
    expect(st.requiresStreaming, isFalse);
    expect(st.toJson()['staticOutput'], 1);
  });
}
