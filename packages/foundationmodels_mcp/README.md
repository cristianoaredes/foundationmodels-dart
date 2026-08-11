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
