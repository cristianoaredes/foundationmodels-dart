import 'embeddings.dart';

/// A document stored in the semantic index.
class FmIndexedDocument {
  /// Creates a document.
  const FmIndexedDocument({
    required this.id,
    required this.text,
    this.metadata = const {},
  });

  /// Stable document id (O(1) lookup / remove).
  final String id;

  /// Indexed text content.
  final String text;

  /// Optional caller metadata (never embedded).
  final Map<String, Object?> metadata;
}

/// A hit from [FmSemanticIndex.query].
class FmSemanticHit {
  /// Creates a hit.
  const FmSemanticHit({
    required this.id,
    required this.score,
    required this.text,
    this.metadata = const {},
  });

  /// Document id.
  final String id;

  /// Cosine similarity in `[0, 1]` for normalized vectors.
  final double score;

  /// Document text.
  final String text;

  /// Document metadata.
  final Map<String, Object?> metadata;
}

/// In-memory semantic index: add / query / remove with O(1) id lookup.
class FmSemanticIndex {
  /// Creates an index over [embeddings].
  FmSemanticIndex(this.embeddings);

  /// Embeddings backend.
  final FmEmbeddingsProvider embeddings;

  final Map<String, _Entry> _byId = {};

  /// Number of documents currently indexed.
  int get length => _byId.length;

  /// Adds or replaces [doc].
  Future<void> add(FmIndexedDocument doc) async {
    final vectors = await embeddings.embed([doc.text]);
    _byId[doc.id] = _Entry(doc: doc, vector: vectors.single);
  }

  /// Adds many documents (batch embed).
  Future<void> addAll(Iterable<FmIndexedDocument> docs) async {
    final list = docs.toList();
    if (list.isEmpty) return;
    final vectors = await embeddings.embed([for (final d in list) d.text]);
    for (var i = 0; i < list.length; i++) {
      _byId[list[i].id] = _Entry(doc: list[i], vector: vectors[i]);
    }
  }

  /// Removes [id] if present. Returns whether it existed.
  bool remove(String id) => _byId.remove(id) != null;

  /// Returns the document for [id], if any.
  FmIndexedDocument? get(String id) => _byId[id]?.doc;

  /// Queries the top-[k] documents by cosine similarity to [query].
  Future<List<FmSemanticHit>> query(String query, {int k = 5}) async {
    if (_byId.isEmpty || k <= 0) return const [];
    final q = (await embeddings.embed([query])).single;
    final scored = <FmSemanticHit>[
      for (final entry in _byId.values)
        FmSemanticHit(
          id: entry.doc.id,
          score: _cosine(q, entry.vector),
          text: entry.doc.text,
          metadata: entry.doc.metadata,
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return scored.take(k).toList();
  }

  static double _cosine(List<double> a, List<double> b) {
    final n = a.length < b.length ? a.length : b.length;
    var dot = 0.0;
    for (var i = 0; i < n; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }
}

class _Entry {
  _Entry({required this.doc, required this.vector});
  final FmIndexedDocument doc;
  final List<double> vector;
}
