# Phase 3 — Full surface (U2–U5)

Implementation spec for ADR-0001 §16 phase 3 ("Superfície completa"). Brings
the remaining core surface on-device: token accounting, guided generation,
multimodal, vision, feedback, full session lifecycle, runtime config knobs,
and the optional policy/redaction package. Closes with a measured
`docs/parity.md` update.

## Goal

Every core capability the Swift core already implements is reachable from
`package:foundationmodels` and verified on device: `countTokens` +
`contextPolicy: guard` measured (U2), guided generation via `extract` with
strict/repair semantics (validated locally by `FmSchema`), multimodal input
(base64 + allowlisted paths with `label`), Vision OCR/barcode (U3),
`feedback.logAttachment` (U4), session `transition`/`prewarm`/`history` (U5),
runtime config (`useCase`, `guardrails`, `maxTotalImageBytes`), and the
optional `foundationmodels_policy` package (redaction `off`/`log-only`/`auto`
+ audit entries, per ADR-0001 §12).

## Depends on

- Phases 0–2 (streaming and cancellation verified on device).
- Upstream tickets: **U2** (`countTokens(params:)`), **U3**
  (`visionOcr`/`visionBarcode`), **U4** (`logFeedbackAttachment(params:)`),
  **U5** (`createSession`/`transition`/`prewarm` with `history`). The Swift
  router cases already exist in `FoundationModelsPlugin.swift` and compile
  once the tickets land.
- Existing pieces reused as-is: `FmMethods.countTokens/visionOcr/
  visionBarcode/feedbackLogAttachment/sessionTransition/sessionPrewarm`
  (`packages/foundationmodels_platform_interface/lib/src/methods.dart`),
  `TokenCount`/`Usage` (`models.dart`), `FoundationModels.guardContext`,
  `ContextPolicy` (`context_policy.dart`), `SecurityConfig`/`RedactionMode`
  (`security.dart`), `FmSchema` with `SchemaMode.output` fail-fast
  (`schema.dart`).

## Scope

### In

- On-device measurement of `countTokens` and the `guardContext` pre-flight
  path (`ContextPolicy.guard`), including the `estimated` flag contract.
- Guided generation on device through `extract`/`respond(schema:)`; defined
  semantics for `strict`/`repair` including client-side validation.
- Multimodal input: image content parts (base64 inline and path-based) with
  fail-closed `allowedImageRoots`, `mimeType`, and `label` metadata;
  `maxTotalImageBytes` enforced locally.
- `FoundationModels.visionOcr` / `visionBarcode`.
- `FoundationModels.logFeedbackAttachment`.
- Session lifecycle: `FmSession.prewarm()`, `createSession(history:)`,
  `transition` (already in `session.dart`; verify on device).
- Runtime config knobs on `createFoundationModels`: `useCase`, `guardrails`,
  `maxTotalImageBytes`.
- `foundationmodels_policy`: optional pure-Dart package implementing PII
  redaction (`off`/`log-only`/`auto`) and audit entries, wired to
  `SecurityConfig.redaction`.
- `docs/parity.md`: flip the phase-3 rows to `supported` with evidence.

### Out

- Tool calling (phase 4) — including `SchemaMode.tool` use beyond what
  already exists, and the `tool` field of `TokenCount` remaining 0 until
  tools land.
- `ContextPolicy.compact` real compaction. The stub (behaves like `guard`,
  fail-fast, never silently drops content) stays; real transcript compaction
  is deferred and must be recorded as such in `docs/parity.md` (partial).
- PCC inference (gated by U9); availability/quota surfaces only.
- HITL, eval, RAG, agent kit, MLX/CoreAI, server (phases 4–8).

## API deltas

All additions live in `package:foundationmodels` unless noted. Nothing
existing is removed; `FmRequest`/`FmResponse` gain fields with defaults.

```dart
// packages/foundationmodels/lib/src/content.dart (new)
/// A single input content part. Text today is a plain String; images are
/// new in phase 3.
sealed class FmContentPart {
  const FmContentPart();
}

final class FmTextPart extends FmContentPart {
  const FmTextPart(this.text);
  final String text;
}

/// An image. Exactly one of [base64] (+ [mimeType]) or [path] is set.
/// Path-based images are subject to the fail-closed
/// [SecurityConfig.allowedImageRoots] allowlist (enforced natively; Dart
/// only forwards). [label] is metadata (TCK-0227), travels outside the
/// allowlist, and is required by native tools (phase 4).
final class FmImagePart extends FmContentPart {
  const FmImagePart.base64({required String base64, required String mimeType, String? label});
  const FmImagePart.path({required String path, String? label});
  final String? base64;
  final String? mimeType;
  final String? path;
  final String? label;

  /// Serializes to the protocol part:
  /// {"type": "image", "base64": ..., "mimeType": ..., "label": ...} or
  /// {"type": "image", "path": ..., "label": ...}.
  Map<String, Object?> toJson();
}

// packages/foundationmodels/lib/src/runtime.dart (extends FoundationModels)
/// Token accounting — exists since phase 1; phase 3 verifies it on device.
Future<TokenCount> countTokens({required String input, String? instructions,
    FmSchema? schema, String model = 'apple.system'});

/// Vision OCR over an image part (U3).
Future<VisionOcrResult> visionOcr({required FmImagePart image});

/// Vision barcode scanning over an image part (U3).
Future<VisionBarcodeResult> visionBarcode({required FmImagePart image});

/// Attach user feedback to a generation (U4). [sentiment] mirrors the
/// upstream thumbs up/down contract; attachments travel as base64 parts.
Future<void> logFeedbackAttachment({
  required String generationId,
  required String sentiment, // "positive" | "negative"
  String? comment,
  List<FmImagePart> attachments = const [],
});

/// Multimodal-capable generation overload: [content] supersedes [input]
/// when provided; [input] remains the text-only convenience path.
Future<FmResponse> respond({
  String? input,
  List<FmContentPart>? content,
  String? instructions,
  GenerationOptions? options,
  FmSchema? schema,
  CancelToken? cancelToken,
  String model = 'apple.system',
});
```

```dart
// packages/foundationmodels/lib/src/session.dart (extends FmSession)
/// Pre-warms the native session (U5) so the first user-visible response is
/// faster. No-op-safe on a disposed session check; forwards
/// `foundationmodels.sessions.prewarm`.
Future<void> prewarm();

// packages/foundationmodels/lib/src/runtime.dart (extends createSession)
/// [history] seeds the native transcript (U5). Providing [history] forces
/// eager materialization via `foundationmodels.sessions.create` at
/// createSession time; without it the session stays lazy.
Future<FmSession> createSession({String? instructions, List<FmTranscriptEntry>? history});

// packages/foundationmodels/lib/src/config.dart (new) + createFoundationModels
/// Runtime config knobs (ADR-0001 §17.2). Forwarded on session create and
/// generation envelopes; `maxTotalImageBytes` is additionally enforced
/// locally before any transport call.
class FmRuntimeConfig {
  const FmRuntimeConfig({this.useCase, this.guardrails, this.maxTotalImageBytes});
  final String? useCase;                 // e.g. "general" | "contentTagging" (upstream values)
  final String? guardrails;              // upstream guardrail mode string
  final int? maxTotalImageBytes;         // local + native enforcement
}

Future<FoundationModels> createFoundationModels({
  List<FmProvider>? providers,
  SecurityConfig? security,
  ContextPolicy? contextPolicy,
  FmRuntimeConfig? config, // NEW
});

// packages/foundationmodels/lib/src/provider.dart (extends FmProvider + FmRequest)
abstract class FmProvider {
  // ... existing members ...
  Future<VisionOcrResult> visionOcr(FmVisionRequest request);      // NEW
  Future<VisionBarcodeResult> visionBarcode(FmVisionRequest request); // NEW
  Future<void> logFeedbackAttachment(FmFeedbackRequest request);   // NEW
  Future<void> prewarmSession({required String sessionId});        // NEW
}

class FmRequest {
  // NEW fields (all optional, defaults preserve phase-1 behavior):
  final List<FmContentPart>? content;   // multimodal input parts
  final FmRuntimeConfig? config;        // per-runtime knobs, stamped by the runtime
}
```

New value types: `VisionOcrResult` (recognized text blocks + confidence),
`VisionBarcodeResult` (payload + symbology), `FmVisionRequest`,
`FmFeedbackRequest`, `FmTranscriptEntry` (`{"role": "user"|"assistant", "text": ...}`).
`TransportProvider` implements the new methods by forwarding
`FmMethods.visionOcr` / `visionBarcode` / `feedbackLogAttachment` /
`sessionPrewarm`; `MockProvider` returns deterministic fixed results and
reports the corresponding feature flags as `false` in `availability()` until
implemented (fail typed, never fake capability — mock may implement them
deterministically but must keep reporting `estimated` usage and its limited
feature map honestly).

New optional package `packages/foundationmodels_policy/` (pure Dart, no
Flutter, no IO by default):

```dart
/// PII redaction engine mirroring upstream `foundationmodels-policy`.
class FmPolicy {
  FmPolicy({required RedactionMode mode, FmAuditSink? audit});
  final RedactionMode mode; // from package:foundationmodels security.dart

  /// Applies the policy to outbound [text]. In `auto` mode redactions are
  /// applied before content reaches the model; in `logOnly` mode content is
  /// untouched but redactions are recorded; `off` is a no-op.
  String apply(String text, {required FmAuditContext context});
}

/// Receives audit entries (redaction hits) for logging/persistence.
abstract class FmAuditSink {
  void record(FmAuditEntry entry); // entry: timestamp, rule, context, counts — never raw PII
}
```

`SecurityConfig.redaction` (already in `security.dart`) selects the mode;
when a policy package instance is provided to `createFoundationModels`, the
runtime runs `FmPolicy.apply` on user input and tool results before the
provider call — never on `instructions` (trusted channel, ADR-0001 §12).

## Work items

1. **countTokens on device (U2).** Wire `TransportProvider.countTokens`
   (already implemented) on device; assert `TokenCount.fromMap` parses the
   core's breakdown (`input`/`instructions`/`tool`/`schema`/`total`/
   `contextWindow`/`remaining`/`estimated`). Measure: when SDK 27 reports
   measured counts, `estimated` must be `false`; otherwise `true`. Extend
   `mock_provider_test.dart`-style coverage with a fake transport replaying a
   recorded core response.
2. **contextPolicy guard on device.** With
   `createFoundationModels(contextPolicy: ContextPolicy.guard)`, assert:
   (a) a fitting request performs one `countTokens` call then generates;
   (b) an oversized request throws `ContextOverflowException` **locally**
   (zero generation envelopes cross the channel) with `contextSize`,
   `tokenCount`, and the full breakdown in `details` (see
   `FoundationModels.guardContext`). Record the measured context window in
   `docs/parity.md`. Confirm `ContextPolicy.compact` still behaves exactly
   like `guard` (stub) and mark it `partial` in parity.
3. **Guided generation on device.** `extract` with nested object schemas,
   `anyOf`, `$ref` (`#/$defs/...`), and nullable `type: ["T","null"]` — all
   already serializable via `FmSchema`. Define and implement `strict`/`repair`
   semantics: with `strict: true` the runtime **validates the returned
   structured value against the schema locally** and throws
   `StructuredOutputValidationException` on mismatch (details never carry
   `rawContent`, per the errors.dart invariant); with `repair: true` exactly
   one retry is issued with repair instructions before throwing; with
   `strict: false` local validation is skipped (documented tolerance). The
   current instruction-hint behavior in `extract` stays as the prompt-level
   signal; local validation is the new hard guarantee.
4. **Multimodal input.** Implement `FmContentPart`/`FmImagePart`; extend
   `TransportProvider._requestParams` to emit mixed `input` part arrays;
   extend `FmRequest` and `MockProvider` (mock echoes a deterministic
   description; keeps `multimodal: false` in its availability features until
   it actually models images). Fail-closed checks: path-based image without
   any `SecurityConfig.allowedImageRoots` entry is rejected — verify the
   rejection comes from the core (Dart forwards `allowedImageRoots` in the
   session-create/config envelope) and add a local pre-check that throws
   `ArgumentError` when `maxTotalImageBytes` is exceeded (sum of decoded
   base64 sizes + path file sizes where readable). `label` travels on every
   image part (TCK-0227).
5. **Vision OCR/barcode (U3).** Add `FmProvider.visionOcr`/`visionBarcode`,
   `TransportProvider` forwarding, result types, mock deterministic results.
   On device: OCR over a base64 fixture returns non-empty blocks; barcode
   over a QR fixture returns payload + symbology. Unavailable devices surface
   `VisionOcrUnavailableException` / `VisionBarcodeUnavailableException`
   (both already in errors.dart).
6. **Feedback attachment (U4).** Add `FmProvider.logFeedbackAttachment` +
   runtime method; on device assert the envelope resolves without error and
   `FEEDBACK_ATTACHMENT_UNAVAILABLE` maps to
   `FeedbackAttachmentUnavailableException` where unsupported.
7. **Session lifecycle (U5).** `FmSession.prewarm()` →
   `foundationmodels.sessions.prewarm`; `createSession(history:)` → eager
   `foundationmodels.sessions.create` with `history`; verify `transition`
   preserves transcript on device (recall a pre-transition fact
   post-transition). Mock: `hasSession`, `sessionTranscriptLength`, and
   `sessionInstructions` inspection hooks already exist — extend them to
   cover prewarm (recorded as a no-op flag) and history seeding.
8. **Config knobs.** Add `FmRuntimeConfig` and thread it through
   `createFoundationModels` → `FoundationModels` → `FmRequest.config` →
   envelope (`options`/session-create params per protocol). Local enforcement
   of `maxTotalImageBytes` (work item 4). Unknown knob values are passed
   through to the core, which fails typed (`UnsupportedOptionException`
   already exists) — no client-side guessing of valid values.
9. **Policy package.** Create `packages/foundationmodels_policy/` with
   `FmPolicy`, rule set (email, phone, credit card, SSN-style patterns — same
   rule inventory as upstream `foundationmodels-policy`), `FmAuditSink`, and
   deterministic behavior in all three `RedactionMode`s. Wire into the
   runtime behind `SecurityConfig.redaction` + an injected `FmPolicy`.
   Audit entries contain rule id, counts, timestamp, and the caller-supplied
   context — never the redacted content itself. Package stays optional:
   `foundationmodels` must compile and behave identically without it.
10. **Parity update.** Fill `docs/parity.md` for every phase-3 row
    (guided generation, multimodal, `countTokens`/overflow, feedback, vision,
    sessions, instructions, policy) with smoke name, date, device, OS build,
    and `swift-core` version; mark `ContextPolicy.compact` as `partial`
    (stub); keep PCC `blocked`.

## Test plan

### Unit (CI, no Mac)

- `TokenCount.fromMap`/`toMap` round-trips; `Usage.estimated` defaults to
  `true` on missing flag (fail-safe, already in models.dart).
- Schema-validation tests for work item 3: valid output passes; drifted
  output throws `StructuredOutputValidationException` whose `details` contain
  no raw model text; repair performs exactly one retry.
- `FmImagePart.toJson` shapes; `maxTotalImageBytes` local check throws
  `ArgumentError` naming the limit; empty `allowedImageRoots` + path part →
  local rejection before transport (fail-closed).
- Policy package: each rule redacts in `auto`, records-only in `logOnly`,
  no-ops in `off`; audit entries never contain matched PII (assert by
  construction — the entry type has no field for it).
- Mock: `visionOcr`/`visionBarcode`/`logFeedbackAttachment` deterministic;
  feature flags unchanged (`vision: false`, `feedback: false`) until the mock
  genuinely models them.

### Contract (CI, fake transport)

- Envelope shapes golden-tested against upstream `docs/protocol.md` fixtures:
  `context.countTokens`, `vision.ocr`, `vision.barcode`,
  `feedback.logAttachment`, `sessions.create` with `history`,
  `sessions.prewarm`, multimodal `input` arrays, config knobs.
- Error mapping: `VISION_OCR_UNAVAILABLE`, `VISION_BARCODE_UNAVAILABLE`,
  `FEEDBACK_ATTACHMENT_UNAVAILABLE`, `MULTIMODAL_INPUT_UNAVAILABLE` map to
  their typed exceptions via a fake transport returning the recorded
  `FlutterError` payloads.

### On-device smoke (Apple Silicon)

- `guidedgen` (strict/repair/anyOf/$ref/nullable), `multimodal` (base64 +
  allowlisted path + label + byte cap), `vision` (OCR + barcode),
  `sessions` (prewarm latency delta, transition recall, history seeding),
  `instructions` (first-request-wins), `countTokens` (breakdown + estimated
  flag). All recorded in `docs/parity.md`.

## Acceptance criteria

- [ ] `countTokens` returns the core's measured breakdown on device;
      `estimated == false` only for natively measured values.
- [ ] `ContextPolicy.guard` throws `ContextOverflowException` locally with
      the full breakdown and zero generation traffic on overflow.
- [ ] `extract(strict: true)` validates output locally and never leaks raw
      model content in errors; `repair: true` retries exactly once.
- [ ] Multimodal requests with base64 and allowlisted paths work on device;
      path images without allowlist are rejected fail-closed; `label` reaches
      the envelope; `maxTotalImageBytes` enforced locally.
- [ ] `visionOcr`/`visionBarcode` return parsed results on device; typed
      unavailability exceptions elsewhere.
- [ ] `logFeedbackAttachment` resolves on device; typed error where
      unavailable.
- [ ] `prewarm`, `history` seeding, and `transition` transcript preservation
      verified on device; lazy semantics preserved when `history` is absent.
- [ ] `useCase`/`guardrails`/`maxTotalImageBytes` forwarded and honored.
- [ ] `foundationmodels_policy` passes its rule suite in all three modes with
      PII-free audit entries; `foundationmodels` works unchanged without it.
- [ ] `docs/parity.md` phase-3 rows updated with measured evidence; `compact`
      recorded as `partial`.
- [ ] CI green without a Mac.

## Estimate

2–4 weeks (matches ADR-0001 §16). Critical path: U2–U5 landing upstream, then
the on-device evidence runs. Work items 3, 4, and 9 are pure Dart and can
proceed in parallel against the mock.
