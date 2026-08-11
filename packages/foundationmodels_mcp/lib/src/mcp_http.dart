import 'dart:convert';
import 'dart:io';

/// Default `httpPost` for [McpSseTransport] using [HttpClient].
///
/// Not used in CI; live tests inject this or their own client.
Future<String> mcpDefaultHttpPost(
  Uri url,
  Map<String, String> headers,
  String body,
) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(url);
    headers.forEach(req.headers.set);
    req.write(body);
    final res = await req.close().timeout(const Duration(seconds: 60));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('HTTP ${res.statusCode}: $text', uri: url);
    }
    return text;
  } finally {
    client.close(force: true);
  }
}
