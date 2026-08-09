import 'package:foundationmodels/foundationmodels.dart';
import 'package:test/test.dart';

void main() {
  group('MockProvider', () {
    const provider = MockProvider();

    test('is deterministic: same input → same output', () async {
      final a = await provider.respond(const FmRequest(id: 'rpc_1', input: 'hello'));
      final b = await provider.respond(const FmRequest(id: 'rpc_2', input: 'hello'));
      expect(a.text, b.text);
    });

    test('usage is always flagged as estimated', () async {
      final response =
          await provider.respond(const FmRequest(id: 'rpc_1', input: 'hello'));
      expect(response.usage?.estimated, isTrue);
    });

    test('availability is available with the mock feature set', () async {
      final report = await provider.availability();
      expect(report.available, isTrue);
      expect(report.supports('streaming'), isTrue);
      expect(report.supports('vision'), isFalse);
    });

    test('countTokens breakdown is coherent and estimated', () async {
      final count = await provider.countTokens(
        const FmCountTokensRequest(input: 'hello world', instructions: 'sys'),
      );
      expect(count.total, count.input + count.instructions + count.schema);
      expect(count.remaining, count.contextWindow - count.total);
      expect(count.estimated, isTrue);
    });

    test('enum strings pick a deterministic label', () async {
      final schema = FmSchema.object({
        'label': FmSchema.string(enumValues: ['a', 'b', 'c']),
      }, required: const ['label']);
      final response = await provider
          .respond(FmRequest(id: 'rpc_1', input: 'x', schema: schema));
      final structured = response.structured! as Map;
      expect(['a', 'b', 'c'], contains(structured['label']));
    });

    test('arrays respect minItems', () async {
      final schema = FmSchema.object({
        'items': FmSchema.array(FmSchema.string(), minItems: 3),
      }, required: const ['items']);
      final response = await provider
          .respond(FmRequest(id: 'rpc_1', input: 'x', schema: schema));
      final items = (response.structured! as Map)['items']! as List;
      expect(items, hasLength(3));
    });

    test('streaming is deterministic and chunk-bounded', () async {
      final events = await provider
          .stream(const FmRequest(id: 'rpc_s', input: 'hello'))
          .toList();
      final deltas = events.whereType<TextDelta>().map((e) => e.delta).join();
      final again = await provider
          .stream(const FmRequest(id: 'rpc_s', input: 'hello'))
          .toList();
      expect(deltas, again.whereType<TextDelta>().map((e) => e.delta).join());
      expect(events.last, isA<StreamDone>());
    });

    test('cancel and dispose are idempotent no-ops', () async {
      await provider.cancelGeneration('rpc_x');
      await provider.cancelGeneration('rpc_x');
      await provider.disposeSession('ses_x');
      await provider.transitionSession(sessionId: 'ses_x', instructions: 'y');
    });
  });
}
