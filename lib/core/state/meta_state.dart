import 'package:flutter/foundation.dart';
import 'package:umbraro/core/observability/app_logger.dart';
import 'package:umbraro/core/services/api_client.dart';

/// Server-side meta exposed at `/api/v1/meta`. Fetched once at app start,
/// before authentication, so the UI can render a "DEMO MODE" ribbon as soon
/// as the first frame paints. Lives as a singleton so AppScaffold can listen
/// for it from anywhere in the widget tree without prop-drilling.
class MetaState extends ChangeNotifier {
  MetaState._();
  static final MetaState instance = MetaState._();

  bool _demoMode = false;
  String _demoToday = '';
  String _environment = '';
  bool _loaded = false;

  bool get demoMode => _demoMode;
  String get demoToday => _demoToday;
  String get environment => _environment;
  bool get loaded => _loaded;

  /// One-shot fetch of `/meta`. Silently no-ops on failure so the rest of the
  /// app keeps working even if the backend has not yet started; the ribbon
  /// simply will not appear. Safe to call multiple times.
  Future<void> init(ApiClient api) async {
    try {
      final body = await api.get('/meta');
      _demoMode = body['demo_mode'] == true;
      _demoToday = (body['demo_today'] as String?) ?? '';
      _environment = (body['environment'] as String?) ?? '';
      _loaded = true;
      notifyListeners();
    } catch (e) {
      AppLog.w('Failed to load /meta (demo-mode ribbon disabled): $e');
      // Leave defaults in place; ribbon will not render. AppLog.w only takes
      // a single string in this codebase, so the exception is interpolated.
    }
  }
}
