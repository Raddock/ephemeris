import Foundation
import SwiftData

/// JSON-RPC 2.0 protocol handler for MCP requests against the live SwiftData library.
/// Mirrors the standalone stdio handler in tools/ephemeris-mcp/ but reads from the
/// app's running `ModelContainer` directly — no SQLite race conditions.
///
/// Per design doc §5.4 throughline #4: every observation carries its `sourceAuthority`
/// so the protocol boundary doesn't erase the canon-vs-heuristic distinction.
@MainActor
struct MCPProtocolHandler {
    let library: EphemerisLibrary

    init(library: EphemerisLibrary) {
        self.library = library
    }

    /// Returns the response bytes (no trailing newline — the HTTP transport handles framing),
    /// or nil for notifications (no id) which get HTTP 204 from the connection handler.
    func handle(requestData: Data) -> Data? {
        do {
            let request = try JSONDecoder().decode(MCPJSONRPCRequest.self, from: requestData)
            let isNotification = request.id == nil
            let result: Result<MCPJSONValue, MCPJSONRPCError>

            switch request.method {
            case "initialize":      result = .success(initializeResult())
            case "tools/list":      result = .success(toolsList())
            case "tools/call":      result = handleToolsCall(params: request.params)
            case "notifications/initialized":
                return nil
            case "ping":
                result = .success(.object([:]))
            default:
                result = .failure(MCPJSONRPCError(code: -32601,
                                                  message: "Method not found: \(request.method)",
                                                  data: nil))
            }
            if isNotification { return nil }

            let response: MCPJSONRPCResponse
            switch result {
            case .success(let v): response = MCPJSONRPCResponse(id: request.id, result: v)
            case .failure(let e): response = MCPJSONRPCResponse(id: request.id, error: e)
            }
            return try JSONEncoder().encode(response)
        } catch {
            let response = MCPJSONRPCResponse(id: .null, error: MCPJSONRPCError.parseError)
            return try? JSONEncoder().encode(response)
        }
    }

    // MARK: - Methods

    private func initializeResult() -> MCPJSONValue {
        .object([
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": .object([
                "name": .string("ephemeris"),
                "version": .string("0.2.0"),
            ]),
        ])
    }

    private func toolsList() -> MCPJSONValue {
        .object([
            "tools": .array(MCPTools.all.map { tool in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "inputSchema": tool.inputSchema,
                ])
            })
        ])
    }

    private func handleToolsCall(params: MCPJSONValue?) -> Result<MCPJSONValue, MCPJSONRPCError> {
        guard let dict = params?.dictValue,
              let name = dict["name"]?.stringValue
        else { return .failure(.invalidParams) }
        let args = dict["arguments"]?.dictValue ?? [:]
        guard let tool = MCPTools.all.first(where: { $0.name == name }) else {
            return .failure(MCPJSONRPCError(code: -32601,
                                            message: "Unknown tool: \(name)",
                                            data: nil))
        }
        let value = tool.invoke(args, library.container)
        let text = MCPJSONFormatter.toPrettyString(value)
        let content: MCPJSONValue = .object([
            "type": .string("text"),
            "text": .string(text),
        ])
        return .success(.object([
            "content": .array([content]),
            "isError": .bool(false),
        ]))
    }
}

// MARK: - JSON-RPC types (in-app variant — namespaced to avoid clashing with the stdio helper)

struct MCPJSONRPCRequest: Decodable {
    let jsonrpc: String
    let method: String
    let params: MCPJSONValue?
    let id: MCPJSONValue?
}

struct MCPJSONRPCResponse: Encodable {
    let jsonrpc: String = "2.0"
    let id: MCPJSONValue?
    let result: MCPJSONValue?
    let error: MCPJSONRPCError?

    init(id: MCPJSONValue?, result: MCPJSONValue) {
        self.id = id; self.result = result; self.error = nil
    }
    init(id: MCPJSONValue?, error: MCPJSONRPCError) {
        self.id = id; self.result = nil; self.error = error
    }
}

struct MCPJSONRPCError: Encodable, Error {
    let code: Int
    let message: String
    let data: MCPJSONValue?
    static let parseError      = MCPJSONRPCError(code: -32700, message: "Parse error",       data: nil)
    static let invalidRequest  = MCPJSONRPCError(code: -32600, message: "Invalid request",   data: nil)
    static let methodNotFound  = MCPJSONRPCError(code: -32601, message: "Method not found",  data: nil)
    static let invalidParams   = MCPJSONRPCError(code: -32602, message: "Invalid params",    data: nil)
    static let internalError   = MCPJSONRPCError(code: -32603, message: "Internal error",    data: nil)
}

indirect enum MCPJSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case integer(Int)
    case string(String)
    case array([MCPJSONValue])
    case object([String: MCPJSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .integer(i); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([MCPJSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: MCPJSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown JSON")
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let b):    try c.encode(b)
        case .integer(let i): try c.encode(i)
        case .number(let d):  try c.encode(d)
        case .string(let s):  try c.encode(s)
        case .array(let a):   try c.encode(a)
        case .object(let o):  try c.encode(o)
        }
    }
    var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    var intValue: Int? {
        switch self {
        case .integer(let i): return i
        case .number(let d): return Int(d)
        default: return nil
        }
    }
    var dictValue: [String: MCPJSONValue]? { if case .object(let o) = self { return o } else { return nil } }
}

enum MCPJSONFormatter {
    static func toPrettyString(_ value: MCPJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let str = String(data: data, encoding: .utf8)
        else { return "{}" }
        return str
    }
}
