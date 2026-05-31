import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight i18n: a global ChangeNotifier holding the active locale plus
/// a flat key → {ro, en} translation table. UI screens call `L10n.t(key)` and
/// rebuild via `ListenableBuilder(listenable: L10n.instance, ...)` at the app
/// root so a single notifyListeners() refreshes every translated widget.
class L10n extends ChangeNotifier {
  L10n._();
  static final L10n instance = L10n._();

  static const _prefsKey = 'app_locale';
  static const _supported = ['ro', 'en'];

  String _locale = 'ro';
  String get locale => _locale;
  bool get isRomanian => _locale == 'ro';
  bool get isEnglish => _locale == 'en';

  /// Load saved locale from SharedPreferences (call once at bootstrap).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null && _supported.contains(saved)) {
        _locale = saved;
      }
    } catch (_) {
      // ignore — fall back to default 'ro'
    }
  }

  Future<void> setLocale(String locale) async {
    if (!_supported.contains(locale) || locale == _locale) return;
    _locale = locale;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, locale);
    } catch (_) {}
  }

  /// Look up a translation. Falls back to Romanian, then to the key itself.
  static String t(String key) {
    final loc = instance._locale;
    return _strings[loc]?[key] ?? _strings['ro']?[key] ?? key;
  }

  // ─── Translation table ────────────────────────────────────────────────────
  static const Map<String, Map<String, String>> _strings = {
    'ro': _ro,
    'en': _en,
  };

  static const Map<String, String> _ro = {
    // Bottom nav
    'nav.dashboard': 'PANOU',
    'nav.standings': 'CLASAMENT',
    'nav.chat': 'CHAT',

    // Auth — login
    'login.tagline': 'PLATFORMĂ DE INTELLIGENCE TACTICĂ',
    'login.title': 'AUTENTIFICARE',
    'login.email': 'EMAIL',
    'login.password': 'PAROLĂ',
    'login.submit': 'INTRĂ',
    'login.noAccount': 'NU AI CONT?',
    'login.register': 'ÎNREGISTREAZĂ-TE',

    // Auth — register
    'register.title': 'CREEAZĂ CONTUL',
    'register.fullName': 'NUME COMPLET',
    'register.email': 'EMAIL',
    'register.password': 'PAROLĂ',
    'register.confirmPassword': 'CONFIRMĂ PAROLA',
    'register.submit': 'ÎNREGISTREAZĂ-TE',
    'register.haveAccount': 'AI DEJA CONT?',
    'register.signIn': 'AUTENTIFICĂ-TE',
    'register.errorRequired': 'Toate câmpurile sunt obligatorii',
    'register.errorPasswordLen': 'Parola trebuie să aibă cel puțin 8 caractere',
    'register.errorPasswordMatch': 'Parolele nu coincid',

    // Dashboard
    'dashboard.errorTitle': 'Eroare la încărcare',
    'dashboard.retry': 'REÎNCEARCĂ',
    'dashboard.weekCurrent': 'SĂPTĂMÂNA CURENTĂ',
    'dashboard.weekRelative': 'SĂPTĂMÂNA',
    'dashboard.uclujResults': 'U CLUJ — REZULTATE',
    'dashboard.uclujThisWeek': 'U CLUJ — ACEASTĂ SĂPTĂMÂNĂ',
    'dashboard.uclujNextRound': 'U CLUJ — RUNDA VIITOARE',
    'dashboard.otherMatches': 'LIGA 1 — ALTE MECIURI',
    'dashboard.empty': 'Nu există meciuri această săptămână.',
    'dashboard.winChance': 'ȘANSĂ CÂȘTIG',
    'dashboard.analysis': 'ANALIZĂ',

    // Demo-mode ribbon
    'demoMode.label': 'MOD DEMO',
    'demoMode.fixturesFrom': 'meciuri din',

    // Match stats sheet
    'sheet.win': 'VICTORIE',
    'sheet.loss': 'ÎNFRÂNGERE',
    'sheet.draw': 'EGAL',
    'sheet.officialStats': 'STATISTICI OFICIALE',
    'sheet.startingLineups': 'ECHIPE DE START',
    'sheet.subs': 'REZERVE',
    'sheet.winChanceUcluj': 'ȘANSĂ DE CÂȘTIG — U CLUJ',
    'sheet.outcomeWin': 'CÂȘTIG',
    'sheet.outcomeRest': 'EGAL + ÎNFRÂNGERE',
    'sheet.modelCaption': 'CatBoost · model binar (câștig vs. rest)',
    'sheet.keyDrivers': 'FACTORI CHEIE AI',
    'sheet.risks': 'RISCURI',
    'sheet.diagnosticPlan': 'DIAGNOSTIC — PLAN TACTIC',
    'sheet.diagnostic': 'DIAGNOSTIC',
    'sheet.recommendedXi': 'XI RECOMANDAT',
    'sheet.optimalPlan': 'PLAN TACTIC OPTIM',
    'sheet.projectedProb': 'PROBABILITATE',
    'sheet.projected': 'PROIECTATĂ',
    'sheet.modelFooter': 'CatBoost · 800 simulări · date Liga 1 2020–2025',
    'sheet.statPossession': 'POSESIE',
    'sheet.statShotsOnTarget': 'ȘUTURI PE POARTĂ',
    'sheet.statShotsTotal': 'ȘUTURI TOTALE',
    'sheet.statCorners': 'CORNERE',
    'sheet.statOffsides': 'OFSAIDURI',
    'sheet.statFouls': 'FAULTURI',
    'sheet.statYellow': 'CARTONAȘE GALBENE',
    'sheet.xiUnavailable': 'XI indisponibil',

    // Profile
    'profile.title': 'PROFIL',
    'profile.tabOverview': 'PREZENTARE',
    'profile.tabAccount': 'CONT',
    'profile.workspace': 'SPAȚIU DE LUCRU',
    'profile.defaultClub': 'CLUB IMPLICIT',
    'profile.email': 'EMAIL',
    'profile.role': 'ROL',
    'profile.language': 'LIMBĂ',
    'profile.club': 'CLUB',
    'profile.access': 'ACCES',
    'profile.planAccess': 'PLAN & ACCES',
    'profile.security': 'SECURITATE',
    'profile.securityValue': 'Acces JWT Standard',
    'profile.notifications': 'NOTIFICĂRI',
    'profile.notificationsValue': 'Activate',
    'profile.logout': 'DECONECTARE',
    'profile.footer': 'U CLUJ v0.1.0  ·  THESIS BUILD',
    'profile.languageRomanian': 'Română',
    'profile.languageEnglish': 'English',
    'profile.coach': 'ANTRENOR',

    // Chat
    'chat.title': 'CHAT ECHIPĂ',
    'chat.createGroup': 'CREEAZĂ GRUP',
    'chat.groupName': 'Nume grup',
    'chat.cancel': 'Anulează',
    'chat.create': 'Creează',
    'chat.empty': 'NICIUN MESAJ ÎNCĂ',
    'chat.typing': 'SCRIE...',
    'chat.writeMessage': 'Scrie un mesaj...',
    'chat.channel': 'CANAL',
  };

  static const Map<String, String> _en = {
    // Bottom nav
    'nav.dashboard': 'DASHBOARD',
    'nav.standings': 'STANDINGS',
    'nav.chat': 'CHAT',

    // Auth — login
    'login.tagline': 'TACTICAL INTELLIGENCE PLATFORM',
    'login.title': 'SIGN IN',
    'login.email': 'EMAIL',
    'login.password': 'PASSWORD',
    'login.submit': 'LOGIN',
    'login.noAccount': "DON'T HAVE AN ACCOUNT?",
    'login.register': 'REGISTER',

    // Auth — register
    'register.title': 'CREATE YOUR ACCOUNT',
    'register.fullName': 'FULL NAME',
    'register.email': 'EMAIL',
    'register.password': 'PASSWORD',
    'register.confirmPassword': 'CONFIRM PASSWORD',
    'register.submit': 'REGISTER',
    'register.haveAccount': 'ALREADY HAVE AN ACCOUNT?',
    'register.signIn': 'SIGN IN',
    'register.errorRequired': 'All fields are required',
    'register.errorPasswordLen': 'Password must be at least 8 characters',
    'register.errorPasswordMatch': 'Passwords do not match',

    // Dashboard
    'dashboard.errorTitle': 'Loading error',
    'dashboard.retry': 'RETRY',
    'dashboard.weekCurrent': 'CURRENT WEEK',
    'dashboard.weekRelative': 'WEEK',
    'dashboard.uclujResults': 'U CLUJ — RESULTS',
    'dashboard.uclujThisWeek': 'U CLUJ — THIS WEEK',
    'dashboard.uclujNextRound': 'U CLUJ — NEXT ROUND',
    'dashboard.otherMatches': 'LIGA 1 — OTHER MATCHES',
    'dashboard.empty': 'No matches this week.',
    'dashboard.winChance': 'WIN CHANCE',
    'dashboard.analysis': 'ANALYSIS',

    // Demo-mode ribbon
    'demoMode.label': 'DEMO MODE',
    'demoMode.fixturesFrom': 'fixtures from',

    // Match stats sheet
    'sheet.win': 'WIN',
    'sheet.loss': 'LOSS',
    'sheet.draw': 'DRAW',
    'sheet.officialStats': 'OFFICIAL STATS',
    'sheet.startingLineups': 'STARTING LINEUPS',
    'sheet.subs': 'SUBSTITUTES',
    'sheet.winChanceUcluj': 'WIN CHANCE — U CLUJ',
    'sheet.outcomeWin': 'WIN',
    'sheet.outcomeRest': 'DRAW + LOSS',
    'sheet.modelCaption': 'CatBoost · binary model (win vs. rest)',
    'sheet.keyDrivers': 'AI KEY DRIVERS',
    'sheet.risks': 'RISKS',
    'sheet.diagnosticPlan': 'DIAGNOSTIC — TACTICAL PLAN',
    'sheet.diagnostic': 'DIAGNOSTIC',
    'sheet.recommendedXi': 'RECOMMENDED XI',
    'sheet.optimalPlan': 'OPTIMAL TACTICAL PLAN',
    'sheet.projectedProb': 'PROBABILITY',
    'sheet.projected': 'PROJECTED',
    'sheet.modelFooter': 'CatBoost · 800 simulations · Liga 1 2020–2025 data',
    'sheet.statPossession': 'POSSESSION',
    'sheet.statShotsOnTarget': 'SHOTS ON TARGET',
    'sheet.statShotsTotal': 'TOTAL SHOTS',
    'sheet.statCorners': 'CORNERS',
    'sheet.statOffsides': 'OFFSIDES',
    'sheet.statFouls': 'FOULS',
    'sheet.statYellow': 'YELLOW CARDS',
    'sheet.xiUnavailable': 'XI unavailable',

    // Profile
    'profile.title': 'PROFILE',
    'profile.tabOverview': 'OVERVIEW',
    'profile.tabAccount': 'ACCOUNT',
    'profile.workspace': 'WORKSPACE',
    'profile.defaultClub': 'DEFAULT CLUB',
    'profile.email': 'EMAIL',
    'profile.role': 'ROLE',
    'profile.language': 'LANGUAGE',
    'profile.club': 'CLUB',
    'profile.access': 'ACCESS',
    'profile.planAccess': 'PLAN & ACCESS',
    'profile.security': 'SECURITY',
    'profile.securityValue': 'Standard JWT Access',
    'profile.notifications': 'NOTIFICATIONS',
    'profile.notificationsValue': 'Enabled',
    'profile.logout': 'LOG OUT',
    'profile.footer': 'U CLUJ v0.1.0  ·  THESIS BUILD',
    'profile.languageRomanian': 'Română',
    'profile.languageEnglish': 'English',
    'profile.coach': 'COACH',

    // Chat
    'chat.title': 'TEAM CHAT',
    'chat.createGroup': 'CREATE GROUP',
    'chat.groupName': 'Group name',
    'chat.cancel': 'Cancel',
    'chat.create': 'Create',
    'chat.empty': 'NO MESSAGES YET',
    'chat.typing': 'IS TYPING...',
    'chat.writeMessage': 'Write a message...',
    'chat.channel': 'CHANNEL',
  };
}
