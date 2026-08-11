import 'package:foundationmodels_rag/foundationmodels_rag.dart';
import 'package:test/test.dart';

void main() {
  test('add / query / remove round-trip with hashing embeddings', () async {
    final index = FmSemanticIndex(const HashingEmbeddingsProvider());
    await index.addAll([
      const FmIndexedDocument(id: '1', text: 'apple fruit orchard'),
      const FmIndexedDocument(id: '2', text: 'car engine motor vehicle'),
      const FmIndexedDocument(id: '3', text: 'apple pie dessert recipe'),
    ]);
    expect(index.length, 3);

    final hits = await index.query('apple dessert', k: 2);
    expect(hits, hasLength(2));
    // The dessert doc should rank at or near the top for this query.
    expect(hits.map((h) => h.id), contains('3'));

    expect(index.remove('2'), isTrue);
    expect(index.length, 2);
    expect(index.get('2'), isNull);
  });

  test('empty index returns no hits', () async {
    final index = FmSemanticIndex(const HashingEmbeddingsProvider());
    expect(await index.query('anything'), isEmpty);
  });
}
