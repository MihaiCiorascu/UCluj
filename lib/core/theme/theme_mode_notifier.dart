import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light/dark theme-mode preference, persisted via SharedPreferences so the
/// choice survives across app launches.
///
/// The notifier is initialised once at app boot (``bootstrap()`` reads the
/// stored value before constructing ``UmbraRoApp``). After construction
/// it is owned by ``UmbraRoApp`` and bound to ``MaterialApp.themeMode``;
/// the profile screen toggles it via ``setMode``.
class ThemeModeNotifier extends ChangeNotifier {
  ThemeModeNotifier(this._mode);

  static const String _prefsKey = "umbraro.theme_mode";

  ThemeMode _mode;

  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _serialise(mode));
    } catch (_) {
      // Persistence failure should not break the toggle.
    }
  }

  Future<void> toggle() {
    final next = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    return setMode(next);
  }

  /// Read the persisted preference (or fall back to ``ThemeMode.light``, the
  /// default) and return a primed notifier.
  static Future<ThemeModeNotifier> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      final mode = _parse(raw);
      return ThemeModeNotifier(mode);
    } catch (_) {
      return ThemeModeNotifier(ThemeMode.light);
    }
  }

  static String _serialise(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return "dark";
      case ThemeMode.light:
        return "light";
      case ThemeMode.system:
        return "system";
    }
  }

  static ThemeMode _parse(String? raw) {
    switch (raw) {
      case "dark":
        return ThemeMode.dark;
      case "system":
        return ThemeMode.system;
      case "light":
      default:
        return ThemeMode.light;
    }
  }
}
