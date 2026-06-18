import 'dart:io';

import 'package:airgapped_sentry/airgapped_sentry.dart';
import 'package:sentry/sentry.dart';

Future<void> main() async {
  await Sentry.init((options) async {
    options.dsn = Platform.environment['SENTRY_DSN'];
    options.compressPayload = false;
    options.httpClient = await AirgappedHttpClient.initialize(
      Platform.environment['SENTRY_LOG'] ?? "sentry.log",
    );
  }, appRunner: initApp);
}

void initApp() async {
  print('Hello World!');

  await Sentry.captureMessage(
    'Message 1',
    level: SentryLevel.warning,
    template: 'Message %s',
    params: ['1'],
  );

  await Sentry.captureException(
    Exception('Example exception'),
    stackTrace: StackTrace.current,
  );

  print('Bye World!');
}
