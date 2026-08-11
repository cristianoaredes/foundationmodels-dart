import 'dart:async';
import 'dart:convert';

import 'package:foundationmodels/foundationmodels.dart';

import 'mcp_types.dart';

/// Minimal MCP **server** (DES-0004): NDJSON JSON-RPC over a line stream.
///
/// Handles `initialize`, `tools/list`, `tools/call`, optional `ping`.
/// Built-in tool [kFmRespondToolName] calls [FoundationModels.respond].
/// Additional [FmTool.callback] tools may be registered.
///
/// **Security:** never writes untrusted content into `instructions`.
final class FmMcpServer {
  FmMcpServer({
    required this.fm,
    List<FmTool>? tools,
    this.serverName = 'foundationmodels_mcp',
    this.serverVersion = '0.1.0',
    this.protocolVersion = '2024-11-05',
  }) : _extraTools = {
          for (final t in tools ?? const <FmTool>[])
            if (t.kind == FmToolKind.callback) t.name: t,
        };

  final FoundationModels fm;
  final String serverName;
  final String serverVersion;
  final String protocolVersion;
  final Map<String, FmTool> _extraTools;

  /// Registers or replaces a callback tool exposed via MCP `tools/list`.
  void registerTool(FmTool tool) {
    if (tool.kind != FmToolKind.callback) {
      throw ArgumentError.value(tool.kind, 'tool.kind', 'callback only');
    }
    _extraTools[tool.name] = tool;
  }

  /// Handles a single JSON-RPC request object. Returns a response map, or
  /// `null` for notifications (no `id`).
  Future<McpJson?> handleMessage(McpJson message) async {
    final method = message['method'] as String?;
    final id = message['id'];
    final params = message['params'];
    final paramsMap = params is Map
        ? Map<String, Object?>.from(params)
        : <String, Object?>{};

    // Notifications (no id) — accept silently.
    if (id == null && method != null) {
      if (method == 'notifications/initialized' ||
          method.startsWith('notifications/')) {
        return null;
      }
      // Unknown notification — ignore.
      return null;
    }

    if (method == null) {
      return _error(id, -32600, 'Invalid Request: missing method');
    }

    try {
      switch (method) {
        case 'initialize':
          return _ok(id, {
            'protocolVersion': protocolVersion,
            'capabilities': {
              'tools': <String, Object?>{},
            },
            'serverInfo': {
              'name': serverName,
              'version': serverVersion,
            },
          });
        case 'ping':
          return _ok(id, <String, Object?>{});
        case 'tools/list':
          return _ok(id, {'tools': _toolDescriptors()});
        case 'tools/call':
          final name = paramsMap['name'] as String? ?? '';
          final args = paramsMap['arguments'];
          final argMap = args is Map
              ? Map<String, Object?>.from(args)
              : <String, Object?>{};
          final text = await _callTool(name, argMap);
          return _ok(id, {
            'content': [
              {'type': 'text', 'text': text},
            ],
            'isError': false,
          });
        default:
          return _error(
            id,
            -32601,
            'Method not found: $method',
            data: {'code': 'METHOD_NOT_FOUND'},
          );
      }
    } catch (e) {
      return _error(
        id,
        -32000,
        e.toString(),
        data: {'code': 'TOOL_ERROR'},
      );
    }
  }

  /// Processes NDJSON lines from [input] and writes response lines to [output].
  Future<void> serve({
    required Stream<List<int>> input,
    required void Function(List<int> bytes) output,
  }) async {
    final lines = utf8.decoder
        .bind(input)
        .transform(const LineSplitter())
        .where((l) => l.trim().isNotEmpty);

    await for (final line in lines) {
      Map<String, Object?> message;
      try {
        message = Map<String, Object?>.from(jsonDecode(line) as Map);
      } catch (_) {
        final err = jsonEncode({
          'jsonrpc': '2.0',
          'id': null,
          'error': {
            'code': -32700,
            'message': 'Parse error',
            'data': {'code': 'PARSE_ERROR'},
          },
        });
        output(utf8.encode('$err\n'));
        continue;
      }

      final response = await handleMessage(message);
      if (response != null) {
        output(utf8.encode('${jsonEncode(response)}\n'));
      }
    }
  }

  List<Map<String, Object?>> _toolDescriptors() {
    final list = <Map<String, Object?>>[
      {
        'name': kFmRespondToolName,
        'description':
            'Unary FoundationModels.respond (mock or Apple provider).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'input': {'type': 'string', 'description': 'User text'},
            'instructions': {
              'type': 'string',
              'description':
                  'Trusted system instructions only — never untrusted blobs',
            },
          },
          'required': ['input'],
        },
      },
    ];
    for (final t in _extraTools.values) {
      list.add({
        'name': t.name,
        'description': t.description,
        'inputSchema': {
          'type': 'object',
          'properties': <String, Object?>{},
        },
      });
    }
    return list;
  }

  Future<String> _callTool(String name, Map<String, Object?> args) async {
    if (name == kFmRespondToolName) {
      final input = args['input'] as String? ?? '';
      // Only pass instructions if explicitly provided as a string (trusted host).
      final instructions = args['instructions'] as String?;
      final r = await fm.respond(
        input: input,
        instructions: instructions,
      );
      return r.text ?? '';
    }
    final tool = _extraTools[name];
    if (tool == null) {
      throw StateError('Unknown tool: $name');
    }
    final result = await tool.callback!(args);
    if (result is String) return result;
    return jsonEncode(result);
  }

  McpJson _ok(Object? id, Object? result) => {
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      };

  McpJson _error(
    Object? id,
    int code,
    String message, {
    Map<String, Object?>? data,
  }) =>
      {
        'jsonrpc': '2.0',
        'id': id,
        'error': {
          'code': code,
          'message': message,
          if (data != null) 'data': data,
        },
      };
}
