import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Outcome of one connection probe against a Firefly base URL.
enum ProbeStatus {
  /// Server answered 2xx — base URL and (if sent) token are good enough.
  ok,

  /// Server answered 401/403 — the host is right, the token is not.
  unauthorized,

  /// Server answered some other status — reachable but not the endpoint we
  /// expect (reverse proxy login page, wrong path, 5xx).
  unexpectedStatus,

  /// No HTTP response at all: DNS, TLS, route (Tailscale down) or timeout.
  unreachable,
}

/// Result of [probeFirefly].
class ProbeResult {
  /// Creates a probe result.
  const new(this.status, {this.statusCode, this.detail});

  /// What the probe concluded.
  final ProbeStatus status;

  /// HTTP status when one was received, else null.
  final int? statusCode;

  /// Short human-readable context (exception text, body snippet).
  final String? detail;

  /// Whether the probe found a working Firefly at the URL.
  bool get isOk => status == ProbeStatus.ok;
}

/// Probes `GET {baseUrl}/api/v1/about` and reports what it learned (P2 §4).
///
/// `about` is the endpoint the pinned 6.7.9 container exposes
/// (`routes/api.php`, group `v1/about`); it is the cheapest authenticated
/// sanity check the app can make because it performs no writes and needs no
/// scope beyond ordinary API access. With a token the endpoint answers 200;
/// without, or with a revoked token, it answers 401/403 — which is itself a
/// useful result, so those are reported as [ProbeStatus.unauthorized] rather
/// than folded into a generic failure.
///
/// [client] and [timeout] are injectable so tests never touch the network.
Future<ProbeResult> probeFirefly({
  required String baseUrl,
  required String? pat,
  Duration timeout = const Duration(seconds: 4),
  http.Client? client,
}) async {
  final ownsClient = client == null;
  final httpc = client ?? http.Client();
  try {
    final uri = Uri.parse('$baseUrl/api/v1/about');
    final request = http.Request('GET', uri);
    if (pat != null && pat.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $pat';
    }
    final streamed =
        await httpc.send(request).timeout(timeout);
    final status = streamed.statusCode;
    if (status >= 200 && status < 300) {
      return const ProbeResult(ProbeStatus.ok, statusCode: 200);
    }
    if (status == 401 || status == 403) {
      return ProbeResult(ProbeStatus.unauthorized, statusCode: status);
    }
    return ProbeResult(ProbeStatus.unexpectedStatus, statusCode: status);
  } on TimeoutException {
    return const ProbeResult(ProbeStatus.unreachable, detail: 'timeout');
  } on SocketException catch (e) {
    return ProbeResult(ProbeStatus.unreachable, detail: e.message);
  } on TlsException catch (e) {
    return ProbeResult(
      ProbeStatus.unreachable,
      detail: e.message,
    );
  } on http.ClientException catch (e) {
    return ProbeResult(ProbeStatus.unreachable, detail: e.message);
  } on FormatException catch (e) {
    return ProbeResult(ProbeStatus.unreachable, detail: e.message);
  } finally {
    if (ownsClient) httpc.close();
  }
}
