import Testing
import Foundation
import SwiftData
@testable import Ephemeris

// MARK: - HTTP request parsing

@Suite("MCP HTTP request parsing")
struct MCPHTTPRequestParseTests {

    private let cap = MCPConnectionHandler.maxRequestBytes

    private func parse(_ raw: String) -> HTTPRequest.ParseOutcome {
        HTTPRequest.parse(Data(raw.utf8), maxBytes: cap)
    }

    private func request(_ outcome: HTTPRequest.ParseOutcome) -> HTTPRequest? {
        if case .request(let r) = outcome { return r }
        return nil
    }

    private func isInvalid(_ outcome: HTTPRequest.ParseOutcome) -> Bool {
        if case .invalid = outcome { return true }
        return false
    }

    private func isIncomplete(_ outcome: HTTPRequest.ParseOutcome) -> Bool {
        if case .incomplete = outcome { return true }
        return false
    }

    @Test func completePostParses() throws {
        let outcome = parse("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nContent-Length: 2\r\n\r\n{}")
        let req = try #require(request(outcome))
        #expect(req.method == "POST")
        #expect(req.path == "/mcp")
        #expect(req.headers["host"] == "127.0.0.1:8080")
        #expect(req.body == Data("{}".utf8))
    }

    @Test func missingContentLengthMeansEmptyBody() throws {
        let outcome = parse("GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let req = try #require(request(outcome))
        #expect(req.body.isEmpty)
    }

    @Test func headersNotYetTerminatedIsIncomplete() {
        #expect(isIncomplete(parse("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\n")))
    }

    @Test func partialBodyIsIncomplete() {
        #expect(isIncomplete(parse("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 10\r\n\r\n{}")))
    }

    /// Regression: a negative Content-Length previously produced an inverted
    /// subdata range and crashed the app. It must be rejected, not buffered.
    @Test func negativeContentLengthIsInvalid() {
        #expect(isInvalid(parse("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: -5\r\n\r\n{}")))
    }

    @Test func nonNumericContentLengthIsInvalid() {
        #expect(isInvalid(parse("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: banana\r\n\r\n{}")))
    }

    /// Regression: a huge declared Content-Length previously made the connection
    /// buffer without bound waiting for a body that never arrives.
    @Test func oversizedContentLengthIsInvalid() {
        let declared = cap + 1
        #expect(isInvalid(parse("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: \(declared)\r\n\r\n")))
    }

    @Test func contentLengthAtCapBoundaryIsNotRejectedForSize() {
        // Headers + declared body fit exactly within the cap: parse should wait for
        // the body (incomplete), not reject it.
        let head = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 100\r\n\r\n"
        let outcome = HTTPRequest.parse(Data(head.utf8), maxBytes: head.utf8.count + 100)
        #expect(isIncomplete(outcome))
    }

    @Test func garbageRequestLineIsInvalid() {
        #expect(isInvalid(parse("GARBAGE\r\n\r\n")))
    }

    /// The parser reads bodies by Content-Length only; a chunked request would
    /// be misread as empty-bodied, so it must be rejected outright.
    @Test func transferEncodingIsInvalid() {
        #expect(isInvalid(parse("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\n\r\n")))
    }
}

// MARK: - Content negotiation gates

@Suite("MCP HTTP content gates")
struct MCPContentGateTests {

    @Test func jsonContentTypeAccepted() {
        #expect(MCPConnectionHandler.isJSONContentType("application/json"))
        #expect(MCPConnectionHandler.isJSONContentType("application/json; charset=utf-8"))
        #expect(MCPConnectionHandler.isJSONContentType("Application/JSON"))
    }

    /// text/plain is the browser CSRF "simple request" content type — the
    /// whole reason the gate exists. Absent is also rejected: the spec
    /// requires clients to send Content-Type on POST.
    @Test func nonJSONContentTypeRejected() {
        #expect(!MCPConnectionHandler.isJSONContentType("text/plain"))
        #expect(!MCPConnectionHandler.isJSONContentType("text/plain;charset=UTF-8"))
        #expect(!MCPConnectionHandler.isJSONContentType(nil))
    }

    @Test func acceptHeaderPermissive() {
        #expect(MCPConnectionHandler.isAcceptableAccept(nil))
        #expect(MCPConnectionHandler.isAcceptableAccept("application/json, text/event-stream"))
        #expect(MCPConnectionHandler.isAcceptableAccept("*/*"))
        #expect(!MCPConnectionHandler.isAcceptableAccept("text/html"))
    }

    @Test func protocolVersionHeaderValidated() {
        #expect(MCPConnectionHandler.isSupportedProtocolVersionHeader(nil))
        #expect(MCPConnectionHandler.isSupportedProtocolVersionHeader("2025-06-18"))
        #expect(MCPConnectionHandler.isSupportedProtocolVersionHeader("2024-11-05"))
        #expect(!MCPConnectionHandler.isSupportedProtocolVersionHeader("1999-01-01"))
    }

    @Test func hostCheckIsCaseInsensitiveAndTolerant() {
        #expect(MCPConnectionHandler.isLoopbackHost("LOCALHOST"))
        #expect(MCPConnectionHandler.isLoopbackHost("localhost."))
        #expect(!MCPConnectionHandler.isLoopbackHost("localhost.evil.com"))
    }
}

// MARK: - Loopback Host gate (DNS-rebinding defense)

@Suite("MCP loopback host check")
struct MCPLoopbackHostTests {

    @Test(arguments: [
        "127.0.0.1",
        "127.0.0.1:8080",
        "localhost",
        "localhost:12345",
        "[::1]:9000",
    ])
    func loopbackHostsAccepted(header: String) {
        #expect(MCPConnectionHandler.isLoopbackHost(header))
    }

    @Test(arguments: [
        "evil.example.com",
        "evil.example.com:80",
        "192.168.1.20:8080",
        "[2001:db8::1]:80",
        "127.0.0.1.evil.com",
        "",
    ])
    func nonLoopbackHostsRejected(header: String) {
        #expect(!MCPConnectionHandler.isLoopbackHost(header))
    }

    @Test func missingHostRejected() {
        #expect(!MCPConnectionHandler.isLoopbackHost(nil))
    }
}

// MARK: - JSON-RPC protocol handler

@Suite("MCP protocol handler")
@MainActor
struct MCPProtocolHandlerTests {

    private func makeHandler() throws -> MCPProtocolHandler {
        MCPProtocolHandler(library: try EphemerisLibrary(inMemory: true))
    }

    private func call(_ handler: MCPProtocolHandler, _ json: String) throws -> [String: Any]? {
        guard let data = handler.handle(requestData: Data(json.utf8)) else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @Test func initializeReturnsServerInfo() throws {
        let handler = try makeHandler()
        let response = try #require(try call(handler, #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#))
        let result = try #require(response["result"] as? [String: Any])
        let serverInfo = try #require(result["serverInfo"] as? [String: Any])
        #expect(serverInfo["name"] as? String == "ephemeris")
    }

    /// Version negotiation: echo a supported requested version; answer with the
    /// latest for unsupported or absent ones.
    @Test func initializeNegotiatesProtocolVersion() throws {
        let handler = try makeHandler()

        let echoed = try #require(try call(handler,
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}"#))
        let echoedResult = try #require(echoed["result"] as? [String: Any])
        #expect(echoedResult["protocolVersion"] as? String == "2024-11-05")

        let fallback = try #require(try call(handler,
            #"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#))
        let fallbackResult = try #require(fallback["result"] as? [String: Any])
        #expect(fallbackResult["protocolVersion"] as? String == MCPProtocolHandler.latestProtocolVersion)
    }

    /// Valid JSON with the wrong JSON-RPC shape is -32600 Invalid Request, not
    /// -32700 Parse Error — the two were previously conflated.
    @Test func wrongShapeIsInvalidRequestNotParseError() throws {
        let handler = try makeHandler()
        let noMethod = try #require(try call(handler, #"{"jsonrpc":"2.0","id":1}"#))
        #expect((noMethod["error"] as? [String: Any])?["code"] as? Int == -32600)

        let wrongVersion = try #require(try call(handler, #"{"jsonrpc":"1.0","id":1,"method":"ping"}"#))
        #expect((wrongVersion["error"] as? [String: Any])?["code"] as? Int == -32600)
    }

    /// 2025-03-26 batch: an array of requests gets an array of responses;
    /// an all-notifications batch gets no body.
    @Test func batchRequestsReturnBatchResponses() throws {
        let handler = try makeHandler()
        let data = try #require(handler.handle(requestData: Data(
            #"[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","id":2,"method":"ping"}]"#.utf8)))
        let responses = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(responses.count == 2)

        let silent = handler.handle(requestData: Data(
            #"[{"jsonrpc":"2.0","method":"notifications/initialized"}]"#.utf8))
        #expect(silent == nil)
    }

    /// Every embedded tool is read-only and must say so in spec vocabulary.
    @Test func toolsListCarriesReadOnlyAnnotations() throws {
        let handler = try makeHandler()
        let response = try #require(try call(handler, #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#))
        let result = try #require(response["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        for tool in tools {
            let annotations = try #require(tool["annotations"] as? [String: Any])
            #expect(annotations["readOnlyHint"] as? Bool == true)
        }
    }

    /// Parity tripwire: the standalone helper pins this same five-tool subset in
    /// tools/ephemeris-mcp (CatalogTests.catalogContainsTheEmbeddedServerSubset).
    /// Changing either catalog without the other fails one of the two tests,
    /// forcing a deliberate parity decision.
    @Test func toolsListReturnsFullCatalog() throws {
        let handler = try makeHandler()
        let response = try #require(try call(handler, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let result = try #require(response["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })
        #expect(names == ["list_rigs", "list_nights", "list_observations",
                          "get_aggregate_stats", "get_corpus_summary"])
    }

    /// The embedded catalog is read-only by design; see the helper-side
    /// CatalogTests for the same invariant on the stdio server.
    @Test func embeddedCatalogIsStrictlyReadOnly() {
        #expect(!MCPTools.all.contains { $0.name == "add_annotation" })
        let writeVerbs = ["add", "create", "write", "update", "delete", "remove", "set_"]
        for tool in MCPTools.all {
            for verb in writeVerbs {
                #expect(!tool.name.hasPrefix(verb),
                        "tool \(tool.name) looks like a write tool in a read-only catalog")
            }
        }
    }

    @Test func unknownMethodReturnsMethodNotFound() throws {
        let handler = try makeHandler()
        let response = try #require(try call(handler, #"{"jsonrpc":"2.0","id":3,"method":"bogus/method"}"#))
        let error = try #require(response["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32601)
    }

    @Test func malformedJSONReturnsParseError() throws {
        let handler = try makeHandler()
        let response = try #require(try call(handler, "not json at all"))
        let error = try #require(response["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32700)
    }

    @Test func notificationReturnsNoBody() throws {
        let handler = try makeHandler()
        let data = handler.handle(requestData: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
        #expect(data == nil)
    }

    @Test func unknownToolReturnsError() throws {
        let handler = try makeHandler()
        let response = try #require(try call(
            handler,
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"delete_everything","arguments":{}}}"#))
        let error = try #require(response["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32601)
    }

    @Test func listRigsSucceedsOnEmptyLibrary() throws {
        let handler = try makeHandler()
        let response = try #require(try call(
            handler,
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"list_rigs","arguments":{}}}"#))
        let result = try #require(response["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content.first?["type"] as? String == "text")
    }
}
