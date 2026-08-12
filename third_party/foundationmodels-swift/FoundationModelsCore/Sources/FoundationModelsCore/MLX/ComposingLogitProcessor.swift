import MLX
import MLXLMCommon

/// Chains penalty (or other) processors before schema masking (TCK-0110c / FND-0116).
@available(macOS 27.0, iOS 27.0, *)
struct ComposingLogitProcessor: LogitProcessor {
    var first: (any LogitProcessor)?
    var second: any LogitProcessor

    mutating func prompt(_ prompt: MLXArray) {
        first?.prompt(prompt)
        second.prompt(prompt)
    }

    func process(logits: MLXArray) -> MLXArray {
        let afterFirst = first?.process(logits: logits) ?? logits
        return second.process(logits: afterFirst)
    }

    mutating func didSample(token: MLXArray) {
        first?.didSample(token: token)
        second.didSample(token: token)
    }
}
