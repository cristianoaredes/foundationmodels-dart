import Darwin
import Foundation

/// TCK-0279 / FND-0216: `Attachment<ImageAttachmentContent>` is weak-linked
/// (`-weak_framework FoundationModels`, TCK-0150). The Xcode 27 SDK mangles the
/// CGImage init as `…ImageC7ContentVRszrlE…` while the installed macOS 27
/// runtime exports `…ImageC7ContentVRszlE…` (one fewer `r` in the generic
/// signature). The weak import therefore resolves to a **null function
/// pointer**; calling it from `buildNativePrompt` is `EXC_BAD_ACCESS` at
/// address 0 (daemon SIGSEGV), not a catchable Swift error.
///
/// Probe the exact symbol **this binary imports** (see `nm -u` on the daemon)
/// before any Attachment construction. When missing, degrade to the typed
/// `MULTIMODAL_INPUT_UNAVAILABLE` path — never crash the daemon. Same pattern
/// as `CoreAIRuntimeAvailability` (TCK-0231 / FND-0171).
public enum AttachmentRuntimeAvailability {
    /// `true` only when the weak-imported Attachment CGImage init is bound.
    public static let isAvailable: Bool = {
        let path =
            "/System/Library/Frameworks/FoundationModels.framework/Versions/A/FoundationModels"
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_FIRST) else {
            return false
        }
        // SDK-emitted mangling (Rszrl). OS currently exports Rszl only — probe
        // must use the name our binary will call, not the name the OS has.
        // Leading underscore is stripped for Darwin dlsym (see CoreAI probe).
        let symbol =
            "$s16FoundationModels10AttachmentVA2A05ImageC7ContentVRszrlE_11orientationACyAEGSo10CGImageRefa_So0G19PropertyOrientationVSgtcfC"
        return dlsym(handle, symbol) != nil
    }()

    /// Stable reasonCode carried on `MULTIMODAL_INPUT_UNAVAILABLE` when the
    /// probe fails. Smoke and clients can distinguish "no vision capability"
    /// from "SDK↔OS Attachment symbol skew".
    public static let unavailableReasonCode = "attachment_symbols_unavailable"
}
