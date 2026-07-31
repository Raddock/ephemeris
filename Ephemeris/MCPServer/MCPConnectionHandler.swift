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
    /// Upper bound on a whole request (request line + headers + body). JSON-RPC tool
    /// calls are a few hundred bytes; anything near this size is not a legitimate
    /// client. The cap is what stops a hostile local process from growing the
    /// receive buffer without bound via a huge (or absent) Content-Length.
    static let maxRequestBytes = 1_048_576

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

            switch HTTPRequest.parse(current, maxBytes: Self.maxRequestBytes) {
            case .request(let request):
                self.respond(to: request, on: connection)
            case .invalid:
                self.send(connection: connection, statusCode: 400, body: Data("bad request\n".utf8), contentType: "text/plain")
            case .incomplete where current.count > Self.maxRequestBytes:
                self.send(connection: connection, statusCode: 413, body: Data("request too large\n".utf8), contentType: "text/plain")
            case .incomplete:
                if isComplete {
                    connection.cancel()
                } else {
                    self.receive(connection: connection, buffer: current)
                }
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        // The listener is loopback-bound, so a non-loopback Host header means the
        // request reached us via DNS rebinding from a browser — reject it before
        // touching the library. Legitimate MCP clients connect straight to
        // 127.0.0.1 / localhost and send a matching Host.
        guard Self.isLoopbackHost(request.headers["host"]) else {
            send(connection: connection, statusCode: 403, body: Data("forbidden\n".utf8), contentType: "text/plain")
            return
        }
        // An Origin header means a browser sent this. No legitimate MCP client
        // is a browser page — the Streamable HTTP spec requires Origin
        // validation precisely because CORS "simple" POSTs reach localhost
        // servers even when the response is unreadable cross-origin. The Host
        // check above can't catch these (the browser sends a loopback Host).
        guard request.headers["origin"] == nil else {
            send(connection: connection, statusCode: 403, body: Data("forbidden\n".utf8), contentType: "text/plain")
            return
        }
        switch (request.method, request.path) {
        case ("POST", "/mcp"), ("POST", "/"):
            handleMCPPost(request: request, on: connection)
        case ("GET", "/mcp"):
            // Spec: the MCP endpoint answers GET with an SSE stream or 405.
            // This server is synchronous-only, so 405 — a 404 here would read
            // as "wrong URL" to clients probing for stream support.
            send(connection: connection, statusCode: 405, body: Data("method not allowed\n".utf8),
                 contentType: "text/plain", extraHeaders: ["Allow": "POST"])
        case ("GET", "/"), ("GET", "/health"):
            send(connection: connection, statusCode: 200, body: Data("ephemeris-mcp running\n".utf8), contentType: "text/plain")
        default:
            send(connection: connection, statusCode: 404, body: Data("not found\n".utf8), contentType: "text/plain")
        }
    }

    /// True when the HTTP `Host` header names a loopback address. Strips the port
    /// and any IPv6 brackets; DNS names are case-insensitive and may carry a
    /// trailing dot. A missing Host is treated as untrusted — HTTP/1.1 clients
    /// are required to send one. Static so tests can exercise it directly.
    static func isLoopbackHost(_ hostHeader: String?) -> Bool {
        guard let hostHeader, !hostHeader.isEmpty else { return false }
        var host: String
        if hostHeader.hasPrefix("[") {
            host = String(hostHeader.dropFirst().prefix { $0 != "]" })
        } else {
            host = String(hostHeader.prefix { $0 != ":" })
        }
        host = host.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    /// POST /mcp content-negotiation gates, split out for testability.
    /// Content-Type must be JSON (the spec requires clients to send it, and the
    /// requirement is also what blocks browser `text/plain` CSRF bodies).
    static func isJSONContentType(_ header: String?) -> Bool {
        guard let header else { return false }
        return header.split(separator: ";")[0].trimmingCharacters(in: .whitespaces).lowercased() == "application/json"
    }

    /// Accept is permissive: absent is fine (curl-style clients), and any of
    /// application/json, text/event-stream, or */* passes. Only an Accept that
    /// excludes JSON outright is rejected.
    static func isAcceptableAccept(_ header: String?) -> Bool {
        guard let header else { return true }
        let types = header.split(separator: ",").map {
            $0.split(separator: ";")[0].trimmingCharacters(in: .whitespaces).lowercased()
        }
        return types.contains("application/json") || types.contains("text/event-stream")
            || types.contains("*/*") || types.contains("application/*")
    }

    /// `MCP-Protocol-Version` (required from clients since 2025-06-18): absent
    /// falls back per spec; present-but-unsupported gets 400.
    static func isSupportedProtocolVersionHeader(_ header: String?) -> Bool {
        guard let header else { return true }
        return MCPProtocolHandler.supportedProtocolVersions.contains(header.trimmingCharacters(in: .whitespaces))
    }

    private func handleMCPPost(request: HTTPRequest, on connection: NWConnection) {
        guard Self.isJSONContentType(request.headers["content-type"]) else {
            send(connection: connection, statusCode: 415, body: Data("unsupported media type\n".utf8), contentType: "text/plain")
            return
        }
        guard Self.isAcceptableAccept(request.headers["accept"]) else {
            send(connection: connection, statusCode: 406, body: Data("not acceptable\n".utf8), contentType: "text/plain")
            return
        }
        guard Self.isSupportedProtocolVersionHeader(request.headers["mcp-protocol-version"]) else {
            send(connection: connection, statusCode: 400, body: Data("unsupported MCP-Protocol-Version\n".utf8), contentType: "text/plain")
            return
        }
        // Synchronously dispatch the JSON-RPC payload. The protocol handler runs on
        // a non-main actor; we trampoline into the MainActor for the SwiftData reads.
        Task { @MainActor in
            let protocolHandler = MCPProtocolHandler(library: library)
            let responseData = protocolHandler.handle(requestData: request.body)
            if let responseData {
                send(connection: connection, statusCode: 200, body: responseData, contentType: "application/json")
            } else {
                // Notification-only payload — spec: 202 Accepted, no body.
                send(connection: connection, statusCode: 202, body: Data(), contentType: "application/json")
            }
        }
    }

    private func send(connection: NWConnection,
                      statusCode: Int,
                      body: Data,
                      contentType: String,
                      extraHeaders: [String: String] = [:]) {
        var response = "HTTP/1.1 \(statusCode) \(statusText(statusCode))\r\n"
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(body.count)\r\n"
        for (key, value) in extraHeaders {
            response += "\(key): \(value)\r\n"
        }
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
        case 202: return "Accepted"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 406: return "Not Acceptable"
        case 413: return "Content Too Large"
        case 415: return "Unsupported Media Type"
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

    /// Three-way outcome so the connection loop can tell "keep reading" apart from
    /// "reject and close". A plain optional conflated the two, which meant a
    /// malformed Content-Length kept the connection buffering forever (or, for a
    /// negative value, crashed on an inverted range).
    enum ParseOutcome {
        case incomplete
        case invalid
        case request(HTTPRequest)
    }

    static func parse(_ data: Data, maxBytes: Int) -> ParseOutcome {
        // Find the \r\n\r\n boundary between headers and body
        guard let separatorRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return .incomplete   // headers not complete yet
        }
        let headerData = data.subdata(in: 0..<separatorRange.lowerBound)
        let bodyStart = separatorRange.upperBound

        guard let headerString = String(data: headerData, encoding: .utf8) else { return .invalid }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .invalid }

        let parts = requestLine.split(separator: " ").map { String($0) }
        guard parts.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            if let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[..<colonIdx]).lowercased()
                let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // This parser reads bodies by Content-Length only. A chunked request
        // would be silently misread as empty-bodied, so reject it outright.
        guard headers["transfer-encoding"] == nil else { return .invalid }

        // Content-Length must be a nonnegative integer within the request cap.
        // Anything else is a hostile or broken client, not an incomplete read.
        let contentLength: Int
        if let rawLength = headers["content-length"] {
            guard let parsed = Int(rawLength), parsed >= 0 else { return .invalid }
            contentLength = parsed
        } else {
            contentLength = 0
        }
        guard bodyStart + contentLength <= maxBytes else { return .invalid }

        let availableBody = data.count - bodyStart
        guard availableBody >= contentLength else { return .incomplete }
        let bodyEnd = bodyStart + contentLength
        let body = data.subdata(in: bodyStart..<bodyEnd)

        return .request(HTTPRequest(method: parts[0], path: parts[1], headers: headers, body: body))
    }
}
