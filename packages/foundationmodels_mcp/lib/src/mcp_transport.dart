import 'dart:async';
import 'dart:convert';

import 'mcp_types.dart';

/// Bidirectional JSON-RPC transport for MCP client/server.
abstract class McpTransport {
  /// Sends a JSON-RPC **request** and waits for the matching response `id`.
  Future<McpJson> request(
    String method, {
    Object? id,
    McpJson? params,
  });

  /// Optional server→client notifications / SSE events (may be empty).
  Stream<McpJson> get events;

  /// Releases resources.
  Future<void> close();
}

/// In-memory loopback: client requests are handled by [FmMcpServer.handleMessage].
///
/// Used for CI dual-run without network or UAB.
final class McpLoopbackTransport implements McpTransport {
  McpLoopbackTransport(this._handler);

  /// Handles one JSON-RPC request map; returns response or null (notification).
  final Future<McpJson?> Function(McpJson message) _handler;

  final _events = StreamController<McpJson>.broadcast();
  var _closed = false;
  var _nextId = 1;

  @override
  Stream<McpJson> get events => _events.stream;

  @override
  Future<McpJson> request(
    String method, {
    Object? id,
    McpJson? params,
  }) async {
    if (_closed) {
      throw StateError('McpLoopbackTransport is closed');
    }
    final reqId = id ?? _nextId++;
    final message = <String, Object?>{
      'jsonrpc': '2.0',
      'id': reqId,
      'method': method,
      if (params != null) 'params': params,
    };
    final res = await _handler(message);
    if (res == null) {
      throw StateError('Handler returned null for request id=$reqId');
    }
    return res;
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _events.close();
  }
}

/// Parses SSE `data:` lines into JSON-RPC maps (unit-testable pure function).
///
/// Supports:
/// - `data: {...json...}`
/// - multi-line `data:` joined with `\n` until blank line (minimal subset)
List<McpJson> parseSseDataFrames(String chunk) {
  final out = <McpJson>[];
  final blocks = chunk.split(RegExp(r'\r?\n\r?\n'));
  for (final block in blocks) {
    final dataLines = <String>[];
    for (final line in block.split(RegExp(r'\r?\n'))) {
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    if (dataLines.isEmpty) continue;
    final payload = dataLines.join('\n').trim();
    if (payload.isEmpty || payload == '[DONE]') continue;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        out.add(Map<String, Object?>.from(decoded));
      }
    } on FormatException {
      // ignore non-JSON data frames
    }
  }
  return out;
}

/// HTTP + SSE style transport for remote MCP (e.g. UAB).
///
/// **v1 contract:**
/// - Requests: `POST [rpcUrl]` with JSON-RPC body, `Accept: application/json`
///   (and optionally `text/event-stream`).
/// - Optional event stream: `GET [sseUrl]` with `Accept: text/event-stream`,
///   frames parsed by [parseSseDataFrames].
///
/// [httpPost] / [openSse] are injectable for tests (no live network in CI).
final class McpSseTransport implements McpTransport {
  McpSseTransport({
    required this.rpcUrl,
    this.sseUrl,
    this.headers = const {},
    required this.httpPost,
    this.openSse,
  });

  /// JSON-RPC POST endpoint (UAB tools endpoint).
  final Uri rpcUrl;

  /// Optional SSE GET endpoint for server-push events.
  final Uri? sseUrl;

  /// Extra headers (e.g. `Authorization: Bearer …`).
  final Map<String, String> headers;

  /// `POST url` → response body string (JSON or SSE).
  final Future<String> Function(
    Uri url,
    Map<String, String> headers,
    String body,
  ) httpPost;

  /// Optional long-lived SSE body stream (UTF-8 text chunks).
  final Stream<String> Function(Uri url, Map<String, String> headers)? openSse;

  final _events = StreamController<McpJson>.broadcast();
  StreamSubscription<String>? _sseSub;
  var _closed = false;
  var _nextId = 1;
  final _pending = <Object, Completer<McpJson>>{};

  /// Starts optional SSE listener (idempotent).
  Future<void> connectEvents() async {
    final open = openSse;
    final url = sseUrl;
    if (open == null || url == null || _sseSub != null) return;
    _sseSub = open(url, {
      'Accept': 'text/event-stream',
      ...headers,
    }).listen((chunk) {
      for (final msg in parseSseDataFrames(chunk)) {
        final id = msg['id'];
        if (id != null && _pending.containsKey(id)) {
          _pending.remove(id)?.complete(msg);
        } else {
          if (!_events.isClosed) _events.add(msg);
        }
      }
    });
  }

  @override
  Stream<McpJson> get events => _events.stream;

  @override
  Future<McpJson> request(
    String method, {
    Object? id,
    McpJson? params,
  }) async {
    if (_closed) throw StateError('McpSseTransport is closed');
    final reqId = id ?? _nextId++;
    final message = <String, Object?>{
      'jsonrpc': '2.0',
      'id': reqId,
      'method': method,
      if (params != null) 'params': params,
    };
    final body = jsonEncode(message);
    final raw = await httpPost(
      rpcUrl,
      {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        ...headers,
      },
      body,
    );

    // Response may be plain JSON or SSE-wrapped JSON.
    // Streamable-HTTP (UAB/FastMCP) often returns:
    //   event: message\ndata: {...}\n\n
    // so detection must not require `data:` as the first line.
    final trimmed = raw.trim();
    final looksLikeSse = trimmed.startsWith('data:') ||
        trimmed.startsWith('event:') ||
        trimmed.contains('\ndata:') ||
        trimmed.contains('\r\ndata:');
    if (looksLikeSse) {
      final frames = parseSseDataFrames(raw);
      if (frames.isEmpty) {
        throw StateError('SSE response contained no JSON frames');
      }
      return frames.last;
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) {
      throw StateError('Expected JSON object response');
    }
    return Map<String, Object?>.from(decoded);
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _sseSub?.cancel();
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('transport closed'));
      }
    }
    _pending.clear();
    await _events.close();
  }
}
