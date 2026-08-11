/// Built-in MCP tool that maps to [FoundationModels.respond].
const String kFmRespondToolName = 'fm_respond';

/// Result of handling one JSON-RPC request (response map or null for notifications).
typedef McpJson = Map<String, Object?>;
