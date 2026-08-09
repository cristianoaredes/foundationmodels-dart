import 'dart:async';

import 'package:foundationmodels/foundationmodels.dart';
import 'package:test/test.dart';

/// Scriptable fake transport: records envelopes, replays configured
/// results/errors and pushes stream events.
class FakeTransport implements FoundationModelsTransport {
  final List<Map<String, Object?>> envelopes = [];
  final StreamController<Map<String, Object?>> _events =
      StreamController<Map<String, Object?>>.broadcast();

  Object? Function(Map<String, Object?> envelope)? onInvoke;

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> envelope) async {
    envelopes.add(envelope);
    final outcome = onInvoke?.call(envelope);
    if (outcome is Exception) throw outcome;
    if (outcome is Map<String, Object?>) return outcome;
    return const {};
  }

  @override
  Stream<Map<String, Object?>> get streamEvents => _events.stream;

  void pushEvent(Map<String, Object?> event) => _events.add(event);
}

void main() {
  group('TransportProvider — unary error mapping (end to end)', () {
    test('transport error maps via error.data.code to the typed exception',
        () async {
      final transport = FakeTransport()
        ..onInvoke = (_) => const FmTransportError(
              code: -32000,
              message: 'slow down',
              data: {'code': 'RATE_LIMITED', 'resetDate': '2026-08-10T00:00:00Z'},
            );
      final fm =
          await createFoundationModels(providers: [TransportProvider(transport)]);
      expect(
        () => fm.respond(input: 'hi'),
        throwsA(isA<RateLimitedException>()
            .having((e) => e.resetDate, 'resetDate', '2026-08-10T00:00:00Z')
            .having((e) => e.isRetryable, 'isRetryable', isTrue)),
      );
    });

    test('numeric code is ignored; only the stable string maps', () async {
      final transport = FakeTransport()
        ..onInvoke = (_) => const FmTransportError(
              code: 12345,
              message: 'guardrail',
              data: {'code': 'GUARDRAIL_VIOLATION'},
            );
      final provider = TransportProvider(transport);
      expect(
        () => provider.respond(const FmRequest(id: 'rpc_1', input: 'x')),
        throwsA(isA<GuardrailViolationException>()
            .having((e) => e.isRetryable, 'isRetryable', isFalse)),
      );
    });

    test('missing stable code falls back to UnknownModelException', () async {
      final transport = FakeTransport()
        ..onInvoke = (_) =>
            const FmTransportError(message: 'native crash', data: null);
      final provider = TransportProvider(transport);
      expect(
        () => provider.respond(const FmRequest(id: 'rpc_1', input: 'x')),
        throwsA(isA<UnknownModelException>()
            .having((e) => e.code, 'code', 'UNKNOWN_MODEL_ERROR')),
      );
    });

    test('apple model unavailable carries reasonCode', () async {
      final transport = FakeTransport()
        ..onInvoke = (_) => const FmTransportError(
              message: 'unavailable',
              data: {
                'code': 'APPLE_MODEL_UNAVAILABLE',
                'reasonCode': 'apple_intelligence_not_enabled',
              },
            );
      final provider = TransportProvider(transport);
      expect(
        () => provider.respond(const FmRequest(id: 'rpc_1', input: 'x')),
        throwsA(isA<AppleModelUnavailableException>().having(
            (e) => e.reasonCode, 'reasonCode', 'apple_intelligence_not_enabled')),
      );
    });
  });

  group('TransportProvider — envelope shape', () {
    test('respond sends the protocol v2 envelope and parses the result',
        () async {
      final transport = FakeTransport()
        ..onInvoke = (envelope) => {
              'content': 'Hello from Swift',
              'usage': {'inputTokens': 2, 'outputTokens': 3, 'estimated': false},
            };
      final provider = TransportProvider(transport);
      final response = await provider.respond(FmRequest(
        id: 'rpc_env',
        input: 'Hi',
        options: const GenerationOptions(temperature: 0.2),
        schema: FmSchema.object({'ok': FmSchema.boolean()}),
      ));

      final envelope = transport.envelopes.single;
      expect(envelope['id'], 'rpc_env');
      expect(envelope['method'], 'foundationmodels.sessions.respond');
      final params = envelope['params']! as Map<String, Object?>;
      expect(params['model'], 'apple.system');
      expect(params['input'], [
        {'type': 'text', 'text': 'Hi'},
      ]);
      expect((params['options']! as Map)['temperature'], 0.2);
      expect(params['responseFormat'], isA<Map<String, Object?>>());

      expect(response.requestId, 'rpc_env');
      expect(response.text, 'Hello from Swift');
      expect(response.usage?.estimated, isFalse);
      expect(response.usage?.totalTokens, 5);
    });

    test('cancelGeneration sends generation.cancel with generationId', () async {
      final transport = FakeTransport();
      await TransportProvider(transport).cancelGeneration('rpc_gen');
      final envelope = transport.envelopes.single;
      expect(envelope['method'], 'foundationmodels.generation.cancel');
      expect((envelope['params']! as Map)['generationId'], 'rpc_gen');
    });
  });

  group('TransportProvider — streaming (end to end)', () {
    test('demultiplexes events by requestId and maps error events', () async {
      final transport = FakeTransport();
      final fm =
          await createFoundationModels(providers: [TransportProvider(transport)]);
      final session = await fm.createSession();

      final events = <FmStreamEvent>[];
      final errors = <Object>[];
      final done = Completer<void>();
      session.stream(input: 'hi').listen(events.add,
          onError: errors.add, onDone: done.complete);

      // Wait for the stream-start invoke so we know the requestId.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final startEnvelope = transport.envelopes.singleWhere(
          (e) => e['method'] == 'foundationmodels.sessions.stream');
      final requestId = startEnvelope['id']! as String;

      // Foreign event for another request is ignored.
      transport.pushEvent(
          {'type': 'text_delta', 'requestId': 'rpc_other', 'delta': 'noise'});
      transport.pushEvent(
          {'type': 'text_delta', 'requestId': requestId, 'delta': 'Hel'});
      transport.pushEvent({
        'type': 'error',
        'requestId': requestId,
        'code': 'SESSION_BUSY',
        'message': 'session busy',
      });
      await done.future;

      expect(events, hasLength(1));
      expect((events.single as TextDelta).delta, 'Hel');
      expect(errors.single, isA<SessionBusyException>());
      expect((errors.single as FoundationModelsException).isRetryable, isTrue);
    });

    test('successful stream ends at done', () async {
      final transport = FakeTransport();
      final provider = TransportProvider(transport);
      final events = <FmStreamEvent>[];
      final done = Completer<void>();
      provider.stream(const FmRequest(id: 'rpc_s', input: 'x')).listen(
            events.add,
            onDone: done.complete,
          );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      transport
        ..pushEvent(
            {'type': 'run_started', 'requestId': 'rpc_s', 'sessionId': 'ses_1'})
        ..pushEvent(
            {'type': 'text_delta', 'requestId': 'rpc_s', 'delta': 'Hi'})
        ..pushEvent({'type': 'done', 'requestId': 'rpc_s'});
      await done.future;
      expect(events.map((e) => e.type), ['run_started', 'text_delta', 'done']);
      expect(events.first.sessionId, 'ses_1');
    });
  });
}
