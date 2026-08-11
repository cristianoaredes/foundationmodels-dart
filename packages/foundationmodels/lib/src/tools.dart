/// Tool definitions for duplex / static / native tool calling (phase 4).
library;

import 'dart:async';

import 'schema.dart';

/// Kind of tool behavior.
enum FmToolKind { staticOutput, callback, native }

/// A request-scoped tool definition.
///
/// Exactly one behavior: [FmTool.static], [FmTool.callback], or [FmTool.native].
/// Tools are never persisted on sessions (upstream contract).
final class FmTool {
  const FmTool._({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.kind,
    this.staticOutput,
    this.callback,
    this.nativeKind,
  });

  /// Static tool: the core answers from [staticOutput] without a host callback.
  /// Usable in both `respond` and `stream`.
  factory FmTool.static({
    required String name,
    required String description,
    required FmSchema inputSchema,
    required Object? staticOutput,
  }) =>
      FmTool._(
        name: name,
        description: description,
        inputSchema: inputSchema,
        kind: FmToolKind.staticOutput,
        staticOutput: staticOutput,
      );

  /// Callback tool: host [callback] runs on `tool_call_request` (stream-only).
  factory FmTool.callback({
    required String name,
    required String description,
    required FmSchema inputSchema,
    required FutureOr<Object?> Function(Map<String, Object?> args) callback,
  }) =>
      FmTool._(
        name: name,
        description: description,
        inputSchema: inputSchema,
        kind: FmToolKind.callback,
        callback: callback,
      );

  /// Native core tool (`ocr` | `barcode`).
  factory FmTool.native({
    required String nativeKind,
    String? name,
    String? description,
    FmSchema? inputSchema,
  }) =>
      FmTool._(
        name: name ?? 'native:$nativeKind',
        description: description ?? 'Native $nativeKind tool',
        inputSchema: inputSchema ?? FmSchema.object(const {}),
        kind: FmToolKind.native,
        nativeKind: nativeKind,
      );

  final String name;
  final String description;
  final FmSchema inputSchema;
  final FmToolKind kind;
  final Object? staticOutput;
  final FutureOr<Object?> Function(Map<String, Object?> args)? callback;
  final String? nativeKind;

  /// Whether this tool requires a streaming generation path.
  bool get requiresStreaming => kind == FmToolKind.callback;

  /// Wire form for protocol `tools` arrays.
  Map<String, Object?> toJson() {
    final schemaJson = inputSchema.toJson(mode: SchemaMode.tool);
    return {
      'name': name,
      'description': description,
      'inputSchema': schemaJson,
      if (kind == FmToolKind.staticOutput) 'staticOutput': staticOutput,
      if (kind == FmToolKind.native) 'native': nativeKind,
      if (kind == FmToolKind.callback) 'callback': true,
    };
  }
}
