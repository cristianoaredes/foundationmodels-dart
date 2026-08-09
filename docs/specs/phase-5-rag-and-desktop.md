# Phase 5 — Semantic index (local RAG) + desktop daemon client

Implementation spec for ADR-0001 §16 phase 5 ("RAG + desktop"). Two
independent deliverables: (a) a port of the upstream semantic index with
pluggable embeddings, and (b) a pure-Dart client of the prebuilt
`foundationmodels` daemon for Flutter desktop macOS, exposed as a second
`FmProvider` under the same contracts.

## Goal

(a) Apps can build a local retrieval index over their own documents —
`add`/`query`/`remove` with O(1) id lookup — using a pluggable embeddings
provider, fully offline and deterministic under the mock.

(b) A Flutter **desktop macOS** app can use the full protocol v1/v2 surface
by talking to the prebuilt daemon binary (from the npm package
`@orqo/foundationmodels-daemon-darwin-arm64`) over a Unix socket, in pure
Dart (`dart:io`, no platform channels), reusing the existing
`TransportProvider` and all of `package:foundationmodels` unchanged.

## Depends on

- Phases 0–3 (runtime, streaming, sessions, multimodal surface). Phase 4 is
  **not** required; if the daemon client is built after phase 4, the duplex
  tool path must work over the socket too (work item 9).
- For (b): access to the upstream daemon protocol docs
  (`docs/protocol.md` in `foundationmodels-js`) for the exact auth handshake
  and notification shapes; the prebuilt daemon binary distributed via the
  npm package `@orqo/foundationmodels-daemon-darwin-arm64`.
- Existing pieces: `FoundationModelsTransport` contract
  (`platform_interface/lib/src/transport.dart` — `invoke` + `streamEvents`),
  `TransportProvider` (already a complete `FmProvider` over any transport),
  `FmMethods`, sealed events, typed errors.

## Scope

### In

- New package `packages/foundationmodels_rag/` (pure Dart, no Flutter, no
  default IO): semantic index port.
- Embeddings provider decision record (work item 2) with the recommended
  default; a deterministic offline fallback embedder.
- New package `packages/foundationmodels_daemon/` (pure Dart, `dart:io`,
  macOS desktop only at runtime): `DaemonSocketTransport implements
  FoundationModelsTransport` over a Unix socket, protocol v1/v2 complete:
  newline-delimited JSON, 8 MiB line cap, challenge-response auth
  (HMAC-SHA256, domain `foundationmodels.auth.v1`), cancel as a notification
  on the same connection, half-close as implicit cancel.
- Process management helper to spawn/locate the prebuilt daemon binary.
- Smoke `semantic-rag` and a desktop `respond`-via-socket smoke.

### Out

- iOS: the daemon client targets macOS desktop only (iOS uses the in-process
  plugin from phases 0–4).
- Changes to the daemon binary itself (consumed as-is; version pinned and
  recorded).
- Vector-store backends beyond simple JSON persistence (callers may layer
  their own storage on top of the index API).
- Reranking/chunking frameworks — the port covers the upstream index
  semantics, not new RAG architecture.

## API deltas

### (a) `packages/foundationmodels_rag/`

```dart
/// Pluggable embeddings backend — the decision point of ADR-0001 §18.6.
abstract class FmEmbeddingsProvider {
  /// Stable provider id (recorded in persistence for compatibility checks).
  String get id;

  /// Vector dimension; constant per provider.
  int get dimensions;

  /// Embeds [texts] in order. Must be deterministic for a given
  /// (provider id, model version, input).
  Future<List<List<double>>> embed(List<String> texts);
}

/// Port of the upstream semantic index: cosine similarity over stored
/// vectors with an O(1) id map (Map<String, int> id → row), no scans for
/// add/remove.
class FmSemanticIndex {
  FmSemanticIndex({required FmEmbeddingsProvider embeddings});

  /// Adds or replaces the entry [id]. Re-adding an id updates its vector
  /// in place (same row — O(1)).
  Future<void> add(String id, String text, {Map<String, Object?>? metadata});

  /// Removes [id]; returns false when absent. O(1) via the id map;
  /// internally uses swap-remove, keeping the map consistent.
  bool remove(String id);

  /// Returns the [topK] most similar entries, best first, with scores in
  /// [-1, 1] (cosine). Deterministic tie-break by id.
  Future<List<FmIndexHit>> query(String text, {int topK = 5});

  int get length;
  bool contains(String id);

  /// Simple persistence: JSON snapshot {providerId, dimensions, entries}.
  /// Throws StateError when loading a snapshot whose providerId/dimensions
  /// differ from the live provider (never silently mixes vector spaces).
  Map<String, Object?> toJson();
  static FmSemanticIndex fromJson(Map<String, Object?> json,
      {required FmEmbeddingsProvider embeddings});
}

final class FmIndexHit {
  const FmIndexHit({required this.id, required this.score, this.metadata});
  final String id;
  final double score;
  final Map<String, Object?>? metadata;
}

/// Default offline embedder: deterministic hashing-based bag-of-words
/// embedding (no model download, no network). Documented as a recall
/// fallback — NOT parity with any neural embedder; parity.md must say so.
final class FmHashingEmbeddingsProvider implements FmEmbeddingsProvider { ... }
```

### (b) `packages/foundationmodels_daemon/`

```dart
/// Pure-Dart transport speaking daemon protocol v1/v2 over a Unix socket.
/// Implements FoundationModelsTransport, so the existing TransportProvider
/// gives a full FmProvider with zero API changes:
///
///   final transport = await DaemonSocketTransport.connect(
///     socketPath: '/tmp/foundationmodels-daemon.sock',
///     authToken: token, // shared secret for the HMAC handshake
///   );
///   final fm = await createFoundationModels(providers: [TransportProvider(transport)]);
class DaemonSocketTransport implements FoundationModelsTransport {
  static Future<DaemonSocketTransport> connect({
    required String socketPath,
    String? authToken,
    Duration handshakeTimeout = const Duration(seconds: 5),
  });

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> envelope);

  /// Multiplexed protocol events for all in-flight streams on this
  /// connection; demux by requestId happens in TransportProvider.
  @override
  Stream<Map<String, Object?>> get streamEvents;

  /// Closes the connection. Half-close (EOF) semantics: closing the socket
  /// implicitly cancels every in-flight generation, mirroring the daemon's
  /// "client EOF is an implicit cancel".
  Future<void> close();
}

/// Locates and spawns the prebuilt daemon from a caller-provided path
/// (typically extracted from the npm package
/// @orqo/foundationmodels-daemon-darwin-arm64). The Dart package never
/// bundles the binary; the app ships/extracts it.
final class FmDaemonProcess {
  static Future<FmDaemonProcess> start({
    required String binaryPath,
    required String socketPath,
    Map<String, String>? environment,
  });
  Future<void> stop({Duration grace = const Duration(seconds: 2)});
}
```

No changes to `package:foundationmodels` or
`package:foundationmodels_platform_interface` are expected — the whole phase
reuses `TransportProvider`/`FoundationModelsTransport`. If gaps appear
(e.g. per-call timeout surfaced as `ModelTimeoutException`), record them as
divergences and prefer the smallest interface addition.

## Work items

1. **Index port.** Implement `FmSemanticIndex` with: `List<double>`-backed
   row storage + `Map<String, int>` id map; swap-remove on `remove`
   (updating the moved row's id entry — O(1), no rebuild); cosine similarity
   with zero-vector guard; deterministic tie-break by id; replace-in-place
   semantics for re-`add`. Unit-test the upstream behaviors: add/query/remove
   basics, re-add replaces, remove shifts rows without corrupting results,
   empty-index query returns `[]`.
2. **Embeddings decision record.** Write the ADR-0001 §18.6 decision into
   the package README section of the spec implementation (a short
   `docs/specs`-referenced rationale, or package README): **native via core**
   (pro: parity with upstream results if Apple exposes on-device embeddings;
   con: no public Apple embeddings API today — would be speculative) vs.
   **pure Dart** (pro: offline, testable, ships now; con: recall quality
   depends on the embedder). **Recommendation: ship the pluggable
   `FmEmbeddingsProvider` abstraction with `FmHashingEmbeddingsProvider` as
   the deterministic default, and add a native-backed provider later if and
   only if the core exposes embeddings.** Record the trade-off and the
   non-parity caveat in `docs/parity.md`.
3. **Persistence.** `toJson`/`fromJson` with provider-compatibility check;
   atomic file write helper is the caller's job (package stays IO-free);
   document the pattern (`File.writeAsString(jsonEncode(index.toJson()))`).
4. **RAG wiring example (test-only).** A test demonstrating retrieval-
   augmented `respond`: query index → stuff top hits into the **input**
   (never into `instructions` — trusted channel, ADR-0001 §12) → generate.
5. **Socket transport core.** `Socket.connect(InternetAddress(socketPath,
   type: InternetAddressType.unix), 0)`; newline-delimited JSON codec with
   **8 MiB per-line cap** (oversized line → fail the connection with
   `FmTransportError`, mirroring the daemon's own cap); request/response
   correlation by envelope `id` with a pending-completer map; protocol v1
   envelopes accepted, v2 methods routed identically (feature-detect via
   `capabilities`).
6. **Auth handshake.** Challenge-response HMAC-SHA256 with the domain
   separation string `foundationmodels.auth.v1`, exactly per upstream
   `docs/protocol.md` (read the nonce/challenge fields from the daemon's
   hello; respond with the hex HMAC of the challenge under the shared
   token, computed over the domain-prefixed message). Handshake failure →
   typed `FmTransportError`; never log the token (ADR-0001 §12 secrets
   rule). Unit-test with a recorded fixture of a real handshake (sanitized
   token).
7. **Streaming + cancel over the socket.** Map daemon stream notifications
   into `streamEvents` (same map shapes as the platform-channel transport —
   `requestId` correlation, flat `error` payload per the phase-2 canonical
   shape). Cancel: send the `foundationmodels.generation.cancel`
   **notification on the same connection** (no response expected) when
   `TransportProvider.cancelGeneration` invokes; half-close/EOF from either
   side implicitly cancels all in-flight generations and completes open
   `invoke` futures with `FmTransportError`.
8. **Process management.** `FmDaemonProcess.start/stop`: spawn detached,
   wait for the socket to appear (timeout), graceful stop (SIGTERM, then
   SIGKILL after grace). Document the version-pinned binary source and record
   the daemon build in `docs/parity.md` evidence entries.
9. **(If after phase 4) Tools over the socket.** Verify `tools.result`
   travels as a normal `invoke` while the generation blocks — no transport
   change should be needed; add a contract test to prevent regressions.
10. **Smokes.** `semantic-rag`: index 3+ documents, query retrieves the
    relevant doc, augmented answer references it (run against mock in CI and
    on device with the in-process provider). Desktop smoke: on an Apple
    Silicon Mac, spawn the prebuilt daemon, run `availability`, unary
    `respond`, a streamed generation with mid-stream cancel, and a
    `countTokens` call through `DaemonSocketTransport`; record evidence in
    `docs/parity.md` (`Semantic index (local RAG)` row and a new
    `Daemon client (Flutter desktop macOS)` row).

## Test plan

### Unit (CI, no Mac)

- Index: behaviors of work item 1; persistence round-trip; provider-mismatch
  `StateError` on load; hashing embedder determinism (same input → identical
  vector across runs).
- Socket codec: line cap enforced at 8 MiB exactly; partial-line buffering;
  malformed JSON line → connection failure with `FmTransportError`.
- Auth: HMAC computed over the exact domain-prefixed challenge; wrong token
  → handshake rejection; token never appears in logs/exceptions.

### Contract (CI)

- Fake in-process daemon (a Dart test server over a local Unix socket)
  replaying recorded v1/v2 sessions: hello/auth, unary respond, streamed
  generation with cancel notification, half-close implicit cancel,
  `countTokens`, and (post-phase-4) a duplex tool sequence.
- `TransportProvider` over `DaemonSocketTransport` passes the same
  golden-fixture suites used for the platform-channel transport in phase 2.

### On-device smoke (Apple Silicon macOS)

- Work item 10: real daemon binary, real model; evidence recorded with date,
  device, OS build, daemon build, and `swift-core` version.

## Acceptance criteria

- [ ] Index add/query/remove are O(1)-mapped (no linear scans for id ops)
      and match upstream behaviors including replace-in-place and
      swap-remove consistency.
- [ ] Embeddings decision recorded with trade-offs; default provider is
      deterministic and offline; recall caveat documented in parity docs.
- [ ] Persistence round-trips; cross-provider loads fail loudly.
- [ ] Retrieval augmentation never injects into `instructions` (tested).
- [ ] Daemon client completes auth (HMAC-SHA256, domain
      `foundationmodels.auth.v1`), unary, streaming, same-connection cancel,
      and half-close implicit cancel against the real prebuilt daemon.
- [ ] 8 MiB line cap enforced; oversized payloads fail typed, never hang.
- [ ] `createFoundationModels(providers: [TransportProvider(DaemonSocketTransport...)])`
      requires zero changes to `package:foundationmodels`.
- [ ] Smokes `semantic-rag` and desktop socket flow green; `docs/parity.md`
      updated with evidence.
- [ ] CI green without a Mac (fake-daemon contract suite).

## Estimate

2–4 weeks (matches ADR-0001 §16). The socket transport (items 5–8) is the
larger half; the RAG port is small and fully parallelizable.
