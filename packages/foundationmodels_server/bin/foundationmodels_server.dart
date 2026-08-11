import 'dart:io';

import 'package:foundationmodels/foundationmodels.dart';
import 'package:foundationmodels_server/foundationmodels_server.dart';

Future<void> main(List<String> args) async {
  var host = '127.0.0.1';
  var port = 11435;
  String? bearer;
  var cors = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--host':
        host = args[++i];
      case '--port':
        port = int.parse(args[++i]);
      case '--bearer-token':
        bearer = args[++i];
      case '--cors':
        cors = true;
      case '--help':
        stdout.writeln(
          'usage: foundationmodels_server [--host H] [--port P] '
          '[--bearer-token T] [--cors]',
        );
        return;
    }
  }

  final fm = await createFoundationModels();
  final server = FmOpenAiServer(
    runtime: fm,
    host: host,
    port: port,
    bearerToken: bearer,
    cors: cors,
  );
  await server.start();
  stdout.writeln(
    'foundationmodels_server listening on http://$host:${server.boundPort} '
    '(provider=${fm.provider.id})',
  );
}
