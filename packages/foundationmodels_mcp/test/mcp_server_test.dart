import 'dart:async';
import 'dart:convert';

import 'package:foundationmodels/foundationmodels.dart';
import 'package:foundationmodels_mcp/foundationmodels_mcp.dart';
import 'package:test/test.dart';

void main() {
  late FoundationModels fm;
  late FmMcpServer server;

  setUp(() async {
    fm = await createFoundationModels(); // mock
    server = FmMcpServer(fm: fm);
  });

  Future<Map<String, Object?>> rpc(
    String method, {
    Object? id = 1,
    Map<String, Object?>? params,
  }) async {
    final msg = <String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      if (id != null) 'id': id,
      if (params != null) 'params': params,
    };
    final res = await server.handleMessage(msg);
    return res ?? <String, Object?>{};
  }

  Future<void> oneRun(int n) async {
    final init = await rpc('initialize', id: 'init_$n');
    expect(init['result'], isA<Map>());
    final info = (init['result'] as Map)['serverInfo'] as Map;
    expect(info['name'], 'foundationmodels_mcp');

    final list = await rpc('tools/list', id: 'list_$n');
    final tools = (list['result'] as Map)['tools'] as List;
    expect(
      tools.any((t) => (t as Map)['name'] == kFmRespondToolName),
      isTrue,
    );

    final call = await rpc(
      'tools/call',
      id: 'call_$n',
      params: {
        'name': kFmRespondToolName,
        'arguments': {'input': 'ping from mcp'},
      },
    );
    final content = (call['result'] as Map)['content'] as List;
    expect(content, isNotEmpty);
    final text = (content.first as Map)['text'] as String;
    expect(text, isNotEmpty);
    print('SMOKE mcp run=$n tools_list_ok call_ok text_len=${text.length}');
  }

  test('dual-run mock initialize + tools/list + tools/call fm_respond',
      () async {
    await oneRun(1);
    await oneRun(2);
    print('SMOKE mcp dual_run_ok=true');
  });

  test('unknown method fail-closed METHOD_NOT_FOUND', () async {
    final res = await rpc('nope/method', id: 99);
    final err = res['error'] as Map;
    expect(err['code'], -32601);
    expect((err['data'] as Map)['code'], 'METHOD_NOT_FOUND');
    print('SMOKE mcp unknown_method failclosed_ok=true');
  });

  test('extra callback tool via tools/call', () async {
    server.registerTool(
      FmTool.callback(
        name: 'echo_tool',
        description: 'echo',
        inputSchema: FmSchema.object(const {}),
        callback: (args) async => 'echo:${args['x']}',
      ),
    );
    final call = await rpc(
      'tools/call',
      id: 3,
      params: {
        'name': 'echo_tool',
        'arguments': {'x': 'hi'},
      },
    );
    final text =
        (((call['result'] as Map)['content'] as List).first as Map)['text'];
    expect(text, 'echo:hi');
  });

  test('serve NDJSON line protocol end-to-end', () async {
    final controller = StreamController<List<int>>();
    final out = <String>[];
    final done = server.serve(
      input: controller.stream,
      output: (bytes) => out.add(utf8.decode(bytes)),
    );

    controller.add(utf8.encode(
      '${jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/list',
            'params': <String, Object?>{},
          })}\n',
    ));
    await controller.close();
    await done;
    expect(out, isNotEmpty);
    final parsed = jsonDecode(out.first.trim()) as Map;
    expect(parsed['result'], isNotNull);
    print('SMOKE mcp ndjson_serve_ok=true');
  });
}
