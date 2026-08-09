import 'package:foundationmodels_platform_interface/foundationmodels_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  group('AvailabilityReport', () {
    test('parses available report with features', () {
      final report = AvailabilityReport.fromMap({
        'available': true,
        'features': {'streaming': true, 'vision': false},
      });
      expect(report.available, isTrue);
      expect(report.reasonCode, isNull);
      expect(report.supports('streaming'), isTrue);
      expect(report.supports('vision'), isFalse);
      expect(report.supports('nonexistent'), isFalse);
    });

    test('parses unavailable report with stable reasonCode', () {
      final report = AvailabilityReport.fromMap({
        'available': false,
        'reasonCode': 'device_not_eligible',
        'reason': 'Requires Apple Silicon-class NPU',
      });
      expect(report.available, isFalse);
      expect(report.reasonCode, AvailabilityReasonCodes.deviceNotEligible);
      expect(report.reason, contains('NPU'));
    });

    test('round-trips through toMap', () {
      const report = AvailabilityReport(
        available: false,
        reasonCode: 'model_not_ready',
        reason: 'downloading',
        features: {'streaming': false},
      );
      final parsed = AvailabilityReport.fromMap(report.toMap());
      expect(parsed.available, isFalse);
      expect(parsed.reasonCode, 'model_not_ready');
      expect(parsed.supports('streaming'), isFalse);
    });
  });

  group('Usage', () {
    test('estimated defaults to true when missing (fail-safe)', () {
      final usage = Usage.fromMap({'inputTokens': 3, 'outputTokens': 4});
      expect(usage.estimated, isTrue);
      expect(usage.totalTokens, 7);
    });

    test('measured usage keeps estimated:false', () {
      final usage = Usage.fromMap(
          {'inputTokens': 3, 'outputTokens': 4, 'estimated': false});
      expect(usage.estimated, isFalse);
    });

    test('totalTokens is null when a side is missing', () {
      expect(const Usage(inputTokens: 3).totalTokens, isNull);
    });

    test('round-trips through toMap', () {
      const usage = Usage(inputTokens: 1, outputTokens: 2, estimated: false);
      final parsed = Usage.fromMap(usage.toMap());
      expect(parsed.estimated, isFalse);
      expect(parsed.totalTokens, 3);
    });
  });

  group('TokenCount', () {
    test('parses full breakdown', () {
      final count = TokenCount.fromMap({
        'input': 100,
        'instructions': 20,
        'tool': 0,
        'schema': 30,
        'total': 150,
        'contextWindow': 4096,
        'remaining': 3946,
        'estimated': true,
      });
      expect(count.total, 150);
      expect(count.contextWindow, 4096);
      expect(count.remaining, 3946);
      expect(count.fits, isTrue);
    });

    test('fits is false on overflow', () {
      const count = TokenCount(
        input: 9000,
        instructions: 0,
        tool: 0,
        schema: 0,
        total: 9000,
        contextWindow: 4096,
        remaining: -4904,
        estimated: true,
      );
      expect(count.fits, isFalse);
      expect(count.remaining, isNegative);
    });

    test('missing fields default to zero and estimated true', () {
      final count = TokenCount.fromMap(const {});
      expect(count.total, 0);
      expect(count.estimated, isTrue);
    });
  });

  test('FmMethods constants match the protocol v2 names', () {
    expect(FmMethods.health, 'foundationmodels.health');
    expect(FmMethods.availability, 'foundationmodels.availability');
    expect(FmMethods.capabilities, 'foundationmodels.capabilities');
    expect(FmMethods.countTokens, 'foundationmodels.context.countTokens');
    expect(FmMethods.sessionCreate, 'foundationmodels.sessions.create');
    expect(FmMethods.sessionRespond, 'foundationmodels.sessions.respond');
    expect(FmMethods.sessionStream, 'foundationmodels.sessions.stream');
    expect(FmMethods.sessionDispose, 'foundationmodels.sessions.dispose');
    expect(FmMethods.sessionTransition, 'foundationmodels.sessions.transition');
    expect(FmMethods.sessionPrewarm, 'foundationmodels.sessions.prewarm');
    expect(FmMethods.generationCancel, 'foundationmodels.generation.cancel');
    expect(FmMethods.toolsResult, 'foundationmodels.tools.result');
    expect(FmMethods.visionOcr, 'foundationmodels.vision.ocr');
    expect(FmMethods.visionBarcode, 'foundationmodels.vision.barcode');
    expect(FmMethods.feedbackLogAttachment,
        'foundationmodels.feedback.logAttachment');
  });
}
