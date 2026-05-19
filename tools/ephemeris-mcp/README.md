# Ephemeris MCP Server

A stdio MCP (Model Context Protocol) server that exposes the Ephemeris library to Claude Desktop, Claude Code, or any conformant MCP client. Per the [v2.0 design doc §5.4](../../docs/ephemeris-2.0-design-document.md), this is the agentic surface — the answer to *"can I just talk to Claude about my data instead of reading observation cards?"*

The server reads the SwiftData library store directly via SQLite — no SwiftData dependency, no app dependency. It's a self-contained CLI binary.

## Build

```sh
cd tools/ephemeris-mcp
swift build -c release
```

The binary lands at `.build/release/ephemeris-mcp`.

## Configure Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "ephemeris": {
      "command": "/absolute/path/to/PHD2-Log-Viewer/tools/ephemeris-mcp/.build/release/ephemeris-mcp"
    }
  }
}
```

Restart Claude Desktop. The Ephemeris tools should appear in the MCP menu.

## Configure Claude Code

Add to `~/.claude.json` (or the project-local `.claude/mcp_servers.json`):

```json
{
  "mcpServers": {
    "ephemeris": {
      "command": "/absolute/path/to/PHD2-Log-Viewer/tools/ephemeris-mcp/.build/release/ephemeris-mcp"
    }
  }
}
```

## Tools

| Tool | What it does |
|---|---|
| `get_corpus_summary` | High-level inventory — rigs, total nights, total observations, date range. Useful first call. |
| `list_rigs` | All rig profiles with mount class, imaging-train values, computed pixel scale. |
| `list_nights` | Per-night rollups (median RMS, integration time, sessions). Filterable by rig and recency. |
| `list_observations` | Recommender observations with severity, source authority, summary, suggested response. |
| `get_aggregate_stats` | Median / p75 / p90 RMS across a rig's nights — for "is my rig getting better or worse?" questions. |

Each observation carries a `source_authority` field that distinguishes PHD2-canon advice (`phd2Manual`, `phd2Measurement`, `phd2BehaviorDocumented`) from community consensus (`communityConsensus`) and Ephemeris heuristics (`ephemerisHeuristic`). Throughline #4 — *reference PHD2 tools by name and use PHD2's measured numbers* — survives the protocol boundary.

## Smoke test

```sh
printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | .build/debug/ephemeris-mcp
```

You should see two JSON-RPC responses on stdout (and diagnostic lines on stderr).

## Privacy

The server speaks stdio only — no outbound network. It reads the local SQLite store in read-only mode (`SQLITE_OPEN_READONLY`). The Ephemeris app retains exclusive write access; the MCP server is a passive reader.

## Notes

- The Ephemeris app must have been run at least once to create the library store. Until you open a PHD2 log in the app, the store is empty and the tools return empty arrays.
- Concurrent access is safe — SwiftData configures SQLite WAL mode, so the app's writes don't block the helper's reads.
- This is the Phase 8 initial ship. Resources (`ephemeris://rig/{id}`, `ephemeris://night/{id}`) and write tools (`add_annotation`) are deferred.
