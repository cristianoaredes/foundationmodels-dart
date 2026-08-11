import 'package:foundationmodels/foundationmodels.dart';
import 'package:test/test.dart';

void main() {
  test('unary-first path works with mock provider', () async {
    final fm = await createFoundationModels();
    expect(fm.provider.id, 'mock');
    final r = await fm.respond(input: 'hello');
    expect(r.text, isNotEmpty);
  });
}
