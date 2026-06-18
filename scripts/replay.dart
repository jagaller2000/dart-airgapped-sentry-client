import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  // Read DSN from environment variable SENTRY_DSN or from the first argument.
  final dsn =
      Platform.environment['SENTRY_DSN'] ?? (args.isNotEmpty ? args[0] : null);

  // Read log file path from environment variable SENTRY_LOG or from the second argument.
  final logFilePath =
      Platform.environment['SENTRY_LOG'] ?? (args.length > 1 ? args[1] : null);

  if (dsn == null || logFilePath == null) {
    stderr.writeln('Usage: dart replay.dart <SENTRY_DSN> <SENTRY_LOG>');
    stderr.writeln('Or set environment variables: SENTRY_DSN and SENTRY_LOG');
    exit(64);
  }

  Uri uri;
  try {
    uri = Uri.parse(dsn);
  } catch (e) {
    stderr.writeln('Invalid SENTRY_DSN: $e');
    exit(64);
  }

  final appId = uri.path;
  final client = HttpClient();
  try {
    final lines = File(logFilePath).readAsLinesSync();
    for (final line in lines) {
      if (line.isEmpty) continue;
      final Map<String, dynamic> logMessage = jsonDecode(line);
      final Map<String, String> headers = Map<String, String>.from(
        logMessage["headers"],
      );

      final endpoint = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: 'api$appId/envelope/',
      );

      try {
        final request = await client.postUrl(endpoint);
        headers.forEach((name, value) {
          request.headers.set(name, value);
        });

        final body = utf8.decode(logMessage["body"].cast<int>());
        request.write(body);

        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();
        print(
          '{"result:": {"statusCode": ${response.statusCode}, "body": "$responseBody"}}',
        );
      } catch (error) {
        print('{"error": "$error"}');
      }
    }
  } catch (e) {
    print('{"error": "$e"}');
  } finally {
    client.close();
  }
}
