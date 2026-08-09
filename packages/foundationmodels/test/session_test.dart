import 'package:foundationmodels/foundationmodels.dart';
import 'package:test/test.dart';

void main() {
  group('FmSession (lazy semantics)', () {
    test('createSession mints a local id without materializing natively',
        () async {
      final fm = await createFoundationModels();
      final session = await fm.createSession(instructions: 'Be concise.');
      expect(session.id, startsWith('ses_'));
      expect(session.isMaterialized, isFalse);
      expect(session.isDisposed, isFalse);
      expect(session.instructions, 'Be concise.');
    });

    test('first respond materializes the native session', () async {
      final fm = await createFoundationModels();
      final session = await fm.createSession(instructions: 'Be concise.');
      await session.respond(input: 'hi');
      expect(session.isMaterialized, isTrue);
    });

    test('first stream materializes the native session', () async {
      final fm = await createFoundationModels();
      final session = await fm.createSession();
      await session.stream(input: 'hi').toList();
      expect(session.isMaterialized, isTrue);
    });

    test('transition on an unmaterialized session only updates local state',
        () async {
      final fm = await createFoundationModels();
      final session = await fm.createSession(instructions: 'A');
      await session.transition(instructions: 'B');
      expect(session.instructions, 'B');
      expect(session.isMaterialized, isFalse); // no native call happened.
    });

    test('transition after materialization preserves the session', () async {
      final fm = await createFoundationModels();
      final session = await fm.createSession(instructions: 'A');
      await session.respond(input: 'hi');
      await session.transition(instructions: 'B');
      expect(session.instructions, 'B');
      await session.respond(input: 'again'); // still usable.
    });

    test('dispose drops the session and blocks further use', () async {
      final fm = await createFoundationModels();
      final session = await fm.createSession();
      await session.respond(input: 'hi');
      await session.dispose();
      expect(session.isDisposed, isTrue);
      expect(() => session.respond(input: 'x'), throwsStateError);
      expect(() => session.stream(input: 'x'), throwsStateError);
    });

    test('dispose is idempotent and works before materialization', () async {
      final fm = await createFoundationModels();
      final session = await fm.createSession();
      await session.dispose();
      await session.dispose(); // no-op.
      expect(session.isDisposed, isTrue);
    });
  });
}
