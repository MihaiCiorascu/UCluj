import 'package:flutter/material.dart';

/// Romanian Superliga 2024-25 club roster — Dart mirror of
/// ``backend/sportradar/team_registry.py``.
///
/// Each entry pairs the team's short label (the exact string the backend
/// auth API expects as ``teamName``), the team's badge asset path, and
/// the official club colours used by the per-team accent overlay
/// (Iteration N.8). The colour list was provided by the user and
/// cross-checked against the clubs' visual identities; tricolor teams
/// (Oţelul Galaţi, FC Hermannstadt, FC Botoşani) carry a third colour
/// via ``tertiaryColor``.
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
