import Foundation
import Network
import SwiftData

/// Per-connection HTTP/1.1 handler. Reads one request, dispatches the JSON-RPC body
/// to the protocol handler, writes the response, closes the connection.
///
/// Implements just enough HTTP to accept POSTs from MCP clients. No keep-alive, no
/// chunked encoding, no compression — clients send a single JSON body, get one JSON
/// response. CORS preflight handled for browser-based MCP clients (rare but cheap).
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
        switch (request.method, request.path) {
        case ("POST", "/mcp"), ("POST", "/"):
            handleMCPPost(request: request, on: connection)
        case ("OPTIONS", _):
            sendCORSPreflight(on: connection)
        case ("GET", "/"), ("GET", "/health"):
            send(connection: connection, statusCode: 200, body: Data("ephemeris-mcp running\n".utf8), contentType: "text/plain")
        default:
            send(connection: connection, statusCode: 404, body: Data("not found\n".utf8), contentType: "text/plain")
        }
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

    private func sendCORSPreflight(on connection: NWConnection) {
        let headers = [
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type, Authorization",
            "Access-Control-Max-Age: 86400",
        ]
        send(connection: connection, statusCode: 204, body: Data(), contentType: "text/plain", extraHeaders: headers)
    }

    private func send(connection: NWConnection,
                      statusCode: Int,
                      body: Data,
                      contentType: String,
                      extraHeaders: [String] = []) {
        var response = "HTTP/1.1 \(statusCode) \(statusText(statusCode))\r\n"
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n"
        response += "Access-Control-Allow-Origin: *\r\n"
        for header in extraHeaders {
            response += "\(header)\r\n"
        }
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
