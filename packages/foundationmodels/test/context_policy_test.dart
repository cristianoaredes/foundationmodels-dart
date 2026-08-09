import 'package:foundationmodels/foundationmodels.dart';
import 'package:test/test.dart';

void main() {
  group('ContextPolicy', () {
    test('none is the default and performs no preflight', () async {
      final fm = await createFoundationModels();
      expect(fm.contextPolicy.mode, ContextPolicyMode.none);
      expect(fm.contextPolicy.performsPreflight, isFalse);
    });

    test('guard performs a preflight countTokens and fits pass', () async {
      final fm = await createFoundationModels(
        contextPolicy: ContextPolicy.guard,
      );
      // Mock context window is 4096; a small input fits.
      final response = await fm.respond(input: 'short');
      expect(response.text, isNotNull);
    });

    test('guard throws ContextOverflowException locally on overflow', () async {
      final fm = await createFoundationModels(
        contextPolicy: ContextPolicy.guard,
      );
      final huge = 'x' * (4096 * 8); // ~8192 estimated tokens > 4096 window.
      expect(
        () => fm.respond(input: huge),
        throwsA(isA<ContextOverflowException>()
            .having((e) => e.contextSize, 'contextSize', 4096)
            .having((e) => e.tokenCount, 'tokenCount', greaterThan(4096))
            .having((e) => e.details, 'details', isNotNull)),
      );
    });

    test('compact is a documented stub behaving like guard', () async {
      final fm = await createFoundationModels(
        contextPolicy: ContextPolicy.compact,
      );
      expect(fm.contextPolicy.performsPreflight, isTrue);
      final huge = 'x' * (4096 * 8);
      expect(
        () => fm.respond(input: huge),
        throwsA(isA<ContextOverflowException>()),
      );
    });
  });
}
