import 'dart:convert';

import 'package:foundationmodels/foundationmodels.dart';
import 'package:foundationmodels_server/foundationmodels_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test('mapChatMessages splits system vs turns', () {
    final mapped = mapChatMessages([
      {'role': 'system', 'content': 'Be brief.'},
      {'role': 'user', 'content': 'Hi'},
    ]);
    expect(mapped.instructions, 'Be brief.');
    expect(mapped.input, contains('user: Hi'));
  });

  test('handler health and chat completions (unary) via shelf', () async {
    final fm = await createFoundationModels();
    final server = FmOpenAiServer(runtime: fm);
    final handler = server.handler;

    final health = await handler(Request('GET', Uri.parse('http://t/health')));
    expect(health.statusCode, 200);
    final healthBody = jsonDecode(await health.readAsString()) as Map;
    expect(healthBody['ok'], isTrue);

    final chat = await handler(Request(
      'POST',
      Uri.parse('http://t/v1/chat/completions'),
      body: jsonEncode({
        'model': 'apple.system',
        'messages': [
          {'role': 'user', 'content': 'Hello server'},
        ],
      }),
      headers: {'content-type': 'application/json'},
    ));
    expect(chat.statusCode, 200);
    final body = jsonDecode(await chat.readAsString()) as Map;
    expect(body['object'], 'chat.completion');
    expect(
      (body['choices'] as List).first['message']['content'],
      isNotEmpty,
    );
  });

  test('bearer auth rejects missing token', () async {
    final fm = await createFoundationModels();
    final server = FmOpenAiServer(runtime: fm, bearerToken: 'secret');
    final res = await server.handler(
      Request('GET', Uri.parse('http://t/health')),
    );
    expect(res.statusCode, 401);
  });

  test('mapError RATE_LIMITED → 429', () {
    final mapped = mapError(const RateLimitedException(
      message: 'slow',
      resetDate: '2026-01-01',
    ));
    expect(mapped.status, 429);
    expect((mapped.body['error'] as Map)['code'], 'RATE_LIMITED');
  });
}
