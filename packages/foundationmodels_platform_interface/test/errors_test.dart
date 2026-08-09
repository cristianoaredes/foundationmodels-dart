import 'package:foundationmodels_platform_interface/foundationmodels_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  group('FoundationModelsException.fromError', () {
    FoundationModelsException map(
      String? code, [
      Map<String, Object?>? data,
    ]) =>
        FoundationModelsException.fromError(
          code: code,
          message: 'boom',
          data: data,
        );

    test('APPLE_MODEL_UNAVAILABLE → AppleModelUnavailableException', () {
      final e = map('APPLE_MODEL_UNAVAILABLE', {'reasonCode': 'model_not_ready'});
      expect(e, isA<AppleModelUnavailableException>());
      expect((e as AppleModelUnavailableException).reasonCode, 'model_not_ready');
      expect(e.code, 'APPLE_MODEL_UNAVAILABLE');
      expect(e.isRetryable, isFalse);
    });

    test('UNSUPPORTED_PLATFORM → UnsupportedPlatformException', () {
      expect(map('UNSUPPORTED_PLATFORM'), isA<UnsupportedPlatformException>());
    });

    test('PCC_UNAVAILABLE → PccUnavailableException with kind/retryable', () {
      final e = map('PCC_UNAVAILABLE',
          {'pccFailureKind': 'attestation', 'retryable': false});
      expect(e, isA<PccUnavailableException>());
      final pcc = e as PccUnavailableException;
      expect(pcc.pccFailureKind, 'attestation');
      expect(pcc.retryable, isFalse);
      expect(pcc.isRetryable, isFalse);
    });

    test('PCC_QUOTA_EXHAUSTED → PccQuotaExhaustedException', () {
      expect(map('PCC_QUOTA_EXHAUSTED'), isA<PccQuotaExhaustedException>());
    });

    test('MULTIMODAL_INPUT_UNAVAILABLE → MultimodalInputUnavailableException',
        () {
      final e = map('MULTIMODAL_INPUT_UNAVAILABLE', {'capability': 'image_input'});
      expect(e, isA<MultimodalInputUnavailableException>());
      expect((e as MultimodalInputUnavailableException).capability,
          'image_input');
    });

    test('UNSUPPORTED_SCHEMA_TYPE → UnsupportedSchemaTypeException', () {
      final e = map('UNSUPPORTED_SCHEMA_TYPE',
          {'keyword': 'oneOf', 'path': '/properties/x', 'schemaErrorCase': 'unsupported_keyword'});
      expect(e, isA<UnsupportedSchemaTypeException>());
      final s = e as UnsupportedSchemaTypeException;
      expect(s.keyword, 'oneOf');
      expect(s.path, '/properties/x');
      expect(s.schemaErrorCase, 'unsupported_keyword');
    });

    test('TOOL_CALLBACKS_REQUIRE_STREAMING → ToolCallbacksRequireStreamingException',
        () {
      final e = map('TOOL_CALLBACKS_REQUIRE_STREAMING', {
        'tools': ['get_weather', 'search']
      });
      expect(e, isA<ToolCallbacksRequireStreamingException>());
      expect((e as ToolCallbacksRequireStreamingException).tools,
          ['get_weather', 'search']);
    });

    test('CONTEXT_OVERFLOW → ContextOverflowException', () {
      final e =
          map('CONTEXT_OVERFLOW', {'contextSize': 4096, 'tokenCount': 5000});
      expect(e, isA<ContextOverflowException>());
      final c = e as ContextOverflowException;
      expect(c.contextSize, 4096);
      expect(c.tokenCount, 5000);
    });

    test('GENERATION_CANCELLED → GenerationCancelledException', () {
      expect(map('GENERATION_CANCELLED'), isA<GenerationCancelledException>());
    });

    test('TOOL_EXECUTION_FAILED → ToolExecutionFailedException', () {
      final e = map('TOOL_EXECUTION_FAILED',
          {'toolName': 'get_weather', 'callbackCode': 'TOOL_CALLBACK_ERROR'});
      expect(e, isA<ToolExecutionFailedException>());
      final t = e as ToolExecutionFailedException;
      expect(t.toolName, 'get_weather');
      expect(t.callbackCode, 'TOOL_CALLBACK_ERROR');
    });

    test('GUARDRAIL_VIOLATION → GuardrailViolationException (never retryable)',
        () {
      final e = map('GUARDRAIL_VIOLATION');
      expect(e, isA<GuardrailViolationException>());
      expect(e.isRetryable, isFalse);
    });

    test('MODEL_REFUSAL → ModelRefusalException (never retryable)', () {
      final e = map('MODEL_REFUSAL');
      expect(e, isA<ModelRefusalException>());
      expect(e.isRetryable, isFalse);
    });

    test('RATE_LIMITED → RateLimitedException (retryable, resetDate)', () {
      final e = map('RATE_LIMITED', {'resetDate': '2026-08-10T00:00:00Z'});
      expect(e, isA<RateLimitedException>());
      final r = e as RateLimitedException;
      expect(r.resetDate, '2026-08-10T00:00:00Z');
      expect(r.isRetryable, isTrue);
    });

    test('MODEL_TIMEOUT → ModelTimeoutException (retryable)', () {
      final e = map('MODEL_TIMEOUT');
      expect(e, isA<ModelTimeoutException>());
      expect(e.isRetryable, isTrue);
    });

    test('SESSION_BUSY → SessionBusyException (retryable)', () {
      final e = map('SESSION_BUSY');
      expect(e, isA<SessionBusyException>());
      expect(e.isRetryable, isTrue);
    });

    test('TRANSCRIPT_MUTATION_WHILE_RESPONDING → TranscriptMutationException',
        () {
      final e = map('TRANSCRIPT_MUTATION_WHILE_RESPONDING');
      expect(e, isA<TranscriptMutationException>());
      expect(e.isRetryable, isTrue);
    });

    test('STRUCTURED_OUTPUT_VALIDATION_FAILED → StructuredOutputValidationException',
        () {
      expect(map('STRUCTURED_OUTPUT_VALIDATION_FAILED'),
          isA<StructuredOutputValidationException>());
    });

    test('UNSUPPORTED_OPTION → UnsupportedOptionException', () {
      final e = map('UNSUPPORTED_OPTION', {'options': ['presencePenalty']});
      expect(e, isA<UnsupportedOptionException>());
      expect((e as UnsupportedOptionException).options, ['presencePenalty']);
    });

    test('UNSUPPORTED_OPERATION → UnsupportedOperationException', () {
      final e = map('UNSUPPORTED_OPERATION', {'capability': 'vision'});
      expect(e, isA<UnsupportedOperationException>());
      expect((e as UnsupportedOperationException).capability, 'vision');
    });

    test('UNSUPPORTED_TRANSCRIPT_CONTENT → UnsupportedTranscriptContentException (entryCount only)',
        () {
      final e = map('UNSUPPORTED_TRANSCRIPT_CONTENT', {'entryCount': 3});
      expect(e, isA<UnsupportedTranscriptContentException>());
      expect((e as UnsupportedTranscriptContentException).entryCount, 3);
    });

    test('UNSUPPORTED_GENERATION_GUIDE → UnsupportedGenerationGuideException',
        () {
      final e = map('UNSUPPORTED_GENERATION_GUIDE', {'schemaName': 'invoice'});
      expect(e, isA<UnsupportedGenerationGuideException>());
      expect((e as UnsupportedGenerationGuideException).schemaName, 'invoice');
    });

    test('UNSUPPORTED_LANGUAGE_OR_LOCALE → UnsupportedLanguageOrLocaleException',
        () {
      final e = map('UNSUPPORTED_LANGUAGE_OR_LOCALE', {'languageCode': 'xx'});
      expect(e, isA<UnsupportedLanguageOrLocaleException>());
      expect((e as UnsupportedLanguageOrLocaleException).languageCode, 'xx');
    });

    test('FEEDBACK_ATTACHMENT_UNAVAILABLE → FeedbackAttachmentUnavailableException',
        () {
      expect(map('FEEDBACK_ATTACHMENT_UNAVAILABLE'),
          isA<FeedbackAttachmentUnavailableException>());
    });

    test('SYSTEM_TOOL_UNAVAILABLE → SystemToolUnavailableException', () {
      expect(map('SYSTEM_TOOL_UNAVAILABLE'),
          isA<SystemToolUnavailableException>());
    });

    test('VISION_OCR_UNAVAILABLE → VisionOcrUnavailableException', () {
      expect(map('VISION_OCR_UNAVAILABLE'),
          isA<VisionOcrUnavailableException>());
    });

    test('VISION_BARCODE_UNAVAILABLE → VisionBarcodeUnavailableException', () {
      expect(map('VISION_BARCODE_UNAVAILABLE'),
          isA<VisionBarcodeUnavailableException>());
    });

    test('UNKNOWN_MODEL_ERROR → UnknownModelException with details', () {
      final e = map('UNKNOWN_MODEL_ERROR', {'weird': 42});
      expect(e, isA<UnknownModelException>());
      expect(e.code, 'UNKNOWN_MODEL_ERROR');
      expect(e.details, {'weird': 42});
    });

    test('missing code → UnknownModelException', () {
      final e = map(null, {'hint': 'native crash'});
      expect(e, isA<UnknownModelException>());
      expect(e.code, 'UNKNOWN_MODEL_ERROR');
      expect(e.details, {'hint': 'native crash'});
    });

    test('unrecognized code → UnknownModelException preserving code', () {
      final e = map('SOME_FUTURE_CODE');
      expect(e, isA<UnknownModelException>());
      expect(e.code, 'SOME_FUTURE_CODE');
    });

    test('toString includes type, code and message', () {
      final e = map('MODEL_TIMEOUT');
      expect(e.toString(), contains('ModelTimeoutException'));
      expect(e.toString(), contains('MODEL_TIMEOUT'));
      expect(e.toString(), contains('boom'));
    });
  });
}
