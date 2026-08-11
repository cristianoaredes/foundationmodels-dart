import Foundation
import ImageIO

/// Reads the EXIF orientation tag from an ImageIO source (TCK-0226 / FND-0150).
///
/// Returns `nil` when the image carries no orientation metadata — deliberately
/// **not** `.up`. Every caller forwards this straight into Apple's optional
/// `orientation:` parameter, so an image without an EXIF tag is handled exactly
/// as it was before this function existed; only tagged images change behaviour.
///
/// Always read the tag from the *same* `CGImageSource` that produced the
/// `CGImage`, never from a caller-supplied field: if the rotation has already
/// been baked into the pixels somewhere upstream while the tag still says
/// "rotate me", honouring a second, unrelated orientation rotates the image twice.
public func imageOrientation(from source: CGImageSource) -> CGImagePropertyOrientation? {
    guard
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        // The tag arrives as a CFNumber. Bridging through NSNumber is required —
        // a direct `as? UInt32` cast fails and would silently drop the orientation.
        let raw = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value
    else {
        return nil
    }
    return CGImagePropertyOrientation(rawValue: raw)
}

/// A parsed multimodal input part received over the daemon protocol.
/// This enum is independent of the native Foundation Models API so it can be
/// validated and routed before any SDK-specific construction.
public enum MultimodalInputPart {
    case text(String)
    /// TCK-0227 / FND-0147: `label` is the caller-supplied tag that Apple's
    /// agentic-vision loop is built on. The model never receives image bytes to
    /// pick from — it emits an `ImageReference { attachmentLabel }`, and the
    /// native tool resolves that label back to the attachment in the transcript.
    /// `nil` means the image is unlabelled and therefore unreferenceable, which
    /// is the pre-TCK-0227 behaviour.
    case image(Data, mimeType: String, label: String? = nil)
    /// A validated `file://` URL reference to an image on the local filesystem.
    /// The URL has already been vetted by the TS runtime (allowlist, extension,
    /// path traversal); the daemon validates the scheme and absence of `../`
    /// before constructing the native `ImageAttachment`.
    case imageURL(URL, mimeType: String?, label: String? = nil)
}

public enum MultimodalInputError: Error {
    case missingMimeType
    case invalidBase64
    case imageTooLarge(maxBytes: Int, actualBytes: Int)
    /// The `imageURL` field was present but contained an invalid or unsafe value.
    case invalidImageURL(String)
}

private let maxInlineImageBytes = 5 * 1024 * 1024

/// Parses the daemon request `input` array into validated multimodal parts.
/// Text parts pass through; base64 image parts are decoded and size-limited;
/// imageURL parts are validated and forwarded as `.imageURL` cases.
public func parseMultimodalInput(from params: [String: Any]) throws -> [MultimodalInputPart] {
    try (JSON.array(params, key: "input") ?? []).map { item in
        let type = JSON.string(item, key: "type") ?? ""

        if type == "text", let text = JSON.string(item, key: "text") {
            return .text(text)
        }

        if type == "image" {
            return try parseImagePart(item)
        }

        // Unknown part types degrade to a diagnostic text token rather than
        // crashing the daemon; the TS provider gate rejects them earlier.
        return .text(String(describing: item))
    }
}

private func parseImagePart(_ item: [String: Any]) throws -> MultimodalInputPart {
    // TCK-0227: an empty `label` is treated as absent. A zero-length tag is one
    // the model can never name unambiguously, so accepting it would produce an
    // attachment that looks referenceable and is not.
    let label = JSON.string(item, key: "label").flatMap { $0.isEmpty ? nil : $0 }

    // imageURL route (TCK-0043 / SPC-0037): the TS runtime has already applied
    // its allowlist and path-safety checks; the daemon re-validates scheme and
    // the absence of path-traversal components as a defence-in-depth layer.
    if let rawURLString = JSON.string(item, key: "imageURL") {
        return try parseImageURLPart(
            rawURLString,
            mimeType: JSON.string(item, key: "mimeType"),
            label: label
        )
    }

    guard let mimeType = JSON.string(item, key: "mimeType") else {
        throw MultimodalInputError.missingMimeType
    }

    guard let base64 = JSON.string(item, key: "base64") else {
        throw MultimodalInputError.invalidBase64
    }

    let normalized = base64.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    guard let data = Data(base64Encoded: normalized), !data.isEmpty else {
        throw MultimodalInputError.invalidBase64
    }

    guard data.count <= maxInlineImageBytes else {
        throw MultimodalInputError.imageTooLarge(maxBytes: maxInlineImageBytes, actualBytes: data.count)
    }

    return .image(data, mimeType: mimeType, label: label)
}

/// Parses and validates an `imageURL` string received from the TS runtime.
///
/// Defence-in-depth validation (the TS runtime has already run its allowlist):
/// - The URL must parse to a valid `Foundation.URL`.
/// - The scheme must be `file` (no remote schemes accepted).
/// - The path must not contain `../` components.
private func parseImageURLPart(
    _ rawURLString: String,
    mimeType: String?,
    label: String?
) throws -> MultimodalInputPart {
    guard let url = URL(string: rawURLString) else {
        throw MultimodalInputError.invalidImageURL("Could not parse URL: \(rawURLString)")
    }

    guard url.scheme == "file" else {
        throw MultimodalInputError.invalidImageURL(
            "imageURL must use the file:// scheme; got \"\(url.scheme ?? "nil")\"."
        )
    }

    let path = url.path
    guard !path.isEmpty else {
        throw MultimodalInputError.invalidImageURL("imageURL has an empty path component.")
    }

    // Defence-in-depth: reject any path that still contains a `..` component.
    // The TS allowlist already blocks this, but we validate again here.
    let segments = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    if segments.contains("..") {
        throw MultimodalInputError.invalidImageURL(
            "imageURL path must not contain \"..\" components."
        )
    }

    return .imageURL(url, mimeType: mimeType, label: label)
}

/// Extracts a plain-text prompt from multimodal parts for the fallback path
/// when the native multimodal binding is unavailable.
public func textOnlyPrompt(from parts: [MultimodalInputPart]) -> String {
    parts.compactMap { part in
        if case .text(let text) = part { return text }
        return nil
    }.joined(separator: "\n")
}
