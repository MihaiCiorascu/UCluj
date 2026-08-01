import 'package:flutter/material.dart';

/// Romanian Superliga 2024-25 club roster — Dart mirror of
/// ``backend/sportradar/team_registry.py``.
///
/// Each entry pairs the team's short label (the exact string the backend
/// auth API expects as ``teamName``), the team's badge asset path, and
/// the official club colours used by the per-team accent overlay.
/// Tricolor teams (Oţelul Galaţi, FC Hermannstadt, FC Botoşani) carry a
/// third colour via ``tertiaryColor``.
class SuperligaTeam {
  const SuperligaTeam({
    required this.short,
    required this.displayName,
    required this.badgeAsset,
    required this.primaryColor,
    required this.secondaryColor,
    this.tertiaryColor,
  });

  /// Short name. Must match the backend's ``TeamRef.short`` exactly because
  /// it is the value submitted as ``teamName`` to ``signUpWithPassword``.
  final String short;

  /// Longer display label shown alongside the badge in the team picker.
  final String displayName;

  /// Path under ``assets/teams/`` (registered in pubspec.yaml).
  final String badgeAsset;

  /// Primary club colour, used for the AppScaffold header accent strip and
  /// the CTA-button gloss bias.
  final Color primaryColor;

  /// Secondary club colour. Used as the right half of the accent strip
  /// when the team has two official colours.
  final Color secondaryColor;

  /// Third colour for tricolor teams. Splits the accent strip 33/33/33
  /// when present.
  final Color? tertiaryColor;
}

const List<SuperligaTeam> kSuperligaTeams = <SuperligaTeam>[
  SuperligaTeam(
    short: "U Cluj",
    displayName: "FC Universitatea Cluj",
    badgeAsset: "assets/teams/universitatea_cluj.png",
    primaryColor: Color(0xFFFFFFFF),
    secondaryColor: Color(0xFF000000),
  ),
  SuperligaTeam(
    short: "U Craiova",
    displayName: "CS Universitatea Craiova",
    badgeAsset: "assets/teams/universitatea_craiova.png",
    primaryColor: Color(0xFF0049A4),
    secondaryColor: Color(0xFFFFFFFF),
  ),
  SuperligaTeam(
    short: "CFR Cluj",
    displayName: "CFR 1907 Cluj",
    badgeAsset: "assets/teams/cfr_cluj.png",
    primaryColor: Color(0xFF8B0000),
    secondaryColor: Color(0xFFFFFFFF),
  ),
  SuperligaTeam(
    short: "FCSB",
    displayName: "FCSB",
    badgeAsset: "assets/teams/fcsb.png",
    primaryColor: Color(0xFFE60012),
    secondaryColor: Color(0xFF0F3F8C),
  ),
  SuperligaTeam(
    short: "Dinamo Bucureşti",
    displayName: "Dinamo Bucureşti",
    badgeAsset: "assets/teams/dinamo_bucuresti.png",
    primaryColor: Color(0xFFE60012),
    secondaryColor: Color(0xFFFFFFFF),
  ),
  SuperligaTeam(
    short: "Rapid Bucureşti",
    displayName: "Rapid Bucureşti",
    badgeAsset: "assets/teams/rapid_bucuresti.png",
    primaryColor: Color(0xFF7B1E2F),
    secondaryColor: Color(0xFFFFFFFF),
  ),
  SuperligaTeam(
    short: "Farul Constanţa",
    displayName: "Farul Constanţa",
    badgeAsset: "assets/teams/farul_constanta.png",
    primaryColor: Color(0xFF0066CC),
    secondaryColor: Color(0xFFFFFFFF),
  ),
  SuperligaTeam(
    short: "UTA Arad",
    displayName: "UTA Arad",
    badgeAsset: "assets/teams/uta_arad.png",
    primaryColor: Color(0xFFE20613),
    secondaryColor: Color(0xFFFFFFFF),
  ),
  SuperligaTeam(
    short: "Petrolul Ploieşti",
    displayName: "Petrolul Ploieşti",
    badgeAsset: "assets/teams/petrolul_ploiesti.png",
    primaryColor: Color(0xFFFFD500),
    secondaryColor: Color(0xFF003399),
  ),
  SuperligaTeam(
    short: "Oţelul Galaţi",
    displayName: "Oţelul Galaţi",
    badgeAsset: "assets/teams/otelul_galati.png",
    primaryColor: Color(0xFFE20613),
    secondaryColor: Color(0xFFFFFFFF),
    tertiaryColor: Color(0xFF003399),
  ),
  SuperligaTeam(
    short: "Hermannstadt",
    displayName: "FC Hermannstadt",
    badgeAsset: "assets/teams/hermannstadt.png",
    primaryColor: Color(0xFFE20613),
    secondaryColor: Color(0xFFFFFFFF),
    tertiaryColor: Color(0xFF000000),
  ),
  SuperligaTeam(
    short: "Botoşani",
    displayName: "FC Botoşani",
    badgeAsset: "assets/teams/botosani.png",
    primaryColor: Color(0xFFE20613),
    secondaryColor: Color(0xFFFFFFFF),
    tertiaryColor: Color(0xFF003399),
  ),
  SuperligaTeam(
    short: "Unirea Slobozia",
    displayName: "Unirea Slobozia",
    badgeAsset: "assets/teams/unirea_slobozia.png",
    primaryColor: Color(0xFFFFD500),
    secondaryColor: Color(0xFF003399),
  ),
  SuperligaTeam(
    short: "FC Argeş",
    displayName: "FC Argeş Piteşti",
    badgeAsset: "assets/teams/arges_pitesti.png",
    primaryColor: Color(0xFF6A0DAD),
    secondaryColor: Color(0xFFFFFFFF),
  ),
  SuperligaTeam(
    short: "Csikszereda",
    displayName: "FK Csíkszereda Miercurea Ciuc",
    badgeAsset: "assets/teams/csikszereda.png",
    primaryColor: Color(0xFF7B1E2F),
    secondaryColor: Color(0xFF000000),
  ),
  SuperligaTeam(
    short: "Metaloglobus",
    displayName: "Metaloglobus Bucureşti",
    badgeAsset: "assets/teams/metaloglobus.png",
    primaryColor: Color(0xFF003399),
    secondaryColor: Color(0xFFFFD500),
  ),
];

/// Look up a team by its short label (case-insensitive). Returns ``null``
/// if no match.
SuperligaTeam? teamByShort(String? short) {
  if (short == null) return null;
  final key = short.trim().toLowerCase();
  for (final t in kSuperligaTeams) {
    if (t.short.toLowerCase() == key) return t;
    if (t.displayName.toLowerCase() == key) return t;
  }
  return null;
}

/// Normalise a team name for matching: lowercase, fold Romanian diacritics,
/// and strip non-alphanumeric characters to single spaces.
String _normalizeTeamName(String s) {
  final lowered = s.toLowerCase();
  final buf = StringBuffer();
  for (final ch in lowered.split('')) {
    switch (ch) {
      case 'ă':
      case 'â':
        buf.write('a');
      case 'î':
        buf.write('i');
      case 'ș':
      case 'ş':
        buf.write('s');
      case 'ț':
      case 'ţ':
        buf.write('t');
      default:
        if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
          buf.write(ch);
        } else {
          buf.write(' ');
        }
    }
  }
  return buf.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Raw name variants (Sportradar full names and CSV names) mapped to crest
/// assets, so a fixture's team string resolves regardless of which feed it
/// came from. Short and display names are handled separately via the team
/// list, so only the extra variants are listed here.
const Map<String, String> _kTeamNameAliases = <String, String>{
  // Sportradar full names
  'FC Universitatea Cluj': 'assets/teams/universitatea_cluj.png',
  'CS Universitatea Craiova': 'assets/teams/universitatea_craiova.png',
  'FC CFR 1907 Cluj': 'assets/teams/cfr_cluj.png',
  'Fotbal Club FCSB': 'assets/teams/fcsb.png',
  'Rapid Bucuresti 1923': 'assets/teams/rapid_bucuresti.png',
  'FC Dinamo Bucuresti 1948': 'assets/teams/dinamo_bucuresti.png',
  'FC Farul Constanta': 'assets/teams/farul_constanta.png',
  'AFC Hermannstadt': 'assets/teams/hermannstadt.png',
  'FC Uta Arad': 'assets/teams/uta_arad.png',
  'FC Petrolul Ploiesti': 'assets/teams/petrolul_ploiesti.png',
  'ASC Otelul Galati': 'assets/teams/otelul_galati.png',
  'AFK Csikszereda Miercurea Ciuc': 'assets/teams/csikszereda.png',
  'FC Unirea 2004 Slobozia': 'assets/teams/unirea_slobozia.png',
  'ACS Champions FC Arges': 'assets/teams/arges_pitesti.png',
  'FC Botosani': 'assets/teams/botosani.png',
  'Metaloglobus Bucuresti': 'assets/teams/metaloglobus.png',
  // CSV / short feed names
  'U Cluj': 'assets/teams/universitatea_cluj.png',
  'Univ. Craiova': 'assets/teams/universitatea_craiova.png',
  'U Craiova 1948': 'assets/teams/universitatea_craiova.png',
  'Rapid Bucuresti': 'assets/teams/rapid_bucuresti.png',
  'Dinamo Bucuresti': 'assets/teams/dinamo_bucuresti.png',
  'Farul Constanta': 'assets/teams/farul_constanta.png',
  'FC Hermannstadt': 'assets/teams/hermannstadt.png',
  'Petrolul Ploiesti': 'assets/teams/petrolul_ploiesti.png',
  'Otelul Galati': 'assets/teams/otelul_galati.png',
  'Csikszereda M. Ciuc': 'assets/teams/csikszereda.png',
  'FC Arges': 'assets/teams/arges_pitesti.png',
  'FC Botosani ': 'assets/teams/botosani.png',
};

final Map<String, String> _normalizedAliasAsset = <String, String>{
  for (final e in _kTeamNameAliases.entries) _normalizeTeamName(e.key): e.value,
  for (final t in kSuperligaTeams) _normalizeTeamName(t.short): t.badgeAsset,
  for (final t in kSuperligaTeams) _normalizeTeamName(t.displayName): t.badgeAsset,
};

/// Resolve any team name variant (short, display, Sportradar full name, or CSV
/// name, diacritic-insensitive) to its crest asset path, or ``null`` when no
/// confident match is found (the caller then shows a shield fallback).
String? badgeAssetForName(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  final key = _normalizeTeamName(name);
  if (key.isEmpty) return null;
  final direct = _normalizedAliasAsset[key];
  if (direct != null) return direct;
  // Loose containment as a last resort, guarded so very short tokens do not
  // produce false positives (for example "cluj" must not match two clubs).
  for (final e in _normalizedAliasAsset.entries) {
    if (e.key.length >= 6 && (key.contains(e.key) || e.key.contains(key))) {
      return e.value;
    }
  }
  return null;
}
