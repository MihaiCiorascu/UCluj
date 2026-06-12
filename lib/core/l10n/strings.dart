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

  String _locale = 'en';
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
      // ignore — fall back to default 'en'
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
    'register.club': 'CLUBUL TĂU',
    'register.clubHint': 'Alege echipa',

    // Auth — field validation
    'validation.nameRequired': 'Introdu numele.',
    'validation.nameLength': 'Numele trebuie să aibă între 2 și 60 de caractere.',
    'validation.nameChars': 'Folosește litere, spații, cratime sau apostrofuri.',
    'validation.nameNoDigits': 'Numele nu poate conține cifre.',
    'validation.emailRequired': 'Introdu adresa de email.',
    'validation.emailInvalid': 'Introdu o adresă de email validă.',
    'validation.passwordRequired': 'Introdu parola.',
    'validation.passwordLength': 'Parola trebuie să aibă cel puțin 8 caractere.',
    'validation.passwordLetter': 'Adaugă cel puțin o literă.',
    'validation.passwordDigit': 'Adaugă cel puțin o cifră.',
    'validation.confirmRequired': 'Confirmă parola.',
    'validation.passwordMatch': 'Parolele nu coincid.',
    'validation.teamRequired': 'Alege un club.',

    // Auth — email verification
    'verify.title': 'VERIFICĂ EMAILUL',
    'verify.sentTo': 'Am trimis un cod din 6 cifre la {email}.',
    'verify.codeLabel': 'COD DE VERIFICARE',
    'verify.submit': 'VERIFICĂ',
    'verify.resend': 'Retrimite codul',
    'verify.resendIn': 'Retrimite în {s}s',
    'verify.backToLogin': 'ÎNAPOI LA AUTENTIFICARE',
    'verify.codeRequired': 'Introdu codul din 6 cifre.',
    'verify.errorMismatch': 'Codul nu este corect. Verifică și încearcă din nou.',
    'verify.errorExpired': 'Codul a expirat. Solicită unul nou.',
    'verify.errorLimit': 'Prea multe încercări. Așteaptă puțin și reîncearcă.',
    'verify.resent': 'Un cod nou este pe drum.',

    // Auth — error messages
    'auth.errorNotConfirmed': 'Verifică-ți emailul pentru a continua.',
    'auth.errorUserExists': 'Există deja un cont cu acest email.',
    'auth.errorInvalidCredentials': 'Email sau parolă incorecte.',
    'auth.errorGeneric': 'A apărut o eroare. Încearcă din nou.',

    // Dashboard
    'dashboard.errorTitle': 'Eroare la încărcare',
    'dashboard.retry': 'REÎNCEARCĂ',
    'dashboard.weekCurrent': 'RUNDA CURENTĂ',
    'dashboard.weekRelative': 'RUNDA',
    'dashboard.subjectResults': '{team} · REZULTAT',
    'dashboard.subjectThisRound': '{team} · ACEASTĂ RUNDĂ',
    'dashboard.subjectNextRound': '{team} · RUNDA VIITOARE',
    'dashboard.otherMatches': 'LIGA 1 · ALTE MECIURI',
    'dashboard.regularSeason': 'SEZON REGULAT',
    'dashboard.knockoutRound': 'Campionat / Retrogradare · Etapa {n}',
    'dashboard.playoff': 'GRUPA CAMPIONAT',
    'dashboard.playout': 'GRUPA RETROGRADARE',
    'dashboard.empty': 'Nu există meciuri în această rundă.',
    'dashboard.emptyBody': 'Reveniți după runda următoare pentru meciurile actualizate.',
    'dashboard.winChance': 'ȘANSĂ CÂȘTIG',
    'dashboard.analysis': 'ANALIZĂ',
    'dashboard.statusUpcoming': 'PRE-MECI',

    // Demo-mode ribbon
    'demoMode.label': 'MOD DEMO',
    'demoMode.fixturesFrom': 'meciuri din',

    // Starting XI empty state
    'xi.noPlayers': 'Niciun jucător disponibil',
    'xi.noPlayersBody': 'Alegeți un alt meci sau verificați conexiunea la sursa Wyscout.',

    // Match stats sheet
    'sheet.win': 'VICTORIE',
    'sheet.loss': 'ÎNFRÂNGERE',
    'sheet.draw': 'EGAL',
    'sheet.officialStats': 'STATISTICI OFICIALE',
    'sheet.statsEstimated': 'Estimat din date Wyscout pe jucător',
    'sheet.startingLineups': 'ECHIPE DE START',
    'sheet.subs': 'REZERVE',
    'pstat.title': 'STATISTICI JUCĂTOR',
    'pstat.minutes': 'Minute',
    'pstat.goals': 'Goluri',
    'pstat.assists': 'Pase decisive',
    'pstat.shots': 'Șuturi (pe poartă)',
    'pstat.passAccuracy': 'Acuratețe pase',
    'pstat.keyPasses': 'Pase cheie',
    'pstat.duelsWon': 'Dueluri câștigate',
    'pstat.dribbles': 'Driblinguri reușite',
    'pstat.interceptions': 'Intercepții',
    'pstat.recoveries': 'Recuperări',
    'pstat.saves': 'Intervenții',
    'pstat.goalsConceded': 'Goluri primite',
    'pstat.cleanSheet': 'Poartă nebătută',
    'pstat.passes': 'Pase',
    'pstat.clearances': 'Degajări',
    'pstat.minShort': 'min',
    'pstat.secAttacking': 'OFENSIVĂ',
    'pstat.secPassing': 'PASE',
    'pstat.secDefending': 'DEFENSIVĂ',
    'pstat.secShotStopping': 'INTERVENȚII',
    'pstat.secDistribution': 'DISTRIBUȚIE',
    'sheet.winChanceUcluj': 'ȘANSĂ DE CÂȘTIG · U CLUJ',
    'sheet.winChance': 'ȘANSĂ CÂȘTIG',
    'sheet.matchWinProbability': 'PROBABILITATE DE CÂȘTIG',
    'sheet.drawShort': 'EGAL',
    'sheet.playerGrade': 'NOTĂ',
    'sheet.outcomeWin': 'CÂȘTIG',
    'sheet.outcomeRest': 'EGAL + ÎNFRÂNGERE',
    'sheet.modelCaption': 'CatBoost · model binar (câștig vs. rest)',
    'sheet.keyDrivers': 'FACTORI CHEIE AI',
    'sheet.risks': 'RISCURI',
    'sheet.diagnosticPlan': 'DIAGNOSTIC · PLAN TACTIC',
    'sheet.diagnostic': 'DIAGNOSTIC',
    'sheet.recommendedXi': 'XI RECOMANDAT',
    'sheet.headToHead': 'CONFRUNTĂRI DIRECTE',
    'sheet.h2hDraws': 'EGALURI',
    'sheet.h2hLast': 'Ultimele {n}',
    'sheet.optimalPlan': 'PLAN TACTIC OPTIM',
    'sheet.projectedProb': 'PROBABILITATE',
    'sheet.projected': 'PROIECTATĂ',
    // Keep the simulation count in sync with settings.optimizer_num_simulations.
    'sheet.modelFooter': 'CatBoost · 25.000 simulări · date Liga 1 2020-2025',
    'sheet.baselineLabel': 'BAZĂ',
    'sheet.optimisedLabel': 'OPTIMIZAT',
    'sheet.upliftLabel': 'CREȘTERE',
    'sheet.verdictDominant': 'POZIȚIE DOMINANTĂ',
    'sheet.verdictFavoured': 'FAVORIT',
    'sheet.verdictContested': 'CONTESTAT',
    'sheet.verdictRisky': 'DEZAVANTAJAT',
    'sheet.tacticalLevers': 'PÂRGHII TACTICE',
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

    // Team / XI panel
    'team.statForm': 'Formă',
    'team.statFormTip': 'Forma medie recentă a titularilor',
    'team.statPerformance': 'Performanță',
    'team.statPerformanceTip': 'Scor mediu de performanță',
    'team.statPasses': 'Pase',
    'team.statPassesTip': 'Acuratețea paselor',
    'team.statDuels': 'Dueluri',
    'team.statDuelsTip': 'Dueluri câștigate',
    'team.segLikelyXi': 'PROBABIL XI',
    'team.segBestXi': 'CEL MAI BUN XI',
    'team.explainLikelyXi': 'Cei 11 cel mai probabil titulari (model de selecție)',
    'team.explainBestXi': 'Cei mai bine cotați 11, pe poziție (calitate brută)',
    'team.segOpponentXi': 'XI ADVERSAR',
    'team.explainOpponentXi': 'XI-ul probabil al adversarului (același model de selecție)',
    'team.explainOtherXi': 'XI-uri probabile pentru ambele echipe',
    'team.playerVolume': 'VOLUM DE JOC',
    'team.playerEfficiency': 'EFICIENȚĂ',
    'team.playerFitness': 'STARE FIZICĂ',
    'team.percentileInLeague': 'percentilă în ligă',
    'team.freshness': 'Prospețime',
    'team.daysRest': 'zile odihnă',
    'team.formationAuto': 'AUTO (optim)',
    'team.formationAutoTag': 'AUTO',
    'team.formation': 'FORMAȚIE',
    'team.formationChosen': 'FORMAȚIE ALEASĂ',
    'team.opponentFormation': 'FORMAȚIE ADVERSARĂ',
    'team.lockToSlot': 'FIXEAZĂ PE POZIȚIE',
    'team.replacePlayer': 'ÎNLOCUIEȘTE…',
    'team.unlock': 'DEBLOCHEAZĂ',
    'team.details': 'DETALII',
    'team.resetLocks': 'RESETEAZĂ',
    'team.locked': 'FIXAT',
    'team.choosePlayer': 'ALEGE UN JUCĂTOR',
    'team.noCompatiblePlayers': 'Niciun jucător compatibil disponibil',
    'team.applyingLineup': 'Se reoptimizează echipa…',
    'team.selTag': 'SEL',
    'team.selExplain': 'scor de selecție (modelul alege pe acest scor)',

    // Standings
    'standings.tabRegular': 'PRINCIPAL',
    'standings.tabChampionship': 'CAMPIONAT',
    'standings.tabRelegation': 'RETROGRADARE',
    'standings.emptyChampionship': 'Grupă Campionat nedisponibilă',
    'standings.emptyRelegation': 'Grupă Retrogradare nedisponibilă',
    'standings.groupNote': 'Clasament din sezonul regulat. Punctele se înjumătățesc când încep grupele campionat și retrogradare.',
    'standings.recordAbbr': 'V-E-Î',
    'standings.colPlayed': 'MJ',
    'standings.colWins': 'V',
    'standings.colDraws': 'E',
    'standings.colLosses': 'Î',
    'standings.colGD': 'DG',
    'standings.colPts': 'PCT',
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
    'register.club': 'YOUR CLUB',
    'register.clubHint': 'Pick your team',

    // Auth — field validation
    'validation.nameRequired': 'Please enter your name.',
    'validation.nameLength': 'Name must be 2 to 60 characters.',
    'validation.nameChars': 'Use letters, spaces, hyphens or apostrophes.',
    'validation.nameNoDigits': "Names can't contain numbers.",
    'validation.emailRequired': 'Please enter your email.',
    'validation.emailInvalid': 'Enter a valid email address.',
    'validation.passwordRequired': 'Please enter your password.',
    'validation.passwordLength': 'Password must be at least 8 characters.',
    'validation.passwordLetter': 'Add at least one letter.',
    'validation.passwordDigit': 'Add at least one number.',
    'validation.confirmRequired': 'Please confirm your password.',
    'validation.passwordMatch': "Passwords don't match.",
    'validation.teamRequired': 'Pick a club.',

    // Auth — email verification
    'verify.title': 'VERIFY YOUR EMAIL',
    'verify.sentTo': 'We sent a 6-digit code to {email}.',
    'verify.codeLabel': 'VERIFICATION CODE',
    'verify.submit': 'VERIFY',
    'verify.resend': 'Resend code',
    'verify.resendIn': 'Resend in {s}s',
    'verify.backToLogin': 'BACK TO SIGN IN',
    'verify.codeRequired': 'Enter the 6-digit code.',
    'verify.errorMismatch': "That code isn't right. Check and try again.",
    'verify.errorExpired': 'That code expired. Request a new one.',
    'verify.errorLimit': 'Too many attempts. Wait a moment and retry.',
    'verify.resent': 'A new code is on its way.',

    // Auth — error messages
    'auth.errorNotConfirmed': 'Please verify your email to continue.',
    'auth.errorUserExists': 'An account with this email already exists.',
    'auth.errorInvalidCredentials': 'Incorrect email or password.',
    'auth.errorGeneric': 'Something went wrong. Please try again.',

    // Dashboard
    'dashboard.errorTitle': 'Loading error',
    'dashboard.retry': 'RETRY',
    'dashboard.weekCurrent': 'CURRENT ROUND',
    'dashboard.weekRelative': 'ROUND',
    'dashboard.subjectResults': '{team} · RESULT',
    'dashboard.subjectThisRound': '{team} · THIS ROUND',
    'dashboard.subjectNextRound': '{team} · NEXT ROUND',
    'dashboard.otherMatches': 'LIGA 1 · OTHER MATCHES',
    'dashboard.regularSeason': 'REGULAR SEASON',
    'dashboard.knockoutRound': 'Championship / Relegation · Round {n}',
    'dashboard.playoff': 'CHAMPIONSHIP GROUP',
    'dashboard.playout': 'RELEGATION GROUP',
    'dashboard.empty': 'No matches in this round.',
    'dashboard.emptyBody': 'Check back after the next matchday for refreshed fixtures.',
    'dashboard.winChance': 'WIN CHANCE',
    'dashboard.analysis': 'ANALYSIS',
    'dashboard.statusUpcoming': 'PRE-MATCH',

    // Demo-mode ribbon
    'demoMode.label': 'DEMO MODE',
    'demoMode.fixturesFrom': 'fixtures from',

    // Starting XI empty state
    'xi.noPlayers': 'No players available',
    'xi.noPlayersBody': 'Pick another fixture or check the Wyscout feed connection.',

    // Match stats sheet
    'sheet.win': 'WIN',
    'sheet.loss': 'LOSS',
    'sheet.draw': 'DRAW',
    'sheet.officialStats': 'OFFICIAL STATS',
    'sheet.statsEstimated': 'Estimated from Wyscout per-player data',
    'sheet.startingLineups': 'STARTING LINEUPS',
    'sheet.subs': 'SUBSTITUTES',
    'pstat.title': 'PLAYER STATS',
    'pstat.minutes': 'Minutes',
    'pstat.goals': 'Goals',
    'pstat.assists': 'Assists',
    'pstat.shots': 'Shots (on target)',
    'pstat.passAccuracy': 'Pass accuracy',
    'pstat.keyPasses': 'Key passes',
    'pstat.duelsWon': 'Duels won',
    'pstat.dribbles': 'Dribbles completed',
    'pstat.interceptions': 'Interceptions',
    'pstat.recoveries': 'Recoveries',
    'pstat.saves': 'Saves',
    'pstat.goalsConceded': 'Goals conceded',
    'pstat.cleanSheet': 'Clean sheet',
    'pstat.passes': 'Passes',
    'pstat.clearances': 'Clearances',
    'pstat.minShort': 'min',
    'pstat.secAttacking': 'ATTACKING',
    'pstat.secPassing': 'PASSING',
    'pstat.secDefending': 'DEFENDING',
    'pstat.secShotStopping': 'SHOT-STOPPING',
    'pstat.secDistribution': 'DISTRIBUTION',
    'sheet.winChanceUcluj': 'WIN CHANCE · U CLUJ',
    'sheet.winChance': 'WIN CHANCE',
    'sheet.matchWinProbability': 'WIN PROBABILITY',
    'sheet.drawShort': 'DRAW',
    'sheet.playerGrade': 'GRADE',
    'sheet.outcomeWin': 'WIN',
    'sheet.outcomeRest': 'DRAW + LOSS',
    'sheet.modelCaption': 'CatBoost · binary model (win vs. rest)',
    'sheet.keyDrivers': 'AI KEY DRIVERS',
    'sheet.risks': 'RISKS',
    'sheet.diagnosticPlan': 'DIAGNOSTIC · TACTICAL PLAN',
    'sheet.diagnostic': 'DIAGNOSTIC',
    'sheet.recommendedXi': 'RECOMMENDED XI',
    'sheet.headToHead': 'HEAD TO HEAD',
    'sheet.h2hDraws': 'DRAWS',
    'sheet.h2hLast': 'Last {n}',
    'sheet.optimalPlan': 'OPTIMAL TACTICAL PLAN',
    'sheet.projectedProb': 'PROBABILITY',
    'sheet.projected': 'PROJECTED',
    // Keep the simulation count in sync with settings.optimizer_num_simulations.
    'sheet.modelFooter': 'CatBoost · 25,000 simulations · Liga 1 2020-2025 data',
    'sheet.baselineLabel': 'BASELINE',
    'sheet.optimisedLabel': 'OPTIMISED',
    'sheet.upliftLabel': 'UPLIFT',
    'sheet.verdictDominant': 'DOMINANT POSITION',
    'sheet.verdictFavoured': 'FAVOURED',
    'sheet.verdictContested': 'CONTESTED',
    'sheet.verdictRisky': 'AT RISK',
    'sheet.tacticalLevers': 'TACTICAL LEVERS',
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

    // Team / XI panel
    'team.statForm': 'Form',
    'team.statFormTip': 'Recent average form of the starters',
    'team.statPerformance': 'Performance',
    'team.statPerformanceTip': 'Average performance score',
    'team.statPasses': 'Passing',
    'team.statPassesTip': 'Pass accuracy',
    'team.statDuels': 'Duels',
    'team.statDuelsTip': 'Duels won',
    'team.segLikelyXi': 'LIKELY XI',
    'team.segBestXi': 'BEST XI',
    'team.explainLikelyXi': 'The 11 most likely starters (selection model)',
    'team.explainBestXi': 'The top-rated 11 by position (raw quality)',
    'team.segOpponentXi': 'OPPONENT XI',
    'team.explainOpponentXi': 'Likely XI of the opponent (same selection model)',
    'team.explainOtherXi': 'Predicted starting XIs for both clubs',
    'team.playerVolume': 'GAME VOLUME',
    'team.playerEfficiency': 'EFFICIENCY',
    'team.playerFitness': 'PHYSICAL STATE',
    'team.percentileInLeague': 'league percentile',
    'team.freshness': 'Freshness',
    'team.daysRest': 'days rest',
    'team.formationAuto': 'AUTO (best)',
    'team.formationAutoTag': 'AUTO',
    'team.formation': 'FORMATION',
    'team.formationChosen': 'CHOSEN SHAPE',
    'team.opponentFormation': 'OPPONENT SHAPE',
    'team.lockToSlot': 'LOCK TO SLOT',
    'team.replacePlayer': 'REPLACE…',
    'team.unlock': 'UNLOCK',
    'team.details': 'DETAILS',
    'team.resetLocks': 'RESET',
    'team.locked': 'LOCKED',
    'team.choosePlayer': 'CHOOSE A PLAYER',
    'team.noCompatiblePlayers': 'No compatible players available',
    'team.applyingLineup': 'Re-optimising lineup…',
    'team.selTag': 'SEL',
    'team.selExplain': 'selection score (the model picks on this)',

    // Standings
    'standings.tabRegular': 'REGULAR',
    'standings.tabChampionship': 'CHAMPIONSHIP',
    'standings.tabRelegation': 'RELEGATION',
    'standings.emptyChampionship': 'Championship group unavailable',
    'standings.emptyRelegation': 'Relegation group unavailable',
    'standings.groupNote': 'Regular-season standings. Points halve when the championship and relegation groups begin.',
    'standings.recordAbbr': 'W-D-L',
    'standings.colPlayed': 'P',
    'standings.colWins': 'W',
    'standings.colDraws': 'D',
    'standings.colLosses': 'L',
    'standings.colGD': 'GD',
    'standings.colPts': 'PTS',
  };
}
