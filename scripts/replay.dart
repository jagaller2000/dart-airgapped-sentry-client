import 'dart:convert';
import 'dart:io';

class _ReplayConfig {
  static const int maxRetries = 5;
  static const Duration defaultRetryDelay = Duration(seconds: 1);
}

void main(List<String> args) async {
  final dsn =
      Platform.environment['SENTRY_DSN'] ?? (args.isNotEmpty ? args[0] : null);
  final logFilePath =
      Platform.environment['SENTRY_LOG'] ?? (args.length > 1 ? args[1] : null);

  if (dsn == null || logFilePath == null) {
    stderr.writeln('Usage: dart replay.dart <SENTRY_DSN> <SENTRY_LOG>');
    stderr.writeln('Or set environment variables: SENTRY_DSN and SENTRY_LOG');
    exit(64);
  }

  final lockFilePath = '$logFilePath.lock';
  final startLineIndex = _readLastSuccessfulLineIndex(lockFilePath);

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
    for (
      var lineIndex = startLineIndex;
      lineIndex < lines.length;
      lineIndex++
    ) {
      final line = lines[lineIndex];
      if (line.isEmpty) {
        _writeLastSuccessfulLineIndex(lockFilePath, lineIndex);
        continue;
      }

      final Map<String, dynamic> logMessage = jsonDecode(line);
      final Map<String, String> headers = Map<String, String>.from(
        logMessage['headers'],
      );

      final endpoint = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: 'api$appId/envelope/',
      );

      final body = utf8.decode(logMessage['body'].cast<int>());
      var attempt = 0;
      var success = false;

      while (true) {
        attempt += 1;
        try {
          final request = await client.postUrl(endpoint);
          headers.forEach((name, value) {
            request.headers.set(name, value);
          });
          request.write(body);

          final response = await request.close();
          final responseBody = await response.transform(utf8.decoder).join();

          if (response.statusCode == 429 || response.statusCode == 503) {
            final delay =
                _parseRetryAfter(response.headers) ??
                _ReplayConfig.defaultRetryDelay;

            if (attempt >= _ReplayConfig.maxRetries) {
              print(
                '{"result":{"error":"rate limited after $attempt attempts","statusCode":${response.statusCode},"body":"$responseBody"},"success":false}',
              );
              break;
            }

            print(
              '{"result":{"warning":"rate limited, retrying after ${delay.inSeconds}s","statusCode":${response.statusCode}},"success":false}',
            );
            await Future.delayed(delay);
            continue;
          }

          print(
            '{"result":{"statusCode":${response.statusCode},"body":"$responseBody"},"success":true}',
          );
          success = true;
          break;
        } catch (error) {
          if (attempt >= _ReplayConfig.maxRetries) {
            print('{"result":{"error":"$error"},"success":false}');
            break;
          }
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (success) {
        _writeLastSuccessfulLineIndex(lockFilePath, lineIndex);
      }
    }
  } catch (e) {
    print('{"result":{"error":"$e"},"success":false}');
  } finally {
    client.close();
  }
}

Duration? _parseRetryAfter(HttpHeaders headers) {
  final retryAfter = headers.value('retry-after');
  if (retryAfter == null) return null;

  final seconds = int.tryParse(retryAfter);
  if (seconds != null) {
    return Duration(seconds: seconds);
  }

  try {
    final date = HttpDate.parse(retryAfter);
    final delay = date.difference(DateTime.now().toUtc());
    return delay.isNegative ? Duration.zero : delay;
  } catch (_) {
    return null;
  }
}

int _readLastSuccessfulLineIndex(String lockFilePath) {
  final lockFile = File(lockFilePath);
  if (!lockFile.existsSync()) return 0;

  try {
    final content = lockFile.readAsStringSync().trim();
    final index = int.parse(content);
    return index < 0 ? 0 : index + 1;
  } catch (_) {
    return 0;
  }
}

void _writeLastSuccessfulLineIndex(String lockFilePath, int lineIndex) {
  File(lockFilePath).writeAsStringSync(lineIndex.toString());
}

String _escapeJson(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
}
