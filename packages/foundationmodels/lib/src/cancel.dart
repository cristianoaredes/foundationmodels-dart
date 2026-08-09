/// Cooperative cancellation for streaming generations.
///
/// Mirrors the upstream `AbortSignal` semantics, adapted to the in-process
/// transport: cancelling a [CancelTokenSource] makes the runtime send
/// `foundationmodels.generation.cancel` with `generationId` equal to the
/// streaming `requestId`; the native side then terminates the stream with a
/// `GENERATION_CANCELLED` error event, surfaced as
/// `GenerationCancelledException`.
///
/// **Scope (verbatim in spirit from upstream):** only streaming is truly
/// interruptible. Cancelling a unary `respond` stops the Dart side from
/// waiting, but does not stop the native generation — "do not read
/// 'cancellation is reachable from the public API' as 'every operation is
/// interruptible'". Cancelling a stream subscription without a token also
/// sends an implicit cancel (analogous to the daemon's "client EOF is an
/// implicit cancel"). Repeated cancels are idempotent.
library;

import 'dart:async';

/// A read-only handle that observers use to watch for cancellation.
class CancelToken {
  CancelToken._(this._source);

  final CancelTokenSource _source;

  /// Whether [CancelTokenSource.cancel] has been called.
  bool get isCancelled => _source.isCancelled;

  /// Completes when the token is cancelled.
  ///
  /// If the token is already cancelled, the future is already complete.
  Future<void> get whenCancelled => _source._whenCancelled;
}

/// The source that owns and triggers a [CancelToken].
class CancelTokenSource {
  final Completer<void> _completer = Completer<void>();
  bool _cancelled = false;
  CancelToken? _token;

  /// The token observed by consumers.
  CancelToken get token => _token ??= CancelToken._(this);

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Future completed by [cancel].
  Future<void> get _whenCancelled => _completer.future;

  /// Cancels the associated token. Idempotent: subsequent calls are no-ops.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _completer.complete();
  }
}
