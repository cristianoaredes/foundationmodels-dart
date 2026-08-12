# foundationmodels_mcp

MCP (Model Context Protocol) surfaces over [`foundationmodels`](../foundationmodels):

| Role | Spec | Types |
|------|------|--------|
| **Server** | [DES-0004](../../.archagents/16-designs/DES-0004-mcp-package.md) | `FmMcpServer` — expose FM to MCP hosts (Cursor/Claude) |
| **Client** | [DES-0005](../../.archagents/16-designs/DES-0005-mcp-client-sse-uab.md) | `FmMcpClient` — consume remote MCP (e.g. UAB) as `FmTool`s |

**Not** a replacement for `foundationmodels_agent` (AG-UI tool loop).  
**Not** Apple matrix parity.  
**`publish_to: none`** (ADR-0002).

---

## Server (stdio / NDJSON)

```dart
import 'dart:io';
import 'package:foundationmodels/foundationmodels.dart';
import 'package:foundationmodels_mcp/foundationmodels_mcp.dart';

final fm = await createFoundationModels(); // mock offline
final mcp = FmMcpServer(fm: fm);
await mcp.serve(input: stdin, output: stdout.add);
```

Handles: `initialize`, `tools/list`, `tools/call`, `ping`, fail-closed unknown methods.  
Built-in tool: **`fm_respond`** → `FoundationModels.respond`.  
Extra tools: `registerTool(FmTool.callback(...))`.

---

## Client (loopback or SSE)

### Loopback (CI / same process)

```dart
final server = FmMcpServer(fm: fm);
final client = FmMcpClient(
  transport: McpLoopbackTransport(server.handleMessage),
);
await client.initialize();
final tools = await client.listToolsAsFmTools(); // List<FmTool>
final text = await client.callTool('fm_respond', {'input': 'hi'});
await client.close();
```

### Remote SSE / Streamable-HTTP (e.g. UAB)

```dart
final transport = McpSseTransport(
  rpcUrl: Uri.parse(Platform.environment['FM_MCP_SSE_URL']!),
  headers: {
    if (Platform.environment['FM_MCP_BEARER'] case final b? when b.isNotEmpty)
      'Authorization': 'Bearer $b',
  },
  httpPost: mcpDefaultHttpPost,
);
final client = FmMcpClient(transport: transport);
await client.initialize();
// …
```

SSE bodies may start with `event: message` then `data: {json}` (Streamable-HTTP / FastMCP).  
`parseSseDataFrames` extracts JSON-RPC maps from chunks.

### Live dual-run (env-gated)

```bash
export FM_MCP_SSE_URL='https://…'   # or UAB_MCP_URL
# optional: export FM_MCP_BEARER='…'
dart test test/mcp_live_env_test.dart
```

If URL unset → test skips with `env_limit=true` (CI safe). Ticket: TCK-0059.

**UAB gotcha — use the trailing slash.** `POST …/mcp` (no trailing slash) 307-redirects to
`…/mcp/`, and the observed `Location` header downgrades the scheme to `http://` (Cloudflare
Access → origin app not honoring `X-Forwarded-Proto`). Dart's `HttpClient` correctly refuses to
follow a same-request scheme downgrade on POST, so the call throws `HttpException: HTTP 307`
instead of silently retrying insecurely. Fix: point `FM_MCP_SSE_URL`/`UAB_MCP_URL` at
`…/mcp/` directly (verified against `uab.orqo.pro`, live dual-run 2026-08-11).

---

## Security

1. Never paste tool results or untrusted MCP content into session **`instructions`**.  
2. No secrets in repo; bearer only via env.  
3. Fail-closed unknown methods / tools.  
4. No silent cloud — use mock FM when Apple unavailable.  

---

## Tests

```bash
cd packages/foundationmodels_mcp
dart analyze --fatal-infos
dart test
```

Coverage: server dual-run, client loopback dual-run, SSE parse, injectable HTTP, Streamable-HTTP body, live env skip/run.

---

## Related tickets

| ID | Topic |
|----|--------|
| TCK-0053 / 0055 | Stage 1 server package + mini-spec |
| TCK-0056…0058 | Client epic + API + SSE transport |
| TCK-0059 | Live env dual-run harness |
