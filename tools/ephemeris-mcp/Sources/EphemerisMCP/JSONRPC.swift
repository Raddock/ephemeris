import Foundation

/// Minimal JSON-RPC 2.0 types for the MCP stdio transport.
/// The MCP protocol uses JSON-RPC 2.0 with a small set of methods (initialize,
/// tools/list, tools/call, resources/list, resources/read, …).

struct JSONRPCRequest: Decodable {
    let jsonrpc: String
    let method: String
    let params: JSONValue?
    let id: JSONValue?  // request when present, notification when nil
}

struct JSONRPCResponse: Encodable {
    let jsonrpc: String = "2.0"
    let id: JSONValue?
    let result: JSONValue?
    let error: JSONRPCError?

    init(id: JSONValue?, result: JSONValue) {
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: JSONValue?, error: JSONRPCError) {
        self.id = id
        self.result = nil
        self.error = error
    }
}

struct JSONRPCError: Encodable, Error {
    let code: Int
    let message: String
    let data: JSONValue?

    static let parseError      = JSONRPCError(code: -32700, message: "Parse error",       data: nil)
    static let invalidRequest  = JSONRPCError(code: -32600, message: "Invalid request",   data: nil)
    static let methodNotFound  = JSONRPCError(code: -32601, message: "Method not found",  data: nil)
    static let invalidParams   = JSONRPCError(code: -32602, message: "Invalid params",    data: nil)
    static let internalError   = JSONRPCError(code: -32603, message: "Internal error",    data: nil)
}

/// Codable any-JSON-value, used for request id (number or string) and the params/result blobs.
indirect enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case integer(Int)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .integer(i); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown JSON")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:          try c.encodeNil()
        case .bool(let b):   try c.encode(b)
        case .integer(let i): try c.encode(i)
        case .number(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a):  try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    // Convenience accessors
    var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    var intValue: Int? {
        switch self {
        case .integer(let i): return i
        case .number(let d): return Int(d)
        default: return nil
        }
    }
    var dictValue: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
    var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
}

extension JSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .string(value) }
}
extension JSONValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) { self = .integer(value) }
}
extension JSONValue: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) { self = .number(value) }
}
extension JSONValue: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) { self = .bool(value) }
}
extension JSONValue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}
extension JSONValue: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        var o: [String: JSONValue] = [:]
        for (k, v) in elements { o[k] = v }
        self = .object(o)
    }
}
