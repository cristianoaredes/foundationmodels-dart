import 'package:foundationmodels/foundationmodels.dart';
import 'package:foundationmodels_langchain/foundationmodels_langchain.dart';
import 'package:test/test.dart';

void main() {
  test('invoke returns assistant text via mock', () async {
    final fm = await createFoundationModels();
    final chat = ChatFoundationModels(fm);
    final result = await chat.invoke([
      const LcChatMessage(role: 'system', content: 'Be short.'),
      const LcChatMessage(role: 'human', content: 'Hello'),
    ]);
    expect(result.content, isNotEmpty);
  });

  test('stream yields text deltas', () async {
    final fm = await createFoundationModels();
    final chat = ChatFoundationModels(fm);
    final chunks = await chat.stream([
      const LcChatMessage(role: 'human', content: 'stream please'),
    ]).toList();
    expect(chunks, isNotEmpty);
  });

  test('extractStructured uses fm.extract', () async {
    final fm = await createFoundationModels();
    final chat = ChatFoundationModels(fm);
    final out = await chat.extractStructured(
      input: 'Paris is in France',
      schema: FmSchema.object({
        'city': FmSchema.string(),
      }, required: const ['city']),
    );
    expect(out, isA<Map>());
  });
}
