import Foundation
import Network
import SwiftData
import Observation

/// Embedded MCP server. Listens on localhost over HTTP and handles JSON-RPC requests
/// per the MCP Streamable HTTP transport (POST → JSON response, synchronous).
///
/// Per design doc §5.4 + the embedded-MCP feedback memory: the app hosts the server
/// itself rather than shipping a separate stdio binary. Clients (Claude Desktop,
/// Claude Code, any conformant MCP client) connect via http://127.0.0.1:PORT/mcp.
///
/// Network: 127.0.0.1 only (no external interfaces). Requires
/// `com.apple.security.network.server` entitlement.
@Observable
@MainActor
final class MCPEmbeddedServer {
    enum Status: Equatable {
        case stopped
        case starting
        case running(port: UInt16)
        case failed(String)
    }

    var status: Status = .stopped
    var requestCount: Int = 0
    var lastConnectionAt: Date?

    /// The library container the server reads from. Same one the app uses, so writes
    /// from the app are immediately visible to tool calls.
    private let library: EphemerisLibrary
    private var listener: NWListener?
    /// Persisted across launches so the user doesn't have to update their MCP client
    /// config when the app restarts.
    @ObservationIgnored
    @UserDefault("mcp.preferredPort", defaultValue: 0)
    private var preferredPort: Int

    init(library: EphemerisLibrary) {
        self.library = library
    }

    /// URL clients should connect to. Returns nil until the server is running.
    var connectionURL: URL? {
        guard case .running(let port) = status else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/mcp")
    }

    func start() {
        guard listener == nil else { return }
        status = .starting

        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.requiredInterfaceType = .loopback

        let portValue: NWEndpoint.Port? = preferredPort > 0
            ? NWEndpoint.Port(rawValue: UInt16(preferredPort))
            : nil

        do {
            let listener = try NWListener(using: parameters, on: portValue ?? .any)
            self.listener = listener

            listener.stateUpdateHandler = { state in
                Task { @MainActor [weak self, listener] in
                    self?.handleListenerState(state, listener: listener)
                }
            }
            listener.newConnectionHandler = { connection in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(connection)
                }
            }

            listener.start(queue: .global(qos: .userInitiated))
        } catch {
            status = .failed("\(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        status = .stopped
    }

    func restart() {
        stop()
        // Give the OS a moment to release the port if we were holding it
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            start()
        }
    }

    private func handleListenerState(_ state: NWListener.State, listener: NWListener) {
        switch state {
        case .ready:
            let port = listener.port?.rawValue ?? 0
            status = .running(port: port)
            preferredPort = Int(port)
        case .failed(let error):
            status = .failed("\(error)")
            self.listener = nil
        case .cancelled:
            if status != .stopped { status = .stopped }
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        requestCount += 1
        lastConnectionAt = .now
        let handler = MCPConnectionHandler(library: library)
        connection.start(queue: .global(qos: .userInitiated))
        handler.handle(connection: connection)
    }
}

// MARK: - UserDefault property wrapper

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T

    init(_ key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var wrappedValue: T {
        get { (UserDefaults.standard.object(forKey: key) as? T) ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
