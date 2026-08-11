import 'package:foundationmodels/foundationmodels.dart';

import 'mcp_transport.dart';
import 'mcp_types.dart';

/// MCP **client** (DES-0005): initialize → tools/list → tools/call.
///
/// Converts remote tools into [FmTool.callback] for use with
/// [FoundationModels.stream] / [FmAgent].
///
/// **Security:** tool results are returned to the caller; never inject them
/// into session `instructions`.
final class FmMcpClient {
  FmMcpClient({
    required this.transport,
    this.protocolVersion = '2024-11-05',
    this.clientName = 'foundationmodels_mcp_client',
    this.clientVersion = '0.1.0',
  });

  final McpTransport transport;
  final String protocolVersion;
  final String clientName;
  final String clientVersion;

  var _initialized = false;
  var _id = 1;

  /// Whether [initialize] has completed successfully.
  bool get isInitialized => _initialized;

  Object _nextId() => 'c_${_id++}';

  /// MCP initialize handshake.
  Future<McpJson> initialize() async {
    final res = await transport.request(
      'initialize',
      id: _nextId(),
      params: {
        'protocolVersion': protocolVersion,
        'capabilities': <String, Object?>{},
        'clientInfo': {
          'name': clientName,
          'version': clientVersion,
        },
      },
    );
    _throwIfError(res);
    // Peer may accept notifications/initialized; ignore transport failures
    // (loopback server returns null → StateError). Handshake is complete.
    try {
      await transport.request(
        'notifications/initialized',
        id: 'notify_init',
        params: const {},
      );
    } on Object {
      // ignore
    }
    _initialized = true;
    final result = res['result'];
    return result is Map
        ? Map<String, Object?>.from(result)
        : <String, Object?>{};
  }

  /// Raw MCP tool descriptors from `tools/list`.
  Future<List<McpJson>> listTools() async {
    _ensureInit();
    final res = await transport.request(
      'tools/list',
      id: _nextId(),
    );
    _throwIfError(res);
    final result = res['result'];
    final tools = result is Map ? result['tools'] : null;
    if (tools is! List) return const [];
    return [
      for (final t in tools)
        if (t is Map) Map<String, Object?>.from(t),
    ];
  }

  /// Calls a remote tool; returns concatenated text content (MCP content[]).
  Future<String> callTool(String name, [McpJson arguments = const {}]) async {
    _ensureInit();
    final res = await transport.request(
      'tools/call',
      id: _nextId(),
      params: {
        'name': name,
        'arguments': arguments,
      },
    );
    _throwIfError(res);
    final result = res['result'];
    if (result is! Map) return '';
    final isError = result['isError'] == true;
    final content = result['content'];
    final buf = StringBuffer();
    if (content is List) {
      for (final c in content) {
        if (c is Map && c['type'] == 'text') {
          buf.write(c['text'] ?? '');
        }
      }
    }
    final text = buf.toString();
    if (isError) {
      throw FmMcpToolException(name: name, message: text.isEmpty ? 'tool error' : text);
    }
    return text;
  }

  /// Adapts remote tools into [FmTool.callback] instances for the FM runtime.
  Future<List<FmTool>> listToolsAsFmTools() async {
    final descriptors = await listTools();
    return [
      for (final d in descriptors) _toFmTool(d),
    ];
  }

  FmTool _toFmTool(McpJson descriptor) {
    final name = descriptor['name'] as String? ?? 'unnamed';
    final description = descriptor['description'] as String? ?? name;
    // MCP inputSchema is JSON Schema-ish; use empty object if missing —
    // runtime tool path sanitizes at edge for tool mode.
    final schema = FmSchema.object(const {});
    return FmTool.callback(
      name: name,
      description: description,
      inputSchema: schema,
      callback: (args) => callTool(name, args),
    );
  }

  void _ensureInit() {
    if (!_initialized) {
      throw StateError('FmMcpClient.initialize() must be called first');
    }
  }

  void _throwIfError(McpJson res) {
    final err = res['error'];
    if (err is Map) {
      final msg = err['message']?.toString() ?? 'MCP error';
      final code = err['code'];
      throw FmMcpRpcException(code: code is int ? code : -32000, message: msg);
    }
  }

  /// Closes the underlying transport.
  Future<void> close() => transport.close();
}

/// JSON-RPC error from the MCP peer.
final class FmMcpRpcException implements Exception {
  FmMcpRpcException({required this.code, required this.message});
  final int code;
  final String message;
  @override
  String toString() => 'FmMcpRpcException($code): $message';
}

/// Tool-level error (`isError: true` or empty failure).
final class FmMcpToolException implements Exception {
  FmMcpToolException({required this.name, required this.message});
  final String name;
  final String message;
  @override
  String toString() => 'FmMcpToolException($name): $message';
}
