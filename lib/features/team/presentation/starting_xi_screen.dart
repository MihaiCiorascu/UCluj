import 'package:flutter/material.dart';

import '../../../core/primitives/app_button.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_bottom_nav.dart';
import '../../../data/models/xi_prediction.dart';
import '../../../data/repositories/xi_repository.dart';

class StartingXiScreen extends StatefulWidget {
  const StartingXiScreen({
    required this.onTabSelected,
    this.onProfileTap,
    super.key,
  });

  final ValueChanged<AppTab> onTabSelected;
  final VoidCallback? onProfileTap;

  @override
  State<StartingXiScreen> createState() => _StartingXiScreenState();
}

class _StartingXiScreenState extends State<StartingXiScreen> {
  final _xiRepository = XiRepository();
  bool _isLoading = false;
  bool _isLoadingOpponents = true;
  XiPredictionResponse? _prediction;
  String _selectedFormation = '4-3-3';
  String? _errorMessage;
  String? _opponentsError;

  int? _selectedOpponentId;
  final Map<int, String> _opponents = {};

  final List<String> _formations = [
    '4-3-3',
    '4-4-2',
    '4-2-3-1',
    '3-5-2',
    '3-4-3',
    '5-3-2',
    '5-4-1',
  ];

  @override
  void initState() {
    super.initState();
    _loadOpponentOptions();
  }

  Future<void> _loadOpponentOptions() async {
    try {
      final opponents = await _xiRepository.fetchOpponentOptions();
      if (!mounted) return;

      setState(() {
        _opponents
          ..clear()
          ..addEntries(opponents.map((o) => MapEntry(o.id, o.name)));
        _selectedOpponentId =
            opponents.isNotEmpty ? opponents.first.id : null;
        _isLoadingOpponents = false;
        _opponentsError = opponents.isEmpty
            ? 'No opponent options available.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingOpponents = false;
        _opponentsError = 'Could not load opponent teams: $e';
      });
    }
  }

  Future<void> _generateXi() async {
    if (_selectedOpponentId == null) {
      setState(() {
        _errorMessage = 'Please select an opponent team first.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _xiRepository.predictXi(
        formation: _selectedFormation,
        opponentTeamId: _selectedOpponentId,
      );
      setState(() {
        _prediction = response;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppScaffold(
      currentTab: AppTab.dashboard,
      onTabSelected: widget.onTabSelected,
      onProfileTap: widget.onProfileTap,
      body: ListView(
        children: [
          Text('TACTICAL BLUEPRINT',
              style: TypographyTokens.sectionLabel
                  .copyWith(color: c.accent)),
          const SizedBox(height: SpacingTokens.xs),
          Text('STARTING XI',
              style: TypographyTokens.displayHero.copyWith(fontSize: 48)),
          const SizedBox(height: SpacingTokens.xl),

          _buildDropdowns(context),
          const SizedBox(height: SpacingTokens.md),

          AppButton.primary(
            label: _isLoading ? 'GENERATING...' : 'GENERATE XI',
            onPressed: _isLoading ? null : () => _generateXi(),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: SpacingTokens.md),
            Text('Error: $_errorMessage', style: TypographyTokens.body.copyWith(color: c.negative)),
          ],

          const SizedBox(height: SpacingTokens.xl),

          if (_prediction != null && !_isLoading) _buildResults(context),
        ],
      ),
    );
  }

  Widget _buildDropdowns(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('FORMATION', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.xs),
        Container(
          color: c.surface,
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: c.surface,
              value: _selectedFormation,
              style: TypographyTokens.body.copyWith(color: c.textPrimary),
              onChanged: (v) {
                if (v != null) setState(() => _selectedFormation = v);
              },
              items: _formations.map((f) => DropdownMenuItem(
                value: f,
                child: Text(f),
              )).toList(),
            ),
          ),
        ),
        const SizedBox(height: SpacingTokens.md),
        Text('OPPONENT', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.xs),
        if (_isLoadingOpponents)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.accent,
              ),
            ),
          )
        else if (_opponentsError != null)
          Text(
            _opponentsError!,
            style: TypographyTokens.body.copyWith(color: c.negative),
          )
        else
          Container(
            color: c.surface,
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                isExpanded: true,
                dropdownColor: c.surface,
                menuMaxHeight: 240,
                value: _selectedOpponentId,
                style: TypographyTokens.body.copyWith(color: c.textPrimary),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedOpponentId = v);
                },
                items: _opponents.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SELECTED XI', style: TypographyTokens.sectionLabel.copyWith(color: c.accent)),
        const SizedBox(height: SpacingTokens.sm),
        _buildPlayerList(context, _prediction!.startingXI),

        const SizedBox(height: SpacingTokens.xl),
        Text('BENCH', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.sm),
        _buildPlayerList(context, _prediction!.bench),
        const SizedBox(height: SpacingTokens.xl),
      ],
    );
  }

  Widget _buildPlayerList(BuildContext context, List<XiPlayer> players) {
    final c = context.colors;
    if (players.isEmpty) {
      return AppEmptyState(
        icon: Icons.person_outline,
        headline: L10n.t('xi.noPlayers'),
        body: L10n.t('xi.noPlayersBody'),
      );
    }

    final order = ['GK', 'DEF', 'MID', 'FWD'];
    final List<Widget> sections = [];

    for (var group in order) {
      // Order players within a coarse section by their official slot so the
      // list reads in the same sequence as the pitch (left to right).
      final groupPlayers = players.where((p) => p.roleGroup == group).toList()
        ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
      if (groupPlayers.isEmpty) continue;

      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: SpacingTokens.md, bottom: SpacingTokens.xs),
          child: Text(group, style: TypographyTokens.sectionLabel),
        ),
      );

      for (var p in groupPlayers) {
        // Prefer the official slot label, then the fine group, then the raw
        // Wyscout role string.
        final positionLabel = p.officialPosition.isNotEmpty
            ? p.officialPosition
            : (p.positionGroupFine.isNotEmpty ? p.positionGroupFine : p.role);
        sections.add(
          Container(
            margin: const EdgeInsets.only(bottom: 2),
            color: c.surfaceLow,
            padding: const EdgeInsets.all(SpacingTokens.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.shortName, style: TypographyTokens.headline.copyWith(fontSize: 16)),
                      Text(positionLabel, style: TypographyTokens.body.copyWith(color: c.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      p.rating > 0
                          ? '${p.rating}'
                          : (p.predictedScore * 100).clamp(0, 99).round().toString(),
                      style: TypographyTokens.headline.copyWith(color: c.accent, fontSize: 16),
                    ),
                    Text('RATING', style: TypographyTokens.body.copyWith(color: c.textMuted, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }
}
