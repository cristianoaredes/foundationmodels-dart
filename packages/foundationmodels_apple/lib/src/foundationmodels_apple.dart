import 'package:foundationmodels_platform_interface/foundationmodels_platform_interface.dart';

import 'apple_rpc_transport.dart';

/// Creates the Apple-platform [FoundationModelsTransport] (iOS + macOS),
/// backed by the `foundationmodels/rpc` + `foundationmodels/streams`
/// platform channels.
///
/// Wiring note: `FoundationModelsTransport` in the platform interface
/// currently exposes no static `instance` holder, so the app-facing package
/// (`package:foundationmodels`) — or the app itself, when constructing the
/// Apple provider — calls this factory to obtain the transport. If the
/// interface later adopts the classic federated-plugin `instance` setter,
/// this is the single call site to change.
FoundationModelsTransport createFoundationModelsAppleTransport() {
  return MethodChannelFoundationModels();
}
