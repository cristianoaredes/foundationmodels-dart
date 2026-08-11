import 'package:foundationmodels/foundationmodels.dart';
import 'package:foundationmodels_mcp/foundationmodels_mcp.dart';
import 'package:test/test.dart';

void main() {
  late FoundationModels fm;
  late FmMcpServer server;
  late FmMcpClient client;

  setUp(() async {
    fm = await createFoundationModels();
    server = FmMcpServer(fm: fm);
    client = FmMcpClient(
      transport: McpLoopbackTransport(server.handleMessage),
    );
  });

  tearDown(() async {
    await client.close();
  });

  Future<void> oneRun(int n) async {
    final init = await client.initialize();
    expect(init['serverInfo'], isA<Map>());
    expect(client.isInitialized, isTrue);

    final tools = await client.listTools();
    expect(
      tools.any((t) => t['name'] == kFmRespondToolName),
      isTrue,
    );

    final text = await client.callTool(
      kFmRespondToolName,
      {'input': 'hello from mcp client $n'},
    );
    expect(text, isNotEmpty);

    final fmTools = await client.listToolsAsFmTools();
    expect(fmTools, isNotEmpty);
    expect(fmTools.first.kind, FmToolKind.callback);

    print(
      'SMOKE mcp_client run=$n init_ok list_ok call_ok '
      'fm_tools=${fmTools.length}',
    );
  }

  test('dual-run client loopback to server mock FM', () async {
    await oneRun(1);
    // second client on same server
    final client2 = FmMcpClient(
      transport: McpLoopbackTransport(server.handleMessage),
    );
    final init2 = await client2.initialize();
    expect(init2['serverInfo'], isA<Map>());
    final text = await client2.callTool(
      kFmRespondToolName,
      {'input': 'second run'},
    );
    expect(text, isNotEmpty);
    await client2.close();
    print('SMOKE mcp_client dual_run_ok=true');
  });

  test('unknown tool surfaces error', () async {
    await client.initialize();
    await expectLater(
      client.callTool('no_such_tool', const {}),
      throwsA(anyOf(isA<FmMcpToolException>(), isA<FmMcpRpcException>(), isA<StateError>(), isA<Exception>())),
    );
  });

  test('parseSseDataFrames extracts JSON data lines', () {
    const chunk = '''
event: message
data: {"jsonrpc":"2.0","id":1,"result":{"ok":true}}

data: {"jsonrpc":"2.0","method":"notifications/progress"}

''';
    final frames = parseSseDataFrames(chunk);
    expect(frames.length, 2);
    expect(frames.first['id'], 1);
    expect(frames.first['result'], isA<Map>());
    expect(frames[1]['method'], 'notifications/progress');
    print('SMOKE sse_parse_ok=true frames=${frames.length}');
  });

  test('McpSseTransport POST path with injectable httpPost', () async {
    final transport = McpSseTransport(
      rpcUrl: Uri.parse('https://uab.example/mcp'),
      httpPost: (url, headers, body) async {
        expect(url.host, 'uab.example');
        expect(headers['Content-Type'], contains('json'));
        // Emulate UAB JSON-RPC response for initialize
        return '{"jsonrpc":"2.0","id":"c_1","result":{"protocolVersion":"2024-11-05","serverInfo":{"name":"uab"},"capabilities":{"tools":{}}}}';
      },
    );
    final c = FmMcpClient(transport: transport);
    // Force id sequence: client uses c_1 first
    final init = await c.initialize();
    expect((init['serverInfo'] as Map)['name'], 'uab');
    await c.close();
    print('SMOKE sse_transport_post_ok=true');
  });
}
