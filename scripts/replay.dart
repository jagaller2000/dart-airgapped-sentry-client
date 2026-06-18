import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';

void main() async {
  String logFilePath = 'logs.txt';

  String dsn =
      "https://6853a1fa429e78d4011ca8d9f1f8841e@sentry.lets-byte.it/39";

  final uri = Uri.parse(dsn);
  final appId = uri.path; // includes leading '/'

  final client = Client();
  try {
    final lines = File(logFilePath).readAsLinesSync();
    for (final line in lines) {
      if (line.isEmpty) continue;
      final Map<String, dynamic> logMessage = jsonDecode(line);
      final Map<String, String> headers = Map<String, String>.from(
        logMessage["headers"],
      );

      headers['X-Sentry-Auth'] = headers['X-Sentry-Auth']!.replaceAll(
        'sentry_key=',
        'sentry_key=${uri.userInfo}',
      );

      final List<String> body = [];

      for (final chunk in logMessage["body"]) {
        body.add(jsonEncode(chunk));
      }

      final endpoint = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: 'api$appId/envelope/',
      );

      try {
        final response = await client.post(
          endpoint,
          headers: headers,
          body: "${body.join("\n")}\n",
        );
        print(
          'Response status: ${response.statusCode}, Body: ${response.body}',
        );
      } catch (error) {
        print('Error sending log: $error');
      }
    }
  } catch (e) {
    print('Error reading log file: $e');
  } finally {
    client.close();
  }
}
