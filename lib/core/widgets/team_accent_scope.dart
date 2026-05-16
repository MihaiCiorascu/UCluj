import 'package:flutter/material.dart';

import '../data/superliga_teams.dart';

/// Iteration N.8 — per-team accent overlay.
///
/// An ``InheritedWidget`` that carries the logged-in user's selected team
/// down the widget tree. Descendants ask for the team's colours via
/// ``TeamAccentScope.of(context)``; widgets like ``GlossyAppBar`` use
/// the returned colour list as the accent strip under the header.
///
/// Logged-out screens wrap their subtree in
/// ``TeamAccentScope(team: null, child: ...)``; the resolver returns
/// ``null`` and dependants render the universal glossy-blue base with no
/// team-coloured strip.
class TeamAccentScope extends InheritedWidget {
  const TeamAccentScope({
    required this.team,
    required super.child,
    super.key,
  });

  final SuperligaTeam? team;

  /// Convenience accessor — returns the closest ``SuperligaTeam`` ancestor,
  /// or ``null`` if not in a logged-in subtree.
  static SuperligaTeam? of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<TeamAccentScope>();
    return scope?.team;
  }

  /// Returns the accent colour list for the current team (1, 2, or 3
  /// colours). Returns an empty list when no team is in scope — in that
  /// case the caller should *not* render the strip.
  static List<Color> colorsOf(BuildContext context) {
    final t = of(context);
    if (t == null) return const [];
    final out = <Color>[t.primaryColor, t.secondaryColor];
    if (t.tertiaryColor != null) out.add(t.tertiaryColor!);
    return out;
  }

  @override
  bool updateShouldNotify(TeamAccentScope oldWidget) =>
      oldWidget.team?.short != team?.short;
}
