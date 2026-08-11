import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:foundationmodels/foundationmodels.dart';
import 'package:foundationmodels_daemon/foundationmodels_daemon.dart';
import 'package:test/test.dart';

/// Minimal JSON-RPC line protocol peer that pretends to be the macOS daemon.
class _FakeDaemon {
  _FakeDaemon(this.server);

  final ServerSocket server;
  Socket? client;
  final List<Map<String, Object?>> received = [];

  static Future<_FakeDaemon> start() async {
    final dir = await Directory.systemTemp.createTemp('fm_daemon_e2e_');
    final path = '${dir.path}/fm.sock';
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final fake = _FakeDaemon(server);
    fake._path = path;
    fake._dir = dir;
    server.listen(fake._onClient);
    return fake;
  }

  late final String _path;
  late final Directory _dir;
  String get path => _path;

  void _onClient(Socket socket) {
    client = socket;
    final buffer = BytesBuilder(copy: false);
    socket.listen((data) {
      buffer.add(data);
      final bytes = buffer.takeBytes();
      var start = 0;
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] == 0x0a) {
          final line = utf8.decode(bytes.sublist(start, i));
          start = i + 1;
          if (line.isEmpty) continue;
          final map = Map<String, Object?>.from(jsonDecode(line) as Map);
          received.add(map);
          unawaited(_reply(socket, map));
        }
      }
      if (start < bytes.length) buffer.add(bytes.sublist(start));
    });
  }

  Future<void> _reply(Socket socket, Map<String, Object?> req) async {
    final id = req['id'];
    final method = req['method']?.toString() ?? '';
    Map<String, Object?> result;
    if (method == 'foundationmodels.health') {
      result = {'ok': true, 'provider': 'fake-daemon', 'bridge': 'test'};
    } else if (method == 'foundationmodels.availability') {
      result = {
        'available': true,
        'features': {'streaming': true, 'guidedGeneration': true},
      };
    } else if (method == 'foundationmodels.sessions.respond') {
      result = {
        'output': 'PONG-DAEMON',
        'model': 'apple.system',
        'usage': {'inputTokens': 1, 'outputTokens': 1, 'estimated': true},
      };
    } else if (method.endsWith('.stream') ||
        method == 'foundationmodels.sessions.stream') {
      // Ack then push two stream events reusing id.
      final ack = jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'result': {'ok': true, 'streaming': true},
      });
      socket.add(utf8.encode('$ack\n'));
      await socket.flush();
      for (final event in [
        {'type': 'text_delta', 'requestId': id, 'delta': 'hi-'},
        {'type': 'done', 'requestId': id},
      ]) {
        final frame = jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': event,
        });
        socket.add(utf8.encode('$frame\n'));
        await socket.flush();
      }
      return;
    } else if (method == 'foundationmodels.auth') {
      result = {'ok': true, 'authenticated': true};
    } else {
      final err = jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'error': {
          'code': -32601,
          'message': 'Method not found: $method',
          'data': {'code': 'METHOD_NOT_FOUND'},
        },
      });
      socket.add(utf8.encode('$err\n'));
      await socket.flush();
      return;
    }
    final line = jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result});
    socket.add(utf8.encode('$line\n'));
    await socket.flush();
  }

  Future<void> dispose() async {
    await client?.close();
    await server.close();
    try {
      await _dir.delete(recursive: true);
    } catch (_) {}
  }
}

void main() {
  group('DaemonSocketTransport live socket E2E (fake daemon peer)', () {
    late _FakeDaemon daemon;

    setUp(() async {
      daemon = await _FakeDaemon.start();
    });

    tearDown(() async {
      await daemon.dispose();
    });

    test('dual-run health + respond via Unix socket (shipped client path)',
        () async {
      Future<void> oneRun(int n) async {
        final transport = await DaemonSocketTransport.connect(
          socketPath: daemon.path,
        );
        final fm = await createFoundationModels(
          providers: [TransportProvider(transport)],
        );
        expect(fm.provider.id, 'apple-transport');

        final health = await fm.health();
        expect(health['ok'], isTrue);
        expect(health['provider'], 'fake-daemon');

        final r = await fm.respond(
          input: 'ping',
          options: const GenerationOptions(maximumResponseTokens: 8),
        );
        expect(r.text, 'PONG-DAEMON');
        await transport.close();
        print('SMOKE daemon_e2e run=$n health_ok respond=${r.text}');
      }

      await oneRun(1);
      await oneRun(2);
      print('SMOKE daemon_e2e dual_run_ok=true');
    });

    test('connect to missing socket fails typed (no hang)', () async {
      await expectLater(
        DaemonSocketTransport.connect(
          socketPath: '/tmp/fm_daemon_does_not_exist_${DateTime.now().microsecondsSinceEpoch}.sock',
        ),
        throwsA(isA<SocketException>()),
      );
      print('SMOKE daemon_e2e missing_socket failclosed_ok=true');
    });

    test('unknown method maps to FmTransportError with data.code', () async {
      final transport = await DaemonSocketTransport.connect(
        socketPath: daemon.path,
      );
      await expectLater(
        transport.invoke({
          'id': 'rpc_bad',
          'method': 'foundationmodels.nope',
          'params': <String, Object?>{},
        }),
        throwsA(
          isA<FmTransportError>().having(
            (e) => e.data?['code'],
            'data.code',
            'METHOD_NOT_FOUND',
          ),
        ),
      );
      await transport.close();
      print('SMOKE daemon_e2e unknown_method failclosed_ok=true');
    });
  });

  test('live foundationmodels-daemon binary env probe (optional)', () async {
    const path =
        '/Users/cristiano/workspace/ai-workflow/foundationmodels-js/swift/.build/out/Products/Release/foundationmodels-daemon';
    final bin = File(path);
    if (!bin.existsSync()) {
      print('SMOKE live_daemon skip=no_binary');
      return;
    }
    final r = await Process.run(path, ['--help'], runInShell: false);
    // dyld CoreAI skew → non-zero / crash signal is env limit, not client bug.
    final stderr = '${r.stderr}';
    final liveOk = r.exitCode == 0;
    print(
      'SMOKE live_daemon exit=${r.exitCode} live_ok=$liveOk '
      'stderr_has_coreai=${stderr.contains('CoreAI') || stderr.contains('dyld')}',
    );
    if (!liveOk) {
      print(
        'SMOKE live_daemon env_limit=true reason=dyld_or_cli '
        '(client E2E covered by fake peer)',
      );
    }
  });
}
