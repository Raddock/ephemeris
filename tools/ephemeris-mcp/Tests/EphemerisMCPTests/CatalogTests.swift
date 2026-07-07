import Testing
import Foundation
@testable import EphemerisMCP

/// Catalog contract tests. Two invariants matter:
///
/// 1. **Read-only.** This helper reads the app's SwiftData SQLite store
///    out-of-process; an external writer on a live Core Data store is coherence
///    Apple does not guarantee. No tool may write, and the removed
///    EPHEMERIS_MCP_ALLOW_WRITES gate must never grow back.
/// 2. **Parity with the embedded server.** The app's embedded HTTP server
///    exposes a five-tool summary subset that must exist here under the same
///    names. The embedded side pins the same list in EphemerisTests
///    (MCPServerTests.toolsListReturnsFullCatalog) — change one and the other
///    test fails, forcing a deliberate parity decision.
@Suite("MCP helper catalog")
struct CatalogTests {

    /// The summary tools both servers must expose under identical names.
    private static let sharedWithEmbeddedServer: Set<String> = [
        "list_rigs", "list_nights", "list_observations",
        "get_aggregate_stats", "get_corpus_summary",
    ]

    @Test func catalogContainsTheEmbeddedServerSubset() {
        let names = Set(Tools.all.map(\.name))
        #expect(Self.sharedWithEmbeddedServer.isSubset(of: names))
    }

    @Test func catalogIsStrictlyReadOnly() {
        let writeVerbs = ["add", "create", "write", "update", "delete", "remove", "set_"]
        for tool in Tools.all {
            for verb in writeVerbs {
                #expect(!tool.name.hasPrefix(verb),
                        "tool \(tool.name) looks like a write tool in a read-only catalog")
            }
        }
        #expect(!Tools.all.contains { $0.name == "add_annotation" })
    }

    @Test func allowWritesEnvironmentVariableHasNoEffect() {
        // The gate was removed; the catalog is static regardless of environment.
        // This test documents that setting EPHEMERIS_MCP_ALLOW_WRITES=1 in a
        // connector config is inert, not a hidden write switch.
        let names = Set(Tools.all.map(\.name))
        #expect(names.count == 13)
        #expect(!names.contains("add_annotation"))
    }

    @Test func toolNamesAreUniqueAndSnakeCase() {
        let names = Tools.all.map(\.name)
        #expect(Set(names).count == names.count)
        for name in names {
            #expect(name.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression) != nil,
                    "tool name \(name) is not snake_case")
        }
    }
}
