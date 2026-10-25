import 'dart:convert';

import 'package:http/http.dart' as http;

import '../mail_exception.dart';
import '../transport.dart';

/// The base of the transports that call an HTTP API.
abstract class HttpTransport extends Transport {
  /// Pass a [client] to share one, or to test with a `MockClient`. Null:
  /// the transport makes its own and closes it in [close].
  HttpTransport(http.Client? client)
    : _ownClient = client == null,
      client = client ?? http.Client();

  final http.Client client;
  final bool _ownClient;

  /// the provider name for error messages, eg. `Resend`
  String get provider;

  /// POSTs [body] (a String or bytes) and gives the response. Throws a
  /// [MailException] when the status is not 2xx or the call fails.
  Future<http.Response> post(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
  }) async {
    http.Request request = http.Request('POST', uri)..headers.addAll(headers);
    if (body is String) {
      request.bodyBytes = utf8.encode(body);
    } else {
      request.bodyBytes = body as List<int>;
    }
    return sendRequest(request);
  }

  /// Sends [request]. Throws a [MailException] when the status is not
  /// 2xx or the call fails.
  Future<http.Response> sendRequest(http.BaseRequest request) async {
    http.Response response;
    try {
      response = await http.Response.fromStream(await client.send(request));
    } on MailException {
      rethrow;
    } catch (error) {
      throw MailException('$provider: the request failed: $error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MailException(
        '$provider: ${response.statusCode} ${response.body}',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
    return response;
  }

  /// The JSON object of [response], or an empty map.
  static Map<String, dynamic> json(http.Response response) {
    try {
      Object? data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) return data;
    } on FormatException {
      // not JSON: no id
    }
    return <String, dynamic>{};
  }

  @override
  Future<void> close() async {
    if (_ownClient) client.close();
  }
}
