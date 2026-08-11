import Foundation

public struct JsonRpcError: Error, @unchecked Sendable {
    let code: Int
    let message: String
    let data: Any?

    public static func invalidRequest(_ message: String) -> JsonRpcError {
        JsonRpcError(code: -32600, message: message, data: nil)
    }

    public static func methodNotFound(_ method: String) -> JsonRpcError {
        JsonRpcError(code: -32601, message: "Unknown method: \(method)", data: nil)
    }

    public static func internalError(_ message: String, data: Any? = nil) -> JsonRpcError {
        JsonRpcError(code: -32603, message: message, data: data)
    }

    public static func modelUnavailable(_ message: String, data: Any? = nil) -> JsonRpcError {
        JsonRpcError(code: -32010, message: message, data: data)
    }

    public static func unsupported(_ message: String, data: Any? = nil) -> JsonRpcError {
        JsonRpcError(code: -32020, message: message, data: data)
    }

    public static func contextOverflow(_ message: String, data: Any? = nil) -> JsonRpcError {
        JsonRpcError(code: -32030, message: message, data: data)
    }

    public static func cancelled(_ message: String, data: Any? = nil) -> JsonRpcError {
        JsonRpcError(code: -32040, message: message, data: data)
    }

    public static func toolExecutionFailed(_ message: String, data: Any? = nil) -> JsonRpcError {
        JsonRpcError(code: -32050, message: message, data: data)
    }

    /// A decision of the safety layer blocked the request or the response
    /// (guardrail violation, model refusal). Never retryable: the same input
    /// produces the same decision (TCK-0208).
    public static func policyBlocked(_ message: String, data: Any? = nil) -> JsonRpcError {
        JsonRpcError(code: -32060, message: message, data: data)
    }

    /// A transient condition of the model or the session (rate limit, timeout,
    /// concurrent request, transcript mutation). Retryable (TCK-0208).
    public static func transient(_ message: String, data: Any? = nil) -> JsonRpcError {
        JsonRpcError(code: -32070, message: message, data: data)
    }

    public static func unauthorized(_ message: String, data: Any? = nil) -> JsonRpcError {
        JsonRpcError(code: -32000, message: message, data: data)
    }
}

public func jsonRpcSuccess(id: Any, result: [String: Any]) -> [String: Any] {
    [
        "jsonrpc": "2.0",
        "id": id,
        "result": result
    ]
}

public func jsonRpcFailure(id: Any?, error: JsonRpcError) -> [String: Any] {
    var errorObject: [String: Any] = [
        "code": error.code,
        "message": error.message
    ]

    if let data = error.data {
        errorObject["data"] = data
    }

    return [
        "jsonrpc": "2.0",
        "id": id ?? NSNull(),
        "error": errorObject
    ]
}
