/// Context-window policy applied by the runtime before generating.
library;

/// How the runtime protects the model context window.
enum ContextPolicyMode {
  /// No pre-flight accounting.
  none,

  /// Call `context.countTokens` before generating and throw
  /// `ContextOverflowException` locally (with the full token breakdown) when
  /// the request does not fit.
  guard,

  /// **Phase-1 stub** — transcript compaction is not implemented yet;
  /// currently behaves exactly like [ContextPolicyMode.guard] (fail-fast).
  /// A later phase will compact the transcript instead of throwing.
  compact,
}

/// Policy guarding generations against context overflow.
///
/// - [ContextPolicy.guard]: pre-flight `countTokens`; throws
///   `ContextOverflowException` with the token breakdown when the request
///   exceeds the window.
/// - [ContextPolicy.compact]: **stub for a later phase** — currently
///   identical to `guard` (fail-fast, never silently drops content).
/// - [ContextPolicy.none] (default): no pre-flight check.
class ContextPolicy {
  const ContextPolicy._(this.mode);

  /// No pre-flight accounting (default).
  static const ContextPolicy none = ContextPolicy._(ContextPolicyMode.none);

  /// Fail-fast overflow protection via `countTokens`.
  static const ContextPolicy guard = ContextPolicy._(ContextPolicyMode.guard);

  /// Compaction policy (stub — currently behaves like [guard]).
  static const ContextPolicy compact =
      ContextPolicy._(ContextPolicyMode.compact);

  /// The policy mode.
  final ContextPolicyMode mode;

  /// Whether a pre-flight `countTokens` check runs before generating.
  bool get performsPreflight => mode != ContextPolicyMode.none;

  @override
  String toString() => 'ContextPolicy.${mode.name}';
}
