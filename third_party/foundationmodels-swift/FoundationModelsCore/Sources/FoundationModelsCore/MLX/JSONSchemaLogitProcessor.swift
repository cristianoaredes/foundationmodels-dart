import Foundation
import MLX
import MLXLMCommon

/// Token lookup surface for schema-guided masking (TCK-0110b).
@available(macOS 27.0, iOS 27.0, *)
public protocol JSONSchemaVocabulary: Sendable {
    var vocabSize: Int { get }
    func tokenText(for id: Int) -> String?
}

/// Masks disallowed logits so decoded output stays on a schema-valid JSON path (TCK-0110b).
@available(macOS 27.0, iOS 27.0, *)
public struct JSONSchemaLogitProcessor: LogitProcessor {
    private let validator: PartialJSONSchemaValidator
    private let vocabulary: any JSONSchemaVocabulary
    private var generatedText: String = ""

    public init(schema: [String: Any], vocabulary: any JSONSchemaVocabulary) throws {
        let root = try JSONSchemaSupport.compile(rootSchema: schema)
        self.validator = PartialJSONSchemaValidator(root: root)
        self.vocabulary = vocabulary
    }

    public mutating func prompt(_ prompt: MLXArray) {}

    public func process(logits: MLXArray) -> MLXArray {
        let negInf = MLXArray(-Float.infinity)
        let masked = MLX.broadcast(negInf, to: logits.shape)
        var result = masked

        let vocabSize = logits.dim(-1)
        for tokenId in 0 ..< vocabSize {
            guard let piece = vocabulary.tokenText(for: tokenId), !piece.isEmpty else {
                continue
            }
            if validator.isValidPrefix(generatedText + piece) {
                result[0, tokenId] = logits[0, tokenId]
            }
        }

        return result
    }

    public mutating func didSample(token: MLXArray) {
        let tokenId = token.item(Int.self)
        guard let piece = vocabulary.tokenText(for: tokenId) else { return }
        generatedText += piece
    }

    /// Exposed for unit tests.
    public var currentGeneratedText: String { generatedText }
}
