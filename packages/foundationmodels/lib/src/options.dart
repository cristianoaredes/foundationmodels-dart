/// Generation options and sampling policies, validated locally before any
/// provider call (fail-fast, mirroring the upstream runtime).
library;

/// Sampling strategy for a generation.
///
/// Maps to the upstream sampling modes `greedy`, `top_k` and `top_p`.
sealed class SamplingPolicy {
  /// Creates a sampling policy with an optional non-negative [seed] for
  /// reproducibility.
  const SamplingPolicy({this.seed});

  /// Optional seed; must be `>= 0` when provided.
  final int? seed;

  /// Wire mode name (`greedy`, `top_k`, `top_p`).
  String get mode;

  /// Validates the policy, throwing [ArgumentError] naming the offending
  /// field.
  void validate() {
    final seed = this.seed;
    if (seed != null && seed < 0) {
      throw ArgumentError.value(seed, 'sampling.seed', 'must be >= 0');
    }
  }

  /// Serializes to the protocol `options.sampling` map.
  Map<String, Object?> toJson() => {
        'mode': mode,
        if (seed != null) 'seed': seed,
      };
}

/// Deterministic greedy decoding (`{"mode": "greedy"}`).
final class GreedySampling extends SamplingPolicy {
  /// Creates a greedy sampling policy.
  const GreedySampling({super.seed});

  @override
  String get mode => 'greedy';
}

/// Top-k sampling (`{"mode": "top_k", "topK": k}`).
final class TopKSampling extends SamplingPolicy {
  /// Creates a top-k sampling policy. [topK] must be a positive integer.
  const TopKSampling({required this.topK, super.seed});

  /// Number of candidate tokens kept at each step; must be `> 0`.
  final int topK;

  @override
  String get mode => 'top_k';

  @override
  void validate() {
    super.validate();
    if (topK <= 0) {
      throw ArgumentError.value(topK, 'sampling.topK', 'must be > 0');
    }
  }

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'topK': topK};
}

/// Top-p (nucleus) sampling (`{"mode": "top_p", "probabilityThreshold": p}`).
final class TopPSampling extends SamplingPolicy {
  /// Creates a top-p sampling policy. [probabilityThreshold] must be in
  /// `(0, 1]`.
  const TopPSampling({required this.probabilityThreshold, super.seed});

  /// Cumulative probability threshold; must be in `(0, 1]`.
  final double probabilityThreshold;

  @override
  String get mode => 'top_p';

  @override
  void validate() {
    super.validate();
    if (probabilityThreshold <= 0 || probabilityThreshold > 1) {
      throw ArgumentError.value(
        probabilityThreshold,
        'sampling.probabilityThreshold',
        'must be in (0, 1]',
      );
    }
  }

  @override
  Map<String, Object?> toJson() =>
      {...super.toJson(), 'probabilityThreshold': probabilityThreshold};
}

/// Options controlling a single generation.
///
/// Validation happens **before** any provider/transport call: [validate]
/// throws [ArgumentError] naming the offending field when:
/// - [temperature] is outside `[0, 1]`;
/// - [maximumResponseTokens] is not positive;
/// - [sampling] fails its own validation.
class GenerationOptions {
  /// Creates generation options.
  const GenerationOptions({
    this.temperature,
    this.maximumResponseTokens,
    this.sampling,
  });

  /// Sensible defaults (no overrides — the native core applies its own).
  static const GenerationOptions defaults = GenerationOptions();

  /// Sampling temperature; must be within `[0, 1]` when provided.
  final double? temperature;

  /// Cap on generated tokens; must be `> 0` when provided.
  final int? maximumResponseTokens;

  /// Sampling policy; validated per [SamplingPolicy.validate].
  final SamplingPolicy? sampling;

  /// Validates all fields, throwing [ArgumentError] on the first violation.
  void validate() {
    final temperature = this.temperature;
    if (temperature != null && (temperature < 0 || temperature > 1)) {
      throw ArgumentError.value(
        temperature,
        'temperature',
        'must be in [0, 1]',
      );
    }
    final maximumResponseTokens = this.maximumResponseTokens;
    if (maximumResponseTokens != null && maximumResponseTokens <= 0) {
      throw ArgumentError.value(
        maximumResponseTokens,
        'maximumResponseTokens',
        'must be > 0',
      );
    }
    sampling?.validate();
  }

  /// Serializes to the protocol `options` map (omitting absent fields).
  Map<String, Object?> toJson() => {
        if (temperature != null) 'temperature': temperature,
        if (maximumResponseTokens != null)
          'maximumResponseTokens': maximumResponseTokens,
        if (sampling != null) 'sampling': sampling!.toJson(),
      };
}
