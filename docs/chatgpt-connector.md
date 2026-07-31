# Using Ephemeris as a ChatGPT MCP connector

ChatGPT's custom connectors (Developer Mode) and deep-research connectors can
only reach MCP servers on **public HTTPS URLs**. They never connect to
`localhost`, never launch stdio binaries, and cannot see servers behind a VPN
or private network. Ephemeris's embedded MCP server listens on
`http://127.0.0.1:PORT/mcp`, so connecting ChatGPT requires a tunnel that
publishes that port over HTTPS.

Claude Desktop and Claude Code do not need any of this — use the one-click
Connect buttons in the MCP Server window, which wire up the local stdio helper.

## What the embedded server provides for ChatGPT

- **Streamable HTTP transport** with protocol-version negotiation
  (2024-11-05, 2025-03-26, 2025-06-18), batch support, and spec status codes.
- **`search` / `fetch` tools** — the retrieval contract ChatGPT deep research
  requires. `search` matches rig names, target catalog names, night dates, and
  observation text; `fetch` returns the full record for a result id.
- **Five domain tools** (`get_corpus_summary`, `list_rigs`, `list_nights`,
  `list_observations`, `get_aggregate_stats`) usable from Developer-Mode
  conversations.
- **Bearer-token auth** — required by default. Once a tunnel is up, remote
  traffic arrives at the loopback listener like any local client, so the token
  is the only thing standing between the internet and your library. Do not
  disable it while a tunnel is running.

## Recipe (cloudflared quick tunnel)

1. In Ephemeris, open the **MCP Server** window, start the server, and note
   the port in the status line. Under **Advanced**, copy the access token.
2. Install cloudflared: `brew install cloudflared`
3. Start a quick tunnel (replace `PORT`):

   ```sh
   cloudflared tunnel --url http://127.0.0.1:PORT
   ```

   cloudflared prints a `https://<random>.trycloudflare.com` URL. Quick
   tunnels are ephemeral — the URL changes each run. For a stable URL, create
   a named tunnel on a domain you control (`cloudflared tunnel create …`).
4. In ChatGPT: **Settings → Connectors → Advanced → Developer mode** (Plus/Pro,
   or workspace-enabled on Business/Enterprise/Edu), then **Create** a custom
   connector:
   - **URL**: `https://<your-tunnel-host>/mcp`
   - **Authentication**: Custom headers →
     `Authorization: Bearer <your token>`
5. For deep research, the connector's `search`/`fetch` tools are picked up
   automatically.

## Security notes

- The tunnel publishes your guiding library to the internet, gated only by
  the bearer token. Treat the token like a password; **Regenerate** it in the
  MCP Server window if it leaks, and stop the tunnel when you're done.
- The server is read-only by construction (see `annotations.readOnlyHint` on
  every tool) — a leaked token exposes reads, never writes.
- Requests carrying a browser `Origin` header are rejected regardless of
  token, so a hostile web page cannot ride a logged-in browser session.
