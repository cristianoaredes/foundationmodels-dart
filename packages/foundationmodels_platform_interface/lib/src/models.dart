/// Value models shared across the FoundationModels Dart packages.
library;

/// Stable availability reason codes reported by the native core.
///
/// These mirror the upstream protocol; use them for feature-detect and
/// graceful degradation instead of string matching on messages.
abstract final class AvailabilityReasonCodes {
  /// The device hardware does not support Apple Intelligence.
  static const String deviceNotEligible = 'device_not_eligible';

  /// Apple Intelligence is disabled in system settings.
  static const String appleIntelligenceNotEnabled =
      'apple_intelligence_not_enabled';

  /// The model assets are not ready (downloading or preparing).
  static const String modelNotReady = 'model_not_ready';

  /// The FoundationModels framework is unavailable on this OS build.
  static const String foundationModelsFrameworkUnavailable =
      'foundation_models_framework_unavailable';

  /// Private Cloud Compute is unavailable (or unentitled).
  static const String pccUnavailable = 'pcc_unavailable';

  /// The platform is not supported (non-Apple OS).
  static const String unsupportedPlatform = 'unsupported_platform';

  /// The availability could not be determined.
  static const String unknown = 'unknown';
}

/// Availability report for Apple Intelligence on this device.
class AvailabilityReport {
  /// Creates the report.
  const AvailabilityReport({
    required this.available,
    this.reasonCode,
    this.reason,
    this.features = const {},
  });

  /// Parses a protocol `availability` result map.
  factory AvailabilityReport.fromMap(Map<String, Object?> map) {
    return AvailabilityReport(
      available: map['available'] as bool? ?? false,
      reasonCode: map['reasonCode'] as String?,
      reason: map['reason'] as String?,
      features: (map['features'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value == true),
          ) ??
          const {},
    );
  }

  /// Whether generation is possible right now.
  final bool available;

  /// Stable reason code when [available] is `false`
  /// (see [AvailabilityReasonCodes]).
  final String? reasonCode;

  /// Human-readable explanation (safe to display/log).
  final String? reason;

  /// Per-feature availability flags (e.g. `streaming`, `guidedGeneration`).
  final Map<String, bool> features;

  /// Whether [feature] is reported as supported. Absent means `false`.
  bool supports(String feature) => features[feature] ?? false;

  /// Serializes back to the protocol map shape.
  Map<String, Object?> toMap() => {
        'available': available,
        if (reasonCode != null) 'reasonCode': reasonCode,
        if (reason != null) 'reason': reason,
        'features': features,
      };

  @override
  String toString() =>
      'AvailabilityReport(available: $available, reasonCode: $reasonCode)';
}

/// Token usage of a generation.
///
/// [estimated] is prominent by design: it is `false` **only** when the usage
/// was measured natively (Apple SDK 27+). Everywhere else — including every
/// value produced by the mock provider — it is `true`, and consumers must
/// not treat the numbers as measurements.
class Usage {
  /// Creates a usage record.
  const Usage({this.inputTokens, this.outputTokens, this.estimated = true});

  /// Parses a protocol usage map. Missing `estimated` defaults to `true`
  /// (fail-safe: unmarked numbers are treated as estimates).
  factory Usage.fromMap(Map<String, Object?> map) {
    return Usage(
      inputTokens: (map['inputTokens'] as num?)?.toInt(),
      outputTokens: (map['outputTokens'] as num?)?.toInt(),
      estimated: map['estimated'] as bool? ?? true,
    );
  }

  /// Prompt/input tokens, when reported.
  final int? inputTokens;

  /// Completion/output tokens, when reported.
  final int? outputTokens;

  /// `true` unless measured natively. See class doc.
  final bool estimated;

  /// Sum of input and output tokens, when both are known.
  int? get totalTokens {
    final input = inputTokens;
    final output = outputTokens;
    if (input == null || output == null) return null;
    return input + output;
  }

  /// Serializes back to the protocol map shape.
  Map<String, Object?> toMap() => {
        if (inputTokens != null) 'inputTokens': inputTokens,
        if (outputTokens != null) 'outputTokens': outputTokens,
        'estimated': estimated,
      };

  @override
  String toString() => 'Usage(input: $inputTokens, output: $outputTokens, '
      'estimated: $estimated)';
}

/// Token accounting for a prospective generation request.
///
/// Produced by `foundationmodels.context.countTokens` (or by a provider's
/// estimator). Used by the `contextPolicy: guard` pre-flight check.
class TokenCount {
  /// Creates the token breakdown.
  const TokenCount({
    required this.input,
    required this.instructions,
    required this.tool,
    required this.schema,
    required this.total,
    required this.contextWindow,
    required this.remaining,
    required this.estimated,
  });

  /// Parses a protocol `countTokens` result map.
  factory TokenCount.fromMap(Map<String, Object?> map) {
    int read(String key) => (map[key] as num?)?.toInt() ?? 0;
    return TokenCount(
      input: read('input'),
      instructions: read('instructions'),
      tool: read('tool'),
      schema: read('schema'),
      total: read('total'),
      contextWindow: read('contextWindow'),
      remaining: read('remaining'),
      estimated: map['estimated'] as bool? ?? true,
    );
  }

  /// Tokens attributable to the user input.
  final int input;

  /// Tokens attributable to instructions (system prompt).
  final int instructions;

  /// Tokens attributable to tool definitions.
  final int tool;

  /// Tokens attributable to the response schema / generation guide.
  final int schema;

  /// Total tokens the request would consume.
  final int total;

  /// Context window of the target model.
  final int contextWindow;

  /// Tokens remaining in the window after this request
  /// (`contextWindow - total`, may be negative on overflow).
  final int remaining;

  /// `true` unless measured natively (same contract as [Usage.estimated]).
  final bool estimated;

  /// Whether [total] fits the [contextWindow].
  bool get fits => total <= contextWindow;

  /// Serializes back to the protocol map shape.
  Map<String, Object?> toMap() => {
        'input': input,
        'instructions': instructions,
        'tool': tool,
        'schema': schema,
        'total': total,
        'contextWindow': contextWindow,
        'remaining': remaining,
        'estimated': estimated,
      };

  @override
  String toString() => 'TokenCount(total: $total, window: $contextWindow, '
      'remaining: $remaining, estimated: $estimated)';
}
