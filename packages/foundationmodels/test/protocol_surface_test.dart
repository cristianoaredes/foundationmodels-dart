import 'dart:async';

import 'package:foundationmodels/foundationmodels.dart';
import 'package:test/test.dart';

/// Contract tests: every protocol-mapping.md method that maps to a public
/// Dart API is reachable end-to-end through the **shipped** mock provider
/// (or throws the honest typed unavailable / unsupported error).
void main() {
  group('protocol surface via createFoundationModels (mock)', () {
    late FoundationModels fm;

    setUp(() async {
      fm = await createFoundationModels();
    });

    test('health', () async {
      final h = await fm.health();
      expect(h['provider'], 'mock');
      expect(h['ok'], isTrue);
    });

    test('availability', () async {
      final a = await fm.availability();
      expect(a.available, isTrue);
    });

    test('capabilities', () async {
      final c = await fm.capabilities();
      expect(c['provider'], 'mock');
    });

    test('countTokens', () async {
      final t = await fm.countTokens(input: 'hello world');
      expect(t.total, greaterThan(0));
      expect(t.estimated, isTrue);
    });

    test('sessions.create + respond + dispose', () async {
      final session = await fm.createSession(instructions: 'Be brief.');
      final response = await session.respond(input: 'Hi');
      expect(response.text, isNotNull);
      await session.dispose();
    });

    test('sessions.stream ends with done', () async {
      final events = await fm.stream(input: 'stream me').toList();
      expect(events.last, isA<StreamDone>());
    });

    test('generation.cancel via CancelToken', () async {
      final fmSlow = await createFoundationModels(
        providers: [const MockProvider(chunkDelay: Duration(milliseconds: 30))],
      );
      final source = CancelTokenSource();
      final errors = <Object>[];
      final finished = Completer<void>();
      fmSlow
          .stream(
            input: 'long enough to cancel mid-stream cancel token path',
            cancelToken: source.token,
          )
          .listen(
            null,
            onError: (Object e, StackTrace _) {
              errors.add(e);
              if (!finished.isCompleted) finished.complete();
            },
            onDone: () {
              if (!finished.isCompleted) finished.complete();
            },
          );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      source.cancel();
      await finished.future.timeout(const Duration(seconds: 2));
      expect(errors, contains(isA<GenerationCancelledException>()));
    });

    test('sessions.transition + prewarm', () async {
      final session = await fm.createSession(instructions: 'A');
      await session.transition(instructions: 'B');
      expect(session.instructions, 'B');
      final warm = await session.prewarm();
      expect(warm['warmed'], isTrue);
      await session.dispose();
    });

    test('vision.ocr is honest unavailable on mock', () async {
      expect(
        () => fm.visionOcr(image: {
          'base64': 'AAAA',
          'mimeType': 'image/png',
        }),
        throwsA(isA<VisionOcrUnavailableException>()),
      );
    });

    test('vision.barcode is honest unavailable on mock', () async {
      expect(
        () => fm.visionBarcode(image: {
          'base64': 'AAAA',
          'mimeType': 'image/png',
        }),
        throwsA(isA<VisionBarcodeUnavailableException>()),
      );
    });

    test('feedback.logAttachment accepted on mock', () async {
      final r = await fm.logFeedbackAttachment(
        generationId: 'rpc_1',
        sentiment: 'up',
      );
      expect(r['ok'], isTrue);
      expect(r['recorded'], isTrue);
    });

    test('tools.result is accepted on mock (duplex path)', () async {
      final r = await fm.submitToolResult(toolCallId: 'tool_1', output: 'x');
      expect(r['ok'], isTrue);
      expect(r['accepted'], isTrue);
    });

    test('path image rejected without allowedImageRoots', () async {
      final secured = await createFoundationModels(
        security: const SecurityConfig(allowedImageRoots: []),
      );
      expect(
        () => secured.visionOcr(image: {'path': '/tmp/x.png'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('TransportProvider protocol envelopes', () {
    test('health / prewarm / vision / feedback / tools envelopes', () async {
      final transport = FakeTransport()
        ..onInvoke = (envelope) {
          final method = envelope['method'] as String?;
          if (method == 'foundationmodels.availability') {
            return const <String, Object?>{
              'available': true,
              'features': <String, Object?>{},
            };
          }
          return {'ok': true, 'method': method};
        };
      final fm = await createFoundationModels(
        providers: [TransportProvider(transport)],
      );
      await fm.health();
      await fm.visionOcr(image: {
        'base64': 'qq',
        'mimeType': 'image/png',
      });
      await fm.visionBarcode(image: {
        'base64': 'qq',
        'mimeType': 'image/png',
      });
      await fm.logFeedbackAttachment(
        sessionId: 'ses_1',
        generationId: 'g1',
        sentiment: 'down',
      );
      await fm.submitToolResult(toolCallId: 't1', output: {'v': 1});
      final session = await fm.createSession();
      await session.prewarm(model: 'apple.system');

      // Vision wire is Core-shaped (top-level base64), not nested image.
      final visionEnvelopes = transport.envelopes.where(
        (e) => (e['method'] as String).startsWith('foundationmodels.vision.'),
      );
      for (final e in visionEnvelopes) {
        final params = e['params']! as Map;
        expect(params['base64'], 'qq');
        expect(params['mimeType'], 'image/png');
        expect(params.containsKey('image'), isFalse);
      }
      final feedback = transport.envelopes.firstWhere(
        (e) => e['method'] == 'foundationmodels.feedback.logAttachment',
      );
      expect((feedback['params']! as Map)['sessionId'], 'ses_1');

      final methods = transport.envelopes
          .map((e) => e['method'] as String)
          .where((m) => m != 'foundationmodels.availability')
          .toSet();
      expect(
        methods,
        containsAll([
          'foundationmodels.health',
          'foundationmodels.vision.ocr',
          'foundationmodels.vision.barcode',
          'foundationmodels.feedback.logAttachment',
          'foundationmodels.tools.result',
          'foundationmodels.sessions.prewarm',
        ]),
      );
    });
  });
}

class FakeTransport implements FoundationModelsTransport {
  final List<Map<String, Object?>> envelopes = [];
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
  Stream<Map<String, Object?>> get streamEvents => const Stream.empty();
}
