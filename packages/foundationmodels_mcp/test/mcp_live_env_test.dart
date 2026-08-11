import 'dart:convert';
import 'dart:io';

import 'package:foundationmodels_mcp/foundationmodels_mcp.dart';
import 'package:test/test.dart';

/// TCK-0059 — live dual-run against remote MCP SSE/RPC endpoint.
///
/// Set `FM_MCP_SSE_URL` or `UAB_MCP_URL` to enable. Optional `FM_MCP_BEARER`.
/// When unset, records honest env_limit and skips (CI default).
void main() {
  test('live MCP dual-run (env-gated TCK-0059)', () async {
    final urlRaw = Platform.environment['FM_MCP_SSE_URL'] ??
        Platform.environment['UAB_MCP_URL'];
    if (urlRaw == null || urlRaw.isEmpty) {
      print(
        'SMOKE mcp_live skip=no_url '
        'env_limit=true reason=FM_MCP_SSE_URL_or_UAB_MCP_URL_unset '
        'reaffirmed=2026-08-11 (TCK-0059)',
      );
      return;
    }

    final rpcUrl = Uri.parse(urlRaw);
    final bearer = Platform.environment['FM_MCP_BEARER'];
    final headers = <String, String>{
      if (bearer != null && bearer.isNotEmpty)
        'Authorization': 'Bearer $bearer',
    };

    Future<String> httpPost(
      Uri url,
      Map<String, String> hdrs,
      String body,
    ) async {
      final client = HttpClient();
      try {
        final req = await client.postUrl(url);
        hdrs.forEach(req.headers.set);
        req.write(body);
        final res = await req.close().timeout(const Duration(seconds: 30));
        final text = await res.transform(utf8.decoder).join();
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HttpException(
            'HTTP ${res.statusCode}: $text',
            uri: url,
          );
        }
        return text;
      } finally {
        client.close(force: true);
      }
    }

    Future<void> oneRun(int n) async {
      final transport = McpSseTransport(
        rpcUrl: rpcUrl,
        headers: headers,
        httpPost: httpPost,
      );
      final client = FmMcpClient(transport: transport);
      try {
        final init = await client.initialize();
        expect(client.isInitialized, isTrue);
        final tools = await client.listTools();
        print(
          'SMOKE mcp_live run=$n init_ok tools=${tools.length} '
          'serverInfo=${init['serverInfo']}',
        );
        // Prefer a safe no-arg or list-only if no tools; try first tool only if present
        if (tools.isNotEmpty) {
          final name = tools.first['name'] as String? ?? '';
          if (name.isNotEmpty) {
            try {
              final text = await client.callTool(name, const {});
              print(
                'SMOKE mcp_live run=$n call_ok name=$name '
                'text_len=${text.length}',
              );
            } on Object catch (e) {
              // Live tools may require args — list+init is enough for dual-run health
              print('SMOKE mcp_live run=$n call_skip err=$e');
            }
          }
        }
      } finally {
        await client.close();
      }
    }

    await oneRun(1);
    await oneRun(2);
    print('SMOKE mcp_live dual_run_ok=true url_host=${rpcUrl.host}');
  });
}
