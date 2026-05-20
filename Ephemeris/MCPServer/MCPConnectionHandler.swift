import Foundation
import Network
import SwiftData

/// Per-connection HTTP/1.1 handler. Reads one request, dispatches the JSON-RPC body
/// to the protocol handler, writes the response, closes the connection.
///
/// Implements just enough HTTP to accept POSTs from MCP clients. No keep-alive, no
/// chunked encoding, no compression — clients send a single JSON body, get one JSON
/// response.
///
/// Hardening: the listener is loopback-bound, but a browser page the user visits
/// could still reach it via DNS rebinding. We validate the `Host` header is a
/// loopback name and emit no CORS headers, so browser-origin requests can neither
/// be routed here under a foreign hostname nor read any response cross-origin.
final class MCPConnectionHandler: @unchecked Sendable {
    let library: EphemerisLibrary
    init(library: EphemerisLibrary) {
        self.library = library
    }

    func handle(connection: NWConnection) {
        receive(connection: connection, buffer: Data())
    }

    private func receive(connection: NWConnection, buffer: Data) {
        // Strong self capture so the handler stays alive until the connection finishes.
        // Each MCPConnectionHandler is exactly one connection's lifecycle; the strong
        // reference releases when the send completion fires and connection.cancel() runs.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            if error != nil {
                connection.cancel()
                return
            }
            var current = buffer
            if let data = data {
                current.append(data)
            }

            if let request = HTTPRequest.parse(current) {
                self.respond(to: request, on: connection)
            } else if isComplete {
                connection.cancel()
            } else {
                self.receive(connection: connection, buffer: current)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        // The listener is loopback-bound, so a non-loopback Host header means the
        // request reached us via DNS rebinding from a browser — reject it before
        // touching the library. Legitimate MCP clients connect straight to
        // 127.0.0.1 / localhost and send a matching Host.
        guard isLoopbackHost(request.headers["host"]) else {
            send(connection: connection, statusCode: 403, body: Data("forbidden\n".utf8), contentType: "text/plain")
            return
        }
        switch (request.method, request.path) {
        case ("POST", "/mcp"), ("POST", "/"):
            handleMCPPost(request: request, on: connection)
        case ("GET", "/"), ("GET", "/health"):
            send(connection: connection, statusCode: 200, body: Data("ephemeris-mcp running\n".utf8), contentType: "text/plain")
        default:
            send(connection: connection, statusCode: 404, body: Data("not found\n".utf8), contentType: "text/plain")
        }
    }

    /// True when the HTTP `Host` header names a loopback address. Strips the port
    /// and any IPv6 brackets. A missing Host is treated as untrusted — HTTP/1.1
    /// clients are required to send one.
    private func isLoopbackHost(_ hostHeader: String?) -> Bool {
        guard let hostHeader, !hostHeader.isEmpty else { return false }
        let host: String
        if hostHeader.hasPrefix("[") {
            host = String(hostHeader.dropFirst().prefix { $0 != "]" })
        } else {
            host = String(hostHeader.prefix { $0 != ":" })
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func handleMCPPost(request: HTTPRequest, on connection: NWConnection) {
        // Synchronously dispatch the JSON-RPC payload. The protocol handler runs on
        // a non-main actor; we trampoline into the MainActor for the SwiftData reads.
        Task { @MainActor in
            let protocolHandler = MCPProtocolHandler(library: library)
            let responseData = protocolHandler.handle(requestData: request.body)
            if let responseData {
                send(connection: connection, statusCode: 200, body: responseData, contentType: "application/json")
            } else {
                // Notification — no body to return; HTTP 204
                send(connection: connection, statusCode: 204, body: Data(), contentType: "application/json")
            }
        }
    }

    private func send(connection: NWConnection,
                      statusCode: Int,
                      body: Data,
                      contentType: String) {
        var response = "HTTP/1.1 \(statusCode) \(statusText(statusCode))\r\n"
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"
        var responseData = Data(response.utf8)
        responseData.append(body)
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default:  return "OK"
        }
    }
}

// MARK: - Minimal HTTP parser

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parse(_ data: Data) -> HTTPRequest? {
        // Find the \r\n\r\n boundary between headers and body
        guard let separatorRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil   // headers not complete yet
        }
        let headerData = data.subdata(in: 0..<separatorRange.lowerBound)
        let bodyStart = separatorRange.upperBound

        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ").map { String($0) }
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            if let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[..<colonIdx]).lowercased()
                let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // Body: require full body before returning the parsed request
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let availableBody = data.count - bodyStart
        guard availableBody >= contentLength else { return nil }
        let bodyEnd = bodyStart + contentLength
        let body = data.subdata(in: bodyStart..<bodyEnd)

        return HTTPRequest(method: parts[0], path: parts[1], headers: headers, body: body)
    }
}
