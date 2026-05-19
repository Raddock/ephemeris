import Foundation

/// Minimal MCP stdio server. Implements the MCP protocol's required surface:
/// initialize, tools/list, tools/call. (Resources, prompts, sampling are out of scope
/// for the initial helper — can be added later.)
///
/// Per design doc §5.4: every tool returns observations / facts in the same shape the
/// document window uses, so the differential voice (throughline #4) survives the
/// protocol boundary. The recommender produces the JSON; the helper just transports it.
struct MCPServer: Sendable {
    let store: LibraryStore

    init(store: LibraryStore) {
        self.store = store
    }

    /// Returns the response bytes (with trailing newline added by the caller), or nil
    /// for notifications (one-way messages, no id).
    func handle(requestData: Data) -> Data? {
        do {
            let request = try JSONDecoder().decode(JSONRPCRequest.self, from: requestData)
            // Notifications have no id; we don't reply
            let isNotification = request.id == nil

            let resultOrError: Result<JSONValue, JSONRPCError>
            switch request.method {
            case "initialize":  resultOrError = .success(initializeResult())
            case "tools/list":  resultOrError = .success(toolsList())
            case "tools/call":  resultOrError = handleToolsCall(params: request.params)
            case "notifications/initialized":
                // Standard MCP handshake notification — ignore.
                return nil
            case "ping":
                resultOrError = .success(.object([:]))
            default:
                resultOrError = .failure(JSONRPCError(
                    code: -32601,
                    message: "Method not found: \(request.method)",
                    data: nil
                ))
            }

            if isNotification { return nil }
            let response: JSONRPCResponse
            switch resultOrError {
            case .success(let value):
                response = JSONRPCResponse(id: request.id, result: value)
            case .failure(let error):
                response = JSONRPCResponse(id: request.id, error: error)
            }
            return try JSONEncoder().encode(response)
        } catch {
            // Couldn't parse the request — return a parse-error with id=null
            let response = JSONRPCResponse(id: .null, error: JSONRPCError.parseError)
            return try? JSONEncoder().encode(response)
        }
    }

    // MARK: - Method handlers

    private func initializeResult() -> JSONValue {
        return .object([
            "protocolVersion": "2024-11-05",
            "capabilities": .object([
                "tools": .object([:]),
            ]),
            "serverInfo": .object([
                "name": "ephemeris-mcp",
                "version": "0.1.0",
            ]),
        ])
    }

    private func toolsList() -> JSONValue {
        .object([
            "tools": .array(Tools.all.map { tool in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "inputSchema": tool.inputSchema,
                ])
            })
        ])
    }

    private func handleToolsCall(params: JSONValue?) -> Result<JSONValue, JSONRPCError> {
        guard let dict = params?.dictValue,
              let name = dict["name"]?.stringValue
        else {
            return .failure(.invalidParams)
        }
        let arguments = dict["arguments"]?.dictValue ?? [:]
        guard let tool = Tools.all.first(where: { $0.name == name }) else {
            return .failure(JSONRPCError(code: -32601,
                                         message: "Unknown tool: \(name)",
                                         data: nil))
        }
        let resultValue = tool.invoke(arguments, store)
        // MCP tool results are wrapped in { content: [...], isError: bool }
        let contentBlock: JSONValue = .object([
            "type": JSONValue.string("text"),
            "text": JSONValue.string(JSONFormatter.toPrettyString(resultValue)),
        ])
        return .success(.object([
            "content": .array([contentBlock]),
            "isError": JSONValue.bool(false),
        ]))
    }
}

enum JSONFormatter {
    static func toPrettyString(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let str = String(data: data, encoding: .utf8)
        else { return "{}" }
        return str
    }
}
