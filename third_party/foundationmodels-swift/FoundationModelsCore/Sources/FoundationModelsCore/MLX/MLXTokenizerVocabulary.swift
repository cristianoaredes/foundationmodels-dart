import Foundation
import MLXLMCommon

/// Adapts an MLX tokenizer to `JSONSchemaVocabulary` (TCK-0110c).
@available(macOS 27.0, iOS 27.0, *)
struct MLXTokenizerVocabulary: JSONSchemaVocabulary {
    private let tokenizer: any Tokenizer
    let vocabSize: Int

    init(tokenizer: any Tokenizer, modelDirectory: URL) {
        self.tokenizer = tokenizer
        self.vocabSize = Self.readVocabSize(from: modelDirectory) ?? Self.probeVocabSize(tokenizer: tokenizer)
    }

    func tokenText(for id: Int) -> String? {
        tokenizer.convertIdToToken(id)
    }

    private static func readVocabSize(from modelDirectory: URL) -> Int? {
        let configURL = modelDirectory.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let size = json["vocab_size"] as? Int, size > 0 {
            return size
        }
        if let size = (json["vocab_size"] as? NSNumber)?.intValue, size > 0 {
            return size
        }
        return nil
    }

    private static func probeVocabSize(tokenizer: any Tokenizer) -> Int {
        var size = 0
        while tokenizer.convertIdToToken(size) != nil {
            size += 1
        }
        return max(size, 1)
    }
}
