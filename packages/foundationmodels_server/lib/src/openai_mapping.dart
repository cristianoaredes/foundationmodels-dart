import 'dart:convert';

import 'package:foundationmodels/foundationmodels.dart';

/// Maps OpenAI chat messages → instructions + input.
({String? instructions, String input}) mapChatMessages(
  List<Map<String, Object?>> messages,
) {
  final instructions = <String>[];
  final turns = <String>[];
  for (final m in messages) {
    final role = m['role']?.toString() ?? 'user';
    final content = m['content'];
    final text = content is String
        ? content
        : content is List
            ? content
                .whereType<Map>()
                .map((p) => p['text']?.toString() ?? '')
                .join()
            : content?.toString() ?? '';
    if (role == 'system') {
      // Trusted-channel note: deployers must treat remote system content as
      // untrusted unless their gateway already sanitizes it.
      instructions.add(text);
    } else {
      turns.add('$role: $text');
    }
  }
  return (
    instructions: instructions.isEmpty ? null : instructions.join('\n'),
    input: turns.join('\n'),
  );
}

/// Unary OpenAI chat.completion body from an [FmResponse].
Map<String, Object?> chatCompletionResponse({
  required String id,
  required String model,
  required FmResponse response,
}) {
  final content = response.text ??
      (response.structured != null ? jsonEncode(response.structured) : '');
  return {
    'id': id,
    'object': 'chat.completion',
    'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'model': model,
    'choices': [
      {
        'index': 0,
        'message': {'role': 'assistant', 'content': content},
        'finish_reason': 'stop',
      }
    ],
    'usage': {
      'prompt_tokens': response.usage?.inputTokens ?? 0,
      'completion_tokens': response.usage?.outputTokens ?? 0,
      'total_tokens': response.usage?.totalTokens ?? 0,
      'estimated': response.usage?.estimated ?? true,
    },
  };
}

/// SSE chunk for streaming.
String chatCompletionChunk({
  required String id,
  required String model,
  required String delta,
  bool finish = false,
}) {
  final body = {
    'id': id,
    'object': 'chat.completion.chunk',
    'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'model': model,
    'choices': [
      {
        'index': 0,
        'delta': finish ? <String, Object?>{} : {'content': delta},
        if (finish) 'finish_reason': 'stop',
      }
    ],
  };
  return 'data: ${jsonEncode(body)}\n\n';
}

/// Maps typed exceptions → HTTP status + OpenAI error envelope.
({int status, Map<String, Object?> body}) mapError(Object error) {
  if (error is FoundationModelsException) {
    final code = error.code;
    final status = switch (code) {
      'RATE_LIMITED' => 429,
      'APPLE_MODEL_UNAVAILABLE' => 503,
      'CONTEXT_OVERFLOW' ||
      'GUARDRAIL_VIOLATION' ||
      'MODEL_REFUSAL' ||
      'UNSUPPORTED_SCHEMA_TYPE' ||
      'INVALID_PARAMS' ||
      'INVALID_REQUEST' =>
        400,
      'GENERATION_CANCELLED' => 499,
      _ => 500,
    };
    return (
      status: status,
      body: {
        'error': {
          'message': error.message,
          'type': code,
          'code': code,
        }
      },
    );
  }
  return (
    status: 500,
    body: {
      'error': {
        'message': error.toString(),
        'type': 'server_error',
        'code': 'UNKNOWN_MODEL_ERROR',
      }
    },
  );
}
