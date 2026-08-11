/// MCP over FoundationModels (Stage 1 server + Stage 2 client).
///
/// - **Server** (DES-0004): stdio NDJSON — expose FM to Cursor/Claude.
/// - **Client** (DES-0005): consume remote MCP (e.g. UAB over SSE) as [FmTool]s.
///
/// Not matrix parity. Not a replacement for `foundationmodels_agent`.
library;

export 'src/mcp_client.dart';
export 'src/mcp_server.dart';
export 'src/mcp_transport.dart';
export 'src/mcp_types.dart';
