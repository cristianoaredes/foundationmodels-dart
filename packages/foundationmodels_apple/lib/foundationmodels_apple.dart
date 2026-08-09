/// Apple platform (iOS + macOS) implementation of the foundationmodels
/// federated plugin.
///
/// Bridges Flutter platform channels to the shared Swift core
/// (`FoundationModelsCore` + `FoundationModelsIOSBridge`) using a single
/// MethodChannel carrying daemon-shaped JSON-RPC envelopes and a single
/// EventChannel carrying stream events multiplexed by `requestId`
/// (ADR-0001 §6/§7).
library;

export 'src/apple_rpc_transport.dart';
export 'src/foundationmodels_apple.dart';
