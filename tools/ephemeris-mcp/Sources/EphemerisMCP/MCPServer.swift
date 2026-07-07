import Foundation

/// Minimal MCP stdio server. Implements the MCP protocol's required surface
/// (initialize, tools/list, tools/call) plus the optional Resources surface
/// (resources/list, resources/read) for `ephemeris://rig/{id}`,
/// `ephemeris://night/{id}`, `ephemeris://observation/{id}`, `ephemeris://help/{topic-id}`.
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
            case "initialize":      resultOrError = .success(initializeResult())
            case "tools/list":      resultOrError = .success(toolsList())
            case "tools/call":      resultOrError = handleToolsCall(params: request.params)
            case "resources/list":  resultOrError = .success(resourcesList())
            case "resources/read":  resultOrError = handleResourcesRead(params: request.params)
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
                "resources": .object([:]),
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
        let resultValue: JSONValue
        do {
            resultValue = try tool.invoke(arguments, store)
        } catch let rpcError as JSONRPCError {
            // Validation failures (e.g. an unknown UUID or malformed argument)
            // reject the call at the JSON-RPC level rather than returning a result.
            return .failure(rpcError)
        } catch {
            return .failure(JSONRPCError(code: -32603,
                                         message: "Internal error: \(error)",
                                         data: nil))
        }
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

    // MARK: - Resources

    /// MCP `resources/list` enumerates a small set of useful URIs. Per the MCP spec
    /// we expose:
    ///   - one resource per rig (`ephemeris://rig/{uuid}`)
    ///   - the 20 most recent nights (`ephemeris://night/{uuid}`)
    ///   - the help topic catalog (`ephemeris://help/{topic-id}`)
    /// Observations are accessible by URI but not enumerated (too many to be useful
    /// in a list); MCP clients can construct `ephemeris://observation/{uuid}` URIs from
    /// the `id` field returned by `list_observations`.
    private func resourcesList() -> JSONValue {
        var items: [JSONValue] = []
        for r in store.listRigs() {
            items.append(.object([
                "uri": .string("ephemeris://rig/\(r.uuid)"),
                "name": .string("Rig: \(r.currentName)"),
                "mimeType": .string("application/json"),
            ]))
        }
        for n in store.listNights(limit: 20) {
            items.append(.object([
                "uri": .string("ephemeris://night/\(n.uuid)"),
                "name": .string("Night \(ISO8601DateFormatter().string(from: n.nightDate))"),
                "mimeType": .string("application/json"),
            ]))
        }
        for topic in HelpCatalog.all {
            items.append(.object([
                "uri": .string("ephemeris://help/\(topic.id)"),
                "name": .string("Help: \(topic.title)"),
                "mimeType": .string("text/plain"),
            ]))
        }
        return .object(["resources": .array(items)])
    }

    /// MCP `resources/read` resolves an `ephemeris://...` URI to its content. Returns
    /// the standard `{ contents: [{ uri, mimeType, text }] }` shape. Unknown URIs
    /// return an invalid-params error.
    private func handleResourcesRead(params: JSONValue?) -> Result<JSONValue, JSONRPCError> {
        guard let dict = params?.dictValue, let uri = dict["uri"]?.stringValue else {
            return .failure(.invalidParams)
        }
        // Parse ephemeris://<kind>/<id>
        guard let parsed = ResourceURI.parse(uri) else {
            return .failure(JSONRPCError(code: -32602, message: "Invalid URI: \(uri)", data: nil))
        }

        let payload: JSONValue?
        let mime: String
        switch parsed.kind {
        case "rig":
            if let r = store.rig(uuid: parsed.id) {
                payload = Tools.rigJSON(r)
                mime = "application/json"
            } else { return .failure(.notFound(uri)) }
        case "night":
            if let n = store.night(uuid: parsed.id) {
                payload = Tools.nightJSON(n)
                mime = "application/json"
            } else { return .failure(.notFound(uri)) }
        case "observation":
            if let o = store.observation(uuid: parsed.id) {
                payload = Tools.observationJSON(o)
                mime = "application/json"
            } else { return .failure(.notFound(uri)) }
        case "help":
            if let topic = HelpCatalog.topic(id: parsed.id) {
                payload = .string("\(topic.title)\n\n\(topic.summary)")
                mime = "text/plain"
            } else { return .failure(.notFound(uri)) }
        default:
            return .failure(JSONRPCError(code: -32602, message: "Unknown resource kind: \(parsed.kind)", data: nil))
        }

        let text: String
        if let payload {
            if case .string(let s) = payload {
                text = s
            } else {
                text = JSONFormatter.toPrettyString(payload)
            }
        } else {
            text = ""
        }
        return .success(.object([
            "contents": .array([
                .object([
                    "uri": .string(uri),
                    "mimeType": .string(mime),
                    "text": .string(text),
                ])
            ])
        ]))
    }
}

/// `ephemeris://<kind>/<id>` URI parser.
private enum ResourceURI {
    struct Parsed: Sendable { let kind: String; let id: String }
    static func parse(_ uri: String) -> Parsed? {
        let scheme = "ephemeris://"
        guard uri.hasPrefix(scheme) else { return nil }
        let rest = String(uri.dropFirst(scheme.count))
        let parts = rest.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return Parsed(kind: String(parts[0]), id: String(parts[1]))
    }
}

extension JSONRPCError {
    static func notFound(_ uri: String) -> JSONRPCError {
        JSONRPCError(code: -32602, message: "Resource not found: \(uri)", data: nil)
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
