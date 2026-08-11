/// Pluggable embeddings backend (ADR-0001 §18.6).
abstract class FmEmbeddingsProvider {
  /// Stable provider id (recorded in persistence for compatibility checks).
  String get id;

  /// Vector dimension; constant per provider.
  int get dimensions;

  /// Embeds [texts] in order. Must be deterministic for a given
  /// (provider id, model version, input) when used offline.
  Future<List<List<double>>> embed(List<String> texts);
}

/// Deterministic bag-of-hashes embedder for offline tests and local dev.
///
/// Not a semantic model — it exists so the index API is fully exercisable
/// without network or native ML. Production apps should inject a real
/// embeddings provider.
class HashingEmbeddingsProvider implements FmEmbeddingsProvider {
  /// Creates a hashing embedder with fixed [dimensions] (default 32).
  const HashingEmbeddingsProvider({this.dimensions = 32});

  @override
  String get id => 'hashing-v1';

  @override
  final int dimensions;

  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    return [for (final text in texts) _embedOne(text)];
  }

  List<double> _embedOne(String text) {
    final out = List<double>.filled(dimensions, 0);
    if (text.isEmpty) return out;
    final tokens = text.toLowerCase().split(RegExp(r'\s+'));
    for (final token in tokens) {
      var h = 0;
      for (final u in token.codeUnits) {
        h = (h * 31 + u) & 0x7fffffff;
      }
      out[h % dimensions] += 1.0;
    }
    // L2 normalize so cosine similarity is well-defined.
    var norm = 0.0;
    for (final v in out) {
      norm += v * v;
    }
    norm = norm == 0 ? 1.0 : (norm > 0 ? _sqrt(norm) : 1.0);
    for (var i = 0; i < out.length; i++) {
      out[i] /= norm;
    }
    return out;
  }

  double _sqrt(double x) {
    // Newton for portability without dart:math import in pure lib tests.
    var g = x / 2;
    for (var i = 0; i < 12; i++) {
      g = 0.5 * (g + x / g);
    }
    return g;
  }
}
