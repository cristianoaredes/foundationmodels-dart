/// AG-UI-shaped agent events (capability parity with upstream agent package).
sealed class FmAgentEvent {
  const FmAgentEvent();
  String get type;
  Map<String, Object?> toJson();
}

final class FmAgentRunStarted extends FmAgentEvent {
  const FmAgentRunStarted({required this.runId});
  final String runId;
  @override
  String get type => 'RUN_STARTED';
  @override
  Map<String, Object?> toJson() => {'type': type, 'runId': runId};
}

final class FmAgentTextContent extends FmAgentEvent {
  const FmAgentTextContent({required this.delta});
  final String delta;
  @override
  String get type => 'TEXT_MESSAGE_CONTENT';
  @override
  Map<String, Object?> toJson() => {'type': type, 'delta': delta};
}

final class FmAgentToolCallStart extends FmAgentEvent {
  const FmAgentToolCallStart({
    required this.toolCallId,
    required this.toolName,
  });
  final String toolCallId;
  final String toolName;
  @override
  String get type => 'TOOL_CALL_START';
  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'toolCallId': toolCallId,
        'toolName': toolName,
      };
}

final class FmAgentToolCallEnd extends FmAgentEvent {
  const FmAgentToolCallEnd({
    required this.toolCallId,
    this.output,
  });
  final String toolCallId;
  final Object? output;
  @override
  String get type => 'TOOL_CALL_END';
  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'toolCallId': toolCallId,
        if (output != null) 'output': output,
      };
}

final class FmAgentInterruptEvent extends FmAgentEvent {
  const FmAgentInterruptEvent({
    required this.interruptId,
    required this.toolName,
    required this.proposedArgs,
  });
  final String interruptId;
  final String toolName;
  final Map<String, Object?> proposedArgs;
  @override
  String get type => 'INTERRUPT';
  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'interruptId': interruptId,
        'toolName': toolName,
        'proposedArgs': proposedArgs,
      };
}

final class FmAgentRunFinished extends FmAgentEvent {
  const FmAgentRunFinished({required this.runId});
  final String runId;
  @override
  String get type => 'RUN_FINISHED';
  @override
  Map<String, Object?> toJson() => {'type': type, 'runId': runId};
}

final class FmAgentRunError extends FmAgentEvent {
  const FmAgentRunError({required this.message, this.code});
  final String message;
  final String? code;
  @override
  String get type => 'RUN_ERROR';
  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'message': message,
        if (code != null) 'code': code,
      };
}
