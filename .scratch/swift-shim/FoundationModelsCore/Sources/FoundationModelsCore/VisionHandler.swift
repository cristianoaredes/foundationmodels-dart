import CoreGraphics
import Foundation
import ImageIO

#if canImport(Vision)
import Vision
#endif

/// Returns true when Vision.framework's text recognition API is available.
///
/// `VNRecognizeTextRequest` requires macOS 10.15+ (available on the current
/// deployment target) and Vision.framework to be importable. This function
/// gates the `visionOCR` capability flag reported by the daemon.
///
/// Barcode detection is a separate capability — see `visionBarcodeSupported()`
/// (TCK-0256 / FND-0238).
public func visionOCRSupported() -> Bool {
    #if canImport(Vision)
    return true
    #else
    return false
    #endif
}

/// Returns true when Vision.framework's barcode detection API is available.
///
/// `VNDetectBarcodesRequest` requires macOS 10.15+ and Vision.framework.
/// This function gates the `visionBarcode` capability flag (TCK-0256 /
/// FND-0238) — deliberately distinct from `visionOCR` so clients can
/// feature-detect barcode without conflating it with OCR.
public func visionBarcodeSupported() -> Bool {
    #if canImport(Vision)
    return true
    #else
    return false
    #endif
}

/// Decodes an inline base64 image from the daemon params into `CGImage`, together
/// with its EXIF orientation (TCK-0226 / FND-0150).
///
/// The orientation travels with the image because Vision needs it explicitly:
/// `VNImageRequestHandler(cgImage:options:)` assumes `.up`.
///
/// Measured on macOS 27, not assumed: `VNRecognizeTextRequest` recovers text on
/// its own from the pure-rotation tags (3, 6), so for those the argument does
/// not change `texts` at all. What it does change is the mirrored and transposed
/// tags (2, 4, 5, 7) — mirrored glyphs are not recoverable, so dropping the
/// orientation there returns an empty `texts` where honouring it returns the
/// word. See `scripts/smoke/verify-orientation-effect.sh`, which A/Bs this very
/// function. Beyond OCR text, the orientation also defines the coordinate space
/// of every `boundingBox` Vision reports, which matters the day this handler
/// starts putting geometry on the wire.
///
/// `nil` means the image carries no tag, in which case callers use `.up` — the
/// same assumption as before, now stated rather than inherited.
/// Returns `nil` if the base64 is missing, invalid, or ImageIO cannot decode it.
private func decodeCGImage(
    from params: [String: Any]
) -> (image: CGImage, orientation: CGImagePropertyOrientation?)? {
    // TCK-0259 / FND-0241 / DES-0098: decode with `.ignoreUnknownCharacters`
    // instead of allocating a stripped copy via regex. Foundation already
    // skips whitespace/newlines under that option — same acceptance, less copy.
    guard
        let base64 = JSON.string(params, key: "base64"),
        let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
        !data.isEmpty,
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        return nil
    }
    return (cgImage, imageOrientation(from: source))
}

// MARK: - OCR (VNRecognizeTextRequest)

/// Performs OCR on the image provided in `params["base64"]` using
/// `VNRecognizeTextRequest` and returns `{ "texts": [...] }`.
///
/// On platforms where Vision.framework is unavailable the call throws a typed
/// `JsonRpcError.unsupported` with `code: VISION_OCR_UNAVAILABLE` — never a crash.
public func performOCR(params: [String: Any]) async throws -> [String: Any] {
    #if canImport(Vision)
    guard let decoded = decodeCGImage(from: params) else {
        throw JsonRpcError.invalidRequest(
            "OCR: image is missing or could not be decoded. Provide a valid base64-encoded image in params.base64."
        )
    }
    let cgImage = decoded.image
    let orientation = decoded.orientation ?? .up

    return try await withCheckedThrowingContinuation { continuation in
        let request = VNRecognizeTextRequest { req, error in
            if let error {
                continuation.resume(
                    throwing: JsonRpcError.internalError(
                        "VNRecognizeTextRequest failed: \(error.localizedDescription)"
                    )
                )
                return
            }
            let texts: [String] = (req.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            continuation.resume(returning: ["texts": texts])
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            continuation.resume(
                throwing: JsonRpcError.internalError(
                    "VNImageRequestHandler.perform failed: \(error.localizedDescription)"
                )
            )
        }
    }
    #else
    throw JsonRpcError.unsupported(
        "Vision.framework is not available on this platform.",
        data: ["code": "VISION_OCR_UNAVAILABLE"]
    )
    #endif
}

// MARK: - Barcode detection (VNDetectBarcodesRequest)

/// Detects barcodes in the image provided in `params["base64"]` using
/// `VNDetectBarcodesRequest` and returns `{ "barcodes": [{ "symbology", "value" }] }`.
///
/// Symbology names are normalized to short human-readable strings (e.g. "QR",
/// "EAN13") by stripping the `VNBarcodeSymbology` prefix when possible.
///
/// On platforms where Vision.framework is unavailable the call throws a typed
/// `JsonRpcError.unsupported` with `code: VISION_BARCODE_UNAVAILABLE`
/// (TCK-0256 / FND-0238 — not VISION_OCR_UNAVAILABLE).
public func performBarcodeDetection(params: [String: Any]) async throws -> [String: Any] {
    #if canImport(Vision)
    guard let decoded = decodeCGImage(from: params) else {
        throw JsonRpcError.invalidRequest(
            "Barcode detection: image is missing or could not be decoded. Provide a valid base64-encoded image in params.base64."
        )
    }
    let cgImage = decoded.image
    let orientation = decoded.orientation ?? .up

    return try await withCheckedThrowingContinuation { continuation in
        let request = VNDetectBarcodesRequest { req, error in
            if let error {
                continuation.resume(
                    throwing: JsonRpcError.internalError(
                        "VNDetectBarcodesRequest failed: \(error.localizedDescription)"
                    )
                )
                return
            }
            let barcodes: [[String: String]] = (req.results as? [VNBarcodeObservation] ?? [])
                .compactMap { obs in
                    guard let value = obs.payloadStringValue else { return nil }
                    let symbology = normalizeSymbology(obs.symbology)
                    return ["symbology": symbology, "value": value]
                }
            continuation.resume(returning: ["barcodes": barcodes])
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            continuation.resume(
                throwing: JsonRpcError.internalError(
                    "VNImageRequestHandler.perform failed: \(error.localizedDescription)"
                )
            )
        }
    }
    #else
    throw JsonRpcError.unsupported(
        "Vision.framework barcode detection is not available on this platform.",
        data: ["code": "VISION_BARCODE_UNAVAILABLE"]
    )
    #endif
}

// MARK: - Helpers

#if canImport(Vision)
/// Converts a `VNBarcodeSymbology` raw value to a short human-readable string.
/// Apple encodes symbologies as strings like "org.gs1.EAN-13"; we normalise to
/// "EAN13", "QR", "Code128", etc. for the JSON contract surface.
private func normalizeSymbology(_ symbology: VNBarcodeSymbology) -> String {
    let raw = symbology.rawValue
    // Strip the common Apple reverse-DNS prefixes.
    let prefixes = ["org.gs1.", "org.iso.", "com.apple.", "org.ansi."]
    for prefix in prefixes {
        if raw.lowercased().hasPrefix(prefix) {
            return String(raw.dropFirst(prefix.count))
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ".", with: "")
        }
    }
    // Fallback: return the raw value as-is.
    return raw
}
#endif
