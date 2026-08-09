/// Platform interface for the FoundationModels Dart/Flutter adapter.
///
/// Exposes the transport contract ([FoundationModelsTransport]), the stable
/// protocol method names ([FmMethods]), typed stream events
/// ([FmStreamEvent] and subtypes), the sealed typed-error hierarchy
/// ([FoundationModelsException]) mirroring `error.data.code`, and the shared
/// value models ([AvailabilityReport], [Usage], [TokenCount]).
///
/// Pure Dart: no Flutter, no IO. Mirrors `docs/protocol.md` (v2) of the
/// upstream `foundationmodels-js` project.
library;

export 'src/errors.dart';
export 'src/events.dart';
export 'src/methods.dart';
export 'src/models.dart';
export 'src/transport.dart';
