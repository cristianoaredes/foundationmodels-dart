import 'dart:async';
import 'dart:convert';

import 'package:foundationmodels/foundationmodels.dart';

/// Routes duplex `tool_call_*` stream events to [FmTool] handlers and submits
/// results via [FoundationModels.submitToolResult].
///
/// Lifecycle:
/// 1. [tool_call_start] — track call id / name.
/// 2. [tool_call_delta] — accumulate argument fragments (JSON string pieces).
/// 3. [tool_call_request] — arguments complete; execute callback and submit.
///
/// Static tools are declared on the wire by the host (core-side); this router
/// only executes **callback** tools registered in [tools].
class FmToolRouter {
  /// Creates a router over [fm] with named callback [tools].
  FmToolRouter(this.fm, {List<FmTool>? tools}) {
    for (final tool in tools ?? const <FmTool>[]) {
      register(tool);
    }
  }

  final FoundationModels fm;

  /// Registered callback tools by name.
  final Map<String, FmTool> tools = {};

  final Map<String, _PendingCall> _pending = {};

  /// Registers or replaces a callback tool. Non-callback tools are ignored.
  void register(FmTool tool) {
    if (tool.kind != FmToolKind.callback) return;
    tools[tool.name] = tool;
  }

  /// Convenience: register a named callback without building [FmTool] first.
  void registerHandler(
    String name,
    FutureOr<Object?> Function(Map<String, Object?> args) handler, {
    String description = '',
    FmSchema? inputSchema,
  }) {
    register(FmTool.callback(
      name: name,
      description: description,
      inputSchema: inputSchema ?? FmSchema.object(const {}),
      callback: handler,
    ));
  }

  /// Handles a stream event. Returns whether the router consumed it
  /// (submitted a tool result or recorded progress).
  Future<bool> handleEvent(FmStreamEvent event) async {
    if (event is ToolCallStart) {
      final id = event.toolCallId;
      if (id == null) return false;
      _pending[id] = _PendingCall(
        toolCallId: id,
        toolName: event.toolName,
      );
      return true;
    }

    if (event is ToolCallDelta) {
      final id = event.toolCallId;
      if (id == null) return false;
      final pending = _pending.putIfAbsent(
        id,
        () => _PendingCall(toolCallId: id),
      );
      pending.argumentBuffer.write(event.delta);
      return true;
    }

    if (event is ToolCallRequest) {
      final id = event.toolCallId;
      final name = event.toolName;
      if (id == null || name == null) return false;

      final pending = _pending.remove(id) ??
          _PendingCall(toolCallId: id, toolName: name);
      var args = event.arguments;
      if (args.isEmpty && pending.argumentBuffer.isNotEmpty) {
        args = _decodeArgs(pending.argumentBuffer.toString());
      }
      await _execute(toolCallId: id, toolName: name, args: args);
      return true;
    }

    return false;
  }

  /// Runs duplex for an entire stream: yields every event, executing tools
  /// mid-stream when `tool_call_request` arrives.
  Stream<FmStreamEvent> bind(Stream<FmStreamEvent> source) async* {
    await for (final event in source) {
      yield event;
      await handleEvent(event);
    }
  }

  Future<void> _execute({
    required String toolCallId,
    required String toolName,
    required Map<String, Object?> args,
  }) async {
    final tool = tools[toolName];
    if (tool == null || tool.callback == null) {
      await fm.submitToolResult(
        toolCallId: toolCallId,
        error: {
          'code': 'TOOL_CALLBACK_NOT_FOUND',
          'message': 'No host handler for tool "$toolName".',
        },
      );
      return;
    }
    try {
      final output = await tool.callback!(args);
      await fm.submitToolResult(toolCallId: toolCallId, output: output);
    } catch (e) {
      await fm.submitToolResult(
        toolCallId: toolCallId,
        error: {
          'code': 'TOOL_CALLBACK_ERROR',
          'message': e.toString(),
        },
      );
    }
  }

  Map<String, Object?> _decodeArgs(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) return decoded;
      if (decoded is Map) {
        return {
          for (final e in decoded.entries) e.key.toString(): e.value,
        };
      }
    } catch (_) {
      // leave empty — host gets empty args map
    }
    return const {};
  }

  /// Submits a successful tool output for [toolCallId].
  Future<Map<String, Object?>> complete({
    required String toolCallId,
    required Object? output,
  }) =>
      fm.submitToolResult(toolCallId: toolCallId, output: output);

  /// Submits a tool failure for [toolCallId].
  Future<Map<String, Object?>> fail({
    required String toolCallId,
    required String message,
    String code = 'TOOL_CALLBACK_ERROR',
  }) =>
      fm.submitToolResult(
        toolCallId: toolCallId,
        error: {'code': code, 'message': message},
      );
}

class _PendingCall {
  _PendingCall({required this.toolCallId, this.toolName});

  final String toolCallId;
  String? toolName;
  final StringBuffer argumentBuffer = StringBuffer();
}
