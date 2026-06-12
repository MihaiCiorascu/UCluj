/// Pure, locale-agnostic auth field validators.
///
/// Each function returns `null` when the value is acceptable, or an `L10n`
/// key that the calling screen resolves through `L10n.t(...)`. The rules are
/// deliberately permissive so that real names (with spaces, diacritics,
/// hyphens, apostrophes) and ordinary work emails pass without friction, while
/// empty or junk input is rejected.
class AuthValidators {
  AuthValidators._();

  // A name starts with a letter and then allows letters (any script, so
  // Romanian diacritics work), spaces, periods, apostrophes, and hyphens.
  static final RegExp _nameAllowed =
      RegExp(r"^[\p{L}][\p{L} .'\-]*$", unicode: true);
  static final RegExp _hasDigit = RegExp(r'\d');
  static final RegExp _hasLetter = RegExp(r'[A-Za-z]');
  // Permissive RFC-lite: exactly one @, no whitespace, a dot in the domain.
  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp _nonDigit = RegExp(r'\D');

  /// Trim and lowercase an email before it is sent to the backend, so the
  /// local `users.email` row stays consistent (Cognito is case-insensitive).
  static String normalizeEmail(String raw) => raw.trim().toLowerCase();

  static String? fullName(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 'validation.nameRequired';
    final len = v.runes.length;
    if (len < 2 || len > 60) return 'validation.nameLength';
    if (_hasDigit.hasMatch(v)) return 'validation.nameNoDigits';
    if (!_nameAllowed.hasMatch(v)) return 'validation.nameChars';
    return null;
  }

  static String? email(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 'validation.emailRequired';
    if (!_email.hasMatch(v)) return 'validation.emailInvalid';
    return null;
  }

  /// Sign-up password rule: at least 8 characters with one letter and one
  /// digit. Mild and predictable, not aggressive.
  static String? password(String raw) {
    if (raw.length < 8) return 'validation.passwordLength';
    if (!_hasLetter.hasMatch(raw)) return 'validation.passwordLetter';
    if (!_hasDigit.hasMatch(raw)) return 'validation.passwordDigit';
    return null;
  }

  static String? confirm(String pass, String confirm) {
    if (confirm.isEmpty) return 'validation.confirmRequired';
    if (pass != confirm) return 'validation.passwordMatch';
    return null;
  }

  /// The 6-digit email confirmation code.
  static String? code(String raw) {
    final v = raw.trim();
    if (v.length != 6 || _nonDigit.hasMatch(v)) return 'verify.codeRequired';
    return null;
  }
}
