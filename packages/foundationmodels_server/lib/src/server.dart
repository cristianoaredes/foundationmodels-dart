import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:foundationmodels/foundationmodels.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'openai_mapping.dart';

/// Embeddable OpenAI-compatible server over a [FoundationModels] runtime.
final class FmOpenAiServer {
  FmOpenAiServer({
    required this.runtime,
    this.host = '127.0.0.1',
    this.port = 11435,
    this.bearerToken,
    this.cors = false,
  });

  final FoundationModels runtime;
  final String host;
  final int port;
  final String? bearerToken;
  final bool cors;

  HttpServer? _server;

  /// Shelf handler (for tests / embedding without binding a port).
  Handler get handler {
    final router = Router()
      ..get('/health', _health)
      ..get('/v1/models', _models)
      ..post('/v1/chat/completions', _chatCompletions);

    var pipeline = const Pipeline().addMiddleware(_authMiddleware);
    if (cors) {
      pipeline = pipeline.addMiddleware(_corsMiddleware);
    }
    return pipeline.addHandler(router.call);
  }

  Future<void> start() async {
    _server = await shelf_io.serve(handler, host, port);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  int? get boundPort => _server?.port;

  Middleware get _authMiddleware => (inner) {
        return (request) async {
          if (bearerToken == null) return inner(request);
          final header = request.headers['authorization'] ?? '';
          if (header != 'Bearer $bearerToken') {
            return Response(
              401,
              body: jsonEncode({
                'error': {
                  'message': 'Invalid bearer token',
                  'type': 'invalid_request_error',
                  'code': 'unauthorized',
                }
              }),
              headers: {'content-type': 'application/json'},
            );
          }
          return inner(request);
        };
      };

  Middleware get _corsMiddleware => (inner) {
        return (request) async {
          if (request.method == 'OPTIONS') {
            return Response.ok('', headers: _corsHeaders);
          }
          final response = await inner(request);
          return response.change(headers: {...response.headers, ..._corsHeaders});
        };
      };

  static const _corsHeaders = {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'authorization, content-type',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
  };

  Future<Response> _health(Request request) async {
    final health = await runtime.health();
    final avail = await runtime.availability();
    return Response.ok(
      jsonEncode({
        'ok': true,
        'provider': runtime.provider.id,
        'available': avail.available,
        'health': health,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _models(Request request) async {
    return Response.ok(
      jsonEncode({
        'object': 'list',
        'data': [
          {
            'id': 'apple.system',
            'object': 'model',
            'owned_by': 'foundationmodels-dart',
          }
        ],
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _chatCompletions(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, Object?>;
      final messages = (body['messages'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, Object?>.from(m))
          .toList();
      final mapped = mapChatMessages(messages);
      final model = body['model']?.toString() ?? 'apple.system';
      final stream = body['stream'] == true;
      final temperature = (body['temperature'] as num?)?.toDouble();
      final maxTokens = (body['max_tokens'] as num?)?.toInt();
      final options = GenerationOptions(
        temperature: temperature,
        maximumResponseTokens: maxTokens,
      );
      final id =
          'chatcmpl_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

      if (stream) {
        final controller = StreamController<List<int>>();
        () async {
          try {
            await for (final event in runtime.stream(
              input: mapped.input,
              instructions: mapped.instructions,
              options: options,
            )) {
              if (event is TextDelta) {
                controller.add(utf8.encode(chatCompletionChunk(
                  id: id,
                  model: model,
                  delta: event.delta,
                )));
              } else if (event is StreamError) {
                controller.add(utf8.encode(
                  'data: ${jsonEncode(mapError(event.toException()).body)}\n\n',
                ));
              }
            }
            controller.add(utf8.encode(chatCompletionChunk(
              id: id,
              model: model,
              delta: '',
              finish: true,
            )));
            controller.add(utf8.encode('data: [DONE]\n\n'));
          } catch (e) {
            final mappedErr = mapError(e);
            controller.add(
              utf8.encode('data: ${jsonEncode(mappedErr.body)}\n\n'),
            );
          } finally {
            await controller.close();
          }
        }();
        return Response.ok(
          controller.stream,
          headers: {
            'content-type': 'text/event-stream',
            'cache-control': 'no-cache',
            'connection': 'keep-alive',
          },
        );
      }

      final response = await runtime.respond(
        input: mapped.input,
        instructions: mapped.instructions,
        options: options,
      );
      return Response.ok(
        jsonEncode(chatCompletionResponse(
          id: id,
          model: model,
          response: response,
        )),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      final mapped = mapError(e);
      return Response(
        mapped.status,
        body: jsonEncode(mapped.body),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
