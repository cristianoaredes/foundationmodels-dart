import 'package:foundationmodels_daemon/foundationmodels_daemon.dart';
import 'package:test/test.dart';

void main() {
  test('auth response is stable HMAC for fixed challenge/secret', () {
    final a = foundationModelsAuthResponse(
      challenge: 'abc',
      secret: 's3cret',
    );
    final b = foundationModelsAuthResponse(
      challenge: 'abc',
      secret: 's3cret',
    );
    expect(a, b);
    expect(a, hasLength(64)); // sha256 hex
    expect(
      foundationModelsAuthResponse(challenge: 'abc', secret: 'other'),
      isNot(a),
    );
  });

  test('max line constant matches protocol 8 MiB', () {
    expect(kDaemonMaxLineBytes, 8 * 1024 * 1024);
  });
}
