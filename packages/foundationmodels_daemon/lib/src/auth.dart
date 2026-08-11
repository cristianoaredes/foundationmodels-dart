import 'dart:convert';

import 'package:crypto/crypto.dart';

/// HMAC-SHA256 challenge-response for daemon auth domain
/// `foundationmodels.auth.v1`.
String foundationModelsAuthResponse({
  required String challenge,
  required String secret,
}) {
  final key = utf8.encode(secret);
  final message = utf8.encode('foundationmodels.auth.v1:$challenge');
  return Hmac(sha256, key).convert(message).toString();
}
