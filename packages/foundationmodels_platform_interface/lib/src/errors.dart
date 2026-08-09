/// Typed exceptions mirroring the upstream `error.data.code` contract.
///
/// The stable machine-readable string code — not the numeric JSON-RPC code
/// and not the human message — is what clients map to typed errors. Every
/// exception in this library extends the sealed [FoundationModelsException]
/// and carries the [FoundationModelsException.code],
/// [FoundationModelsException.message] and optional
/// [FoundationModelsException.details].
///
/// Invariants inherited from upstream:
/// - Errors never carry raw model content (`rawContent`) in [details].
/// - [GuardrailViolationException] and [ModelRefusalException] are never
///   retryable; [RateLimitedException], [ModelTimeoutException],
///   [SessionBusyException] and [TranscriptMutationException] are retryable.
library;

/// Base type of every typed FoundationModels error.
///
/// Use [FoundationModelsException.fromError] to map a native error payload
/// (`error.data.code` + `message` + `error.data`) to the correct subtype.
sealed class FoundationModelsException implements Exception {
  /// Creates an exception with a stable [code], human [message] and optional
  /// structured [details] (never containing raw model content).
  const FoundationModelsException({
    required this.code,
    required this.message,
    this.details,
  });

  /// Stable machine-readable code (e.g. `CONTEXT_OVERFLOW`).
  final String code;

  /// Human-readable description. Safe to log; never contains secrets.
  final String message;

  /// Structured payload copied from `error.data` (minus the `code` string,
  /// which is exposed as [code]). Never contains raw model output.
  final Map<String, Object?>? details;

  /// Whether the operation may succeed if retried later.
  ///
  /// Defaults to `false`. Retriable failures override this to `true`.
  bool get isRetryable => false;

  /// Maps a native error payload to the correct typed exception.
  ///
  /// [code] is the stable string from `error.data.code`; [message] the human
  /// message; [data] the full `error.data` map (used for code-specific
  /// fields such as `reasonCode`, `tokenCount`, `toolName`, ...).
  ///
  /// Unknown or missing codes (including `UNKNOWN_MODEL_ERROR`) produce an
  /// [UnknownModelException] carrying [data] as [details].
  factory FoundationModelsException.fromError({
    required String? code,
    required String message,
    Map<String, Object?>? data,
  }) {
    String? str(String key) => data?[key] as String?;
    int? integer(String key) => (data?[key] as num?)?.toInt();
    bool boolean(String key, {required bool fallback}) =>
        data?[key] as bool? ?? fallback;
    List<String> strings(String key) =>
        (data?[key] as List?)?.whereType<String>().toList() ?? const [];

    switch (code) {
      case 'APPLE_MODEL_UNAVAILABLE':
        return AppleModelUnavailableException(
          message: message,
          reasonCode: str('reasonCode') ?? 'unknown',
          details: data,
        );
      case 'UNSUPPORTED_PLATFORM':
        return UnsupportedPlatformException(message: message, details: data);
      case 'PCC_UNAVAILABLE':
        return PccUnavailableException(
          message: message,
          pccFailureKind: str('pccFailureKind'),
          retryable: boolean('retryable', fallback: true),
          details: data,
        );
      case 'PCC_QUOTA_EXHAUSTED':
        return PccQuotaExhaustedException(message: message, details: data);
      case 'MULTIMODAL_INPUT_UNAVAILABLE':
        return MultimodalInputUnavailableException(
          message: message,
          capability: str('capability') ?? 'multimodal_input',
          details: data,
        );
      case 'UNSUPPORTED_SCHEMA_TYPE':
        return UnsupportedSchemaTypeException(
          message: message,
          keyword: str('keyword'),
          path: str('path'),
          schemaErrorCase: str('schemaErrorCase'),
          details: data,
        );
      case 'TOOL_CALLBACKS_REQUIRE_STREAMING':
        return ToolCallbacksRequireStreamingException(
          message: message,
          tools: strings('tools'),
          details: data,
        );
      case 'CONTEXT_OVERFLOW':
        return ContextOverflowException(
          message: message,
          contextSize: integer('contextSize'),
          tokenCount: integer('tokenCount'),
          details: data,
        );
      case 'GENERATION_CANCELLED':
        return GenerationCancelledException(message: message, details: data);
      case 'TOOL_EXECUTION_FAILED':
        return ToolExecutionFailedException(
          message: message,
          toolName: str('toolName') ?? 'unknown',
          callbackCode: str('callbackCode'),
          details: data,
        );
      case 'GUARDRAIL_VIOLATION':
        return GuardrailViolationException(message: message, details: data);
      case 'MODEL_REFUSAL':
        return ModelRefusalException(message: message, details: data);
      case 'RATE_LIMITED':
        return RateLimitedException(
          message: message,
          resetDate: str('resetDate'),
          details: data,
        );
      case 'MODEL_TIMEOUT':
        return ModelTimeoutException(message: message, details: data);
      case 'SESSION_BUSY':
        return SessionBusyException(message: message, details: data);
      case 'TRANSCRIPT_MUTATION_WHILE_RESPONDING':
        return TranscriptMutationException(message: message, details: data);
      case 'STRUCTURED_OUTPUT_VALIDATION_FAILED':
        return StructuredOutputValidationException(
          message: message,
          details: data,
        );
      case 'UNSUPPORTED_OPTION':
        return UnsupportedOptionException(
          message: message,
          options: strings('options'),
          details: data,
        );
      case 'UNSUPPORTED_OPERATION':
        return UnsupportedOperationException(
          message: message,
          capability: str('capability') ?? 'unknown',
          details: data,
        );
      case 'UNSUPPORTED_TRANSCRIPT_CONTENT':
        return UnsupportedTranscriptContentException(
          message: message,
          entryCount: integer('entryCount') ?? 0,
          details: data,
        );
      case 'UNSUPPORTED_GENERATION_GUIDE':
        return UnsupportedGenerationGuideException(
          message: message,
          schemaName: str('schemaName') ?? 'unknown',
          details: data,
        );
      case 'UNSUPPORTED_LANGUAGE_OR_LOCALE':
        return UnsupportedLanguageOrLocaleException(
          message: message,
          languageCode: str('languageCode') ?? 'unknown',
          details: data,
        );
      case 'FEEDBACK_ATTACHMENT_UNAVAILABLE':
        return FeedbackAttachmentUnavailableException(
          message: message,
          details: data,
        );
      case 'SYSTEM_TOOL_UNAVAILABLE':
        return SystemToolUnavailableException(message: message, details: data);
      case 'VISION_OCR_UNAVAILABLE':
        return VisionOcrUnavailableException(message: message, details: data);
      case 'VISION_BARCODE_UNAVAILABLE':
        return VisionBarcodeUnavailableException(
          message: message,
          details: data,
        );
      default:
        return UnknownModelException(
          code: code ?? 'UNKNOWN_MODEL_ERROR',
          message: message,
          details: data,
        );
    }
  }

  @override
  String toString() => '$runtimeType(code: $code, message: $message)';
}

/// `APPLE_MODEL_UNAVAILABLE` — the on-device model cannot be used right now.
final class AppleModelUnavailableException extends FoundationModelsException {
  /// Creates the exception with the stable availability [reasonCode]
  /// (e.g. `device_not_eligible`, `model_not_ready`).
  const AppleModelUnavailableException({
    required super.message,
    required this.reasonCode,
    super.details,
  }) : super(code: 'APPLE_MODEL_UNAVAILABLE');

  /// Stable availability reason code (see [AvailabilityReasonCodes]).
  final String reasonCode;
}

/// `UNSUPPORTED_PLATFORM` — Apple Foundation Models is unavailable here.
final class UnsupportedPlatformException extends FoundationModelsException {
  /// Creates the exception.
  const UnsupportedPlatformException({required super.message, super.details})
      : super(code: 'UNSUPPORTED_PLATFORM');
}

/// `PCC_UNAVAILABLE` — Private Cloud Compute inference failed or is gated.
final class PccUnavailableException extends FoundationModelsException {
  /// Creates the exception.
  const PccUnavailableException({
    required super.message,
    this.pccFailureKind,
    this.retryable = true,
    super.details,
  }) : super(code: 'PCC_UNAVAILABLE');

  /// Optional machine-readable failure kind reported by the core.
  final String? pccFailureKind;

  /// Whether the core marked this PCC failure as retryable.
  final bool retryable;

  @override
  bool get isRetryable => retryable;
}

/// `PCC_QUOTA_EXHAUSTED` — the PCC quota for this entitlement is spent.
final class PccQuotaExhaustedException extends FoundationModelsException {
  /// Creates the exception.
  const PccQuotaExhaustedException({required super.message, super.details})
      : super(code: 'PCC_QUOTA_EXHAUSTED');
}

/// `MULTIMODAL_INPUT_UNAVAILABLE` — image/other modality input unsupported.
final class MultimodalInputUnavailableException
    extends FoundationModelsException {
  /// Creates the exception naming the unavailable [capability].
  const MultimodalInputUnavailableException({
    required super.message,
    required this.capability,
    super.details,
  }) : super(code: 'MULTIMODAL_INPUT_UNAVAILABLE');

  /// Capability that is unavailable (e.g. `image_input`).
  final String capability;
}

/// `UNSUPPORTED_SCHEMA_TYPE` — schema keyword outside the accepted subset.
///
/// Raised locally by `FmSchema` (fail-fast, before the channel) and by the
/// native core for schemas rejected at generation time.
final class UnsupportedSchemaTypeException extends FoundationModelsException {
  /// Creates the exception naming the offending [keyword] and the JSON
  /// Pointer [path] where it was found, when known.
  const UnsupportedSchemaTypeException({
    required super.message,
    this.keyword,
    this.path,
    this.schemaErrorCase,
    super.details,
  }) : super(code: 'UNSUPPORTED_SCHEMA_TYPE');

  /// The unsupported JSON Schema keyword (e.g. `oneOf`, `minLength`).
  final String? keyword;

  /// JSON Pointer to the schema node containing the violation.
  final String? path;

  /// Optional machine-readable sub-case (e.g. `empty_enum`, `external_ref`).
  final String? schemaErrorCase;
}

/// `TOOL_CALLBACKS_REQUIRE_STREAMING` — callback tools need `stream`, not
/// `respond`. Enforced locally before the channel, mirroring upstream.
final class ToolCallbacksRequireStreamingException
    extends FoundationModelsException {
  /// Creates the exception listing the offending [tools].
  const ToolCallbacksRequireStreamingException({
    required super.message,
    this.tools = const [],
    super.details,
  }) : super(code: 'TOOL_CALLBACKS_REQUIRE_STREAMING');

  /// Names of callback tools that require streaming mode.
  final List<String> tools;
}

/// `CONTEXT_OVERFLOW` — the request does not fit the model context window.
final class ContextOverflowException extends FoundationModelsException {
  /// Creates the exception with the window [contextSize] and the offending
  /// [tokenCount], when reported.
  const ContextOverflowException({
    required super.message,
    this.contextSize,
    this.tokenCount,
    super.details,
  }) : super(code: 'CONTEXT_OVERFLOW');

  /// Model context window size in tokens, when known.
  final int? contextSize;

  /// Token count that overflowed the window, when known.
  final int? tokenCount;
}

/// `GENERATION_CANCELLED` — the generation was cooperatively cancelled.
final class GenerationCancelledException extends FoundationModelsException {
  /// Creates the exception.
  const GenerationCancelledException({required super.message, super.details})
      : super(code: 'GENERATION_CANCELLED');
}

/// `TOOL_EXECUTION_FAILED` — a client tool callback failed or was missing.
final class ToolExecutionFailedException extends FoundationModelsException {
  /// Creates the exception naming the failed [toolName].
  const ToolExecutionFailedException({
    required super.message,
    required this.toolName,
    this.callbackCode,
    super.details,
  }) : super(code: 'TOOL_EXECUTION_FAILED');

  /// Name of the tool whose callback failed.
  final String toolName;

  /// Optional callback failure sub-code (e.g. `TOOL_CALLBACK_ERROR`).
  final String? callbackCode;
}

/// `GUARDRAIL_VIOLATION` — safety guardrails rejected input or output.
///
/// Never retryable: retrying the same content will fail again.
final class GuardrailViolationException extends FoundationModelsException {
  /// Creates the exception.
  const GuardrailViolationException({required super.message, super.details})
      : super(code: 'GUARDRAIL_VIOLATION');
}

/// `MODEL_REFUSAL` — the model declined to answer.
///
/// Never retryable: retrying the same prompt will fail again.
final class ModelRefusalException extends FoundationModelsException {
  /// Creates the exception.
  const ModelRefusalException({required super.message, super.details})
      : super(code: 'MODEL_REFUSAL');
}

/// `RATE_LIMITED` — the caller exceeded a rate or quota limit. Retryable.
final class RateLimitedException extends FoundationModelsException {
  /// Creates the exception, optionally with the [resetDate] after which a
  /// retry is expected to succeed.
  const RateLimitedException({
    required super.message,
    this.resetDate,
    super.details,
  }) : super(code: 'RATE_LIMITED');

  /// ISO-8601 timestamp when the limit resets, when reported.
  final String? resetDate;

  @override
  bool get isRetryable => true;
}

/// `MODEL_TIMEOUT` — the generation exceeded its time budget. Retryable.
final class ModelTimeoutException extends FoundationModelsException {
  /// Creates the exception.
  const ModelTimeoutException({required super.message, super.details})
      : super(code: 'MODEL_TIMEOUT');

  @override
  bool get isRetryable => true;
}

/// `SESSION_BUSY` — the session already has an in-flight generation.
/// Retryable after the current generation settles.
final class SessionBusyException extends FoundationModelsException {
  /// Creates the exception.
  const SessionBusyException({required super.message, super.details})
      : super(code: 'SESSION_BUSY');

  @override
  bool get isRetryable => true;
}

/// `TRANSCRIPT_MUTATION_WHILE_RESPONDING` — the transcript changed while a
/// generation was in flight. Retryable once the session is idle.
final class TranscriptMutationException extends FoundationModelsException {
  /// Creates the exception.
  const TranscriptMutationException({required super.message, super.details})
      : super(code: 'TRANSCRIPT_MUTATION_WHILE_RESPONDING');

  @override
  bool get isRetryable => true;
}

/// `STRUCTURED_OUTPUT_VALIDATION_FAILED` — guided generation produced output
/// that does not validate against the requested schema. [details] never
/// carries the raw model content.
final class StructuredOutputValidationException
    extends FoundationModelsException {
  /// Creates the exception.
  const StructuredOutputValidationException({
    required super.message,
    super.details,
  }) : super(code: 'STRUCTURED_OUTPUT_VALIDATION_FAILED');
}

/// `UNSUPPORTED_OPTION` — a generation option is not supported by the core.
final class UnsupportedOptionException extends FoundationModelsException {
  /// Creates the exception listing the unsupported [options].
  const UnsupportedOptionException({
    required super.message,
    this.options = const [],
    super.details,
  }) : super(code: 'UNSUPPORTED_OPTION');

  /// Names of the unsupported option fields.
  final List<String> options;
}

/// `UNSUPPORTED_OPERATION` — the requested capability is not supported.
final class UnsupportedOperationException extends FoundationModelsException {
  /// Creates the exception naming the unsupported [capability].
  const UnsupportedOperationException({
    required super.message,
    required this.capability,
    super.details,
  }) : super(code: 'UNSUPPORTED_OPERATION');

  /// Capability that is not supported on this build/device.
  final String capability;
}

/// `UNSUPPORTED_TRANSCRIPT_CONTENT` — a session transcript contains entries
/// the core cannot replay. Carries only the [entryCount], never the content.
final class UnsupportedTranscriptContentException
    extends FoundationModelsException {
  /// Creates the exception reporting how many entries were rejected.
  const UnsupportedTranscriptContentException({
    required super.message,
    required this.entryCount,
    super.details,
  }) : super(code: 'UNSUPPORTED_TRANSCRIPT_CONTENT');

  /// Number of transcript entries that are unsupported. The transcript
  /// content itself is never included, by design.
  final int entryCount;
}

/// `UNSUPPORTED_GENERATION_GUIDE` — a named generation guide is unknown.
final class UnsupportedGenerationGuideException
    extends FoundationModelsException {
  /// Creates the exception naming the unknown [schemaName].
  const UnsupportedGenerationGuideException({
    required super.message,
    required this.schemaName,
    super.details,
  }) : super(code: 'UNSUPPORTED_GENERATION_GUIDE');

  /// Name of the generation guide/schema that is not supported.
  final String schemaName;
}

/// `UNSUPPORTED_LANGUAGE_OR_LOCALE` — the requested language/locale pair is
/// not supported by the model.
final class UnsupportedLanguageOrLocaleException
    extends FoundationModelsException {
  /// Creates the exception naming the unsupported [languageCode].
  const UnsupportedLanguageOrLocaleException({
    required super.message,
    required this.languageCode,
    super.details,
  }) : super(code: 'UNSUPPORTED_LANGUAGE_OR_LOCALE');

  /// BCP-47 language/locale code that is not supported.
  final String languageCode;
}

/// `FEEDBACK_ATTACHMENT_UNAVAILABLE` — feedback attachments unsupported.
final class FeedbackAttachmentUnavailableException
    extends FoundationModelsException {
  /// Creates the exception.
  const FeedbackAttachmentUnavailableException({
    required super.message,
    super.details,
  }) : super(code: 'FEEDBACK_ATTACHMENT_UNAVAILABLE');
}

/// `SYSTEM_TOOL_UNAVAILABLE` — a native/system tool is not available.
final class SystemToolUnavailableException extends FoundationModelsException {
  /// Creates the exception.
  const SystemToolUnavailableException({required super.message, super.details})
      : super(code: 'SYSTEM_TOOL_UNAVAILABLE');
}

/// `VISION_OCR_UNAVAILABLE` — Vision OCR is not available on this device.
final class VisionOcrUnavailableException extends FoundationModelsException {
  /// Creates the exception.
  const VisionOcrUnavailableException({required super.message, super.details})
      : super(code: 'VISION_OCR_UNAVAILABLE');
}

/// `VISION_BARCODE_UNAVAILABLE` — Vision barcode scanning is not available.
final class VisionBarcodeUnavailableException
    extends FoundationModelsException {
  /// Creates the exception.
  const VisionBarcodeUnavailableException({
    required super.message,
    super.details,
  }) : super(code: 'VISION_BARCODE_UNAVAILABLE');
}

/// Generic fallback for `UNKNOWN_MODEL_ERROR`, missing or unrecognized codes.
///
/// Carries whatever [details] the native side reported. This is the only
/// [FoundationModelsException] subtype whose [code] is not fixed.
final class UnknownModelException extends FoundationModelsException {
  /// Creates the generic exception preserving the original [code].
  const UnknownModelException({
    required super.code,
    required super.message,
    super.details,
  });
}
