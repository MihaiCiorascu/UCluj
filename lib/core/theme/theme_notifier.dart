import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton ChangeNotifier that owns dark/light mode state.
/// Persists the preference via SharedPreferences.
class ThemeNotifier extends ChangeNotifier {
  ThemeNotifier._();
  static final ThemeNotifier instance = ThemeNotifier._();

  bool _isDark = true;
  bool get isDark => _isDark;

  /// Call once at app startup (after WidgetsFlutterBinding.ensureInitialized).
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isDark = prefs.getBool('app_theme_dark') ?? true;
    notifyListeners();
  }

  /// Toggle between dark and light, persisting the choice.
  Future<void> toggle() async {
    _isDark = !_isDark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_theme_dark', _isDark);
  }
}
