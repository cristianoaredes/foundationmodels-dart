import 'package:foundationmodels/foundationmodels.dart';
import 'package:foundationmodels_eval/foundationmodels_eval.dart';
import 'package:test/test.dart';

void main() {
  test('harness runs classify cases against mock', () async {
    final fm = await createFoundationModels();
    final sink = FmTraceSink();
    final harness = FmEvalHarness(fm, traceSink: sink);
    final report = await harness.run([
      const FmEvalCase(
        id: 'c1',
        input: 'I love it',
        labels: ['positive', 'negative'],
      ),
      const FmEvalCase(
        id: 'c2',
        input: 'hello',
        expectContains: 'echo',
      ),
    ]);
    expect(report.results, hasLength(2));
    expect(report.passed, greaterThanOrEqualTo(1));
    expect(sink.records, isNotEmpty);
  });
}
