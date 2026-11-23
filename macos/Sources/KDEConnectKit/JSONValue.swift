import Foundation

/// A JSON value that can cross concurrency domains.
///
/// KDE Connect peers are loose about types: Android sends some booleans as `"true"` and some
/// numbers as strings (a notification's `time`, for example). The accessors below accept every
/// spelling a peer is known to use, so callers can ask for the type they want.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Accessors

public extension JSONValue {
    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    var string: String? {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .bool(let value): String(value)
        default: nil
        }
    }

    var int: Int64? {
        switch self {
        case .int(let value): value
        case .double(let value): value.isFinite ? Int64(value) : nil
        case .bool(let value): value ? 1 : 0
        case .string(let value): Int64(value) ?? Double(value).flatMap { $0.isFinite ? Int64($0) : nil }
        default: nil
        }
    }

    var double: Double? {
        switch self {
        case .int(let value): Double(value)
        case .double(let value): value
        case .string(let value): Double(value)
        default: nil
        }
    }

    var bool: Bool? {
        switch self {
        case .bool(let value): value
        case .int(let value): value != 0
        case .string(let value):
            switch value.lowercased() {
            case "true", "1": true
            case "false", "0": false
            default: nil
            }
        default: nil
        }
    }

    var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var stringArray: [String] { array?.compactMap(\.string) ?? [] }
}

// MARK: - Literals

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByFloatLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral
{
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(nilLiteral: ()) { self = .null }
}

public extension JSONValue {
    init(_ value: String) { self = .string(value) }
    init(_ value: Int) { self = .int(Int64(value)) }
    init(_ value: Int64) { self = .int(value) }
    init(_ value: Bool) { self = .bool(value) }
    init(_ strings: [String]) { self = .array(strings.map(JSONValue.string)) }
}

// MARK: - Foundation bridging

extension JSONValue {
    /// Converts a `JSONSerialization` result. NSNumber booleans are told apart from numbers by
    /// their CoreFoundation type, which `as? Bool` cannot do.
    init(foundation value: Any) {
        switch value {
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.int64Value)
            }
        case let array as [Any]:
            self = .array(array.map(JSONValue.init(foundation:)))
        case let object as [String: Any]:
            self = .object(object.mapValues(JSONValue.init(foundation:)))
        default:
            self = .null
        }
    }

    var foundationValue: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .int(let value): value
        case .double(let value): value
        case .string(let value): value
        case .array(let value): value.map(\.foundationValue)
        case .object(let value): value.mapValues(\.foundationValue)
        }
    }
}
