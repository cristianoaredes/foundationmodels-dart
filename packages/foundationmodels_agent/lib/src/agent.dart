import 'dart:async';

import 'package:foundationmodels/foundationmodels.dart';
import 'package:foundationmodels_tools/foundationmodels_tools.dart';

import 'events.dart';
import 'hitl.dart';

/// Autonomous-but-supervised tool loop over [FoundationModels.stream].
///
/// Emits AG-UI-shaped [FmAgentEvent]s. When [requireHitl] is true, each
/// `tool_call_request` pauses with an [FmAgentInterruptEvent]; the host must
/// call [resumeInterrupt] before the tool executes.
///
/// **Single-executor contract:** [run] always calls
/// `fm.stream(..., tools: tools, autoExecuteTools: false)` so the runtime
/// does not submit `tools.result`. This agent (via [_router] / HITL) is the
/// sole owner of tool execution — never double-submit.
class FmAgent {
  FmAgent({
    required this.fm,
    List<FmTool>? tools,
    this.requireHitl = false,
    FmInterruptRegistry? interrupts,
  })  : tools = List<FmTool>.unmodifiable(tools ?? const []),
        interrupts = interrupts ?? FmInterruptRegistry(),
        _router = FmToolRouter(fm, tools: tools);

  final FoundationModels fm;
  final List<FmTool> tools;
  final bool requireHitl;
  final FmInterruptRegistry interrupts;
  final FmToolRouter _router;

  final Map<String, Completer<Map<String, Object?>>> _hitlWaiters = {};

  /// Registers a callback tool on the duplex router.
  void registerTool(FmTool tool) => _router.register(tool);

  /// Resumes a HITL interrupt (approve / edit / reject).
  void resumeInterrupt({
    required String interruptId,
    required FmInterruptDecision decision,
    Map<String, Object?>? editedArgs,
  }) {
    final completer = _hitlWaiters.remove(interruptId);
    try {
      final args = interrupts.resume(
        id: interruptId,
        decision: decision,
        editedArgs: editedArgs,
      );
      completer?.complete(args);
    } catch (e, st) {
      completer?.completeError(e, st);
    }
  }

  /// Runs one agent turn: streams model events, executes tools (optionally
  /// via HITL), and yields AG-UI events.
  Stream<FmAgentEvent> run({
    required String input,
    String? instructions,
    CancelToken? cancelToken,
  }) async* {
    final runId =
        'run_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    yield FmAgentRunStarted(runId: runId);

    // Ensure every constructor tool is on the router (sole executor).
    for (final t in tools) {
      if (t.kind == FmToolKind.callback) {
        _router.register(t);
      }
    }

    try {
      // tools: on the wire so the mock/provider emits tool_call_*;
      // autoExecuteTools: false so only this agent submits tools.result.
      await for (final event in fm.stream(
        input: input,
        instructions: instructions,
        tools: tools,
        autoExecuteTools: false,
        cancelToken: cancelToken,
      )) {
        if (event is TextDelta) {
          yield FmAgentTextContent(delta: event.delta);
        } else if (event is ToolCallStart) {
          yield FmAgentToolCallStart(
            toolCallId: event.toolCallId ?? 'tc_unknown',
            toolName: event.toolName ?? 'unknown',
          );
          await _router.handleEvent(event);
        } else if (event is ToolCallDelta) {
          await _router.handleEvent(event);
        } else if (event is ToolCallRequest) {
          final toolCallId = event.toolCallId ?? 'tc_unknown';
          final toolName = event.toolName ?? 'unknown';
          var args = Map<String, Object?>.from(event.arguments);

          if (requireHitl) {
            final interrupt = interrupts.create(
              toolName: toolName,
              proposedArgs: args,
            );
            final waiter = Completer<Map<String, Object?>>();
            _hitlWaiters[interrupt.id] = waiter;
            yield FmAgentInterruptEvent(
              interruptId: interrupt.id,
              toolName: toolName,
              proposedArgs: args,
            );
            args = await waiter.future;
            // Single submit via router with approved/edited args.
            await _router.handleEvent(ToolCallRequest(
              requestId: event.requestId,
              toolCallId: toolCallId,
              toolName: toolName,
              arguments: args,
            ));
          } else {
            // Single submit via router (runtime auto-exec is off).
            await _router.handleEvent(event);
          }
          yield FmAgentToolCallEnd(toolCallId: toolCallId);
        } else if (event is StreamError) {
          yield FmAgentRunError(
            message: event.message,
            code: event.code,
          );
          return;
        }
      }
      yield FmAgentRunFinished(runId: runId);
    } catch (e) {
      yield FmAgentRunError(message: e.toString());
    }
  }
}
