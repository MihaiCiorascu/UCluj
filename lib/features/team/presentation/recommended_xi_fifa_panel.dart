import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/formation_slots.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../core/widgets/player_photo_avatar.dart';
import '../../../data/models/match_preview.dart';

/// Map an XI role group to its colour. Reads from the role family in
/// ``AppColorTokens`` so the Match Preview pitch and the Match Stats pitch
/// agree, and so no role collides with the cobalt CTA accent.
Color recommendedXiRoleColor(String g, AppColorTokens c) {
  switch (g) {
    case 'GK':
      return c.roleGoalkeeper;
    case 'DEF':
      return c.roleDefender;
    case 'MID':
      return c.roleMidfielder;
    case 'FWD':
      return c.roleForward;
    default:
      return c.textMuted;
  }
}

/// FIFA-style pitch + bench + player detail (dashboard sheet & match preview).
class RecommendedXiFifaPanel extends StatefulWidget {
  const RecommendedXiFifaPanel({
    super.key,
    required this.preview,
    required this.formation,
    this.ratingForDisplay = _defaultRatingForDisplay,
  });

  final MatchPreviewResponse preview;
  final String formation;
  final double Function(MatchPreviewPlayer p) ratingForDisplay;

  static double _defaultRatingForDisplay(MatchPreviewPlayer p) =>
      // Honest display rating: the backend `rating` is the within-position
      // league percentile of the player's performance score (a striker ranked
      // among strikers, a left-back among left-backs), mapped to a
      // discriminative band. Fall back to the legacy start-probability scaling
      // only if an older backend has not sent `rating`.
      p.rating > 0
          ? p.rating.toDouble()
          : (p.predictedScore * 100).clamp(0, 99).toDouble();

  @override
  State<RecommendedXiFifaPanel> createState() => _RecommendedXiFifaPanelState();
}

class _RecommendedXiFifaPanelState extends State<RecommendedXiFifaPanel> {
  MatchPreviewPlayer? _selected;

  @override
  void initState() {
    super.initState();
    _pickDefault();
  }

  @override
  void didUpdateWidget(covariant RecommendedXiFifaPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview != widget.preview ||
        oldWidget.formation != widget.formation) {
      _pickDefault();
    }
  }

  void _pickDefault() {
    final xi = widget.preview.startingXi;
    _selected = xi.isNotEmpty ? xi.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.preview;
    final rf = widget.ratingForDisplay;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final statsRow = _statsBar(p.teamStats, c);
        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            statsRow,
            const SizedBox(height: SpacingTokens.md),
            AspectRatio(
              aspectRatio: 4 / 5,
              child: FifaRecommendedXiPitch(
                formation: widget.formation,
                players: p.startingXi,
                selected: _selected,
                ratingForDisplay: rf,
                onSelect: (pl) => setState(() => _selected = pl),
              ),
            ),
            const SizedBox(height: SpacingTokens.md),
            Text(
              'SUBSTITUTES',
              style: TypographyTokens.sectionLabel.copyWith(
                fontSize: 9,
                color: c.textMuted,
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
            _benchWrap(p.bench, rf, c),
          ],
        );

        final detail = _PlayerDetailColumn(
          player: _selected,
          ratingForDisplay: rf,
        );

        if (wide) {
          return SizedBox(
            height: 520,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 11,
                  child: SingleChildScrollView(child: left),
                ),
                Container(width: 1, color: c.divider),
                Expanded(
                  flex: 9,
                  child: detail,
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            left,
            Divider(color: c.divider, height: 1),
            SizedBox(height: 360, child: detail),
          ],
        );
      },
    );
  }

  Widget _statsBar(MatchTeamStats s, AppColorTokens c) {
    return Row(
      children: [
        _statCell('FORMĂ', s.avgRecentForm.toStringAsFixed(1), c),
        _statCell('PERF', s.avgPerformanceScore.toStringAsFixed(1), c),
        _statCell('PAS%', '${s.avgPassAccuracy.toStringAsFixed(0)}%', c),
        _statCell('DUEL%', '${s.avgDuelWinRate.toStringAsFixed(0)}%', c),
      ],
    );
  }

  Widget _statCell(String label, String value, AppColorTokens c) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 2),
        color: c.surfaceHigh,
        padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
        child: Column(
          children: [
            Text(
              value,
              style: TypographyTokens.headline.copyWith(
                fontSize: 15,
                color: c.textPrimary,
              ),
            ),
            Text(
              label,
              style: TypographyTokens.body.copyWith(
                color: c.textMuted,
                fontSize: 9,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _benchWrap(
    List<MatchPreviewPlayer> bench,
    double Function(MatchPreviewPlayer p) rf,
    AppColorTokens c,
  ) {
    if (bench.isEmpty) {
      return Text(
        '—',
        style: TypographyTokens.body.copyWith(color: c.textMuted),
      );
    }
    // Horizontal scroll strip with the same chip shape as the pitch chip
    // (left-edge role rule, dominant rating, demoted position). Replaces
    // the previous 4-wide Wrap grid, which crammed every substitute into
    // a single screen height even when there were 12+ benches to scroll.
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: bench.length,
        separatorBuilder: (_, __) => const SizedBox(width: SpacingTokens.xs),
        itemBuilder: (context, i) {
          final pl = bench[i];
          final sel = _selected?.playerId == pl.playerId;
          // Bench players are not slot-assigned, so colour and label come from
          // their primary fine group (CB, ST, ...) when known, else the coarse
          // role group.
          final benchCoarse = pl.positionGroupFine.isNotEmpty
              ? coarseForFineGroup(pl.positionGroupFine)
              : pl.roleGroup;
          final benchLabel =
              pl.positionGroupFine.isNotEmpty ? pl.positionGroupFine : pl.roleGroup;
          final roleColor = recommendedXiRoleColor(
              benchCoarse.isNotEmpty ? benchCoarse : pl.roleGroup, c);
          return GestureDetector(
            onTap: () => setState(() => _selected = pl),
            child: Container(
              width: 84,
              decoration: BoxDecoration(
                color: sel ? c.surfaceHigh : c.surfaceLow,
                border: Border(
                  left: BorderSide(color: roleColor, width: 3),
                  top: BorderSide(color: sel ? c.accent : c.divider, width: sel ? 2 : 1),
                  right: BorderSide(color: sel ? c.accent : c.divider, width: sel ? 2 : 1),
                  bottom: BorderSide(color: sel ? c.accent : c.divider, width: sel ? 2 : 1),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                SpacingTokens.xs,
                SpacingTokens.xs,
                SpacingTokens.xxs,
                SpacingTokens.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PlayerPhotoAvatar(
                    photoUrl: pl.photoUrl,
                    name: pl.shortName,
                    ringColor: roleColor,
                    size: 46,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rf(pl).toStringAsFixed(0),
                    style: TypographyTokens.headline.copyWith(
                      color: c.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pl.shortName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypographyTokens.body.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                      color: c.textPrimary,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    benchLabel,
                    style: TypographyTokens.sectionLabel.copyWith(
                      fontSize: 8,
                      color: c.textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FIFA-style attribute definition
// ---------------------------------------------------------------------------
class _FifaAttr {
  const _FifaAttr(this.label, this.value);
  final String label;
  final double value; // 0–100
}

// Honest attribute bars. Every value is the player's WITHIN-POSITION league
// percentile (0-100) for a real Wyscout-derived KPI, computed server-side
// (statPct), so a striker is ranked among strikers and a left-back among
// left-backs. Labels name the actual metric, not a fabricated FIFA attribute.
List<_FifaAttr> _fifaAttrs(MatchPreviewPlayer p) {
  double pct(String key) => (p.statPct[key] ?? 50.0).clamp(0, 100).toDouble();

  if (p.roleGroup == 'GK') {
    return [
      _FifaAttr('Saves', pct('per90_gkSaves')),
      _FifaAttr('Clean Sheets', pct('per90_gkCleanSheets')),
      _FifaAttr('Aerial', pct('aerial_win_rate')),
      _FifaAttr('Distribution', pct('pass_accuracy')),
      _FifaAttr('Form', pct('recent_form_score')),
      _FifaAttr('Rating', pct('performance_score')),
    ];
  }

  switch (p.roleGroup) {
    case 'DEF':
      return [
        _FifaAttr('Duels', pct('duel_win_rate')),
        _FifaAttr('Interceptions', pct('per90_interceptions')),
        _FifaAttr('Def Actions', pct('def_action_success')),
        _FifaAttr('Aerial', pct('aerial_win_rate')),
        _FifaAttr('Passing', pct('pass_accuracy')),
        _FifaAttr('Form', pct('recent_form_score')),
      ];
    case 'MID':
      return [
        _FifaAttr('Passing', pct('pass_accuracy')),
        _FifaAttr('Key Passes', pct('per90_keyPasses')),
        _FifaAttr('Dribbling', pct('dribble_success')),
        _FifaAttr('Duels', pct('duel_win_rate')),
        _FifaAttr('Assists', pct('per90_assists')),
        _FifaAttr('Form', pct('recent_form_score')),
      ];
    default: // FWD
      return [
        _FifaAttr('Goals', pct('per90_goals')),
        _FifaAttr('Shots', pct('per90_shots')),
        _FifaAttr('Shot Acc', pct('shot_accuracy')),
        _FifaAttr('Dribbling', pct('dribble_success')),
        _FifaAttr('Key Passes', pct('per90_keyPasses')),
        _FifaAttr('Form', pct('recent_form_score')),
      ];
  }
}

/// The comparison group the attribute percentiles were computed against: the
/// fine position when the backend used it, otherwise the coarse role group.
String _attrCompareLabel(MatchPreviewPlayer p) {
  if (p.positionNorm == 'FINE' && p.positionGroupFine.isNotEmpty) {
    return p.positionGroupFine.toUpperCase();
  }
  return p.roleGroup.toUpperCase();
}

Color _attrColor(double v, AppColorTokens c) {
  if (v >= 70) return c.positive;
  if (v >= 45) return c.accent;
  return c.negative;
}

// ---------------------------------------------------------------------------
// Player detail panel (FIFA style)
// ---------------------------------------------------------------------------
class _PlayerDetailColumn extends StatelessWidget {
  const _PlayerDetailColumn({
    required this.player,
    required this.ratingForDisplay,
  });

  final MatchPreviewPlayer? player;
  final double Function(MatchPreviewPlayer p) ratingForDisplay;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = player;
    if (p == null) {
      return Center(
        child: Text(
          'Select a player',
          style: TypographyTokens.body.copyWith(color: c.textMuted),
        ),
      );
    }
    final rating = ratingForDisplay(p).clamp(0, 100).toInt();
    final attrs  = _fifaAttrs(p);
    // Prefer the official slot label, then the fine group, then the coarse
    // role; colour by the corresponding coarse group.
    final detailLabel = p.officialPosition.isNotEmpty
        ? p.officialPosition
        : (p.positionGroupFine.isNotEmpty ? p.positionGroupFine : p.roleGroup);
    final detailCoarse = p.positionGroupFine.isNotEmpty
        ? coarseForFineGroup(p.positionGroupFine)
        : p.roleGroup;
    final roleColor = recommendedXiRoleColor(
        detailCoarse.isNotEmpty ? detailCoarse : p.roleGroup, c);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top row: card + radar ──────────────────────────────────────
          // Hero header: large headshot, identity, and the dominant rating,
          // anchored by a role-coloured left accent rule (tonal depth, sharp
          // edges, no shadows).
          Container(
            decoration: BoxDecoration(
              color: c.surfaceHigh,
              border: Border(left: BorderSide(color: roleColor, width: 4)),
            ),
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PlayerPhotoAvatar(
                  photoUrl: p.photoUrl,
                  name: p.shortName,
                  ringColor: roleColor,
                  size: 84,
                ),
                const SizedBox(width: SpacingTokens.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        p.shortName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TypographyTokens.cardTitle.copyWith(
                          color: c.textPrimary,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            color: roleColor.withValues(alpha: 0.16),
                            child: Text(
                              detailLabel.toUpperCase(),
                              style: TypographyTokens.sectionLabel.copyWith(
                                fontSize: 10,
                                color: roleColor,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: SpacingTokens.xs),
                          Flexible(
                            child: Text(
                              p.role.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TypographyTokens.sectionLabel.copyWith(
                                fontSize: 9,
                                color: c.textMuted,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$rating',
                      style: TypographyTokens.displayHero.copyWith(
                        fontSize: 56,
                        height: 0.9,
                        letterSpacing: -1.5,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      'RATING',
                      style: TypographyTokens.sectionLabel.copyWith(
                        fontSize: 8,
                        color: c.textMuted,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: SpacingTokens.lg),

          // Radar: larger and role-coloured so the silhouette reads as an
          // attacker / defender shape at a glance, on a tonal tray.
          Container(
            color: c.surfaceLow,
            padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
            child: SizedBox(
              height: 210,
              child: FifaPlayerRadar(
                player: p,
                accentColor: roleColor,
                labelColor: c.textSecondary,
              ),
            ),
          ),

          const SizedBox(height: SpacingTokens.lg),

          // ── Attribute bars ──────────────────────────────────────────────
          // Section title in Romanian so it stops being the only English
          // string on a screen that otherwise reads "FACTORI CHEIE AI",
          // "RISCURI", "DIAGNOSTIC - PLAN TACTIC". Localisation through
          // L10n.t is deferred to the cross-cutting polish PR.
          Text(
            'ATRIBUTE JUCATOR',
            style: TypographyTokens.sectionLabel.copyWith(
              fontSize: 9,
              color: c.accent,
              letterSpacing: 1.5,
            ),
          ),
          // Each bar is a within-position league percentile, so name the
          // comparison group honestly (the fine position when it was used,
          // else the coarse group).
          Text(
            'percentilă în liga · ${_attrCompareLabel(p)}',
            style: TypographyTokens.sectionLabel.copyWith(
              fontSize: 8,
              color: c.textMuted,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
          for (final a in attrs) _fifaAttrRow(a, c),
        ],
      ),
    );
  }

  Widget _fifaAttrRow(_FifaAttr a, AppColorTokens c) {
    final v   = a.value.clamp(0, 100).toDouble();
    final t   = v / 100;
    final col = _attrColor(v, c);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // Value
          SizedBox(
            width: 30,
            child: Text(
              v.toStringAsFixed(0),
              style: TypographyTokens.body.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: col,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: SpacingTokens.xs),
          // Bar on a tonal tray
          Expanded(
            child: Container(
              height: 8,
              color: c.surfaceHigh,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: t,
                alignment: Alignment.centerLeft,
                child: Container(height: 8, color: col),
              ),
            ),
          ),
          const SizedBox(width: SpacingTokens.sm),
          // Label
          SizedBox(
            width: 70,
            child: Text(
              a.label,
              style: TypographyTokens.body.copyWith(
                fontSize: 11,
                color: c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FifaRecommendedXiPitch extends StatelessWidget {
  const FifaRecommendedXiPitch({
    super.key,
    required this.formation,
    required this.players,
    required this.selected,
    required this.onSelect,
    required this.ratingForDisplay,
  });

  final String formation;
  final List<MatchPreviewPlayer> players;
  final MatchPreviewPlayer? selected;
  final ValueChanged<MatchPreviewPlayer> onSelect;
  final double Function(MatchPreviewPlayer p) ratingForDisplay;

  List<_PitchPlacement> _placements() {
    // Preferred path: the backend assigns every starter an official slot via
    // the Hungarian matching and returns a slot_index. When all eleven carry a
    // valid slot_index we place each player at its official pitch slot (label
    // and coarse colour come from the shared formation_slots table, whose order
    // mirrors the backend FORMATION_SLOTS). Otherwise we fall back to the
    // legacy coarse-bucket layout so older payloads still render.
    final slots = kFormationSlots[formation];
    if (slots != null &&
        players.isNotEmpty &&
        players.every((p) => p.slotIndex >= 0 && p.slotIndex < slots.length)) {
      final out = <_PitchPlacement>[];
      for (final p in players) {
        final slot = slots[p.slotIndex];
        out.add(_PitchPlacement(
          player: p,
          offset: Offset(slot.x, slot.y),
          label: slot.label,
          coarse: slot.coarse,
        ));
      }
      return out;
    }

    // ── Legacy coarse-bucket fallback ────────────────────────────────────
    final gk = players.where((p) => p.roleGroup == 'GK').toList();
    final defs = players.where((p) => p.roleGroup == 'DEF').toList();
    final mids = players.where((p) => p.roleGroup == 'MID').toList();
    final fwds = players.where((p) => p.roleGroup == 'FWD').toList();

    var defIndex = 0;
    var midIndex = 0;
    var fwdIndex = 0;

    final out = <_PitchPlacement>[];
    if (gk.isNotEmpty) {
      out.add(_PitchPlacement(player: gk.first, offset: const Offset(0.50, 0.90)));
    }

    final lines = _formationTemplate(formation);
    for (final line in lines) {
      for (var i = 0; i < line.xs.length; i++) {
        MatchPreviewPlayer? player;
        if (line.role == 'DEF') {
          if (defIndex < defs.length) player = defs[defIndex++];
        } else if (line.role == 'MID') {
          if (midIndex < mids.length) player = mids[midIndex++];
        } else {
          if (fwdIndex < fwds.length) player = fwds[fwdIndex++];
        }
        if (player != null) {
          out.add(_PitchPlacement(player: player, offset: Offset(line.xs[i], line.y)));
        }
      }
    }
    return out;
  }

  List<_PitchLine> _formationTemplate(String key) {
    switch (key) {
      case '3-1-4-2':
        return const [
          _PitchLine(role: 'DEF', y: 0.73, xs: [0.26, 0.50, 0.74]),
          _PitchLine(role: 'MID', y: 0.58, xs: [0.50]),
          _PitchLine(role: 'MID', y: 0.40, xs: [0.10, 0.36, 0.64, 0.90]),
          _PitchLine(role: 'FWD', y: 0.18, xs: [0.38, 0.62]),
        ];
      case '4-2-3-1':
        return const [
          _PitchLine(role: 'DEF', y: 0.73, xs: [0.14, 0.38, 0.62, 0.86]),
          _PitchLine(role: 'MID', y: 0.56, xs: [0.38, 0.62]),
          _PitchLine(role: 'MID', y: 0.38, xs: [0.18, 0.50, 0.82]),
          _PitchLine(role: 'FWD', y: 0.18, xs: [0.50]),
        ];
      case '4-4-2':
        return const [
          _PitchLine(role: 'DEF', y: 0.73, xs: [0.14, 0.38, 0.62, 0.86]),
          _PitchLine(role: 'MID', y: 0.43, xs: [0.14, 0.38, 0.62, 0.86]),
          _PitchLine(role: 'FWD', y: 0.18, xs: [0.38, 0.62]),
        ];
      case '3-5-2':
        return const [
          _PitchLine(role: 'DEF', y: 0.73, xs: [0.26, 0.50, 0.74]),
          _PitchLine(role: 'MID', y: 0.40, xs: [0.14, 0.32, 0.50, 0.68, 0.86]),
          _PitchLine(role: 'FWD', y: 0.18, xs: [0.38, 0.62]),
        ];
      case '3-4-3':
        return const [
          _PitchLine(role: 'DEF', y: 0.73, xs: [0.26, 0.50, 0.74]),
          _PitchLine(role: 'MID', y: 0.43, xs: [0.14, 0.38, 0.62, 0.86]),
          _PitchLine(role: 'FWD', y: 0.18, xs: [0.22, 0.50, 0.78]),
        ];
      case '5-3-2':
        return const [
          _PitchLine(role: 'DEF', y: 0.73, xs: [0.08, 0.26, 0.50, 0.74, 0.92]),
          _PitchLine(role: 'MID', y: 0.43, xs: [0.26, 0.50, 0.74]),
          _PitchLine(role: 'FWD', y: 0.18, xs: [0.38, 0.62]),
        ];
      case '5-4-1':
        return const [
          _PitchLine(role: 'DEF', y: 0.73, xs: [0.08, 0.26, 0.50, 0.74, 0.92]),
          _PitchLine(role: 'MID', y: 0.43, xs: [0.14, 0.38, 0.62, 0.86]),
          _PitchLine(role: 'FWD', y: 0.18, xs: [0.50]),
        ];
      default:
        return _genericTemplate(key);
    }
  }

  List<_PitchLine> _genericTemplate(String key) {
    final parts = key
        .split('-')
        .map((v) => int.tryParse(v))
        .whereType<int>()
        .toList();
    if (parts.length < 3) {
      return const [
        _PitchLine(role: 'DEF', y: 0.73, xs: [0.14, 0.38, 0.62, 0.86]),
        _PitchLine(role: 'MID', y: 0.43, xs: [0.28, 0.50, 0.72]),
        _PitchLine(role: 'FWD', y: 0.18, xs: [0.22, 0.50, 0.78]),
      ];
    }

    final def = parts.first;
    final fwd = parts.last;
    final midLines = parts.sublist(1, parts.length - 1);
    final lines = <_PitchLine>[
      _PitchLine(role: 'DEF', y: 0.73, xs: _distributedXs(def)),
    ];

    const yBottom = 0.56;
    const yTop = 0.34;
    final step = midLines.length <= 1 ? 0.0 : (yBottom - yTop) / (midLines.length - 1);
    for (var i = 0; i < midLines.length; i++) {
      lines.add(_PitchLine(
        role: 'MID',
        y: yBottom - i * step,
        xs: _distributedXs(midLines[i]),
      ));
    }
    lines.add(_PitchLine(role: 'FWD', y: 0.18, xs: _distributedXs(fwd)));
    return lines;
  }

  List<double> _distributedXs(int count) {
    if (count <= 1) return const [0.50];
    const left = 0.18;
    const right = 0.82;
    final step = (right - left) / (count - 1);
    return List<double>.generate(count, (i) => left + step * i);
  }

  @override
  Widget build(BuildContext context) {
    final placements = _placements();
    final maxLineCount = _maxLineCountFor(formation);
    final tokens = context.colors;

    return LayoutBuilder(
      builder: (ctx, c) {
        final chipSize = _chipSizeFor(c.maxWidth, maxLineCount);
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: FifaPitchPainter(
                surface: tokens.pitchSurface,
                line: tokens.pitchLine,
                halo: tokens.pitchHalo,
                accent: tokens.accent,
                border: tokens.chromeDeep,
              ),
            ),
            for (final p in placements)
              Positioned(
                left: p.offset.dx * c.maxWidth - chipSize / 2,
                top: p.offset.dy * c.maxHeight - chipSize / 2,
                width: chipSize,
                height: chipSize,
                child: FifaPitchPlayerChip(
                  player: p.player,
                  selected: selected?.playerId == p.player.playerId,
                  rating: ratingForDisplay(p.player),
                  chipSize: chipSize,
                  onTap: () => onSelect(p.player),
                  positionLabel: p.label,
                  coarseGroup: p.coarse,
                ),
              ),
          ],
        );
      },
    );
  }

  int _maxLineCountFor(String key) {
    final tpl = _formationTemplate(key);
    var maxCount = 1;
    for (final line in tpl) {
      if (line.xs.length > maxCount) maxCount = line.xs.length;
    }
    return maxCount;
  }

  double _chipSizeFor(double width, int maxLineCount) {
    final base = width < 430 ? 50.0 : 58.0;
    if (maxLineCount >= 5) return base - 6;
    if (maxLineCount >= 4) return base - 3;
    return base;
  }
}

class _PitchLine {
  const _PitchLine({required this.role, required this.y, required this.xs});
  final String role;
  final double y;
  final List<double> xs;
}

class _PitchPlacement {
  const _PitchPlacement({
    required this.player,
    required this.offset,
    this.label,
    this.coarse,
  });
  final MatchPreviewPlayer player;
  final Offset offset;

  /// Official slot label and coarse group when placed by slot_index; null on
  /// the legacy coarse-bucket fallback path.
  final String? label;
  final String? coarse;
}

class FifaPitchPainter extends CustomPainter {
  const FifaPitchPainter({
    required this.surface,
    required this.line,
    required this.halo,
    required this.accent,
    required this.border,
  });

  /// Pitch background. Comes from ``AppColorTokens.pitchSurface`` so the
  /// pitch reads as a single product element across both themes.
  final Color surface;

  /// Pitch line colour (centre circle, halfway, penalty boxes, outer rect).
  /// Comes from ``AppColorTokens.pitchLine``.
  final Color line;

  /// Subtle cobalt halo used inside the centre circle so the eye anchors
  /// on the middle of the pitch. Comes from ``AppColorTokens.pitchHalo``.
  final Color halo;

  /// Cobalt accent rule along the top and bottom edge of the pitch, so
  /// the pitch reads as part of the Stoic Analyst editorial layout. Comes
  /// from ``AppColorTokens.accent``.
  final Color accent;

  /// 2 px sharp-cornered outer border, so the pitch sits inside the same
  /// crisp boundary as sibling ``AppCard`` panels. Comes from
  /// ``AppColorTokens.chromeDeep``.
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final bgPaint = Paint()..color = surface;
    canvas.drawRect(rect, bgPaint);

    // Centre-circle halo first so the pitch lines overlay it.
    final haloPaint = Paint()..color = halo;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.12;
    canvas.drawCircle(center, radius, haloPaint);

    final linePaint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawRect(rect.deflate(8), linePaint);

    final midY = size.height / 2;
    canvas.drawLine(Offset(8, midY), Offset(size.width - 8, midY), linePaint);

    canvas.drawCircle(center, radius, linePaint);

    final boxW = size.width * 0.36;
    final boxH = size.height * 0.18;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width / 2, 8 + boxH / 2),
        width: boxW,
        height: boxH,
      ),
      linePaint,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height - 8 - boxH / 2),
        width: boxW,
        height: boxH,
      ),
      linePaint,
    );

    // Cobalt accent rule along the top and bottom edges (thin, full-width).
    final accentPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(Offset.zero, Offset(size.width, 0), accentPaint);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), accentPaint);

    // Sharp-cornered chrome border.
    final borderPaint = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant FifaPitchPainter oldDelegate) =>
      oldDelegate.surface != surface ||
      oldDelegate.line != line ||
      oldDelegate.halo != halo ||
      oldDelegate.accent != accent ||
      oldDelegate.border != border;
}

class FifaPitchPlayerChip extends StatelessWidget {
  const FifaPitchPlayerChip({
    super.key,
    required this.player,
    required this.selected,
    required this.rating,
    required this.chipSize,
    required this.onTap,
    this.positionLabel,
    this.coarseGroup,
  });

  final MatchPreviewPlayer player;
  final bool selected;
  final double rating;
  final double chipSize;
  final VoidCallback onTap;

  /// Official slot label to show on the chip (RB, RCB, DM, RW, ST, ...). Falls
  /// back to the player's coarse role group when not supplied.
  final String? positionLabel;

  /// Coarse group used for the role colour. Falls back to the player's role
  /// group. On the pitch this is the SLOT's coarse group so the colour reads
  /// positionally even when a player covers an adjacent role.
  final String? coarseGroup;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = (positionLabel != null && positionLabel!.isNotEmpty)
        ? positionLabel!
        : player.roleGroup;
    final roleColor = recommendedXiRoleColor(
      (coarseGroup != null && coarseGroup!.isNotEmpty) ? coarseGroup! : player.roleGroup,
      c,
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: c.surfaceHigh,
          border: Border.all(
            color: selected ? c.accent : c.divider,
            width: selected ? 2 : 1,
          ),
        ),
        padding: EdgeInsets.all(chipSize * 0.06),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Face-forward FIFA card: the headshot is the chip, ringed in the
            // role colour (the ring replaces the old left-edge rule). The
            // avatar degrades to initials when no photo is available.
            PlayerPhotoAvatar(
              photoUrl: player.photoUrl,
              name: player.shortName,
              ringColor: roleColor,
              size: chipSize * 0.62,
            ),
            const SizedBox(height: 2),
            // League-relative rating stays prominent beneath the face.
            Text(
              rating.toStringAsFixed(0),
              style: TypographyTokens.headline.copyWith(
                color: c.textPrimary,
                fontSize: chipSize * 0.24,
                fontWeight: FontWeight.w900,
                height: 1.0,
                letterSpacing: -0.5,
              ),
            ),
            // Official position label (RB, RCB, DM, RW, ST, ...).
            Text(
              label,
              style: TypographyTokens.sectionLabel.copyWith(
                fontSize: chipSize * 0.11,
                color: c.textMuted,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FifaPlayerRadar extends StatelessWidget {
  const FifaPlayerRadar({
    super.key,
    required this.player,
    this.accentColor,
    this.labelColor,
  });

  final MatchPreviewPlayer player;
  final Color? accentColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final attrs = _fifaAttrs(player);
    final values = attrs.map((a) => (a.value / 100).clamp(0.0, 1.0)).toList();
    final labels = attrs.map((a) => a.label.toUpperCase()).toList();
    return CustomPaint(
      painter: FifaRadarPainter(
        values: values,
        labels: labels,
        accentColor: accentColor ?? c.accent,
        labelColor: labelColor ?? c.textMuted,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class FifaRadarPainter extends CustomPainter {
  FifaRadarPainter({
    required this.values,
    required this.labels,
    required this.accentColor,
    required this.labelColor,
  });

  final List<double> values;
  final List<String> labels;
  final Color accentColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2 + 8);
    final r = math.min(size.width, size.height) * 0.38;
    const n = 6;
    final points = <Offset>[];

    for (var i = 0; i < n; i++) {
      final ang = -math.pi / 2 + (2 * math.pi * i / n);
      final vr = r * values[i].clamp(0.05, 1.0);
      points.add(Offset(c.dx + vr * math.cos(ang), c.dy + vr * math.sin(ang)));
    }

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var k = 1; k <= 3; k++) {
      final rr = r * k / 3;
      final ring = <Offset>[];
      for (var i = 0; i < n; i++) {
        final ang = -math.pi / 2 + (2 * math.pi * i / n);
        ring.add(Offset(c.dx + rr * math.cos(ang), c.dy + rr * math.sin(ang)));
      }
      final path = Path()..moveTo(ring[0].dx, ring[0].dy);
      for (var i = 1; i < n; i++) {
        path.lineTo(ring[i].dx, ring[i].dy);
      }
      path.close();
      canvas.drawPath(path, grid);
    }

    final fill = Paint()
      ..color = accentColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final poly = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < n; i++) {
      poly.lineTo(points[i].dx, points[i].dy);
    }
    poly.close();
    canvas.drawPath(poly, fill);
    canvas.drawPath(poly, border);

    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < n; i++) {
      final ang = -math.pi / 2 + (2 * math.pi * i / n);
      final lx = c.dx + (r + 14) * math.cos(ang);
      final ly = c.dy + (r + 14) * math.sin(ang);
      tp.text = TextSpan(
        text: labels[i],
        style: TextStyle(
          color: labelColor,
          fontSize: 8,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant FifaRadarPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.labelColor != labelColor;
}
