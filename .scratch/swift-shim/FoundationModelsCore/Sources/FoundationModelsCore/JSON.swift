import Foundation

public enum JSON {
    public static func parseObject(_ data: Data) throws -> [String: Any] {
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard let object = decoded as? [String: Any] else {
            throw JsonRpcError.invalidRequest("JSON-RPC request must be an object.")
        }
        return object
    }

    public static func line(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [])
        data.append(0x0A)
        return data
    }

    public static func string(_ object: [String: Any], key: String) -> String? {
        object[key] as? String
    }

    public static func object(_ object: [String: Any], key: String) -> [String: Any]? {
        object[key] as? [String: Any]
    }

    public static func array(_ object: [String: Any], key: String) -> [[String: Any]]? {
        object[key] as? [[String: Any]]
    }

    public static func int(_ object: [String: Any], key: String) -> Int? {
        if let value = object[key] as? Int {
            return value
        }
        return (object[key] as? NSNumber)?.intValue
    }

    public static func double(_ object: [String: Any], key: String) -> Double? {
        if let value = object[key] as? Double {
            return value
        }
        return (object[key] as? NSNumber)?.doubleValue
    }

    public static func bool(_ object: [String: Any], key: String) -> Bool? {
        if let value = object[key] as? Bool {
            return value
        }
        return (object[key] as? NSNumber)?.boolValue
    }
}
