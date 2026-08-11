/// Redaction mode mirrored from foundationmodels SecurityConfig.
enum PolicyRedactionMode { off, logOnly, auto }

/// One audit entry produced by [FmRedactionPolicy.apply].
class FmAuditEntry {
  const FmAuditEntry({
    required this.kind,
    required this.count,
    this.sample,
  });

  final String kind;
  final int count;
  final String? sample;

  Map<String, Object?> toJson() => {
        'kind': kind,
        'count': count,
        if (sample != null) 'sample': sample,
      };
}

/// Result of redacting text.
class FmRedactionResult {
  const FmRedactionResult({
    required this.text,
    required this.audit,
    required this.mode,
  });

  final String text;
  final List<FmAuditEntry> audit;
  final PolicyRedactionMode mode;
}

/// Simple offline redaction of common PII patterns.
///
/// Patterns are intentionally conservative and pure-Dart (no ML). This is the
/// phase-3 policy surface; production apps can swap the regex set.
class FmRedactionPolicy {
  /// Creates a policy for [mode].
  const FmRedactionPolicy({this.mode = PolicyRedactionMode.off});

  final PolicyRedactionMode mode;

  static final _email = RegExp(
    r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
    caseSensitive: false,
  );
  static final _phone = RegExp(r'\b\+?\d[\d\s().-]{7,}\d\b');

  /// Applies redaction according to [mode].
  FmRedactionResult apply(String input) {
    if (mode == PolicyRedactionMode.off) {
      return FmRedactionResult(text: input, audit: const [], mode: mode);
    }
    final audit = <FmAuditEntry>[];
    var text = input;

    final emails = _email.allMatches(text).length;
    if (emails > 0) {
      audit.add(FmAuditEntry(kind: 'email', count: emails));
      if (mode == PolicyRedactionMode.auto) {
        text = text.replaceAll(_email, '[REDACTED_EMAIL]');
      }
    }
    final phones = _phone.allMatches(text).length;
    if (phones > 0) {
      audit.add(FmAuditEntry(kind: 'phone', count: phones));
      if (mode == PolicyRedactionMode.auto) {
        text = text.replaceAll(_phone, '[REDACTED_PHONE]');
      }
    }
    return FmRedactionResult(text: text, audit: audit, mode: mode);
  }
}
