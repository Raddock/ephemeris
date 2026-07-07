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

    @Test func toolsListReturnsFullCatalog() throws {
        let handler = try makeHandler()
        let response = try #require(try call(handler, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let result = try #require(response["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })
        #expect(names == ["list_rigs", "list_nights", "list_observations",
                          "get_aggregate_stats", "get_corpus_summary"])
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
