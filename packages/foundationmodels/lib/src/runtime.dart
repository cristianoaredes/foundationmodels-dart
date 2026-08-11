/// The public runtime: `FoundationModels` and `createFoundationModels`.
library;

import 'dart:async';

import 'package:foundationmodels_platform_interface/foundationmodels_platform_interface.dart';

import 'cancel.dart';
import 'context_policy.dart';
import 'mock/mock_provider.dart';
import 'options.dart';
import 'provider.dart';
import 'schema.dart';
import 'security.dart';
import 'session.dart';
import 'tools.dart';

/// Creates the runtime.
///
/// With no [providers], returns a runtime backed by [MockProvider] —
/// deterministic, offline, CI-friendly, no Apple hardware required. Pass a
/// provider list to try real backends in order (first available wins).
///
/// [security] defaults to [SecurityConfig.defaults] (fail-closed image
/// allowlist). [contextPolicy] defaults to [ContextPolicy.none].
Future<FoundationModels> createFoundationModels({
  List<FmProvider> providers = const [],
  SecurityConfig security = SecurityConfig.defaults,
  ContextPolicy contextPolicy = ContextPolicy.none,
  bool Function(FmProvider provider)? isAvailable,
}) async {
  final candidates = providers.isEmpty ? [const MockProvider()] : providers;
  if (providers.isEmpty) {
    return FoundationModels._(
      provider: candidates.single,
      security: security,
      contextPolicy: contextPolicy,
    );
  }
  for (final provider in candidates) {
    if (isAvailable != null) {
      if (isAvailable(provider)) return FoundationModels._(provider: provider, security: security, contextPolicy: contextPolicy);
      continue;
    }
    final report = await provider.availability();
    if (report.available) {
      return FoundationModels._(
        provider: provider,
        security: security,
        contextPolicy: contextPolicy,
      );
    }
  }
  // None available: degrade explicitly to the mock so callers keep a usable,
  // deterministic surface (and can inspect `provider.id == 'mock'`).
  return FoundationModels._(
    provider: const MockProvider(),
    security: security,
    contextPolicy: contextPolicy,
  );
}

/// The FoundationModels runtime: primitives, sessions and configuration.
class FoundationModels {
  FoundationModels._({
    required this._provider,
    required this._security,
    required this._contextPolicy,
  });

  final FmProvider _provider;
  final SecurityConfig _security;
  final ContextPolicy _contextPolicy;
  int _idCounter = 0;

  /// The provider backing this runtime (e.g. `mock`, `apple-transport`).
  FmProvider get provider => _provider;

  /// The security configuration (see [SecurityConfig] invariants).
  SecurityConfig get security => _security;

  /// The context-window policy applied before generating.
  ContextPolicy get contextPolicy => _contextPolicy;

  String _nextId(String prefix) =>
      '${prefix}_${(++_idCounter).toRadixString(36)}_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  // --- Diagnostics ------------------------------------------------------------

  /// Health probe for the active provider / native core.
  Future<Map<String, Object?>> health() => _provider.health();

  /// Availability report with the stable `reasonCode` contract.
  Future<AvailabilityReport> availability() => _provider.availability();

  /// Capability descriptor for feature-detect before use.
  Future<Map<String, Object?>> capabilities() => _provider.capabilities();

  /// Token accounting for a prospective generation.
  Future<TokenCount> countTokens({
    required String input,
    String? instructions,
    FmSchema? schema,
  }) =>
      _provider.countTokens(FmCountTokensRequest(
        input: input,
        instructions: instructions,
        schema: schema,
      ));

  /// Vision OCR (`foundationmodels.vision.ocr`).
  ///
  /// [image] is a protocol-shaped image object (`base64` + `mimeType`, or
  /// `path` under [SecurityConfig.allowedImageRoots]).
  ///
  /// Wire shape matches the Swift core: top-level `base64` / `mimeType`
  /// (or `path`), not a nested `image` object.
  Future<Map<String, Object?>> visionOcr({
    required Map<String, Object?> image,
    String? locale,
  }) {
    _assertImageAllowed(image);
    return _provider.visionOcr(_visionWireParams(image, locale: locale));
  }

  /// Vision barcode scan (`foundationmodels.vision.barcode`).
  Future<Map<String, Object?>> visionBarcode({
    required Map<String, Object?> image,
  }) {
    _assertImageAllowed(image);
    return _provider.visionBarcode(_visionWireParams(image));
  }

  /// Flatten consumer image maps into the Core VisionHandler wire shape.
  Map<String, Object?> _visionWireParams(
    Map<String, Object?> image, {
    String? locale,
  }) {
    final params = <String, Object?>{};
    final base64 = image['base64'];
    final path = image['path'];
    final mimeType = image['mimeType'];
    if (base64 != null) params['base64'] = base64;
    if (path != null) params['path'] = path;
    if (mimeType != null) params['mimeType'] = mimeType;
    // Preserve nested form for providers that already unwrap `image`.
    if (params.isEmpty) {
      params['image'] = image;
    }
    if (locale != null) params['locale'] = locale;
    return params;
  }

  /// Attach user feedback to a prior generation
  /// (`foundationmodels.feedback.logAttachment`).
  ///
  /// Native Core requires [sessionId] (LanguageModelSession). Prefer
  /// [sessionId]; [generationId] is kept for mock/telemetry correlation and
  /// is used as a fallback session key when [sessionId] is omitted.
  Future<Map<String, Object?>> logFeedbackAttachment({
    String? sessionId,
    String? generationId,
    required String sentiment,
    String? comment,
    String? desiredResponseText,
    Map<String, Object?>? metadata,
  }) {
    final sid = sessionId ?? generationId;
    if (sid == null || sid.isEmpty) {
      throw ArgumentError(
        'logFeedbackAttachment requires sessionId (native) or generationId.',
      );
    }
    return _provider.logFeedbackAttachment({
      'sessionId': sid,
      if (generationId != null) 'generationId': generationId,
      'sentiment': sentiment,
      if (comment != null) 'comment': comment,
      if (desiredResponseText != null) 'desiredResponseText': desiredResponseText,
      if (metadata != null) 'metadata': metadata,
    });
  }

  /// Deliver a duplex tool result (`foundationmodels.tools.result`).
  Future<Map<String, Object?>> submitToolResult({
    required String toolCallId,
    Object? output,
    Map<String, Object?>? error,
  }) =>
      _provider.submitToolResult({
        'toolCallId': toolCallId,
        if (output != null) 'output': output,
        if (error != null) 'error': error,
      });

  void _assertImageAllowed(Map<String, Object?> image) {
    final path = image['path'] as String?;
    if (path == null) return;
    if (!_security.isPathAllowed(path)) {
      throw ArgumentError.value(
        path,
        'image.path',
        'Path is outside SecurityConfig.allowedImageRoots (fail-closed).',
      );
    }
  }

  // --- Core generation ----------------------------------------------------------

  /// Unary generation without an explicit session.
  ///
  /// Only streaming is truly interruptible: cancelling [cancelToken] here
  /// stops the Dart wait but not the native generation.
  ///
  /// Callback tools are **stream-only**: if [tools] contains any
  /// [FmTool.callback], this throws [ToolCallbacksRequireStreamingException]
  /// before any provider/transport call.
  Future<FmResponse> respond({
    required String input,
    String? instructions,
    GenerationOptions? options,
    FmSchema? schema,
    List<FmTool> tools = const [],
    CancelToken? cancelToken,
  }) {
    _assertNoCallbackToolsOnUnary(tools);
    final request = _buildRequest(
      input: input,
      instructions: instructions,
      options: options,
      schema: schema,
      tools: tools,
    );
    return _respondWithPolicy(request, cancelToken);
  }

  /// Streaming generation without an explicit session.
  ///
  /// See [FmSession.stream] for the full cancellation contract.
  ///
  /// When [tools] includes callback tools and [autoExecuteTools] is `true`
  /// (default), the runtime executes them on each [ToolCallRequest] and
  /// submits `foundationmodels.tools.result` (duplex). Set
  /// [autoExecuteTools] to `false` when an external owner (agent/HITL
  /// router) is the sole executor — tools still go on the wire and events
  /// still yield, but the runtime will not submit results.
  Stream<FmStreamEvent> stream({
    required String input,
    String? instructions,
    GenerationOptions? options,
    FmSchema? schema,
    List<FmTool> tools = const [],
    bool autoExecuteTools = true,
    CancelToken? cancelToken,
  }) {
    final request = _buildRequest(
      input: input,
      instructions: instructions,
      options: options,
      schema: schema,
      tools: tools,
      autoExecuteTools: autoExecuteTools,
    );
    return _streamWithCancel(request, cancelToken);
  }

  // --- Sessions ------------------------------------------------------------------

  /// Mints a **lazy** session. No native session exists until the first
  /// [FmSession.respond] / [FmSession.stream] — and that first request's
  /// instructions win (see [FmSession] docs).
  Future<FmSession> createSession({String? instructions}) async {
    return FmSession.mint(
      id: _nextId('ses'),
      runtime: this,
      instructions: instructions,
    );
  }

  /// Internal: unary generation bound to [session].
  Future<FmResponse> respondInSession(
    FmSession session, {
    required String input,
    String? instructions,
    GenerationOptions? options,
    FmSchema? schema,
    List<FmTool> tools = const [],
    CancelToken? cancelToken,
  }) {
    _assertNoCallbackToolsOnUnary(tools);
    final request = _buildRequest(
      input: input,
      // First request wins: pass the session instructions only while the
      // native session does not exist yet.
      instructions: session.isMaterialized ? null : session.instructions,
      options: options,
      schema: schema,
      sessionId: session.id,
      tools: tools,
    );
    return _respondWithPolicy(request, cancelToken)
        .then((response) {
      session.markMaterialized();
      return response;
    });
  }

  /// Internal: streaming generation bound to [session].
  Stream<FmStreamEvent> streamInSession(
    FmSession session, {
    required String input,
    String? instructions,
    GenerationOptions? options,
    FmSchema? schema,
    List<FmTool> tools = const [],
    bool autoExecuteTools = true,
    CancelToken? cancelToken,
  }) {
    final request = _buildRequest(
      input: input,
      instructions: session.isMaterialized ? null : session.instructions,
      options: options,
      schema: schema,
      sessionId: session.id,
      tools: tools,
      autoExecuteTools: autoExecuteTools,
    );
    session.markMaterialized();
    return _streamWithCancel(request, cancelToken);
  }

  /// Internal: transitions a materialized native session.
  Future<void> transitionSessionInternal({
    required String sessionId,
    String? instructions,
  }) =>
      _provider.transitionSession(
        sessionId: sessionId,
        instructions: instructions,
      );

  /// Internal: pre-warms a session/model.
  Future<Map<String, Object?>> prewarmSessionInternal({
    String? sessionId,
    String? model,
  }) =>
      _provider.prewarm(sessionId: sessionId, model: model);

  /// Internal: disposes a materialized native session.
  Future<void> disposeSessionInternal(String sessionId) =>
      _provider.disposeSession(sessionId);

  // --- Primitives ------------------------------------------------------------------

  /// Classifies [input] into exactly one of [labels] (deterministic on the
  /// mock; guided `enum` schema on real backends).
  Future<String> classify({
    required String input,
    required List<String> labels,
    GenerationOptions? options,
    CancelToken? cancelToken,
  }) async {
    if (labels.isEmpty) {
      throw ArgumentError.value(labels, 'labels', 'must not be empty');
    }
    final schema = FmSchema.object({
      'label': FmSchema.string(enumValues: labels),
    }, required: const ['label']);
    final response = await respond(
      input: input,
      options: options,
      schema: schema,
      cancelToken: cancelToken,
    );
    final structured = response.structured;
    final label =
        structured is Map ? structured['label'] as String? : null;
    return label ?? labels[_fallbackIndex(input, labels.length)];
  }

  /// Extracts structured data per [schema].
  ///
  /// - [strict] (default `true`): output must validate; failures throw
  ///   [StructuredOutputValidationException] (no raw model content attached).
  /// - [repair]: allows a best-effort fix-up pass (forwarded as metadata;
  ///   enforced by the native core in a later phase).
  Future<Object?> extract({
    required String input,
    required FmSchema schema,
    bool strict = true,
    bool repair = false,
    GenerationOptions? options,
    CancelToken? cancelToken,
  }) async {
    // Fail-fast locally on out-of-subset schemas before any native call.
    schema.toJson();
    final response = await respond(
      input: input,
      options: options,
      schema: schema,
      cancelToken: cancelToken,
    );
    final structured = response.structured;
    if (strict && structured == null) {
      throw const StructuredOutputValidationException(
        message: 'Guided generation returned no structured content.',
      );
    }
    return structured;
  }

  /// Ranks [candidates] against [input] (best first). Deterministic on the
  /// mock.
  Future<List<String>> rank({
    required String input,
    required List<String> candidates,
    GenerationOptions? options,
    CancelToken? cancelToken,
  }) async {
    if (candidates.isEmpty) {
      throw ArgumentError.value(
          candidates, 'candidates', 'must not be empty');
    }
    final schema = FmSchema.object({
      'ranking': FmSchema.array(FmSchema.integer(), minItems: 1),
    }, required: const ['ranking']);
    final response = await respond(
      input: '$input\n\nCandidates:\n${candidates.join('\n')}',
      options: options,
      schema: schema,
      cancelToken: cancelToken,
    );
    final structured = response.structured;
    final ranking = structured is Map ? structured['ranking'] : null;
    if (ranking is List) {
      final indices = ranking
          .map((e) => e is int ? e : (e is num ? e.toInt() : null))
          .whereType<int>()
          .toList();
      final seen = <int>{};
      final ordered = <String>[
        for (final i in indices)
          if (i >= 0 && i < candidates.length && seen.add(i)) candidates[i],
        // Append any candidates the model omitted, preserving order.
        for (var i = 0; i < candidates.length; i++)
          if (!seen.contains(i)) candidates[i],
      ];
      if (ordered.length == candidates.length) {
        // Always growable: callers may sort/mutate the result.
        return List<String>.of(ordered);
      }
    }
    // fail-safe: never drop candidates; always return a growable copy.
    return List<String>.of(candidates);
  }

  /// Summarizes [input].
  Future<String> summarize({
    required String input,
    GenerationOptions? options,
    CancelToken? cancelToken,
  }) async {
    final response = await respond(
      input: 'Summarize concisely.\n\n$input',
      options: options,
      cancelToken: cancelToken,
    );
    return response.text ?? '';
  }

  // --- Internals -------------------------------------------------------------------

  int _fallbackIndex(String input, int length) {
    var hash = 0;
    for (final unit in input.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash % length;
  }

  /// Local stream-only enforcement (phase 4): callback tools never reach the
  /// transport on a unary path.
  void _assertNoCallbackToolsOnUnary(List<FmTool> tools) {
    final names = [
      for (final t in tools)
        if (t.requiresStreaming) t.name,
    ];
    if (names.isEmpty) return;
    throw ToolCallbacksRequireStreamingException(
      message: 'Callback tools require stream(), not respond(): $names',
      tools: names,
    );
  }

  FmRequest _buildRequest({
    required String input,
    String? instructions,
    GenerationOptions? options,
    FmSchema? schema,
    String? sessionId,
    List<FmTool> tools = const [],
    bool autoExecuteTools = true,
  }) {
    final effectiveOptions = options ?? GenerationOptions.defaults;
    effectiveOptions.validate();
    final request = FmRequest(
      id: _nextId('rpc'),
      input: input,
      instructions: instructions,
      options: effectiveOptions,
      schema: schema,
      sessionId: sessionId,
      sessionInstructions: instructions,
      tools: tools,
      autoExecuteTools: autoExecuteTools,
    );
    return request;
  }

  Future<FmResponse> _respondWithPolicy(
    FmRequest request,
    CancelToken? cancelToken,
  ) async {
    await _preflight(request);
    if (cancelToken != null) {
      final response = await Future.any<FmResponse>([
        _provider.respond(request),
        cancelToken.whenCancelled.then(
          (_) => throw GenerationCancelledException(
            message: 'Generation ${request.id} was cancelled before '
                'completion (unary wait aborted; the native generation may '
                'still have completed — only streaming is truly interruptible).',
          ),
        ),
      ]);
      return response;
    }
    return _provider.respond(request);
  }

  /// Executes a duplex tool call and submits `tools.result` to the provider.
  Future<void> _executeToolCall(
    FmRequest request,
    ToolCallRequest event,
  ) async {
    final toolCallId = event.toolCallId;
    final toolName = event.toolName;
    if (toolCallId == null || toolName == null) return;

    FmTool? tool;
    for (final t in request.tools) {
      if (t.name == toolName) {
        tool = t;
        break;
      }
    }

    if (tool == null || tool.callback == null) {
      await _provider.submitToolResult({
        'toolCallId': toolCallId,
        'error': {
          'code': 'TOOL_CALLBACK_NOT_FOUND',
          'message': 'No host handler for tool "$toolName".',
        },
      });
      return;
    }

    try {
      final output = await tool.callback!(event.arguments);
      await _provider.submitToolResult({
        'toolCallId': toolCallId,
        'output': output,
      });
    } catch (e) {
      await _provider.submitToolResult({
        'toolCallId': toolCallId,
        'error': {
          'code': 'TOOL_CALLBACK_ERROR',
          'message': e.toString(),
        },
      });
    }
  }

  Stream<FmStreamEvent> _streamWithCancel(
    FmRequest request,
    CancelToken? cancelToken,
  ) {
    final controller = StreamController<FmStreamEvent>(sync: true);
    StreamSubscription<FmStreamEvent>? subscription;
    var settled = false;
    // Sequential duplex: one callback at a time per stream (daemon parity).
    Future<void> toolChain = Future<void>.value();

    void settle() {
      if (settled) return;
      settled = true;
      unawaited(subscription?.cancel());
      if (!controller.isClosed) {
        unawaited(controller.close());
      }
    }

    void forward(FmStreamEvent event) {
      if (settled || controller.isClosed) return;
      if (event is StreamError) {
        controller.addError(event.toException());
        settle();
        return;
      }
      controller.add(event);
      // Single-executor contract: only auto-run callbacks when the request
      // opts in. Agents set autoExecuteTools:false so their router/HITL is
      // the sole owner of submitToolResult (avoids double submission).
      if (event is ToolCallRequest &&
          request.tools.isNotEmpty &&
          request.autoExecuteTools) {
        // Chain tool execution after yielding the event so consumers observe
        // the request before the result is submitted.
        toolChain = toolChain.then((_) => _executeToolCall(request, event));
      }
      if (event is StreamDone) {
        // Wait for any in-flight tool submission before settling.
        unawaited(toolChain.whenComplete(settle));
      }
    }

    controller.onListen = () async {
      try {
        await _preflight(request);
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
        settle();
        return;
      }

      if (cancelToken != null && cancelToken.isCancelled) {
        unawaited(_provider.cancelGeneration(request.id));
        if (!controller.isClosed) {
          controller.addError(GenerationCancelledException(
            message: 'Generation ${request.id} cancelled.',
          ));
        }
        settle();
        return;
      }

      // Watch cancel token without converting the Future to a multi-listen
      // stream — complete once, then terminate with a typed cancel error if
      // the provider has not already settled the stream.
      if (cancelToken != null) {
        unawaited(cancelToken.whenCancelled.then((_) async {
          await _provider.cancelGeneration(request.id);
          if (settled || controller.isClosed) return;
          controller.addError(GenerationCancelledException(
            message: 'Generation ${request.id} cancelled.',
          ));
          settle();
        }));
      }

      subscription = _provider.stream(request).listen(
            forward,
            onError: (Object error, StackTrace st) {
              if (!settled && !controller.isClosed) {
                controller.addError(error, st);
              }
              settle();
            },
            onDone: () {
              // Provider may end without StreamDone if cancelled mid-flight.
              unawaited(toolChain.whenComplete(settle));
            },
          );
    };

    controller.onCancel = () {
      if (settled) return;
      settled = true;
      // Abandoning the subscription is an implicit cancel.
      unawaited(_provider.cancelGeneration(request.id));
      unawaited(subscription?.cancel());
    };

    return controller.stream;
  }

  Future<void> _preflight(FmRequest request) async {
    if (!_contextPolicy.performsPreflight) return;
    final count = await _provider.countTokens(FmCountTokensRequest(
      input: request.input,
      instructions: request.instructions,
      schema: request.schema,
      model: request.model,
    ));
    if (!count.fits) {
      // `compact` is a phase-1 stub: it currently fails fast like `guard`
      // (never silently drops transcript content).
      throw ContextOverflowException(
        message: 'Request needs ${count.total} tokens but the context window '
            'is ${count.contextWindow} (${count.remaining} remaining).',
        contextSize: count.contextWindow,
        tokenCount: count.total,
        details: count.toMap(),
      );
    }
  }
}
