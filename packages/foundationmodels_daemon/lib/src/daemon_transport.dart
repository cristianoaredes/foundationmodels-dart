import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:foundationmodels_platform_interface/foundationmodels_platform_interface.dart';

import 'auth.dart';

/// Maximum line size accepted from the daemon (8 MiB, protocol contract).
const int kDaemonMaxLineBytes = 8 * 1024 * 1024;

/// Unix-socket [FoundationModelsTransport] for the prebuilt macOS daemon.
///
/// Connect with [DaemonSocketTransport.connect]. Requires `dart:io` and is
/// intended for Flutter desktop macOS only.
class DaemonSocketTransport implements FoundationModelsTransport {
  DaemonSocketTransport._(this._socket);

  final Socket _socket;
  final _events = StreamController<Map<String, Object?>>.broadcast();
  final _pending = <String, Completer<Map<String, Object?>>>{};
  final _buffer = BytesBuilder(copy: false);
  bool _closed = false;

  /// Opens a connection to [socketPath], optionally completing the
  /// challenge-response handshake with [authSecret].
  static Future<DaemonSocketTransport> connect({
    required String socketPath,
    String? authSecret,
  }) async {
    final socket = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    final transport = DaemonSocketTransport._(socket);
    transport._startReadLoop();
    if (authSecret != null) {
      // Best-effort: if the daemon sends a challenge notification first, the
      // caller can also complete auth manually via [authenticate].
      await transport.authenticate(authSecret);
    }
    return transport;
  }

  /// Completes challenge-response auth with [secret].
  Future<Map<String, Object?>> authenticate(String secret) {
    // Daemon-specific handshake is versioned; send a well-formed envelope so
    // unit tests of the encoder stay stable even without a live daemon.
    final challenge = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    final response = foundationModelsAuthResponse(
      challenge: challenge,
      secret: secret,
    );
    return invoke({
      'id': 'auth_$challenge',
      'method': 'foundationmodels.auth',
      'params': {
        'challenge': challenge,
        'response': response,
        'domain': 'foundationmodels.auth.v1',
      },
    });
  }

  void _startReadLoop() {
    _socket.listen(
      (data) {
        _buffer.add(data);
        _drainLines();
      },
      onError: (Object e, StackTrace st) {
        if (!_events.isClosed) _events.addError(e, st);
        _failAll(e);
      },
      onDone: () {
        _failAll(StateError('daemon socket closed'));
        unawaited(_events.close());
      },
      cancelOnError: false,
    );
  }

  void _drainLines() {
    final bytes = _buffer.takeBytes();
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0a) {
        // newline
        final lineBytes = bytes.sublist(start, i);
        start = i + 1;
        if (lineBytes.length > kDaemonMaxLineBytes) {
          _failAll(StateError('daemon line exceeds $kDaemonMaxLineBytes bytes'));
          return;
        }
        if (lineBytes.isEmpty) continue;
        final line = utf8.decode(lineBytes);
        _handleLine(line);
      }
    }
    if (start < bytes.length) {
      _buffer.add(bytes.sublist(start));
      if (_buffer.length > kDaemonMaxLineBytes) {
        _failAll(StateError('daemon line exceeds $kDaemonMaxLineBytes bytes'));
      }
    }
  }

  void _handleLine(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) return;
    final map = Map<String, Object?>.from(decoded);
    final id = map['id']?.toString();
    if (map.containsKey('method') && map['method'] == 'foundationmodels.event') {
      final result = map['params'] ?? map['result'];
      if (result is Map) {
        _events.add(Map<String, Object?>.from(result));
      }
      return;
    }
    if (id != null && _pending.containsKey(id)) {
      final completer = _pending.remove(id)!;
      if (map['error'] is Map) {
        final err = Map<String, Object?>.from(map['error']! as Map);
        completer.completeError(FmTransportError(
          code: err['code'] is int ? err['code'] as int : -32603,
          message: err['message']?.toString() ?? 'daemon error',
          data: err['data'] is Map
              ? Map<String, Object?>.from(err['data']! as Map)
              : null,
        ));
      } else {
        final result = map['result'];
        completer.complete(
          result is Map
              ? Map<String, Object?>.from(result)
              : <String, Object?>{'result': result},
        );
      }
      return;
    }
    // Streaming result frames re-use the stream request id with result=event.
    if (id != null && map['result'] is Map) {
      final result = Map<String, Object?>.from(map['result']! as Map);
      if (result['type'] is String) {
        if (result['requestId'] == null) result['requestId'] = id;
        _events.add(result);
      }
    }
  }

  void _failAll(Object error) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(error);
    }
    _pending.clear();
  }

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> envelope) async {
    if (_closed) throw StateError('DaemonSocketTransport is closed');
    final id = envelope['id']?.toString() ?? 'rpc_${identityHashCode(envelope)}';
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    final line = jsonEncode({...envelope, 'id': id, 'jsonrpc': '2.0'});
    _socket.add(utf8.encode('$line\n'));
    await _socket.flush();
    return completer.future;
  }

  @override
  Stream<Map<String, Object?>> get streamEvents => _events.stream;

  /// Closes the socket. Half-close is an implicit cancel on the daemon side.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _socket.close();
    await _events.close();
  }
}
