/// Stable JSON-RPC method names of the FoundationModels protocol (v2).
///
/// These mirror `docs/protocol.md` of the upstream `foundationmodels-js`
/// project. The transport envelope is
/// `{"id": "rpc_...", "method": FmMethods.x, "params": {...}}`.
abstract final class FmMethods {
  /// Health probe. Returns build/version information about the native core.
  static const String health = 'foundationmodels.health';

  /// Availability report for Apple Intelligence on this device.
  static const String availability = 'foundationmodels.availability';

  /// Feature/capability descriptor used for feature-detect before use.
  static const String capabilities = 'foundationmodels.capabilities';

  /// Token accounting for a prospective generation request.
  static const String countTokens = 'foundationmodels.context.countTokens';

  /// Explicitly create a native session (sessions are otherwise lazy).
  static const String sessionCreate = 'foundationmodels.sessions.create';

  /// Unary (non-streaming) generation within an optional session.
  static const String sessionRespond = 'foundationmodels.sessions.respond';

  /// Streaming generation; events arrive on the multiplexed event channel.
  static const String sessionStream = 'foundationmodels.sessions.stream';

  /// Dispose a native session and drop its transcript.
  static const String sessionDispose = 'foundationmodels.sessions.dispose';

  /// Change instructions of an existing session, preserving its transcript.
  static const String sessionTransition = 'foundationmodels.sessions.transition';

  /// Pre-warm a session so the first user-visible response is faster.
  static const String sessionPrewarm = 'foundationmodels.sessions.prewarm';

  /// Cooperative cancellation of an in-flight streaming generation.
  static const String generationCancel = 'foundationmodels.generation.cancel';

  /// Deliver the result (or error) of a client-executed tool callback.
  static const String toolsResult = 'foundationmodels.tools.result';

  /// Vision OCR over a base64 or allowlisted-path image.
  static const String visionOcr = 'foundationmodels.vision.ocr';

  /// Vision barcode scanning over a base64 or allowlisted-path image.
  static const String visionBarcode = 'foundationmodels.vision.barcode';

  /// Attach user feedback (thumbs up/down + attachments) to a generation.
  static const String feedbackLogAttachment =
      'foundationmodels.feedback.logAttachment';
}
