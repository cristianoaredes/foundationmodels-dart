import 'package:foundationmodels/foundationmodels.dart';

/// Minimal chat message for the adapter (mirrors LangChain BaseMessage shape).
class LcChatMessage {
  const LcChatMessage({required this.role, required this.content});
  final String role; // system | human | ai
  final String content;
}

/// Result of a chat call.
class LcChatResult {
  const LcChatResult({required this.content, this.raw});
  final String content;
  final FmResponse? raw;
}

/// `ChatFoundationModels` — LangChain.dart-shaped wrapper over [FoundationModels].
///
/// Capability parity with the upstream AI SDK adapter: text, streaming,
/// guided generation, tools (via host wiring). Implemented idiomatically
/// without requiring `langchain_core` at publish time.
class ChatFoundationModels {
  ChatFoundationModels(this.fm, {this.defaultInstructions});

  final FoundationModels fm;
  final String? defaultInstructions;

  /// Unary chat over [messages].
  Future<LcChatResult> invoke(List<LcChatMessage> messages) async {
    final system = messages
        .where((m) => m.role == 'system')
        .map((m) => m.content)
        .join('\n');
    final input = messages
        .where((m) => m.role != 'system')
        .map((m) => '${m.role}: ${m.content}')
        .join('\n');
    final response = await fm.respond(
      input: input.isEmpty ? messages.last.content : input,
      instructions: system.isEmpty ? defaultInstructions : system,
    );
    return LcChatResult(
      content: response.text ?? '',
      raw: response,
    );
  }

  /// Streaming chat tokens (text deltas).
  Stream<String> stream(List<LcChatMessage> messages) async* {
    final system = messages
        .where((m) => m.role == 'system')
        .map((m) => m.content)
        .join('\n');
    final input = messages
        .where((m) => m.role != 'system')
        .map((m) => '${m.role}: ${m.content}')
        .join('\n');
    await for (final event in fm.stream(
      input: input.isEmpty ? messages.last.content : input,
      instructions: system.isEmpty ? defaultInstructions : system,
    )) {
      if (event is TextDelta) yield event.delta;
    }
  }

  /// Guided generation helper (structured output).
  Future<Object?> extractStructured({
    required String input,
    required FmSchema schema,
  }) {
    return fm.extract(input: input, schema: schema);
  }
}
