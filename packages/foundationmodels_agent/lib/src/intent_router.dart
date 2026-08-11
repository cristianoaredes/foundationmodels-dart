import 'package:foundationmodels/foundationmodels.dart';

/// Routes free-text input to a route id via [FoundationModels.classify].
class FmIntentRouter {
  FmIntentRouter(this.fm, {required this.routes});

  final FoundationModels fm;

  /// Route ids (labels) the classifier may return.
  final List<String> routes;

  /// Classifies [input] into one of [routes].
  Future<String> classifyRouteIntent(String input) {
    if (routes.isEmpty) {
      throw ArgumentError.value(routes, 'routes', 'must not be empty');
    }
    return fm.classify(input: input, labels: routes);
  }
}
