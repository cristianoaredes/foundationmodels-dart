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
    required FmProvider provider,
    required SecurityConfig security,
    required ContextPolicy contextPolicy,
  })  : _provider = provider,
        _security = security,
        _contextPolicy = contextPolicy;

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

  // --- Core generation ----------------------------------------------------------

  /// Unary generation without an explicit session.
  ///
  /// Only streaming is truly interruptible: cancelling [cancelToken] here
  /// stops the Dart wait but not the native generation.
  Future<FmResponse> respond({
    required String input,
    String? instructions,
    GenerationOptions? options,
    FmSchema? schema,
    CancelToken? cancelToken,
  }) {
    final request = _buildRequest(
      input: input,
      instructions: instructions,
      options: options,
      schema: schema,
    );
    return _respondWithPolicy(request, cancelToken);
  }

  /// Streaming generation without an explicit session.
  ///
  /// See [FmSession.stream] for the full cancellation contract.
  Stream<FmStreamEvent> stream({
    required String input,
    String? instructions,
    GenerationOptions? options,
    FmSchema? schema,
    CancelToken? cancelToken,
  }) {
    final request = _buildRequest(
      input: input,
      instructions: instructions,
      options: options,
      schema: schema,
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
    CancelToken? cancelToken,
  }) {
    final request = _buildRequest(
      input: input,
      // First request wins: pass the session instructions only while the
      // native session does not exist yet.
      instructions: session.isMaterialized ? null : session.instructions,
      options: options,
      schema: schema,
      sessionId: session.id,
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
    CancelToken? cancelToken,
  }) {
    final request = _buildRequest(
      input: input,
      instructions: session.isMaterialized ? null : session.instructions,
      options: options,
      schema: schema,
      sessionId: session.id,
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
      final indices = ranking.whereType<int>().toList();
      final seen = <int>{};
      final ordered = <String>[
        for (final i in indices)
          if (i >= 0 && i < candidates.length && seen.add(i)) candidates[i],
        // Append any candidates the model omitted, preserving order.
        for (var i = 0; i < candidates.length; i++)
          if (!seen.contains(i)) candidates[i],
      ];
      if (ordered.length == candidates.length) return ordered;
    }
    return candidates; // fail-safe: never drop candidates.
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

  FmRequest _buildRequest({
    required String input,
    String? instructions,
    GenerationOptions? options,
    FmSchema? schema,
    String? sessionId,
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

  Stream<FmStreamEvent> _streamWithCancel(
    FmRequest request,
    CancelToken? cancelToken,
  ) async* {
    await _preflight(request);
    if (cancelToken == null) {
      yield* _provider.stream(request);
      return;
    }
    final controller = StreamController<FmStreamEvent>();
    StreamSubscription<FmStreamEvent>? subscription;
    StreamSubscription<void>? cancelSubscription;

    controller.onListen = () {
      subscription = _provider.stream(request).listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
      cancelSubscription = cancelToken.whenCancelled.then((_) async {
        // Cooperative cancel: notify the native side, then terminate with the
        // typed cancellation error. Idempotent at the provider level.
        await _provider.cancelGeneration(request.id);
        await subscription?.cancel();
        if (!controller.isClosed) {
          controller.addError(GenerationCancelledException(
            message: 'Generation ${request.id} cancelled.',
          ));
          await controller.close();
        }
      }).asStream().listen(null);
    };
    controller.onCancel = () async {
      // Abandoning the subscription is an implicit cancel.
      await _provider.cancelGeneration(request.id);
      await subscription?.cancel();
      await cancelSubscription?.cancel();
    };
    yield* controller.stream;
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
