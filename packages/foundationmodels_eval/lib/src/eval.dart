import 'package:foundationmodels/foundationmodels.dart';

import 'trace.dart';

/// One eval case: input + optional expected substring / classifier label.
class FmEvalCase {
  /// Creates a case.
  const FmEvalCase({
    required this.id,
    required this.input,
    this.expectContains,
    this.expectLabel,
    this.labels,
  });

  final String id;
  final String input;
  final String? expectContains;
  final String? expectLabel;
  final List<String>? labels;
}

/// Result of running one [FmEvalCase].
class FmEvalCaseResult {
  const FmEvalCaseResult({
    required this.caseId,
    required this.passed,
    required this.output,
    this.reason,
  });

  final String caseId;
  final bool passed;
  final String output;
  final String? reason;
}

/// Aggregate eval report.
class FmEvalReport {
  const FmEvalReport({
    required this.results,
    required this.passed,
    required this.failed,
  });

  final List<FmEvalCaseResult> results;
  final int passed;
  final int failed;

  double get passRate =>
      results.isEmpty ? 0 : passed / results.length;
}

/// Runs [cases] against [fm], optionally recording traces.
class FmEvalHarness {
  /// Creates a harness.
  const FmEvalHarness(this.fm, {this.traceSink});

  final FoundationModels fm;
  final FmTraceSink? traceSink;

  /// Runs all cases sequentially.
  Future<FmEvalReport> run(List<FmEvalCase> cases) async {
    final results = <FmEvalCaseResult>[];
    for (final c in cases) {
      results.add(await _runOne(c));
    }
    final passed = results.where((r) => r.passed).length;
    return FmEvalReport(
      results: results,
      passed: passed,
      failed: results.length - passed,
    );
  }

  Future<FmEvalCaseResult> _runOne(FmEvalCase c) async {
    final started = DateTime.now().toUtc();
    try {
      String output;
      if (c.labels != null && c.labels!.isNotEmpty) {
        output = await fm.classify(input: c.input, labels: c.labels!);
      } else {
        final response = await fm.respond(input: c.input);
        output = response.text ?? '';
        traceSink?.add(FmTraceRecord(
          traceId: response.traceId ?? 'trc_${c.id}',
          requestId: response.requestId,
          input: c.input,
          output: output,
          usage: response.usage?.toMap(),
          startedAt: started,
          endedAt: DateTime.now().toUtc(),
        ));
      }

      if (c.expectLabel != null && output != c.expectLabel) {
        return FmEvalCaseResult(
          caseId: c.id,
          passed: false,
          output: output,
          reason: 'expected label ${c.expectLabel}',
        );
      }
      if (c.expectContains != null && !output.contains(c.expectContains!)) {
        return FmEvalCaseResult(
          caseId: c.id,
          passed: false,
          output: output,
          reason: 'expected to contain ${c.expectContains}',
        );
      }
      return FmEvalCaseResult(caseId: c.id, passed: true, output: output);
    } catch (e) {
      return FmEvalCaseResult(
        caseId: c.id,
        passed: false,
        output: '',
        reason: e.toString(),
      );
    }
  }
}
