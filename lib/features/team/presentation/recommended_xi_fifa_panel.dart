import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/formation_slots.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/primitives/app_sheet.dart';
import '../../../core/primitives/haptics.dart';
import '../../../core/primitives/segmented_toggle.dart';
import '../../../core/primitives/stat_tile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/shape_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../core/widgets/player_photo_avatar.dart';
import '../../../data/models/match_preview.dart';
import '../../../data/repositories/xi_repository.dart';

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
///
/// When [opponentName] is supplied the pitch becomes interactive: tapping a
/// player opens an action menu (Lock to slot, Replace…, Unlock, Details) and
/// any lock/replace/unlock re-requests the preview through the POST contract
/// (current resolved formation + the locked map) and re-renders the returned
/// XI/bench. Without [opponentName] the panel stays read-only (older callers).
class RecommendedXiFifaPanel extends StatefulWidget {
  const RecommendedXiFifaPanel({
    super.key,
    required this.preview,
    required this.formation,
    this.opponentName,
    this.homeTeam,
    this.xiRepository,
    this.onPreviewChanged,
    this.onShowOpponentChanged,
    this.ratingForDisplay = _defaultRatingForDisplay,
  });

  final MatchPreviewResponse preview;
  final String formation;

  /// Opponent short label used to re-request the preview when the staff edit
  /// the XI. When null the panel is read-only (no action menu, no locks).
  final String? opponentName;

  /// Home-team override for the preview re-fetch, mirroring the sheet's initial
  /// load. Non-null only for non-subject ("other") matches, where the previewed
  /// home team is the fixture's home club rather than the user's; passing it on
  /// every edit keeps the re-optimised XI framed on the same team. Also used to
  /// label the toggle by team name for those matches.
  final String? homeTeam;

  /// Repository used for the flexible-XI POST round-trips. Defaults to a fresh
  /// [XiRepository] when interactivity is enabled and none is injected.
  final XiRepository? xiRepository;

  /// Notifies the parent when an edit produced a new preview, so a host screen
  /// can keep its own copy (e.g. a formation badge) in sync.
  final ValueChanged<MatchPreviewResponse>? onPreviewChanged;

  /// Notifies the parent when the user toggles between our XI and the opponent
  /// XI, so a host can hide controls that only apply to our team (e.g. the
  /// formation selector) while the read-only opponent XI is shown.
  final ValueChanged<bool>? onShowOpponentChanged;

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
  // Which eleven the pitch shows: our predicted XI (default) or the opponent's
  // predicted XI. The opponent lists are empty on older backends, so the toggle
  // is hidden and this stays false.
  bool _showOpponent = false;

  // The live preview the pitch renders. It starts as the widget's preview and
  // is swapped for the POST result after every edit, so the panel re-renders
  // the re-optimised XI/bench without waiting on the parent.
  late MatchPreviewResponse _preview;

  // Current pins: 0-based slot index -> playerId. Sent on every edit and shown
  // as a small lock badge on the pinned chip.
  final Map<int, int> _locked = {};

  // True while a POST round-trip is in flight; the pitch dims and ignores taps.
  bool _busy = false;

  XiRepository? _repo;

  // Editing (formation locks, replace, reset) only makes sense for the user's
  // own team. [homeTeam] is non-null only on "other" matches (neither club is the
  // subject), where the panel is a read-only scouting view of both predicted XIs.
  bool get _interactive =>
      widget.opponentName != null && widget.homeTeam == null;

  XiRepository get _repository =>
      widget.xiRepository ?? (_repo ??= XiRepository());

  // The resolved formation always comes from the live preview (never the
  // requested value), because AUTO and skipped-lock shapes can differ.
  String get _resolvedFormation =>
      _preview.formation.isNotEmpty ? _preview.formation : widget.formation;

  // Formation used to lay the CURRENTLY SHOWN XI out on the pitch. When the
  // opponent XI is displayed, use the opponent's OWN resolved shape so its pitch
  // arrangement is distinct from ours; otherwise fall back to our formation.
  // Edits (_applyEdits / replace picker) keep using _resolvedFormation because
  // editing is disabled while the opponent XI is shown.
  String get _displayFormation =>
      _showOpponent && _preview.opponentFormation.isNotEmpty
          ? _preview.opponentFormation
          : _resolvedFormation;

  List<MatchPreviewPlayer> get _activeXi =>
      _showOpponent ? _preview.opponentXi : _preview.startingXi;
  List<MatchPreviewPlayer> get _activeBench =>
      _showOpponent ? _preview.opponentBench : _preview.bench;

  @override
  void initState() {
    super.initState();
    _preview = widget.preview;
    _pickDefault();
  }

  @override
  void didUpdateWidget(covariant RecommendedXiFifaPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview != widget.preview &&
        !identical(widget.preview, _preview)) {
      // A genuinely fresh preview from the parent (e.g. opponent or formation
      // change) supersedes any local edits and clears the locks. We skip the
      // case where the parent is simply echoing back the same object our own
      // edit produced (via onPreviewChanged), which must NOT drop the locks.
      _preview = widget.preview;
      _locked.clear();
      _pickDefault();
    } else if (oldWidget.formation != widget.formation) {
      _pickDefault();
    }
  }

  void _pickDefault() {
    final xi = _activeXi;
    _selected = xi.isNotEmpty ? xi.first : null;
  }

  void _setShowOpponent(bool v) {
    if (_showOpponent == v) return;
    setState(() {
      _showOpponent = v;
      _pickDefault();
    });
    widget.onShowOpponentChanged?.call(v);
  }

  // ── Flexible-XI editing ──────────────────────────────────────────────────

  /// Re-request the preview through the POST contract with the current resolved
  /// formation and locked map, then swap in the returned XI/bench. The lock map
  /// is sent as-is; the backend silently drops invalid locks and may even drop
  /// all of them (still returning an XI), so we trust whatever comes back.
  Future<void> _applyEdits() async {
    if (!_interactive) return;
    setState(() => _busy = true);
    try {
      final updated = await _repository.postMatchPreview(
        opponentName: widget.opponentName!,
        formation: _resolvedFormation,
        locked: Map<int, int>.from(_locked),
        homeTeam: widget.homeTeam,
      );
      if (!mounted) return;
      setState(() {
        _preview = updated;
        _busy = false;
        // Keep the selection on the same player when it survived the
        // re-optimisation; otherwise fall back to the first starter.
        final keepId = _selected?.playerId;
        final all = [...updated.startingXi, ...updated.bench];
        _selected = all.cast<MatchPreviewPlayer?>().firstWhere(
              (p) => p?.playerId == keepId,
              orElse: () => updated.startingXi.isNotEmpty
                  ? updated.startingXi.first
                  : null,
            );
      });
      widget.onPreviewChanged?.call(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppHaptics.error();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('${L10n.t('sheet.xiUnavailable')}: $e')),
      );
    }
  }

  Future<void> _lockToSlot(MatchPreviewPlayer p) async {
    if (p.slotIndex < 0) return;
    AppHaptics.medium();
    // A player can hold only one slot, and a slot only one player: clear any
    // prior pin for either before adding the new one.
    _locked.removeWhere((slot, id) => id == p.playerId);
    _locked[p.slotIndex] = p.playerId;
    await _applyEdits();
  }

  Future<void> _unlock(MatchPreviewPlayer p) async {
    AppHaptics.selection();
    _locked.removeWhere((slot, id) => id == p.playerId);
    await _applyEdits();
  }

  /// Pin [replacement] to [target]'s current slot, swapping the incumbent out.
  Future<void> _replaceInSlot(
      MatchPreviewPlayer target, MatchPreviewPlayer replacement) async {
    if (target.slotIndex < 0) return;
    AppHaptics.medium();
    // The replacement takes the target's slot; drop any other pin it held and
    // any pin of the player it displaces.
    _locked.removeWhere((slot, id) =>
        id == replacement.playerId || id == target.playerId);
    _locked[target.slotIndex] = replacement.playerId;
    await _applyEdits();
  }

  Future<void> _resetLocks() async {
    if (_locked.isEmpty) return;
    AppHaptics.selection();
    _locked.clear();
    await _applyEdits();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = _preview;
    final rf = widget.ratingForDisplay;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide layouts keep the inline side panel; on phones, tapping a player
        // opens the detail in a bottom sheet so the pitch stays the focus.
        final wide = constraints.maxWidth >= 640;
        // When interactive, a tap opens the action menu (lock / replace /
        // unlock / details); otherwise it falls back to the read-only detail.
        void onSelect(MatchPreviewPlayer pl) {
          if (_busy) return;
          if (_interactive && !_showOpponent) {
            _openActionMenu(pl);
          } else if (wide) {
            setState(() => _selected = pl);
          } else {
            _openPlayerSheet(pl);
          }
        }

        final pitch = Stack(
          children: [
            FifaRecommendedXiPitch(
              formation: _displayFormation,
              players: _activeXi,
              selected: wide ? _selected : null,
              ratingForDisplay: rf,
              onSelect: onSelect,
              lockedSlots: _interactive && !_showOpponent
                  ? _locked.keys.toSet()
                  : const {},
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: c.scrim.withValues(alpha: 0.35),
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
              ),
          ],
        );

        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_interactive && !_showOpponent) ...[
              _editBar(c),
              const SizedBox(height: SpacingTokens.sm),
            ],
            if (p.opponentXi.isNotEmpty) ...[
              _xiToggle(c),
              const SizedBox(height: SpacingTokens.md),
            ],
            _statsBar(_showOpponent ? p.opponentStats : p.teamStats, c),
            const SizedBox(height: SpacingTokens.md),
            AspectRatio(
              aspectRatio: 4 / 5,
              child: pitch,
            ),
            const SizedBox(height: SpacingTokens.md),
            Text(
              L10n.t('sheet.subs'),
              style:
                  TypographyTokens.sectionLabel.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: SpacingTokens.sm),
            _benchWrap(_activeBench, rf, c, onSelect),
          ],
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
                  child: _PlayerDetailColumn(
                      player: _selected, ratingForDisplay: rf),
                ),
              ],
            ),
          );
        }

        return left;
      },
    );
  }

  // Edit affordance row: the resolved-shape badge, a locked-count tag, and a
  // Reset that clears every pin and returns to the pure best XI. Editing the
  // best-by-rating view is disabled (it is the opponent-agnostic ideal XI and
  // is not produced from the lock map), so the toggle is what governs it.
  Widget _editBar(AppColorTokens c) {
    final lockCount = _locked.length;
    return Row(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: 3),
          color: c.accent.withValues(alpha: 0.14),
          child: Text(
            _displayFormation,
            style: TypographyTokens.sectionLabel
                .copyWith(color: c.accent, letterSpacing: 1.2),
          ),
        ),
        if (lockCount > 0) ...[
          const SizedBox(width: SpacingTokens.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock, size: 12, color: c.textMuted),
              const SizedBox(width: 3),
              Text(
                '$lockCount ${L10n.t('team.locked')}',
                style: TypographyTokens.sectionLabel
                    .copyWith(color: c.textMuted, fontSize: 9, letterSpacing: 1.0),
              ),
            ],
          ),
        ],
        const Spacer(),
        TextButton.icon(
          onPressed: (_busy || lockCount == 0) ? null : _resetLocks,
          icon: Icon(Icons.restart_alt, size: 16, color: c.accent),
          label: Text(
            L10n.t('team.resetLocks'),
            style: TypographyTokens.sectionLabel.copyWith(color: c.accent),
          ),
        ),
      ],
    );
  }

  void _openPlayerSheet(MatchPreviewPlayer pl) {
    AppHaptics.light();
    showAppSheet<void>(
      context,
      title: pl.shortName,
      builder: (ctx) => _PlayerDetailColumn(
        player: pl,
        ratingForDisplay: widget.ratingForDisplay,
        scrollable: false,
      ),
    );
  }

  // ── Action menu (lock / replace / unlock / details) ──────────────────────

  void _openActionMenu(MatchPreviewPlayer pl) {
    AppHaptics.light();
    final c = context.colors;
    final isStarter =
        _preview.startingXi.any((s) => s.playerId == pl.playerId);
    final isLocked = _locked.values.contains(pl.playerId);
    showAppSheet<void>(
      context,
      title: pl.shortName,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Lock to slot - only meaningful for an assigned starter.
            if (isStarter && !isLocked)
              _actionTile(
                ctx,
                icon: Icons.lock_outline,
                label: L10n.t('team.lockToSlot'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _lockToSlot(pl);
                },
              ),
            if (isLocked)
              _actionTile(
                ctx,
                icon: Icons.lock_open,
                label: L10n.t('team.unlock'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _unlock(pl);
                },
              ),
            if (isStarter)
              _actionTile(
                ctx,
                icon: Icons.swap_horiz,
                label: L10n.t('team.replacePlayer'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openReplacePicker(pl);
                },
              ),
            _actionTile(
              ctx,
              icon: Icons.bar_chart,
              label: L10n.t('team.details'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openPlayerSheet(pl);
              },
            ),
            const SizedBox(height: SpacingTokens.sm),
            Divider(height: 1, color: c.divider),
            const SizedBox(height: SpacingTokens.sm),
          ],
        );
      },
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: SpacingTokens.sm, horizontal: SpacingTokens.xs),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.accent),
            const SizedBox(width: SpacingTokens.md),
            Text(
              label,
              style: TypographyTokens.body.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Replace picker: every other player whose coarse group matches the target
  // slot's coarse group (so a CB slot offers defenders, an AM slot offers
  // midfielders, ...), drawn from both the current bench and the rest of the
  // starting XI. The pick is pinned to the target's slot.
  void _openReplacePicker(MatchPreviewPlayer target) {
    final slots = kFormationSlots[_resolvedFormation];
    final targetCoarse = (slots != null &&
            target.slotIndex >= 0 &&
            target.slotIndex < slots.length)
        ? slots[target.slotIndex].coarse
        : (target.positionGroupFine.isNotEmpty
            ? coarseForFineGroup(target.positionGroupFine)
            : target.roleGroup);

    String coarseOf(MatchPreviewPlayer p) => p.positionGroupFine.isNotEmpty
        ? coarseForFineGroup(p.positionGroupFine)
        : p.roleGroup;

    final pool = <MatchPreviewPlayer>[
      ..._preview.bench,
      ..._preview.startingXi,
    ].where((p) =>
        p.playerId != target.playerId && coarseOf(p) == targetCoarse).toList()
      ..sort((a, b) =>
          widget.ratingForDisplay(b).compareTo(widget.ratingForDisplay(a)));

    AppHaptics.light();
    showAppSheet<void>(
      context,
      title: L10n.t('team.choosePlayer'),
      builder: (ctx) {
        final c = ctx.colors;
        if (pool.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: SpacingTokens.lg),
            child: Text(
              L10n.t('team.noCompatiblePlayers'),
              style: TypographyTokens.body.copyWith(color: c.textMuted),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final cand in pool)
              _replaceCandidateTile(ctx, cand, () {
                Navigator.of(ctx).pop();
                _replaceInSlot(target, cand);
              }),
            const SizedBox(height: SpacingTokens.sm),
          ],
        );
      },
    );
  }

  Widget _replaceCandidateTile(
      BuildContext context, MatchPreviewPlayer p, VoidCallback onTap) {
    final c = context.colors;
    final coarse = p.positionGroupFine.isNotEmpty
        ? coarseForFineGroup(p.positionGroupFine)
        : p.roleGroup;
    final roleColor =
        recommendedXiRoleColor(coarse.isNotEmpty ? coarse : p.roleGroup, c);
    final label =
        p.positionGroupFine.isNotEmpty ? p.positionGroupFine : p.roleGroup;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        color: c.surfaceLow,
        padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.sm, vertical: SpacingTokens.sm),
        child: Row(
          children: [
            PlayerPhotoAvatar(
              photoUrl: p.photoUrl,
              name: p.shortName,
              ringColor: roleColor,
              size: 38,
            ),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.shortName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypographyTokens.body
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    label.toUpperCase(),
                    style: TypographyTokens.sectionLabel.copyWith(
                        color: c.textMuted, fontSize: 9, letterSpacing: 1.2),
                  ),
                ],
              ),
            ),
            Text(
              widget.ratingForDisplay(p).toStringAsFixed(0),
              style: TypographyTokens.statValue
                  .copyWith(color: c.textPrimary, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsBar(MatchTeamStats s, AppColorTokens c) {
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceLow,
        borderRadius: ShapeTokens.card,
        border: Border.all(color: c.divider),
      ),
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
      child: Row(
        children: [
          Expanded(
            child: StatTile(
              value: s.avgRecentForm.toStringAsFixed(1),
              icon: Icons.show_chart,
              caption: L10n.t('team.statForm'),
              tooltip: L10n.t('team.statFormTip'),
            ),
          ),
          Expanded(
            child: StatTile(
              value: s.avgPerformanceScore.toStringAsFixed(1),
              icon: Icons.speed,
              caption: L10n.t('team.statPerformance'),
              tooltip: L10n.t('team.statPerformanceTip'),
            ),
          ),
          Expanded(
            child: StatTile(
              value: '${s.avgPassAccuracy.toStringAsFixed(0)}%',
              icon: Icons.alt_route,
              caption: L10n.t('team.statPasses'),
              tooltip: L10n.t('team.statPassesTip'),
            ),
          ),
          Expanded(
            child: StatTile(
              value: '${s.avgDuelWinRate.toStringAsFixed(0)}%',
              icon: Icons.sports_kabaddi,
              caption: L10n.t('team.statDuels'),
              tooltip: L10n.t('team.statDuelsTip'),
            ),
          ),
        ],
      ),
    );
  }

  // Predicted-most-likely XI (default) vs the best-by-rating 'ideal' XI, so the
  // committee can contrast selection-likelihood against raw quality.
  /// Segment label for a club: shorten U Cluj's long form and upper-case it.
  String _teamLabel(String name) =>
      name.replaceAll('Universitatea Cluj', 'U Cluj').toUpperCase();

  Widget _xiToggle(AppColorTokens c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedToggle<bool>(
          value: _showOpponent,
          onChanged: _setShowOpponent,
          segments: [
            SegmentOption(
                value: false, label: _teamLabel(_preview.homeTeamShort)),
            SegmentOption(
                value: true, label: _teamLabel(_preview.opponentName)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          L10n.t('team.explainOtherXi'),
          style: TypographyTokens.bodySmall.copyWith(
            color: c.textMuted,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _benchWrap(
    List<MatchPreviewPlayer> bench,
    double Function(MatchPreviewPlayer p) rf,
    AppColorTokens c,
    void Function(MatchPreviewPlayer) onSelect,
  ) {
    if (bench.isEmpty) {
      return Text(
        '-',
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
          final baseLabel =
              pl.positionGroupFine.isNotEmpty ? pl.positionGroupFine : pl.roleGroup;
          // Reveal the L/R flank on bench cards: their fine group (FB/WB/W) does
          // not itself encode a side the way a slot label (RB/LB) does, so we
          // prefix the side tag when the player has a clear preferred flank.
          final side = pl.sideTag;
          final benchLabel = side.isNotEmpty ? '$side $baseLabel' : baseLabel;
          final roleColor = recommendedXiRoleColor(
              benchCoarse.isNotEmpty ? benchCoarse : pl.roleGroup, c);
          return GestureDetector(
            onTap: () => onSelect(pl),
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
                  // Quality rating (within-position percentile) and the
                  // optimiser's SEL selection score side by side, so a coach
                  // sees why a high-rated sub is still on the bench (low SEL).
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        rf(pl).toStringAsFixed(0),
                        style: TypographyTokens.statValue.copyWith(
                          color: c.textPrimary,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'SEL ${pl.selectionScore}',
                        style: TypographyTokens.sectionLabel.copyWith(
                          fontSize: 8,
                          color: c.accent,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
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
  final double value; // 0-100
}

// Two honest lenses, kept separate (a club reads volume and efficiency as
// different questions, never one blended number). Every value is the player's
// WITHIN-POSITION league percentile (0-100) of a real Wyscout KPI, computed
// server-side (statPct), so a striker is ranked among strikers and a centre-back
// among centre-backs.

// OUTPUT / VOLUME lens (the radar): per-90 raw counts. These are the stats that
// actually build performance_score, so the radar explains WHY a player earns
// their rating. Exactly six axes (the radar is a hexagon).
List<_FifaAttr> _outputAttrs(MatchPreviewPlayer p) {
  double pct(String key) => (p.statPct[key] ?? 50.0).clamp(0, 100).toDouble();

  if (p.roleGroup == 'GK') {
    return [
      _FifaAttr(L10n.t('stat.saves'), pct('per90_gkSaves')),
      _FifaAttr(L10n.t('stat.cleanSheet'), pct('per90_gkCleanSheets')),
      _FifaAttr(L10n.t('stat.sweeping'), pct('per90_gkSuccessfulExits')),
      _FifaAttr(L10n.t('stat.aerial'), pct('per90_gkAerialDuelsWon')),
      _FifaAttr(L10n.t('stat.passing'), pct('per90_successfulPasses')),
      _FifaAttr(L10n.t('stat.form'), pct('recent_form_score')),
    ];
  }

  switch (p.roleGroup) {
    case 'DEF':
      return [
        _FifaAttr(L10n.t('stat.passing'), pct('per90_successfulPasses')),
        _FifaAttr(L10n.t('stat.duels'), pct('per90_defensiveDuelsWon')),
        _FifaAttr(L10n.t('stat.aerial'), pct('per90_aerialDuelsWon')),
        _FifaAttr(L10n.t('stat.clears'), pct('per90_clearances')),
        _FifaAttr(L10n.t('stat.intercept'), pct('per90_interceptions')),
        _FifaAttr(L10n.t('stat.blocks'), pct('per90_shotsBlocked')),
      ];
    case 'MID':
      return [
        _FifaAttr(L10n.t('stat.passing'), pct('per90_successfulPasses')),
        _FifaAttr(L10n.t('stat.progress'), pct('per90_progressivePasses')),
        _FifaAttr(L10n.t('stat.keyPass'), pct('per90_keyPasses')),
        _FifaAttr(L10n.t('stat.recover'), pct('per90_recoveries')),
        _FifaAttr(L10n.t('stat.duels'), pct('per90_defensiveDuelsWon')),
        _FifaAttr(L10n.t('stat.dribbles'), pct('per90_successfulDribbles')),
      ];
    default: // FWD
      return [
        _FifaAttr(L10n.t('stat.goals'), pct('per90_goals')),
        _FifaAttr(L10n.t('stat.shots'), pct('per90_shots')),
        _FifaAttr(L10n.t('stat.dribbles'), pct('per90_successfulDribbles')),
        _FifaAttr(L10n.t('stat.keyPass'), pct('per90_keyPasses')),
        _FifaAttr(L10n.t('stat.crosses'), pct('per90_successfulCrosses')),
        _FifaAttr(L10n.t('stat.boxTouches'), pct('per90_touchInBox')),
      ];
  }
}

// EFFICIENCY lens (the bars): success rates, the quality-per-action view. A
// high-volume player with low rates (busy but beaten) reads honestly here.
List<_FifaAttr> _efficiencyAttrs(MatchPreviewPlayer p) {
  double pct(String key) => (p.statPct[key] ?? 50.0).clamp(0, 100).toDouble();

  if (p.roleGroup == 'GK') {
    return [
      _FifaAttr(L10n.t('stat.passPct'), pct('pass_accuracy')),
      _FifaAttr(L10n.t('stat.aerialPct'), pct('aerial_win_rate')),
      _FifaAttr(L10n.t('stat.form'), pct('recent_form_score')),
    ];
  }

  switch (p.roleGroup) {
    case 'DEF':
      return [
        _FifaAttr(L10n.t('stat.duelsPct'), pct('duel_win_rate')),
        _FifaAttr(L10n.t('stat.aerialPct'), pct('aerial_win_rate')),
        _FifaAttr(L10n.t('stat.defPct'), pct('def_action_success')),
        _FifaAttr(L10n.t('stat.passPct'), pct('pass_accuracy')),
        _FifaAttr(L10n.t('stat.form'), pct('recent_form_score')),
      ];
    case 'MID':
      return [
        _FifaAttr(L10n.t('stat.passPct'), pct('pass_accuracy')),
        _FifaAttr(L10n.t('stat.dribblePct'), pct('dribble_success')),
        _FifaAttr(L10n.t('stat.duelsPct'), pct('duel_win_rate')),
        _FifaAttr(L10n.t('stat.defPct'), pct('def_action_success')),
        _FifaAttr(L10n.t('stat.form'), pct('recent_form_score')),
      ];
    default: // FWD
      return [
        _FifaAttr(L10n.t('stat.shotPct'), pct('shot_accuracy')),
        _FifaAttr(L10n.t('stat.dribblePct'), pct('dribble_success')),
        _FifaAttr(L10n.t('stat.duelsPct'), pct('duel_win_rate')),
        _FifaAttr(L10n.t('stat.passPct'), pct('pass_accuracy')),
        _FifaAttr(L10n.t('stat.form'), pct('recent_form_score')),
      ];
  }
}

/// Two-line section caption (header + percentile sublabel), used to title the
/// game-volume and efficiency blocks on the player card.
Widget _sectionCaption(String title, String sub, AppColorTokens c) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TypographyTokens.sectionLabel.copyWith(
          fontSize: 9,
          color: c.accent,
          letterSpacing: 1.5,
        ),
      ),
      Text(
        sub,
        style: TypographyTokens.sectionLabel.copyWith(
          fontSize: 8,
          color: c.textMuted,
          letterSpacing: 1.0,
        ),
      ),
    ],
  );
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
    this.scrollable = true,
  });

  final MatchPreviewPlayer? player;
  final double Function(MatchPreviewPlayer p) ratingForDisplay;

  /// When false (inside a bottom sheet that already scrolls), returns the bare
  /// content column instead of wrapping it in its own scroll view + padding.
  final bool scrollable;

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
    final effAttrs = _efficiencyAttrs(p);
    // Prefer the official slot label (which already encodes side, e.g. RB/LB),
    // then the fine group prefixed with the L/R flank when meaningful, then the
    // coarse role; colour by the corresponding coarse group.
    final detailLabel = p.officialPosition.isNotEmpty
        ? p.officialPosition
        : (p.positionGroupFine.isNotEmpty
            ? (p.sideTag.isNotEmpty
                ? '${p.sideTag} ${p.positionGroupFine}'
                : p.positionGroupFine)
            : p.roleGroup);
    final detailCoarse = p.positionGroupFine.isNotEmpty
        ? coarseForFineGroup(p.positionGroupFine)
        : p.roleGroup;
    final roleColor = recommendedXiRoleColor(
        detailCoarse.isNotEmpty ? detailCoarse : p.roleGroup, c);

    final content = Column(
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
                      style: TypographyTokens.statLarge.copyWith(
                        fontSize: 40,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      L10n.t('team.rating'),
                      style: TypographyTokens.sectionLabel.copyWith(
                        fontSize: 8,
                        color: c.textMuted,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Selection score: the optimiser's selection signal, kept
                    // distinct from the quality rating so a coach reads why a
                    // high-rated player can still be benched (low SEL).
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      color: c.accent.withValues(alpha: 0.16),
                      child: Text(
                        '${L10n.t('team.selTag')} ${p.selectionScore}',
                        style: TypographyTokens.sectionLabel.copyWith(
                          fontSize: 9,
                          color: c.accent,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: SpacingTokens.lg),

          // ── Output / volume lens (radar) ────────────────────────────────
          // The per-90 work-rate stats that BUILD the rating, so the headline
          // number is explained. Role-coloured silhouette on a tonal tray.
          _sectionCaption(
            L10n.t('team.playerVolume'),
            '${L10n.t('team.percentileInLeague')} · ${_attrCompareLabel(p)}',
            c,
          ),
          const SizedBox(height: SpacingTokens.sm),
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

          // ── Efficiency lens (bars) ──────────────────────────────────────
          // Success rates: quality per action, kept separate from the raw
          // volume above so a busy-but-beaten profile reads true.
          _sectionCaption(
            L10n.t('team.playerEfficiency'),
            '${L10n.t('team.percentileInLeague')} · ${_attrCompareLabel(p)}',
            c,
          ),
          const SizedBox(height: SpacingTokens.sm),
          for (final a in effAttrs) _fifaAttrRow(a, c),

          const SizedBox(height: SpacingTokens.lg),

          // ── Fitness / rotation (load advisor) ───────────────────────────
          // Freshness plus the rotation read from the ACWR + age + season-role
          // model: a high freshness bar, a status pill, and a "rested, ready"
          // tag for a rested regular.
          _sectionCaption(
            L10n.t('team.playerFitness'),
            'ACWR ${p.acwr.toStringAsFixed(2)} · ${p.restDays.toStringAsFixed(0)} ${L10n.t('team.daysRest')}',
            c,
          ),
          const SizedBox(height: SpacingTokens.sm),
          _fifaAttrRow(_FifaAttr(L10n.t('team.freshness'), p.freshness), c),
          const SizedBox(height: SpacingTokens.xs),
          _loadStatusRow(p, c),
        ],
    );

    if (!scrollable) return content;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: content,
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
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                a.label,
                maxLines: 1,
                style: TypographyTokens.body.copyWith(
                  fontSize: 11,
                  color: c.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Rotation status pill row: fatigue-risk band plus a "rested, ready" tag.
  Widget _loadStatusRow(MatchPreviewPlayer p, AppColorTokens c) {
    Color color;
    String label;
    switch (p.loadStatus) {
      case 'at_risk':
        color = c.negative;
        label = L10n.t('team.loadAtRisk');
        break;
      case 'fresh':
        color = c.positive;
        label = L10n.t('team.loadFresh');
        break;
      default:
        color = c.accent;
        label = L10n.t('team.loadOk');
    }
    return Wrap(
      spacing: SpacingTokens.xs,
      runSpacing: SpacingTokens.xs,
      children: [
        _loadPill(label, color, c),
        if (p.restedAndReady) _loadPill(L10n.t('team.restedReady'), c.accent, c),
      ],
    );
  }

  Widget _loadPill(String text, Color color, AppColorTokens c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: color.withValues(alpha: 0.16),
      child: Text(
        text,
        style: TypographyTokens.sectionLabel.copyWith(
          fontSize: 9,
          color: color,
          letterSpacing: 1.0,
        ),
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
    this.lockedSlots = const {},
  });

  final String formation;
  final List<MatchPreviewPlayer> players;
  final MatchPreviewPlayer? selected;
  final ValueChanged<MatchPreviewPlayer> onSelect;
  final double Function(MatchPreviewPlayer p) ratingForDisplay;

  /// Slot indices currently pinned by the staff; the chip in each pinned slot
  /// shows a small lock badge. Empty in read-only mode.
  final Set<int> lockedSlots;

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
                  locked: lockedSlots.contains(p.player.slotIndex),
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
    this.locked = false,
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

  /// Whether this player is pinned to its slot. When true a small lock badge is
  /// drawn in the chip's top-right corner.
  final bool locked;

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
    // FIFA-style token: a clean rounded headshot with the rating + position in
    // a solid role-coloured corner badge (no heavy ring, no surface box). The
    // selection state lifts the avatar ring to the accent colour.
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: chipSize,
        height: chipSize,
        child: Stack(
          children: [
            Positioned.fill(
              child: PlayerPhotoAvatar(
                photoUrl: player.photoUrl,
                name: player.shortName,
                ringColor: selected ? c.accent : roleColor,
                size: chipSize,
              ),
            ),
            Positioned(
              top: chipSize * 0.05,
              left: chipSize * 0.05,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: chipSize * 0.07,
                  vertical: chipSize * 0.02,
                ),
                decoration: BoxDecoration(
                  color: roleColor,
                  borderRadius: BorderRadius.circular(chipSize * 0.1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      rating.toStringAsFixed(0),
                      style: TypographyTokens.statValue.copyWith(
                        color: Colors.white,
                        fontSize: chipSize * 0.22,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      label,
                      style: TypographyTokens.sectionLabel.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: chipSize * 0.1,
                        height: 1.15,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (locked)
              Positioned(
                top: chipSize * 0.04,
                right: chipSize * 0.04,
                child: Container(
                  padding: EdgeInsets.all(chipSize * 0.04),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(chipSize * 0.1),
                  ),
                  child: Icon(
                    Icons.lock,
                    size: chipSize * 0.20,
                    color: Colors.white,
                  ),
                ),
              ),
            // Selection-score tag (bottom-left): the optimiser's selection
            // signal (round(predicted_score*100)), labelled "SEL" so it reads
            // distinctly from the role-coloured quality rating in the top-left.
            // This is why a high-rating player can still be benched.
            Positioned(
              bottom: chipSize * 0.04,
              left: chipSize * 0.04,
              child: _SelTag(value: player.selectionScore, chipSize: chipSize),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact "SEL" tag: a cobalt selection-score chip used on the pitch chip and
/// the bench card so a coach can read the optimiser's selection signal next to
/// the within-position quality rating. Sharp edges, tonal, no shadow.
class _SelTag extends StatelessWidget {
  const _SelTag({required this.value, required this.chipSize});

  final int value;
  final double chipSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: chipSize * 0.06,
        vertical: chipSize * 0.015,
      ),
      decoration: BoxDecoration(
        color: c.scrim.withValues(alpha: 0.82),
        border: Border(left: BorderSide(color: c.accent, width: 1.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            L10n.t('team.selTag'),
            style: TypographyTokens.sectionLabel.copyWith(
              color: c.accent,
              fontSize: chipSize * 0.10,
              height: 1.0,
              letterSpacing: 0.4,
            ),
          ),
          SizedBox(width: chipSize * 0.04),
          Text(
            '$value',
            style: TypographyTokens.statValue.copyWith(
              color: Colors.white,
              fontSize: chipSize * 0.15,
              height: 1.0,
            ),
          ),
        ],
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
    final attrs = _outputAttrs(player);
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
    if (values.isEmpty) return;
    final c = Offset(size.width / 2, size.height / 2 + 8);
    final r = math.min(size.width, size.height) * 0.38;
    final n = values.length;
    final points = <Offset>[];

    for (var i = 0; i < n; i++) {
      final ang = -math.pi / 2 + (2 * math.pi * i / n);
      final vr = r * values[i].clamp(0.05, 1.0);
      points.add(Offset(c.dx + vr * math.cos(ang), c.dy + vr * math.sin(ang)));
    }

    final grid = Paint()
      // Derive from labelColor (light on the dark theme, dark on the light
      // theme) so the radar grid stays visible on both surfaces.
      ..color = labelColor.withValues(alpha: 0.18)
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
