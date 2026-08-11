import Foundation

/// Validates incremental JSON text against a compiled schema node (TCK-0110b).
@available(macOS 27.0, *)
struct PartialJSONSchemaValidator {
    let root: JSONSchemaNode

    func isValidPrefix(_ text: String) -> Bool {
        var parser = PartialJSONParser(input: text, root: root)
        return parser.isValidPartialDocument()
    }
}

@available(macOS 27.0, *)
private enum ValueParseOutcome {
    case complete
    case partial
    case invalid
}

@available(macOS 27.0, *)
private struct PartialJSONParser {
    let input: String
    let root: JSONSchemaNode
    private var index: String.Index

    init(input: String, root: JSONSchemaNode) {
        self.input = input
        self.root = root
        self.index = input.startIndex
    }

    mutating func isValidPartialDocument() -> Bool {
        skipWhitespace()
        guard index < input.endIndex || input.isEmpty else {
            return false
        }

        if input.isEmpty {
            return canCompleteFromValue(root, allowEmpty: true)
        }

        switch parseValue(root, allowPartial: true) {
        case .complete, .partial:
            return true
        case .invalid:
            return false
        }
    }

    private mutating func parseValue(_ schema: JSONSchemaNode, allowPartial: Bool) -> ValueParseOutcome {
        skipWhitespace()
        if index >= input.endIndex {
            return allowPartial && canCompleteFromValue(schema, allowEmpty: true) ? .partial : .invalid
        }

        switch schema {
        case .anyOf(let choices):
            let saved = index
            var sawPartial = false
            for choice in choices {
                index = saved
                switch parseValue(choice, allowPartial: allowPartial) {
                case .complete:
                    return .complete
                case .partial:
                    sawPartial = true
                case .invalid:
                    continue
                }
            }
            index = saved
            if sawPartial {
                return .partial
            }
            return allowPartial && choices.contains { canCompleteFromValue($0, allowEmpty: true) }
                ? .partial
                : .invalid

        case .string, .stringPattern, .stringEnum:
            return parseString(schema: schema, allowPartial: allowPartial)

        case .integer(let minimum, let maximum):
            return parseNumber(allowPartial: allowPartial) { text in
                guard let value = Int(text) else { return false }
                if let minimum, value < minimum { return false }
                if let maximum, value > maximum { return false }
                return true
            }

        case .number(let minimum, let maximum):
            return parseNumber(allowPartial: allowPartial) { text in
                guard let value = Double(text) else { return false }
                if let minimum, value < minimum { return false }
                if let maximum, value > maximum { return false }
                return true
            }

        case .boolean:
            return parseLiteral(options: ["true", "false"], allowPartial: allowPartial)

        case .array(let items, let minimumElements, let maximumElements):
            return parseArray(
                items: items,
                minimumElements: minimumElements,
                maximumElements: maximumElements,
                allowPartial: allowPartial
            )

        case .object(let properties, let required, let propertyOrder):
            return parseObject(
                properties: properties,
                required: required,
                propertyOrder: propertyOrder,
                allowPartial: allowPartial
            )
        }
    }

    private mutating func parseObject(
        properties: [String: JSONSchemaNode],
        required: Set<String>,
        propertyOrder: [String],
        allowPartial: Bool
    ) -> ValueParseOutcome {
        guard consume("{") else {
            if allowPartial, input.allSatisfy(\.isWhitespace) {
                return .partial
            }
            return .invalid
        }

        skipWhitespace()
        if consume("}") {
            return required.isEmpty ? .complete : .invalid
        }

        var seenKeys: Set<String> = []
        while true {
            skipWhitespace()
            let parsedKey: String?
            switch parseQuotedString(allowPartial: allowPartial) {
            case .complete(let key):
                guard properties[key] != nil else { return .invalid }
                seenKeys.insert(key)
                parsedKey = key
            case .partial:
                return allowPartial && canContinueObject(
                    seenKeys: seenKeys,
                    required: required,
                    propertyOrder: propertyOrder,
                    stage: .key
                ) ? .partial : .invalid
            case .notStarted:
                return allowPartial && canContinueObject(
                    seenKeys: seenKeys,
                    required: required,
                    propertyOrder: propertyOrder,
                    stage: .key
                ) ? .partial : .invalid
            }

            skipWhitespace()
            guard consume(":") else {
                return allowPartial && canContinueObject(
                    seenKeys: seenKeys,
                    required: required,
                    propertyOrder: propertyOrder,
                    stage: .colon
                ) ? .partial : .invalid
            }

            guard let key = parsedKey, let propertySchema = properties[key] else { return .invalid }
            switch parseValue(propertySchema, allowPartial: allowPartial) {
            case .invalid:
                return .invalid
            case .partial:
                return allowPartial ? .partial : .invalid
            case .complete:
                break
            }

            skipWhitespace()
            if consume("}") {
                return required.isSubset(of: seenKeys) ? .complete : .invalid
            }

            guard consume(",") else {
                return allowPartial && canContinueObject(
                    seenKeys: seenKeys,
                    required: required,
                    propertyOrder: propertyOrder,
                    stage: .comma
                ) ? .partial : .invalid
            }
        }
    }

    private enum ObjectStage {
        case key
        case colon
        case comma
    }

    private func canContinueObject(
        seenKeys: Set<String>,
        required: Set<String>,
        propertyOrder: [String],
        stage: ObjectStage
    ) -> Bool {
        switch stage {
        case .key:
            return nextExpectedKey(seenKeys: seenKeys, propertyOrder: propertyOrder) != nil
                || required.isSubset(of: seenKeys)
        case .colon:
            return true
        case .comma:
            return nextExpectedKey(seenKeys: seenKeys, propertyOrder: propertyOrder) != nil
                || required.isSubset(of: seenKeys)
        }
    }

    private func nextExpectedKey(seenKeys: Set<String>, propertyOrder: [String]) -> String? {
        propertyOrder.first { !seenKeys.contains($0) }
    }

    private mutating func parseArray(
        items: JSONSchemaNode,
        minimumElements: Int?,
        maximumElements: Int?,
        allowPartial: Bool
    ) -> ValueParseOutcome {
        guard consume("[") else {
            return allowPartial ? .partial : .invalid
        }

        skipWhitespace()
        if consume("]") {
            return (minimumElements ?? 0) <= 0 ? .complete : .invalid
        }

        var count = 0
        while true {
            switch parseValue(items, allowPartial: allowPartial) {
            case .invalid:
                return .invalid
            case .partial:
                return allowPartial ? .partial : .invalid
            case .complete:
                break
            }
            count += 1
            if let maximumElements, count > maximumElements {
                return .invalid
            }

            skipWhitespace()
            if consume("]") {
                return count >= (minimumElements ?? 0) ? .complete : .invalid
            }

            guard consume(",") else {
                return allowPartial ? .partial : .invalid
            }
        }
    }

    private mutating func parseString(schema: JSONSchemaNode, allowPartial: Bool) -> ValueParseOutcome {
        switch parseQuotedString(allowPartial: allowPartial) {
        case .complete(let content):
            return validateCompleteString(content, schema: schema) ? .complete : .invalid
        case .partial:
            return allowPartial && canContinuePartialString(schema: schema) ? .partial : .invalid
        case .notStarted:
            return allowPartial && canStartString(schema: schema) ? .partial : .invalid
        }
    }

    private func validateCompleteString(_ content: String, schema: JSONSchemaNode) -> Bool {
        switch schema {
        case .string:
            return true
        case .stringPattern(let pattern):
            guard let regex = try? Regex(pattern) else { return false }
            return content.wholeMatch(of: regex) != nil
        case .stringEnum(let choices):
            return choices.contains(content)
        default:
            return false
        }
    }

    private func canContinuePartialString(schema: JSONSchemaNode) -> Bool {
        switch schema {
        case .string, .stringPattern:
            return true
        case .stringEnum:
            return true
        default:
            return false
        }
    }

    private func canStartString(schema: JSONSchemaNode) -> Bool {
        switch schema {
        case .string, .stringPattern:
            return true
        case .stringEnum(let choices):
            return choices.contains { !$0.isEmpty }
        default:
            return false
        }
    }

    private mutating func parseNumber(allowPartial: Bool, validate: (String) -> Bool) -> ValueParseOutcome {
        skipWhitespace()
        let start = index
        if index < input.endIndex, input[index] == "-" {
            index = input.index(after: index)
        }

        var sawDigit = false
        while index < input.endIndex {
            let ch = input[index]
            if ch.isNumber || ch == "." {
                sawDigit = true
                index = input.index(after: index)
                continue
            }
            break
        }

        if !sawDigit {
            index = start
            return allowPartial ? .partial : .invalid
        }

        let token = String(input[start ..< index])
        if index >= input.endIndex {
            return allowPartial || isCompleteNumberPrefix(token) ? .partial : .invalid
        }

        guard isNumberBoundary(at: index) else {
            index = start
            return .invalid
        }

        return validate(token) ? .complete : .invalid
    }

    private mutating func parseLiteral(options: [String], allowPartial: Bool) -> ValueParseOutcome {
        skipWhitespace()
        let start = index
        for option in options {
            index = start
            if consume(option) {
                if index >= input.endIndex || isValueBoundary(at: index) {
                    return .complete
                }
            }
        }

        index = start
        if allowPartial {
            let hasPartial = options.contains { option in
                option.hasPrefix(String(input[start ..< min(input.endIndex, input.index(start, offsetBy: option.count, limitedBy: input.endIndex) ?? input.endIndex)]))
                    && String(input[start...]).count <= option.count
            }
            return hasPartial ? .partial : .invalid
        }
        return .invalid
    }

    private enum QuotedStringParse {
        case complete(String)
        case partial
        case notStarted
    }

    private mutating func parseQuotedString(allowPartial: Bool) -> QuotedStringParse {
        skipWhitespace()
        guard consume("\"") else { return .notStarted }

        var content = ""
        var escaped = false
        while index < input.endIndex {
            let ch = input[index]
            index = input.index(after: index)

            if escaped {
                content.append(ch)
                escaped = false
                continue
            }

            if ch == "\\" {
                escaped = true
                continue
            }

            if ch == "\"" {
                return .complete(content)
            }

            content.append(ch)
        }

        _ = content
        return allowPartial ? .partial : .notStarted
    }

    private mutating func skipWhitespace() {
        while index < input.endIndex, input[index].isWhitespace {
            index = input.index(after: index)
        }
    }

    @discardableResult
    private mutating func consume(_ literal: String) -> Bool {
        skipWhitespace()
        guard input[index...].hasPrefix(literal) else { return false }
        index = input.index(index, offsetBy: literal.count)
        return true
    }

    private func isNumberBoundary(at position: String.Index) -> Bool {
        isValueBoundary(at: position)
    }

    private func isValueBoundary(at position: String.Index) -> Bool {
        guard position < input.endIndex else { return true }
        let ch = input[position]
        return ch.isWhitespace || ch == "," || ch == "}" || ch == "]"
    }

    private func isCompleteNumberPrefix(_ token: String) -> Bool {
        Double(token) != nil || Int(token) != nil
    }

    private func canCompleteFromValue(_ schema: JSONSchemaNode, allowEmpty: Bool) -> Bool {
        switch schema {
        case .object(_, let required, _):
            return allowEmpty && required.isEmpty
        case .array(_, let minimumElements, _):
            return allowEmpty && (minimumElements ?? 0) <= 0
        case .string, .stringPattern, .stringEnum, .integer, .number, .boolean, .anyOf:
            return allowEmpty
        }
    }
}
