import 'package:foundationmodels/foundationmodels.dart';
import 'package:test/test.dart';

void main() {
  group('streaming', () {
    test('emits the full event lifecycle and ends with done', () async {
      final fm = await createFoundationModels();
      final events = await fm.stream(input: 'hello').toList();
      expect(events.first, isA<RunStarted>());
      expect(events[1], isA<MessageStart>());
      expect(events.whereType<TextDelta>(), isNotEmpty);
      expect(events[events.length - 2], isA<MessageEnd>());
      expect(events.last, isA<StreamDone>());
      // requestId correlates every event of the stream.
      expect(events.map((e) => e.requestId).toSet(), hasLength(1));
    });

    test('guided output streams structured deltas', () async {
      final fm = await createFoundationModels();
      final events = await fm
          .stream(
            input: 'x',
            schema: FmSchema.object({'city': FmSchema.string()}),
          )
          .toList();
      expect(events.whereType<StructuredDelta>(), isNotEmpty);
      expect(events.whereType<TextDelta>(), isEmpty);
    });

    test('cancel token terminates the stream with typed cancellation',
        () async {
      final fm = await createFoundationModels(
        providers: [const MockProvider(chunkDelay: Duration(milliseconds: 20))],
      );
      final source = CancelTokenSource();
      final errors = <Object>[];
      final done = fm
          .stream(input: 'a reasonably long input to chunk', cancelToken: source.token)
          .listen(null, onError: errors.add);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      source.cancel();
      await done.asFuture<void>().catchError((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(errors, contains(isA<GenerationCancelledException>()));
    });

    test('cancelling the subscription is an implicit cancel (no hang)',
        () async {
      final fm = await createFoundationModels(
        providers: [const MockProvider(chunkDelay: Duration(milliseconds: 20))],
      );
      final subscription = fm.stream(input: 'chunky input text here').listen(null);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await subscription.cancel(); // must complete, not hang.
    });
  });
}
