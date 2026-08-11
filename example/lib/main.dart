import 'package:foundationmodels/foundationmodels.dart';

/// Unary-first demo (pre-U1 / mock path).
///
/// ```sh
/// cd example && dart run
/// ```
Future<void> main() async {
  final fm = await createFoundationModels(); // mock offline by default
  print('provider=${fm.provider.id}');
  final health = await fm.health();
  print('health=$health');
  final avail = await fm.availability();
  print('available=${avail.available}');

  // Unary respond — the only generation path until U1 lands on device.
  final response = await fm.respond(
    input: 'Say hello from on-device AI.',
    instructions: 'Answer in one short sentence.',
  );
  print('respond: ${response.text}');

  final session = await fm.createSession(instructions: 'Be concise.');
  final again = await session.respond(input: 'Name one benefit of on-device models.');
  print('session.respond: ${again.text}');
  await session.dispose();
}
