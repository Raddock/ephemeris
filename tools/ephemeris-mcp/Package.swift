// swift-tools-version: 6.0
// Ephemeris MCP server — design doc §5.4 / Phase 8.
//
// Standalone stdio executable that exposes the Ephemeris library to MCP clients
// (Claude Desktop, Claude Code, any conformant MCP client). Reads the SwiftData
// store via raw SQLite — no SwiftData dependency, so the helper stays light and
// the Xcode project isn't touched.

import PackageDescription

let package = Package(
    name: "EphemerisMCP",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ephemeris-mcp", targets: ["EphemerisMCP"]),
    ],
    targets: [
        .executableTarget(
            name: "EphemerisMCP",
            // No external dependencies — Foundation + sqlite3 only.
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        // Test target removed for the initial Phase 8 ship — tests would require
        // refactoring main into a library target. The MCP protocol is exercised
        // end-to-end via the smoke-test script in this package's README.
    ]
)
