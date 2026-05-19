import Foundation

/// Ephemeris MCP server entry point.
/// Reads JSON-RPC 2.0 requests from stdin, writes responses to stdout per MCP stdio transport.
/// Diagnostics go to stderr so they don't corrupt the JSON-RPC stream.
@main
struct EphemerisMCPMain {
    static func main() {
        let storeURL = LibraryStore.defaultStoreURL()
        FileHandle.standardError.write(
            "Ephemeris MCP server starting · store: \(storeURL.path)\n".data(using: .utf8)!
        )

        // The MCP stdio loop is synchronous — read a line of JSON, dispatch, write a line.
        // Notifications (no id) get no response. Requests (with id) get one.
        let store = LibraryStore(url: storeURL)
        let server = MCPServer(store: store)

        let stdin = FileHandle.standardInput
        let stdout = FileHandle.standardOutput

        // Read lines one at a time. JSON-RPC framing per MCP stdio transport is "one JSON
        // object per line, terminated by \n".
        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }
            if let responseData = server.handle(requestData: data) {
                stdout.write(responseData)
                stdout.write(Data([0x0A]))  // newline
            }
        }
        _ = stdin
        FileHandle.standardError.write("Ephemeris MCP server exiting.\n".data(using: .utf8)!)
    }
}
