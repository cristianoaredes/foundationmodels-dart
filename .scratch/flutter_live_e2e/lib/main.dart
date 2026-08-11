import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:foundationmodels/foundationmodels.dart';
import 'package:foundationmodels_apple/foundationmodels_apple.dart';

/// Live Flutter plugin E2E (public API only). Prints SMOKE_* lines and exits.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var rc = 0;
  try {
    final okAvail = await dual('availability', _smokeAvailability);
    final okRespond = await dual('respond', _smokeRespond);
    final okStream = await dual('stream_cancel', _smokeStreamCancel);
    final okDuplex = await dual('tools_duplex', _smokeToolsDuplex);
    if (!(okAvail && okRespond && okStream && okDuplex)) rc = 1;
    print(
      'SMOKE flutter_live summary avail=$okAvail respond=$okRespond '
      'stream_cancel=$okStream tools_duplex=$okDuplex',
    );
  } catch (e, st) {
    print('SMOKE flutter_live fatal=$e\n$st');
    rc = 1;
  }
  print('SMOKE_RC:$rc');
  // Give the engine a moment to flush logs, then exit.
  await Future<void>.delayed(const Duration(milliseconds: 200));
  exit(rc);
}

// Single transport for the process: EventChannel.receiveBroadcastStream must
// not be re-subscribed per call (native onCancel cancels all generations).
FoundationModels? _cachedFm;

Future<FoundationModels> _liveFm() async {
  if (_cachedFm != null) return _cachedFm!;
  final transport = createFoundationModelsAppleTransport();
  final provider = TransportProvider(transport);
  final fm = await createFoundationModels(providers: [provider]);
  if (fm.provider.id == 'mock') {
    throw StateError(
      'Fell back to mock — Apple transport unavailable. '
      'provider=${fm.provider.id}',
    );
  }
  _cachedFm = fm;
  return fm;
}

Future<bool> dual(String name, Future<bool> Function() body) async {
  final oks = <bool>[];
  for (var i = 1; i <= 2; i++) {
    print('SMOKE flutter_live $name run=$i start');
    try {
      final ok = await body();
      oks.add(ok);
      print('SMOKE flutter_live $name run=$i ok=$ok');
      if (!ok) {
        print('SMOKE flutter_live $name dual_run_ok=false');
        return false;
      }
    } catch (e, st) {
      print('SMOKE flutter_live $name run=$i error=$e\n$st');
      print('SMOKE flutter_live $name dual_run_ok=false');
      return false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }
  print('SMOKE flutter_live $name dual_run_ok=true results=$oks');
  return true;
}

Future<bool> _smokeAvailability() async {
  final fm = await _liveFm();
  print('SMOKE flutter_live provider=${fm.provider.id}');
  final avail = await fm.availability();
  print(
    'SMOKE flutter_live available=${avail.available} '
    'reasonCode=${avail.reasonCode}',
  );
  return avail.available;
}

Future<bool> _smokeRespond() async {
  final fm = await _liveFm();
  final r = await fm.respond(
    input: 'Reply with exactly the word PONG and nothing else.',
    instructions: 'Be terse. One word only.',
    options: const GenerationOptions(maximumResponseTokens: 16),
  );
  final text = r.text ?? '';
  final short = text.length > 120 ? text.substring(0, 120) : text;
  print('SMOKE flutter_live respond text=$short');
  return text.trim().isNotEmpty;
}

Future<bool> _smokeStreamCancel() async {
  final fm = await _liveFm();
  final cancelSource = CancelTokenSource();
  final types = <String>[];
  var sawDelta = false;
  try {
    final stream = fm.stream(
      input: 'Count from 1 to 20 slowly, one number per line.',
      options: const GenerationOptions(maximumResponseTokens: 64),
      cancelToken: cancelSource.token,
    );
    await for (final event in stream.timeout(
      const Duration(seconds: 45),
      onTimeout: (sink) {
        print('SMOKE flutter_live stream_cancel TIMEOUT types=$types sawDelta=$sawDelta');
        sink.addError(TimeoutException('stream cancel smoke timed out'));
        sink.close();
      },
    )) {
      types.add(event.type);
      print('SMOKE flutter_live stream_cancel event=${event.type}');
      if (event is TextDelta) {
        sawDelta = true;
        cancelSource.cancel();
      }
      if (event is StreamDone || event is StreamError) break;
    }
  } on GenerationCancelledException catch (e) {
    print('SMOKE flutter_live stream_cancel typed=$e types=$types');
    return sawDelta;
  } on TimeoutException catch (e) {
    print('SMOKE flutter_live stream_cancel timeout=$e types=$types');
    return false;
  } catch (e) {
    print('SMOKE flutter_live stream_cancel other_error=$e types=$types');
    // Accept: first delta then terminal error path.
    return sawDelta && types.any((t) => t == 'error' || t == 'done' || t == 'text_delta');
  }
  print('SMOKE flutter_live stream_cancel types=$types sawDelta=$sawDelta');
  return sawDelta;
}

Future<bool> _smokeToolsDuplex() async {
  final fm = await _liveFm();
  final types = <String>[];
  final buf = StringBuffer();
  var sawRequest = false;

  await for (final event in fm.stream(
    input:
        'Call get_secret_code with topic=parity, then reply with ONLY the code from the tool.',
    instructions:
        'You must use tools when available. Prefer tool results over guessing.',
    tools: [
      FmTool.callback(
        name: 'get_secret_code',
        description:
            'Returns a secret code. Always call this tool when asked for the secret code.',
        inputSchema: FmSchema.object(
          {'topic': FmSchema.string()},
          required: const ['topic'],
        ),
        callback: (args) async {
          print('SMOKE flutter_live duplex callback args=$args');
          return {'code': 'DUPLEX-99', 'source': 'flutter'};
        },
      ),
    ],
    autoExecuteTools: true,
    options: const GenerationOptions(maximumResponseTokens: 160),
  )) {
    types.add(event.type);
    if (event is ToolCallRequest) {
      sawRequest = true;
      print(
        'SMOKE flutter_live duplex tool_call_request '
        'id=${event.toolCallId} name=${event.toolName}',
      );
    }
    if (event is TextDelta) {
      buf.write(event.delta);
    }
    if (event is StreamDone || event is StreamError) break;
  }

  final text = buf.toString();
  final contentOk = text.toUpperCase().contains('DUPLEX-99');
  final ok = sawRequest && contentOk;
  final short = text.length > 200 ? text.substring(0, 200) : text;
  print(
    'SMOKE flutter_live duplex types=$types saw_request=$sawRequest '
    'content_ok=$contentOk text=$short',
  );
  print('SMOKE flutter_live tools_duplex_ok=$ok');
  return ok;
}
