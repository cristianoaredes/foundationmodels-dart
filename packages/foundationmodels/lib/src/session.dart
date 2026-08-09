/// Lazy generation sessions, mirroring the upstream semantics.
library;

import 'package:foundationmodels_platform_interface/foundationmodels_platform_interface.dart';

import 'cancel.dart';
import 'options.dart';
import 'provider.dart';
import 'runtime.dart';
import 'schema.dart';

/// A conversation session with the model.
///
/// **Lazy semantics (upstream "Instruction Precedence" — the #1 consumer
/// pitfall, documented here with the same emphasis):**
///
/// - [FoundationModels.createSession] only mints a local `ses_*` id. **No
///   native session exists yet.**
/// - The native session is born on the **first** [respond] or [stream]
///   call, materialized with the instructions known at that moment.
/// - Instructions passed to subsequent requests on an existing session are
///   **ignored** ("first request wins").
/// - To change instructions afterwards: [transition] (preserves the
///   transcript), or [dispose] + `createSession` (blank transcript).
class FmSession {
  /// Internal constructor — sessions are created via
  /// [FoundationModels.createSession].
  FmSession.mint({
    required this.id,
    required FoundationModels runtime,
    String? instructions,
    // ignore: prefer_initializing_formals
  })  : _runtime = runtime,
        // ignore: prefer_initializing_formals
        _instructions = instructions;

  /// Locally minted session id (`ses_...`). Matches the native session id
  /// once materialized.
  final String id;

  final FoundationModels _runtime;
  String? _instructions;
  bool _materialized = false;
  bool _disposed = false;

  /// Whether the native session already exists (created lazily by the first
  /// generation).
  bool get isMaterialized => _materialized;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// The instructions this session was (or will be) materialized with.
  String? get instructions => _instructions;

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('Session $id has been disposed.');
    }
  }

  void markMaterialized() => _materialized = true;

  /// Unary generation within this session.
  ///
  /// [instructions] only take effect on the very first generation of the
  /// session (first request wins); afterwards they are ignored.
  ///
  /// Cancellation scope: only streaming ([stream]) is truly interruptible.
  /// Cancelling a unary [respond] stops the Dart wait but not the native
  /// generation.
  Future<FmResponse> respond({
    required String input,
    String? instructions,
    GenerationOptions? options,
    FmSchema? schema,
    CancelToken? cancelToken,
  }) {
    _ensureUsable();
    return _runtime.respondInSession(
      this,
      input: input,
      instructions: instructions,
      options: options,
      schema: schema,
      cancelToken: cancelToken,
    );
  }

  /// Streaming generation within this session.
  ///
  /// Emits typed [FmStreamEvent]s (`TextDelta`, `StructuredDelta`, ...)
  /// terminating with [StreamDone]; failures surface as typed
  /// [FoundationModelsException]s on the stream.
  ///
  /// Cancelling [cancelToken] sends `foundationmodels.generation.cancel`
  /// with `generationId == requestId`; the stream then terminates with a
  /// [GenerationCancelledException]. Cancelling the subscription without a
  /// token is an implicit cancel. Repeated cancels are idempotent.
  Stream<FmStreamEvent> stream({
    required String input,
    String? instructions,
    GenerationOptions? options,
    FmSchema? schema,
    CancelToken? cancelToken,
  }) {
    _ensureUsable();
    return _runtime.streamInSession(
      this,
      input: input,
      instructions: instructions,
      options: options,
      schema: schema,
      cancelToken: cancelToken,
    );
  }

  /// Changes the session instructions while **preserving the transcript**
  /// (`foundationmodels.sessions.transition`).
  ///
  /// If the native session does not exist yet (lazy), only the local
  /// instructions are updated — no transport call is made.
  Future<void> transition({String? instructions}) async {
    _ensureUsable();
    if (_materialized) {
      await _runtime.transitionSessionInternal(
        sessionId: id,
        instructions: instructions,
      );
    }
    if (instructions != null) {
      _instructions = instructions;
    }
  }

  /// Disposes the session. The native transcript is dropped; the object
  /// becomes unusable. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_materialized) {
      await _runtime.disposeSessionInternal(id);
    }
  }
}
