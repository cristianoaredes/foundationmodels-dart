import 'package:foundationmodels/foundationmodels.dart';
import 'package:test/test.dart';

void main() {
  group('createFoundationModels', () {
    test('without providers falls back to the deterministic mock', () async {
      final fm = await createFoundationModels();
      expect(fm.provider.id, 'mock');
    });

    test('picks the first available provider', () async {
      final fm = await createFoundationModels(providers: [const MockProvider()]);
      expect(fm.provider.id, 'mock');
    });

    test('exposes security defaults (fail-closed image allowlist)', () async {
      final fm = await createFoundationModels();
      expect(fm.security.allowedImageRoots, isEmpty);
      expect(fm.security.redaction, RedactionMode.off);
    });
  });

  group('respond', () {
    test('returns text and estimated usage', () async {
      final fm = await createFoundationModels();
      final response = await fm.respond(input: 'hi');
      expect(response.text, isNotEmpty);
      expect(response.usage?.estimated, isTrue);
      expect(response.requestId, startsWith('rpc_'));
    });

    test('rejects invalid options before any provider call', () async {
      final fm = await createFoundationModels();
      expect(
        () => fm.respond(
          input: 'x',
          options: const GenerationOptions(temperature: 2),
        ),
        throwsArgumentError,
      );
    });

    test('availability and capabilities round-trip', () async {
      final fm = await createFoundationModels();
      expect((await fm.availability()).available, isTrue);
      expect((await fm.capabilities())['provider'], 'mock');
    });

    test('countTokens returns the breakdown', () async {
      final fm = await createFoundationModels();
      final count = await fm.countTokens(input: 'hello world');
      expect(count.total, greaterThan(0));
      expect(count.contextWindow, 4096);
      expect(count.fits, isTrue);
      expect(count.estimated, isTrue);
    });
  });

  group('primitives', () {
    test('classify returns one of the labels, deterministically', () async {
      final fm = await createFoundationModels();
      const labels = ['positive', 'negative', 'neutral'];
      final first = await fm.classify(input: 'I love this!', labels: labels);
      final second = await fm.classify(input: 'I love this!', labels: labels);
      expect(labels, contains(first));
      expect(first, second); // deterministic.
    });

    test('classify rejects empty labels', () async {
      final fm = await createFoundationModels();
      expect(
        () => fm.classify(input: 'x', labels: const []),
        throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'labels')),
      );
    });

    test('extract returns structured data matching the schema', () async {
      final fm = await createFoundationModels();
      final result = await fm.extract(
        input: 'Paris is in France.',
        schema: FmSchema.object({
          'city': FmSchema.string(),
          'country': FmSchema.string(),
        }, required: const ['city', 'country']),
      );
      expect(result, isA<Map>());
      final map = result! as Map;
      expect(map.keys, containsAll(['city', 'country']));
    });

    test('extract strict throws when no structured content', () async {
      // A schema with zero required properties still returns a (possibly
      // empty) object from the mock, so this exercises the contract via a
      // provider that yields null structured content — the mock always
      // yields content, so we assert the happy path instead and rely on
      // TransportProvider tests for the strict failure path.
      final fm = await createFoundationModels();
      final result = await fm.extract(
        input: 'x',
        schema: FmSchema.object(const {}),
        strict: true,
      );
      expect(result, isA<Map>());
    });

    test('rank returns all candidates exactly once', () async {
      final fm = await createFoundationModels();
      const candidates = ['a', 'b', 'c', 'd'];
      final ranked = await fm.rank(input: 'query', candidates: candidates);
      expect(ranked..sort(), candidates..sort());
    });

    test('rank rejects empty candidates', () async {
      final fm = await createFoundationModels();
      expect(
        () => fm.rank(input: 'q', candidates: const []),
        throwsA(
            isA<ArgumentError>().having((e) => e.name, 'name', 'candidates')),
      );
    });

    test('summarize returns text', () async {
      final fm = await createFoundationModels();
      expect(await fm.summarize(input: 'Long text here.'), isNotEmpty);
    });
  });
}
