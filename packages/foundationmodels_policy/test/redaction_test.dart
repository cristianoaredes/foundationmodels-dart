import 'package:foundationmodels_policy/foundationmodels_policy.dart';
import 'package:test/test.dart';

void main() {
  test('auto redacts email and phone', () {
    const policy = FmRedactionPolicy(mode: PolicyRedactionMode.auto);
    final r = policy.apply('Contact me@example.com or +1 (555) 123-4567');
    expect(r.text, contains('[REDACTED_EMAIL]'));
    expect(r.text, contains('[REDACTED_PHONE]'));
    expect(r.audit.map((a) => a.kind), containsAll(['email', 'phone']));
  });

  test('logOnly audits without mutating', () {
    const policy = FmRedactionPolicy(mode: PolicyRedactionMode.logOnly);
    const input = 'mail a@b.co';
    final r = policy.apply(input);
    expect(r.text, input);
    expect(r.audit.single.kind, 'email');
  });

  test('off is a no-op', () {
    const policy = FmRedactionPolicy();
    final r = policy.apply('a@b.co');
    expect(r.text, 'a@b.co');
    expect(r.audit, isEmpty);
  });
}
