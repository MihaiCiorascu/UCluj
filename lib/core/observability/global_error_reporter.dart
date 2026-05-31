import 'package:flutter/foundation.dart';
import 'package:umbraro/core/observability/app_logger.dart';

void installGlobalErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLog.e('flutter', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.e('platform', error, stack);
    return true;
  };
}
