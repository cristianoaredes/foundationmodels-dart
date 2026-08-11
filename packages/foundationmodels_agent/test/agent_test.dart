import 'package:foundationmodels/foundationmodels.dart';
import 'package:foundationmodels_agent/foundationmodels_agent.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    MockProvider.submittedToolResults.clear();
  });

  test('intent router classifies into routes via mock', () async {
    final fm = await createFoundationModels();
    final router = FmIntentRouter(fm, routes: const ['chat', 'search', 'code']);
    final route = await router.classifyRouteIntent('I want to search docs');
    expect(['chat', 'search', 'code'], contains(route));
  });

  test('HITL registry is consume-once and rejects pollution', () {
    final reg = FmInterruptRegistry(ttl: const Duration(minutes: 5));
    final i = reg.create(toolName: 'echo', proposedArgs: {'x': 1});
    final approved = reg.resume(
      id: i.id,
      decision: FmInterruptDecision.approve,
    );
    expect(approved['x'], 1);
    expect(
      () => reg.resume(id: i.id, decision: FmInterruptDecision.approve),
      throwsStateError,
    );

    final i2 = reg.create(toolName: 'echo', proposedArgs: {'x': 1});
    expect(
      () => reg.resume(
        id: i2.id,
        decision: FmInterruptDecision.edit,
        editedArgs: {
          '__proto__': {'admin': true},
        },
      ),
      throwsArgumentError,
    );
  });

  test('agent run emits RUN_STARTED and RUN_FINISHED on mock stream', () async {
    final fm = await createFoundationModels();
    final agent = FmAgent(fm: fm);
    final events = await agent.run(input: 'hello agent').toList();
    expect(events.first, isA<FmAgentRunStarted>());
    expect(events.last, isA<FmAgentRunFinished>());
    expect(events.whereType<FmAgentTextContent>(), isNotEmpty);
  });

  test('prototype pollution detector', () {
    expect(containsPrototypePollution({'a': 1}), isFalse);
    expect(containsPrototypePollution({'__proto__': {}}), isTrue);
    expect(
      containsPrototypePollution({
        'nested': {'constructor': {}},
      }),
      isTrue,
    );
  });

  group('tool loop (shipped path)', () {
    FmTool echoTool() => FmTool.callback(
          name: 'echo',
          description: 'echo',
          inputSchema: FmSchema.object({
            'input': FmSchema.string(),
          }),
          callback: (args) async => 'agent-echo:${args['input']}',
        );

    test('FmAgent(tools:) produces tool events and exactly one tools.result',
        () async {
      final fm = await createFoundationModels();
      final agent = FmAgent(fm: fm, tools: [echoTool()]);

      final events = await agent.run(input: 'hello from agent').toList();

      expect(events.whereType<FmAgentToolCallStart>(), isNotEmpty);
      expect(events.whereType<FmAgentToolCallEnd>(), isNotEmpty);
      expect(events.first, isA<FmAgentRunStarted>());
      expect(events.last, isA<FmAgentRunFinished>());

      // Sole executor: agent router only (autoExecuteTools: false).
      expect(MockProvider.submittedToolResults, hasLength(1));
      final submitted = MockProvider.submittedToolResults.single;
      expect(submitted['output'], 'agent-echo:hello from agent');
      expect(submitted['toolCallId'], isNotNull);
    });

    test('requireHitl: interrupt then approve → still exactly one tools.result',
        () async {
      final fm = await createFoundationModels();
      final agent = FmAgent(
        fm: fm,
        tools: [echoTool()],
        requireHitl: true,
      );

      final events = <FmAgentEvent>[];
      late String interruptId;
      final sub = agent.run(input: 'hitl please').listen((e) {
        events.add(e);
        if (e is FmAgentInterruptEvent) {
          interruptId = e.interruptId;
          // Resume asynchronously so the agent loop can await the waiter.
          Future<void>.microtask(() {
            agent.resumeInterrupt(
              interruptId: interruptId,
              decision: FmInterruptDecision.approve,
            );
          });
        }
      });
      await sub.asFuture<void>();

      expect(events.whereType<FmAgentInterruptEvent>(), hasLength(1));
      expect(events.whereType<FmAgentToolCallStart>(), isNotEmpty);
      expect(events.whereType<FmAgentToolCallEnd>(), isNotEmpty);
      expect(events.last, isA<FmAgentRunFinished>());

      expect(MockProvider.submittedToolResults, hasLength(1));
      expect(
        MockProvider.submittedToolResults.single['output'],
        'agent-echo:hitl please',
      );
    });

    test('autoExecuteTools true alone submits once; agent does not double',
        () async {
      // Guard: default stream path (runtime owns execution) submits once.
      final fm = await createFoundationModels();
      MockProvider.submittedToolResults.clear();
      await fm
          .stream(
            input: 'runtime owns',
            tools: [echoTool()],
            autoExecuteTools: true,
          )
          .toList();
      await Future<void>.delayed(Duration.zero);
      expect(MockProvider.submittedToolResults, hasLength(1));
      expect(
        MockProvider.submittedToolResults.single['output'],
        'agent-echo:runtime owns',
      );

      // Agent path with same tool must still be exactly one (not runtime+agent).
      MockProvider.submittedToolResults.clear();
      final agent = FmAgent(fm: fm, tools: [echoTool()]);
      await agent.run(input: 'agent owns').toList();
      expect(MockProvider.submittedToolResults, hasLength(1));
      expect(
        MockProvider.submittedToolResults.single['output'],
        'agent-echo:agent owns',
      );
    });
  });
}
