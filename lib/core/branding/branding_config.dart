/// Single source of truth for the UmbraRo brand strings and logo asset
/// paths, so the brand can be swapped in one place.
///
/// The user's selected club is a separate concept (lives on the auth state
/// and surfaces as the per-team accent overlay); the UmbraRo identity is
/// what wraps the application as a whole.
class BrandingConfig {
  const BrandingConfig._();

  static const String appName = "UmbraRo";
  static const String tagline = "Tactical Intelligence";

  /// Full application title shown in the OS task switcher.
  static const String title = "$appName · $tagline";

  /// Square icon, used in the AppScaffold header and any 24-48 px slot.
  static const String logoIcon = "assets/branding/logo_icon.png";

  /// Full hero logo, used on the login / register splash and the marketing
  /// surfaces where the wordmark would be cramped.
  static const String logoFull = "assets/branding/logo_full.png";

  /// Horizontal wordmark — appears wherever the brand needs to coexist
  /// with another visual element on the same row.
  static const String wordmark = "assets/branding/umbraro_wordmark.png";
}
