/// Security configuration and invariants of the runtime.
///
/// Invariants inherited from upstream (also enforced as doc contracts):
///
/// - **Instructions are a trusted channel.** The runtime *never* concatenates
///   user input, tool results or web content into `instructions` — callers
///   must follow the same rule (upstream TCK-0209/FND-0142).
/// - **Errors never carry raw model content** (`rawContent`), mirroring the
///   upstream serialization contract.
/// - **Image allowlist is fail-closed**: without entries in
///   [SecurityConfig.allowedImageRoots], path-based images are rejected by
///   the native core; the runtime only forwards the configuration.
/// - **No silent cloud fallback**: the mock never touches the network and
///   the Apple provider stays on-device.
library;

/// PII redaction mode (surface for the phase-3 policy package).
enum RedactionMode {
  /// No redaction.
  off,

  /// Redact only in logs/audit entries.
  logOnly,

  /// Redact before content reaches the model.
  auto,
}

/// Security knobs for [createFoundationModels].
class SecurityConfig {
  /// Creates the configuration.
  const SecurityConfig({
    this.allowedImageRoots = const [],
    this.redaction = RedactionMode.off,
  });

  /// Conservative defaults: empty image allowlist (fail-closed), redaction
  /// off.
  static const SecurityConfig defaults = SecurityConfig();

  /// Directories from which path-based images may be read. Empty means all
  /// path-based images are rejected (fail-closed). Inline base64 images with
  /// an explicit `mimeType` are unaffected.
  final List<String> allowedImageRoots;

  /// PII redaction mode (wired to the policy package in a later phase).
  final RedactionMode redaction;

  /// Fail-closed allowlist check for path-based images.
  ///
  /// Returns `false` when [allowedImageRoots] is empty (nothing is allowed)
  /// or when [path] is not under any allowed root. Base64 images never call
  /// this method.
  bool isPathAllowed(String path) {
    if (allowedImageRoots.isEmpty) return false;
    // Normalize trivial trailing slashes for prefix comparison. Full path
    // canonicalization (symlinks, `..`) is enforced natively; this is the
    // Dart-side first gate so we never silently forward a banned path.
    final normalized = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    for (final root in allowedImageRoots) {
      final normalizedRoot =
          root.endsWith('/') ? root.substring(0, root.length - 1) : root;
      if (normalized == normalizedRoot ||
          normalized.startsWith('$normalizedRoot/')) {
        return true;
      }
    }
    return false;
  }
}
