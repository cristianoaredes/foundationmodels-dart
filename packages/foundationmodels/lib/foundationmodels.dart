/// Dart API for Apple Foundation Models — port of `@orqo/foundationmodels`
/// (ADR-0001, phase 1).
///
/// ```dart
/// import 'package:foundationmodels/foundationmodels.dart';
///
/// final fm = await createFoundationModels(); // mock determinístico em CI
/// final cls = await fm.classify(input: 'I love it', labels: ['positive', 'negative']);
/// final out = await fm.extract(
///   input: 'Paris is in France.',
///   schema: FmSchema.object({'city': FmSchema.string(), 'country': FmSchema.string()}),
/// );
/// final session = await fm.createSession(instructions: 'Answer concisely.');
/// await for (final event in session.stream(input: 'One sentence on on-device AI.')) {
///   if (event is TextDelta) stdout.write(event.delta);
/// }
/// await session.dispose();
/// ```
///
/// Pure Dart: no Flutter, no IO; the mock provider never touches the network.
library;

export 'package:foundationmodels_platform_interface/foundationmodels_platform_interface.dart';

export 'src/cancel.dart';
export 'src/context_policy.dart';
export 'src/mock/mock_provider.dart';
export 'src/options.dart';
export 'src/provider.dart';
export 'src/runtime.dart';
export 'src/schema.dart';
export 'src/security.dart';
export 'src/session.dart';
export 'src/tools.dart';
export 'src/transport_provider.dart';
