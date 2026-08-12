import Foundation

/// JSON Schema keyword validation and compilation for MLX guided decoding (TCK-0110b).
/// Mirrors the native `DynamicGenerationSchema` subset in `FoundationModelsCore.swift`.
@available(macOS 27.0, iOS 27.0, *)
enum JSONSchemaSupport {
    /// Mirrors `FoundationModelsCore.unsupportedSchemaKeywords` (TCK-0215 /
    /// FND-0143, FND-0145). `const` stays listed here — unlike the native
    /// list — because this compiler builds its own `JSONSchemaNode` IR for MLX
    /// guided decoding (`JSONSchemaLogitProcessor` /
    /// `PartialJSONSchemaValidator`), not `DynamicGenerationSchema` /
    /// `GenerationGuide`. The `.constant` guide mapping added for FND-0146 is
    /// a native-bridge-only fix (design explicitly scopes it to
    /// `FoundationModelsCore.stringGenerationSchema`); wiring an equivalent
    /// here (e.g. via `.stringEnum([value])`, which the partial validator
    /// already treats as an exact-match constraint) is a plausible follow-up
    /// but out of scope for this ticket.
    static let unsupportedKeywords: [String] = [
        "$dynamicRef", "$dynamicAnchor",
        "allOf", "oneOf", "not", "if", "then", "else",
        "patternProperties", "propertyNames", "dependentRequired", "dependentSchemas",
        "unevaluatedProperties", "minProperties", "maxProperties",
        "prefixItems", "contains", "unevaluatedItems", "uniqueItems",
        "const", "format", "minLength", "maxLength",
        "exclusiveMinimum", "exclusiveMaximum", "multipleOf"
    ]

    static func ensureSupported(_ schema: [String: Any], path: String) throws {
        if let keyword = unsupportedKeywords.first(where: { schema[$0] != nil }) {
            throw JSONSchemaCompileError.unsupportedKeyword(keyword, path: path)
        }

        // FND-0145 / TCK-0233: a `type` array containing `"null"` used to be
        // silently narrowed to its first non-null member by `jsonType(_:)`
        // below. The Apple-native bridge now maps mappable shapes via
        // `anyOf: [T, DynamicGenerationSchema.null]` (DES-0083), but this MLX
        // compiler builds its own `JSONSchemaNode` IR — which has no `null`
        // case — so keep rejecting by name rather than inventing unverified
        // logit-processor behavior or reintroducing silent narrowing.
        if let types = schema["type"] as? [String], types.contains("null") {
            throw JSONSchemaCompileError.unsupportedKeyword("type", path: path)
        }

        if let additional = schema["additionalProperties"], (additional as? Bool) != false {
            throw JSONSchemaCompileError.unsupportedKeyword("additionalProperties", path: path)
        }
    }

    static func compile(rootSchema: [String: Any]) throws -> JSONSchemaNode {
        var resolver = SchemaReferenceResolver(rootSchema: rootSchema)
        return try compileNode(from: rootSchema, path: "#", resolver: &resolver)
    }

    private struct SchemaReferenceResolver {
        let rootSchema: [String: Any]
        private var cache: [String: JSONSchemaNode] = [:]
        private var resolving: Set<String> = []

        mutating func resolve(_ ref: String, path: String) throws -> JSONSchemaNode {
            guard ref.hasPrefix("#/") else {
                throw JSONSchemaCompileError.unsupportedKeyword("$ref", path: path)
            }

            let components = ref.dropFirst(2).split(separator: "/").map(String.init)
            guard components.count >= 2,
                  components[0] == "$defs" || components[0] == "definitions" else {
                throw JSONSchemaCompileError.unsupportedKeyword("$ref", path: path)
            }

            let defName = components[1]
            if let cached = cache[defName] {
                return cached
            }
            if resolving.contains(defName) {
                throw JSONSchemaCompileError.invalidSchema("Circular $ref at \(path)")
            }

            let defGroup = components[0]
            let defs = JSON.object(rootSchema, key: defGroup) ?? [:]
            guard let defSchema = defs[defName] as? [String: Any] else {
                throw JSONSchemaCompileError.invalidSchema("Undefined $ref \(ref) at \(path)")
            }

            resolving.insert(defName)
            defer { resolving.remove(defName) }

            let resolved = try JSONSchemaSupport.compileNode(
                from: defSchema,
                path: "#/\(defGroup)/\(defName)",
                resolver: &self
            )
            cache[defName] = resolved
            return resolved
        }
    }

    private static func compileNode(
        from schema: [String: Any],
        path: String,
        resolver: inout SchemaReferenceResolver
    ) throws -> JSONSchemaNode {
        try ensureSupported(schema, path: path)

        if let ref = JSON.string(schema, key: "$ref") {
            return try resolver.resolve(ref, path: path)
        }

        if let anyOf = schema["anyOf"] as? [Any] {
            let choices = try anyOf.enumerated().map { index, item -> JSONSchemaNode in
                guard let itemSchema = item as? [String: Any] else {
                    throw JSONSchemaCompileError.invalidSchema("anyOf entry at \(path)/anyOf/\(index) must be an object.")
                }
                return try compileNode(from: itemSchema, path: "\(path)/anyOf/\(index)", resolver: &resolver)
            }
            guard !choices.isEmpty else {
                throw JSONSchemaCompileError.unsupportedKeyword("anyOf", path: path)
            }
            return .anyOf(choices)
        }

        if schema["enum"] != nil {
            guard let choices = schema["enum"] as? [String], !choices.isEmpty else {
                throw JSONSchemaCompileError.unsupportedKeyword("enum", path: path)
            }
            return .stringEnum(choices)
        }

        if let properties = schema["properties"] as? [String: Any] {
            return try compileObject(schema: schema, properties: properties, path: path, resolver: &resolver)
        }

        switch jsonType(schema) {
        case "object":
            return try compileObject(schema: schema, properties: [:], path: path, resolver: &resolver)
        case "array":
            let itemSchema = (schema["items"] as? [String: Any]) ?? ["type": "string"]
            let items = try compileNode(from: itemSchema, path: "\(path)/items", resolver: &resolver)
            return .array(
                items: items,
                minimumElements: JSON.int(schema, key: "minItems"),
                maximumElements: JSON.int(schema, key: "maxItems")
            )
        case "string":
            if let pattern = JSON.string(schema, key: "pattern") {
                return .stringPattern(pattern)
            }
            return .string
        case "integer":
            return .integer(
                minimum: JSON.int(schema, key: "minimum"),
                maximum: JSON.int(schema, key: "maximum")
            )
        case "number":
            return .number(
                minimum: JSON.double(schema, key: "minimum"),
                maximum: JSON.double(schema, key: "maximum")
            )
        case "boolean":
            return .boolean
        default:
            throw JSONSchemaCompileError.unsupportedType(jsonType(schema) ?? "missing", path: path)
        }
    }

    private static func compileObject(
        schema: [String: Any],
        properties: [String: Any],
        path: String,
        resolver: inout SchemaReferenceResolver
    ) throws -> JSONSchemaNode {
        let required = Set((schema["required"] as? [String]) ?? [])
        var compiled: [String: JSONSchemaNode] = [:]
        for key in properties.keys.sorted() {
            guard let propertySchema = properties[key] as? [String: Any] else {
                throw JSONSchemaCompileError.invalidSchema("JSON Schema property '\(key)' must be an object.")
            }
            compiled[key] = try compileNode(
                from: propertySchema,
                path: "\(path)/properties/\(key)",
                resolver: &resolver
            )
        }
        return .object(
            properties: compiled,
            required: required,
            propertyOrder: compiled.keys.sorted()
        )
    }

    private static func jsonType(_ schema: [String: Any]) -> String? {
        if let type = schema["type"] as? String {
            return type
        }
        if let types = schema["type"] as? [String] {
            return types.first { $0 != "null" } ?? types.first
        }
        return nil
    }
}

@available(macOS 27.0, iOS 27.0, *)
enum JSONSchemaCompileError: Error, Equatable {
    case unsupportedKeyword(String, path: String)
    case unsupportedType(String, path: String)
    case invalidSchema(String)
}

@available(macOS 27.0, iOS 27.0, *)
indirect enum JSONSchemaNode: Equatable {
    case object(properties: [String: JSONSchemaNode], required: Set<String>, propertyOrder: [String])
    case array(items: JSONSchemaNode, minimumElements: Int?, maximumElements: Int?)
    case string
    case stringPattern(String)
    case stringEnum([String])
    case integer(minimum: Int?, maximum: Int?)
    case number(minimum: Double?, maximum: Double?)
    case boolean
    case anyOf([JSONSchemaNode])
}
