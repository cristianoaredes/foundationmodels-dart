import 'package:foundationmodels/foundationmodels.dart';
import 'package:test/test.dart';

void main() {
  group('GenerationOptions.validate', () {
    test('defaults pass', () {
      GenerationOptions.defaults.validate();
    });

    test('temperature within [0,1] passes; outside throws naming the field',
        () {
      const GenerationOptions(temperature: 0.0).validate();
      const GenerationOptions(temperature: 1.0).validate();
      expect(
        () => const GenerationOptions(temperature: -0.1).validate(),
        throwsA(isA<ArgumentError>()
            .having((e) => e.name, 'name', 'temperature')),
      );
      expect(
        () => const GenerationOptions(temperature: 1.1).validate(),
        throwsA(isA<ArgumentError>()
            .having((e) => e.name, 'name', 'temperature')),
      );
    });

    test('maximumResponseTokens must be positive', () {
      const GenerationOptions(maximumResponseTokens: 1).validate();
      expect(
        () => const GenerationOptions(maximumResponseTokens: 0).validate(),
        throwsA(isA<ArgumentError>()
            .having((e) => e.name, 'name', 'maximumResponseTokens')),
      );
      expect(
        () => const GenerationOptions(maximumResponseTokens: -5).validate(),
        throwsArgumentError,
      );
    });

    test('greedy sampling with negative seed throws naming sampling.seed',
        () {
      const GenerationOptions(sampling: GreedySampling(seed: 1)).validate();
      expect(
        () => const GenerationOptions(sampling: GreedySampling(seed: -1))
            .validate(),
        throwsA(isA<ArgumentError>()
            .having((e) => e.name, 'name', 'sampling.seed')),
      );
    });

    test('top_k requires topK > 0', () {
      const TopKSampling(topK: 1).validate();
      expect(() => const TopKSampling(topK: 0).validate(),
          throwsA(isA<ArgumentError>()
              .having((e) => e.name, 'name', 'sampling.topK')));
    });

    test('top_p requires probabilityThreshold in (0,1]', () {
      const TopPSampling(probabilityThreshold: 1.0).validate();
      const TopPSampling(probabilityThreshold: 0.5).validate();
      expect(
        () => const TopPSampling(probabilityThreshold: 0).validate(),
        throwsA(isA<ArgumentError>().having(
            (e) => e.name, 'name', 'sampling.probabilityThreshold')),
      );
      expect(
        () => const TopPSampling(probabilityThreshold: 1.5).validate(),
        throwsArgumentError,
      );
    });

    test('serialization omits absent fields', () {
      expect(GenerationOptions.defaults.toJson(), isEmpty);
      expect(
        const GenerationOptions(
          temperature: 0.5,
          maximumResponseTokens: 100,
          sampling: TopKSampling(topK: 40, seed: 7),
        ).toJson(),
        {
          'temperature': 0.5,
          'maximumResponseTokens': 100,
          'sampling': {'mode': 'top_k', 'seed': 7, 'topK': 40},
        },
      );
      expect(const GreedySampling().toJson(), {'mode': 'greedy'});
      expect(
        const TopPSampling(probabilityThreshold: 0.9).toJson(),
        {'mode': 'top_p', 'probabilityThreshold': 0.9},
      );
    });
  });
}
