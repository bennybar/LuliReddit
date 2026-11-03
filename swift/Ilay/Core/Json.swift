import Foundation

/// An insertion-ordered string-keyed map (Kotlin's LinkedHashMap). JSON objects
/// keep their key order, and several stores evict "oldest first" through it.
struct OrderedMap<Value> {
    private(set) var keys: [String] = []
    private var storage: [String: Value] = [:]

    init() {}

    var count: Int { keys.count }
    var isEmpty: Bool { keys.isEmpty }
    var values: [Value] { keys.map { storage[$0]! } }
    var dictionary: [String: Value] { storage }

    subscript(key: String) -> Value? {
        get { storage[key] }
        set {
            guard let newValue else {
                removeValue(forKey: key)
                return
            }
            if storage.updateValue(newValue, forKey: key) == nil { keys.append(key) }
        }
    }

    @discardableResult
    mutating func removeValue(forKey key: String) -> Value? {
        guard let old = storage.removeValue(forKey: key) else { return nil }
        keys.remove(at: keys.firstIndex(of: key)!)
        return old
    }

    /// Drops the first (oldest) entry.
    mutating func removeFirst() {
        guard let k = keys.first else { return }
        keys.removeFirst()
        storage.removeValue(forKey: k)
    }
}

extension OrderedMap: Sequence {
    func makeIterator() -> AnyIterator<(key: String, value: Value)> {
        var i = 0
        return AnyIterator {
            guard i < keys.count else { return nil }
            defer { i += 1 }
            return (keys[i], storage[keys[i]]!)
        }
    }
}

extension OrderedMap: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, Value)...) {
        for (k, v) in elements { self[k] = v }
    }
}

// Same keys and values, like Kotlin's Map equality: order doesn't count.
extension OrderedMap: Equatable where Value: Equatable {
    static func == (a: Self, b: Self) -> Bool { a.storage == b.storage }
}

extension OrderedMap: Sendable where Value: Sendable {}

typealias JsonObject = OrderedMap<JsonElement>

/// A parsed JSON value. Lenient JSON for Reddit responses and local stores,
/// with key order kept and whole numbers kept whole.
enum JsonElement: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JsonElement])
    case object(JsonObject)
}

extension JsonElement: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringInterpolation, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    init(nilLiteral: ()) { self = .null }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(stringLiteral value: String) { self = .string(value) }
    init(arrayLiteral elements: JsonElement...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JsonElement)...) {
        var o = JsonObject()
        for (k, v) in elements { o[k] = v }
        self = .object(o)
    }

    /// An optional value; nil is a JSON null, like Kotlin's `put(key, null)`.
    static func of(_ v: String?) -> JsonElement { v.map(JsonElement.string) ?? .null }
    static func of(_ v: Int?) -> JsonElement { v.map(JsonElement.int) ?? .null }
    static func of(_ v: Bool?) -> JsonElement { v.map(JsonElement.bool) ?? .null }
    static func strings(_ v: [String]) -> JsonElement { .array(v.map(JsonElement.string)) }
}

/*
 * Safe accessors for Reddit's polymorphic fields (a value can be an object,
 * "", false or null depending on the post — never assume a shape).
 */
extension JsonElement {
    subscript(key: String) -> JsonElement? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    subscript(index: Int) -> JsonElement? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    func obj() -> JsonObject? {
        if case .object(let o) = self { return o }
        return nil
    }

    func arr() -> [JsonElement]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// A JSON string value (not a number/bool/null rendered as text).
    func str() -> String? {
        if case .string(let s) = self { return s }
        return nil
    }

    func double() -> Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }

    func long() -> Int? {
        switch self {
        case .int(let i): return i
        case .double(let d):
            if d.isNaN { return 0 }
            // Saturates, like Kotlin's Double.toLong().
            return d >= 9.2e18 ? Int.max : d <= -9.2e18 ? Int.min : Int(d)
        default: return nil
        }
    }

    func int() -> Int? { long() }

    /// A JSON boolean (strict: "true" as a string is not a boolean).
    func bool() -> Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    func isTrue() -> Bool { bool() == true }

    /// A primitive as text, whatever its type (Kotlin's JsonPrimitive.content); nil for arrays and objects.
    func content() -> String? {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return "\(d)"
        case .string(let s): return s
        case .array, .object: return nil
        }
    }
}

extension Optional where Wrapped == JsonElement {
    subscript(key: String) -> JsonElement? { self?[key] }
    subscript(index: Int) -> JsonElement? { self?[index] }
    func obj() -> JsonObject? { self?.obj() }
    func arr() -> [JsonElement]? { self?.arr() }
    func str() -> String? { self?.str() }
    func double() -> Double? { self?.double() }
    func long() -> Int? { self?.long() }
    func int() -> Int? { self?.int() }
    func bool() -> Bool? { self?.bool() }
    func isTrue() -> Bool { self?.isTrue() ?? false }
    func content() -> String? { self?.content() }
}

// MARK: - Writing

extension JsonElement {
    /// Compact JSON text (Kotlin's `toString()`).
    func encoded() -> String {
        var out = ""
        write(to: &out, indent: nil, depth: 0)
        return out
    }

    /// Indented JSON, for backups.
    func pretty() -> String {
        var out = ""
        write(to: &out, indent: "  ", depth: 0)
        return out
    }

    private func write(to out: inout String, indent: String?, depth: Int) {
        func newline(_ d: Int) {
            guard let indent else { return }
            out += "\n"
            for _ in 0..<d { out += indent }
        }
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d): out += d.isFinite ? "\(d)" : "null"
        case .string(let s): JsonElement.writeString(s, to: &out)
        case .array(let a):
            if a.isEmpty {
                out += "[]"
                return
            }
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                newline(depth + 1)
                v.write(to: &out, indent: indent, depth: depth + 1)
            }
            newline(depth)
            out += "]"
        case .object(let o):
            if o.isEmpty {
                out += "{}"
                return
            }
            out += "{"
            var first = true
            for (k, v) in o {
                if !first { out += "," }
                first = false
                newline(depth + 1)
                JsonElement.writeString(k, to: &out)
                out += indent == nil ? ":" : ": "
                v.write(to: &out, indent: indent, depth: depth + 1)
            }
            newline(depth)
            out += "}"
        }
    }

    private static func writeString(_ s: String, to out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where u.value < 0x20: out += String(format: "\\u%04x", u.value)
            default: out.unicodeScalars.append(u)
            }
        }
        out += "\""
    }
}

extension OrderedMap where Value == JsonElement {
    func encoded() -> String { JsonElement.object(self).encoded() }
}

// MARK: - Parsing

struct JsonParseError: Error {}

enum AppJson {
    static func parse(_ text: String) throws -> JsonElement {
        var s = text
        return try s.withUTF8 { try parse(bytes: $0) }
    }

    static func parse(_ data: Data) throws -> JsonElement {
        try data.withUnsafeBytes { try parse(bytes: $0.bindMemory(to: UInt8.self)) }
    }

    private static func parse(bytes: UnsafeBufferPointer<UInt8>) throws -> JsonElement {
        var p = Parser(p: bytes)
        let v = try p.value()
        p.skipSpace()
        guard p.i == bytes.count else { throw JsonParseError() }
        return v
    }

    // Hand-written rather than JSONSerialization: that loses the key order and
    // can't tell a whole number from a double.
    private struct Parser {
        let p: UnsafeBufferPointer<UInt8>
        var i = 0

        mutating func skipSpace() {
            while i < p.count, p[i] == 0x20 || p[i] == 0x0A || p[i] == 0x0D || p[i] == 0x09 { i += 1 }
        }

        mutating func value() throws -> JsonElement {
            skipSpace()
            guard i < p.count else { throw JsonParseError() }
            switch p[i] {
            case UInt8(ascii: "{"): return .object(try object())
            case UInt8(ascii: "["): return .array(try array())
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return try number()
            }
        }

        mutating func literal(_ s: StaticString) throws {
            let n = s.utf8CodeUnitCount
            guard i + n <= p.count, memcmp(p.baseAddress! + i, s.utf8Start, n) == 0 else { throw JsonParseError() }
            i += n
        }

        mutating func object() throws -> JsonObject {
            i += 1
            var out = JsonObject()
            skipSpace()
            if i < p.count, p[i] == UInt8(ascii: "}") {
                i += 1
                return out
            }
            while true {
                skipSpace()
                guard i < p.count, p[i] == UInt8(ascii: "\"") else { throw JsonParseError() }
                let k = try string()
                skipSpace()
                guard i < p.count, p[i] == UInt8(ascii: ":") else { throw JsonParseError() }
                i += 1
                out[k] = try value()
                skipSpace()
                guard i < p.count else { throw JsonParseError() }
                if p[i] == UInt8(ascii: ",") {
                    i += 1
                } else if p[i] == UInt8(ascii: "}") {
                    i += 1
                    return out
                } else {
                    throw JsonParseError()
                }
            }
        }

        mutating func array() throws -> [JsonElement] {
            i += 1
            var out: [JsonElement] = []
            skipSpace()
            if i < p.count, p[i] == UInt8(ascii: "]") {
                i += 1
                return out
            }
            while true {
                out.append(try value())
                skipSpace()
                guard i < p.count else { throw JsonParseError() }
                if p[i] == UInt8(ascii: ",") {
                    i += 1
                } else if p[i] == UInt8(ascii: "]") {
                    i += 1
                    return out
                } else {
                    throw JsonParseError()
                }
            }
        }

        mutating func string() throws -> String {
            i += 1
            let start = i
            while i < p.count, p[i] != UInt8(ascii: "\""), p[i] != UInt8(ascii: "\\") { i += 1 }
            guard i < p.count else { throw JsonParseError() }
            if p[i] == UInt8(ascii: "\"") {
                defer { i += 1 }
                return String(decoding: UnsafeBufferPointer(rebasing: p[start..<i]), as: UTF8.self)
            }
            // Has escapes: the slow path.
            var bytes = Array(p[start..<i])
            while true {
                guard i < p.count else { throw JsonParseError() }
                let c = p[i]
                i += 1
                if c == UInt8(ascii: "\"") { return String(decoding: bytes, as: UTF8.self) }
                guard c == UInt8(ascii: "\\") else {
                    bytes.append(c)
                    continue
                }
                guard i < p.count else { throw JsonParseError() }
                let e = p[i]
                i += 1
                switch e {
                case UInt8(ascii: "n"): bytes.append(0x0A)
                case UInt8(ascii: "r"): bytes.append(0x0D)
                case UInt8(ascii: "t"): bytes.append(0x09)
                case UInt8(ascii: "b"): bytes.append(0x08)
                case UInt8(ascii: "f"): bytes.append(0x0C)
                case UInt8(ascii: "u"):
                    var unit = try hex4()
                    if (0xD800..<0xDC00).contains(unit), i + 1 < p.count, p[i] == UInt8(ascii: "\\"), p[i + 1] == UInt8(ascii: "u") {
                        let save = i
                        i += 2
                        let low = try hex4()
                        if (0xDC00..<0xE000).contains(low) {
                            unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            i = save
                        }
                    }
                    // A lone surrogate isn't a character.
                    let scalar = Unicode.Scalar(unit) ?? "\u{FFFD}"
                    bytes.append(contentsOf: Array(String(scalar).utf8))
                default: bytes.append(e) // \" \\ \/
                }
            }
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= p.count else { throw JsonParseError() }
            var v: UInt32 = 0
            for _ in 0..<4 {
                let c = p[i]
                i += 1
                let d: UInt8
                switch c {
                case 0x30...0x39: d = c - 0x30
                case 0x41...0x46: d = c - 0x41 + 10
                case 0x61...0x66: d = c - 0x61 + 10
                default: throw JsonParseError()
                }
                v = v << 4 | UInt32(d)
            }
            return v
        }

        mutating func number() throws -> JsonElement {
            let start = i
            var whole = true
            while i < p.count {
                switch p[i] {
                case 0x30...0x39, UInt8(ascii: "-"): break
                case UInt8(ascii: "."), UInt8(ascii: "e"), UInt8(ascii: "E"), UInt8(ascii: "+"): whole = false
                default:
                    return try finish(start, whole)
                }
                i += 1
            }
            return try finish(start, whole)
        }

        private func finish(_ start: Int, _ whole: Bool) throws -> JsonElement {
            guard i > start else { throw JsonParseError() }
            let text = String(decoding: UnsafeBufferPointer(rebasing: p[start..<i]), as: UTF8.self)
            if whole, let v = Int(text) { return .int(v) }
            guard let d = Double(text) else { throw JsonParseError() }
            return .double(d)
        }
    }
}

func parseJsonOrNull(_ text: String) -> JsonElement? { try? AppJson.parse(text) }
