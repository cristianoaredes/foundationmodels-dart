# foundationmodels_mcp

Minimal **MCP server** (stdio / NDJSON JSON-RPC) over `FoundationModels`.

- Spec: DES-0004  
- Built-in tool: `fm_respond` → `FoundationModels.respond`  
- Extra `FmTool.callback` tools supported  
- **Not** a replacement for `foundationmodels_agent`  
- **Not** Apple matrix parity  

```dart
final fm = await createFoundationModels();
final mcp = FmMcpServer(fm: fm);
await mcp.serve(input: stdin, output: stdout.add);
```

`publish_to: none` (ADR-0002).


## Client (DES-0005 / UAB)

```dart
// Loopback CI:
final server = FmMcpServer(fm: fm);
final client = FmMcpClient(transport: McpLoopbackTransport(server.handleMessage));
await client.initialize();
final tools = await client.listToolsAsFmTools(); // → List<FmTool>

// Remote UAB (SSE/JSON-RPC):
final transport = McpSseTransport(
  rpcUrl: Uri.parse('https://uab.example/mcp'),
  sseUrl: Uri.parse('https://uab.example/sse'), // optional
  headers: {'Authorization': 'Bearer …'},
  httpPost: yourPost,
);
```

**Security:** never paste tool results into session `instructions`.
