import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
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
      (p.compositeScore * 100).clamp(0, 99).toDouble();

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
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: bench.map((pl) {
        final sel = _selected?.playerId == pl.playerId;
        return GestureDetector(
          onTap: () => setState(() => _selected = pl),
          child: Container(
            width: 88,
            padding: const EdgeInsets.all(SpacingTokens.xs),
            decoration: BoxDecoration(
              color: sel ? c.surfaceHigh : c.surfaceLow,
              border: Border.all(
                color: sel ? c.accent : c.divider,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pl.roleGroup,
                  style: TypographyTokens.body.copyWith(
                    fontSize: 9,
                    color: recommendedXiRoleColor(pl.roleGroup, c),
                  ),
                ),
                Text(
                  pl.shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypographyTokens.body.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  rf(pl).toStringAsFixed(0),
                  style: TypographyTokens.headline.copyWith(
                    color: c.accent,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
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

// All per90_* and performance/form scores arrive pre-normalized to 0-100
// by the backend (league-wide, within position group, 5th-95th percentile).
// pass_accuracy and duel_win_rate are raw percentages (already 0-100).
List<_FifaAttr> _fifaAttrs(MatchPreviewPlayer p) {
  // GK gets keeper-specific attribute labels
  if (p.roleGroup == 'GK') {
    return [
      _FifaAttr('Speed',       p.recentFormScore.clamp(0, 100).toDouble()),
      _FifaAttr('Reflexes',    p.per90GkSaves.clamp(0, 100).toDouble()),
      _FifaAttr('Kicking',     p.passAccuracy.clamp(0, 100).toDouble()),
      _FifaAttr('Positioning', p.performanceScore.clamp(0, 100).toDouble()),
      _FifaAttr('Handling',    p.duelWinRate.clamp(0, 100).toDouble()),
      _FifaAttr('Diving',      p.per90GkCleanSheets.clamp(0, 100).toDouble()),
    ];
  }

  final pace      = p.recentFormScore.clamp(0, 100).toDouble();
  final physical  = p.performanceScore.clamp(0, 100).toDouble();
  final passing   = p.passAccuracy.clamp(0, 100).toDouble();
  final defending = p.duelWinRate.clamp(0, 100).toDouble();
  final double shooting;
  final double dribbling;

  switch (p.roleGroup) {
    case 'DEF':
      shooting  = p.per90Interceptions.clamp(0, 100).toDouble();
      dribbling = p.per90Assists.clamp(0, 100).toDouble();
    case 'MID':
      shooting  = p.per90KeyPasses.clamp(0, 100).toDouble();
      dribbling = p.per90Assists.clamp(0, 100).toDouble();
    default: // FWD
      shooting  = p.per90Goals.clamp(0, 100).toDouble();
      dribbling = p.per90KeyPasses.clamp(0, 100).toDouble();
  }

  return [
    _FifaAttr('Pace',      pace),
    _FifaAttr('Shooting',  shooting),
    _FifaAttr('Passing',   passing),
    _FifaAttr('Physical',  physical),
    _FifaAttr('Defending', defending),
    _FifaAttr('Dribbling', dribbling),
  ];
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top row: card + radar ──────────────────────────────────────
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left: position card
                Container(
                  width: 90,
                  color: c.surfaceHigh,
                  padding: const EdgeInsets.symmetric(
                    vertical: SpacingTokens.md,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        p.roleGroup,
                        style: TypographyTokens.sectionLabel.copyWith(
                          fontSize: 10,
                          color: recommendedXiRoleColor(p.roleGroup, c),
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        '$rating',
                        style: TypographyTokens.displayHero.copyWith(
                          fontSize: 52,
                          height: 0.95,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.shortName.toUpperCase(),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TypographyTokens.body.copyWith(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        p.role.toUpperCase(),
                        style: TypographyTokens.body.copyWith(
                          fontSize: 8,
                          color: c.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                // Right: radar
                Expanded(
                  child: SizedBox(
                    height: 170,
                    child: FifaPlayerRadar(
                      player: p,
                      accentColor: c.accent,
                      labelColor: c.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: SpacingTokens.lg),

          // ── Attribute comparison bars (FIFA style) ─────────────────────
          Text(
            'PLAYER INFO COMPARISON',
            style: TypographyTokens.sectionLabel.copyWith(
              fontSize: 9,
              color: c.accent,
              letterSpacing: 1.5,
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
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          // Value
          SizedBox(
            width: 28,
            child: Text(
              v.toStringAsFixed(0),
              style: TypographyTokens.body.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: col,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 6),
          // Bar
          Expanded(
            child: Container(
              height: 5,
              color: c.surfaceHigh,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: t,
                alignment: Alignment.centerLeft,
                child: Container(height: 5, color: col),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Label
          SizedBox(
            width: 62,
            child: Text(
              a.label,
              style: TypographyTokens.body.copyWith(
                fontSize: 11,
                color: c.textMuted,
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
    final base = width < 430 ? 44.0 : 50.0;
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
  const _PitchPlacement({required this.player, required this.offset});
  final MatchPreviewPlayer player;
  final Offset offset;
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
  });

  final MatchPreviewPlayer player;
  final bool selected;
  final double rating;
  final double chipSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
        padding: EdgeInsets.all(chipSize * 0.08),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              player.roleGroup,
              style: TypographyTokens.body.copyWith(
                fontSize: chipSize * 0.13,
                color: recommendedXiRoleColor(player.roleGroup, c),
              ),
            ),
            Text(
              player.shortName.split(' ').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypographyTokens.body.copyWith(
                fontSize: chipSize * 0.16,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            Text(
              rating.toStringAsFixed(0),
              style: TypographyTokens.headline.copyWith(
                color: c.accent,
                fontSize: chipSize * 0.22,
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
