"""
Starting-XI service for UmbraRo.

Iteration L generalisation: ``XiService`` now accepts a per-request
``home_team_substring`` (or a team short label or Sportradar ID) and
returns the predicted XI for that team. The previous U Cluj-only path
is preserved as the default — every method falls back to U Cluj when
the caller does not specify a team. The Flutter app keeps working
unchanged, but any of the sixteen Romanian Superliga teams can now be
queried.

Per-team feature DataFrames are cached on the service instance so that
repeat calls for the same team stay fast (the cold path costs roughly
five seconds while the league dataset is materialised and the per-team
availability features are computed).
"""

from __future__ import annotations

import glob
import os
import pickle
from typing import Dict, List, Optional

import numpy as np
import pandas as pd

from ml.feature_engineering import get_team_squad_from_matches
from ml.pipeline import _format_output, build_dataset_from_files, load_player_profiles
from ml.match_dates import load_match_dates, parse_date
from ml.xi_predictor import CURATED_FORMATIONS, MAX_BENCH, StartingXIPredictor
from app.config import effective_now
from services.load_service import assess_player
from services.player_photo_service import PlayerPhotoService
from sportradar.team_registry import (
    SUPERLIGA_TEAMS,
    TeamRef,
    team_by_alias,
    team_by_short,
    team_by_sr_id,
)

# Wyscout team IDs (used historically by the front-end for team selection).
# Retained for backwards compatibility — new code should prefer
# :data:`sportradar.team_registry.SUPERLIGA_TEAMS`.
FIXTURE_NAME_TO_ID: dict[str, int] = {
    "U Cluj": 11571,
    "CFR Cluj": 11611,
    "FCSB": 8164,
    "Rapid Bucuresti": 11566,
    "Dinamo Bucuresti": 11564,
    "FC Botosani": 11634,
    "Unirea Slobozia": 11663,
    "Metaloglobus Bucuresti": 11943,
    "Csikszereda M. Ciuc": 22731,
    "FC Arges": 23334,
    "U Craiova 1948": 26233,
    "Univ. Craiova": 26233,
    "UTA Arad": 30817,
    "FC Hermannstadt": 55427,
    "Petrolul Ploiesti": 60390,
    "Farul Constanta": 61242,
    "Otelul Galati": 69049,
    "Sepsi Sf. Gheorghe": None,
}


# Columns shown on the player card / radar. Each is normalised into a
# within-position league percentile (0-100) so a striker is ranked against
# strikers and a left-back against left-backs, never across roles. These are
# all real Wyscout-derived aggregates already emitted by feature_engineering.
_RAW_COLS = [
    "performance_score", "recent_form_score",
    "pass_accuracy", "duel_win_rate",
    "shot_accuracy", "dribble_success", "def_action_success", "aerial_win_rate",
    "per90_goals", "per90_assists", "per90_keyPasses", "per90_shots",
    "per90_interceptions", "per90_gkSaves", "per90_gkCleanSheets",
    # Output / volume drivers (per-90 raw counts). These are the stats that
    # actually build performance_score, so the card can show WHY a player earns
    # their rating (the radar), kept distinct from the efficiency rates above
    # (the "quality per action" strip). All confirmed present in the Wyscout
    # total block.
    "per90_defensiveDuelsWon", "per90_aerialDuelsWon", "per90_clearances",
    "per90_recoveries", "per90_shotsBlocked", "per90_successfulPasses",
    "per90_progressivePasses", "per90_successfulCrosses", "per90_successfulDribbles",
    "per90_passesToFinalThird", "per90_touchInBox", "per90_shotsOnTarget",
    "per90_gkSuccessfulExits", "per90_gkAerialDuelsWon",
]

# A fine position group needs at least this many league players for a stable
# percentile; below it (for example wing-backs, of which the league has only a
# handful) the player is ranked against the coarse group instead.
_MIN_FINE_GROUP = 15
# Minimum minutes for a player to enter the percentile reference pool. Rate
# stats (duel %, pass %, per-90s) from tiny samples are noise, and including
# them made the within-position percentiles and the derived rating jumpy, e.g.
# a regular centre-back reading an 11th-percentile duel rate against fringe
# players with fluky high rates. Regulars only give a stable, fair reference.
_MIN_MINUTES = 450

# Columns pulled from the feature frame into each player record before
# ``_normalise_player`` attaches the within-position percentiles + rating.
# Mirrors ml.pipeline._format_output so the standalone XI screen and the match
# preview carry the same fields, and includes the per-90 output drivers so the
# radar can be built from the rating's own components.
_PLAYER_COLS = [
    "playerId", "shortName", "role", "role_group",
    "position_group_fine", "position_side", "official_position", "slot_index",
    "predicted_score", "performance_score", "recent_form_score",
    "total_minutes", "matches_played",
    "pass_accuracy", "duel_win_rate",
    "shot_accuracy", "dribble_success", "def_action_success", "aerial_win_rate",
    "per90_goals", "per90_assists", "per90_shots",
    "per90_keyPasses", "per90_interceptions", "per90_gkSaves",
    "per90_gkCleanSheets",
    "per90_defensiveDuelsWon", "per90_aerialDuelsWon", "per90_clearances",
    "per90_recoveries", "per90_shotsBlocked", "per90_successfulPasses",
    "per90_progressivePasses", "per90_successfulCrosses", "per90_successfulDribbles",
    "per90_passesToFinalThird", "per90_touchInBox", "per90_shotsOnTarget",
    "per90_gkSuccessfulExits", "per90_gkAerialDuelsWon",
    # Load / fatigue / age / role (point-in-time), for the rotation advisor + UI.
    "age_at_fixture", "season_start_rate", "rest_days",
    "minutes_last_14d", "matches_last_10d", "acute_load", "chronic_load",
    "acwr", "minutes_trend",
    "cumulative_minutes_before_fixture", "cumulative_appearances",
]


def _normalise_formation(formation: Optional[str]) -> str:
    """Coerce a requested formation to ``"auto"`` or a curated key.

    The only formations offered to (and evaluated for) the coach are the curated
    nine in :data:`CURATED_FORMATIONS`. ``"auto"`` (case-insensitive), an empty
    value, or any formation outside the curated set all collapse to ``"auto"`` so
    the predictor searches the curated shapes and returns the best one. A curated
    key passes through unchanged.
    """
    f = (formation or "").strip()
    if not f or f.lower() == "auto":
        return "auto"
    return f if f in CURATED_FORMATIONS else "auto"


class XiService:
    """Starting-XI predictor service that supports any Romanian Superliga team.

    The default home team remains FC Universitatea Cluj for backwards
    compatibility, but the public methods now accept a
    ``home_team_substring`` (or any team-registry alias) so that callers
    can request another club's predicted XI without touching service
    internals.
    """

    DEFAULT_HOME_TEAM_SUBSTRING = "Universitatea Cluj"

    def __init__(self, model_path: str, data_dir: str):
        self.model_path = model_path
        self.data_dir = data_dir
        self.predictor: Optional[StartingXIPredictor] = None
        self._df_by_team: Dict[str, pd.DataFrame] = {}
        self._squad_by_team: Dict[str, set] = {}
        self._profiles: Dict = {}
        # League-wide frame + per-group percentile tables, built once and reused
        # for the within-position rating and stat normalisation.
        self._league_df: Optional[pd.DataFrame] = None
        self._pct_fine: Optional[Dict[str, Dict[str, np.ndarray]]] = None
        self._pct_coarse: Optional[Dict[str, Dict[str, np.ndarray]]] = None

        # Self-hosted player headshots (Wyscout id -> S3 URL). Reads a committed
        # mapping next to the match data; empty/missing means the UI uses
        # initials. Never calls SofaScore or AWS at runtime.
        self._photos = PlayerPhotoService(
            os.path.join(os.path.dirname(data_dir), "wyscout_to_sofascore.json")
        )

        # Pre-load the heuristic-predictor pickle.
        if os.path.exists(model_path):
            with open(model_path, "rb") as f:
                self.predictor = pickle.load(f)

        # Iteration J.4: Auto-load the supervised lineup-classifier bundle
        # alongside the heuristic predictor. Iteration L will replace this
        # path with the league-wide bundle (``xi_lineup_model_league.joblib``)
        # once the pooled supervised model is retrained.
        league_bundle = os.path.join(
            os.path.dirname(model_path), "xi_lineup_model_league.joblib"
        )
        ucluj_bundle = os.path.join(
            os.path.dirname(model_path), "xi_lineup_model.joblib"
        )
        bundle_path = league_bundle if os.path.exists(league_bundle) else ucluj_bundle
        if self.predictor is not None and os.path.exists(bundle_path):
            try:
                import joblib
                self.predictor.supervised_bundle = joblib.load(bundle_path)
            except Exception:
                pass

    # ── Team-registry helpers ────────────────────────────────────────────────

    def _resolve_home_team(
        self,
        home_team_substring: Optional[str] = None,
        home_team_sr_id: Optional[str] = None,
        home_team_short: Optional[str] = None,
    ) -> TeamRef:
        """Resolve a TeamRef from any of the supported caller inputs."""
        if home_team_sr_id:
            t = team_by_sr_id(home_team_sr_id)
            if t is not None:
                return t
        if home_team_short:
            t = team_by_short(home_team_short)
            if t is not None:
                return t
        if home_team_substring:
            t = team_by_alias(home_team_substring)
            if t is not None:
                return t
            # Fall back to a free-form substring (handy for older callers).
            return TeamRef(
                short=home_team_substring,
                wy_substr=home_team_substring,
                sr_id="",
            )
        return team_by_alias(self.DEFAULT_HOME_TEAM_SUBSTRING) or SUPERLIGA_TEAMS[0]

    # ── Feature-DataFrame builder (cached per home team) ─────────────────────

    @staticmethod
    def _asof_date():
        """Reference 'next fixture' date for the load / fatigue windows.

        Anchored just after the most recent match present in the data, capped at
        the effective clock. The player data can end before the demo's pinned
        'today', so anchoring to the data (rather than the raw demo date) keeps
        the rolling 7/14/28-day windows populated and the fatigue signal
        meaningful instead of reading everyone as long-rested.
        """
        from datetime import timedelta
        dates = [d for d in (parse_date(v) for v in load_match_dates().values()) if d]
        if not dates:
            return effective_now().date()
        return min(effective_now().date(), max(dates) + timedelta(days=4))

    def _get_feature_df(self, home_team: TeamRef) -> pd.DataFrame:
        cache_key = home_team.wy_substr
        if cache_key in self._df_by_team:
            return self._df_by_team[cache_key]

        match_files = sorted(glob.glob(os.path.join(self.data_dir, "*.json")))
        profile_path = os.path.join(self.data_dir, "players (1).json")
        if not self._profiles and os.path.exists(profile_path):
            self._profiles = load_player_profiles(profile_path)

        # Availability features are computed against *this* home team's
        # chronological fixture list. A player who does not belong to
        # the home team's empirical squad receives neutral availability
        # zeros — the same convention as the per-U Cluj implementation
        # used in Iterations J and K.
        df = build_dataset_from_files(
            match_files,
            self._profiles,
            availability_team_substring=home_team.wy_substr,
            as_of_date=self._asof_date(),
        )

        squad_ids = get_team_squad_from_matches(
            match_files,
            home_team.wy_substr,
            as_of_date=self._asof_date(),
        )

        def _resolve_team(pid):
            profile = self._profiles.get(pid, {})
            return profile.get("currentTeamId", None)

        df["teamId"] = df["playerId"].apply(_resolve_team)
        df["is_home_squad"] = df["playerId"].isin(squad_ids)

        self._df_by_team[cache_key] = df
        self._squad_by_team[cache_key] = squad_ids
        return df

    # ── League-relative normalisation (within fine position group) ────────────

    def _get_league_df(self) -> pd.DataFrame:
        """Return one row per league player, used as the percentile reference.

        Built once from every match file (so it spans all sixteen clubs) with
        no availability-team coupling. Deduplicated by playerId, keeping the
        row with the most matches played.
        """
        if self._league_df is not None:
            return self._league_df

        match_files = sorted(glob.glob(os.path.join(self.data_dir, "*.json")))
        profile_path = os.path.join(self.data_dir, "players (1).json")
        if not self._profiles and os.path.exists(profile_path):
            self._profiles = load_player_profiles(profile_path)

        df = build_dataset_from_files(match_files, self._profiles)
        if "playerId" in df.columns and "matches_played" in df.columns:
            df = df.sort_values("matches_played", ascending=False).drop_duplicates("playerId")
        # The percentiles and the rating are league-relative, so the reference
        # pool must be players with enough minutes for their rate stats to be
        # real. Filter to regulars, but only when that still leaves a usable
        # pool, so a thin data slice never collapses the reference to nothing.
        if "total_minutes" in df.columns:
            mins = pd.to_numeric(df["total_minutes"], errors="coerce").fillna(0)
            regulars = df[mins >= _MIN_MINUTES]
            if len(regulars) >= 80:
                df = regulars
        self._league_df = df
        return df

    @staticmethod
    def _build_percentile_table(
        league_df: pd.DataFrame, group_col: str
    ) -> Dict[str, Dict[str, np.ndarray]]:
        """Sorted league values for each (position group, KPI), for percentiles."""
        table: Dict[str, Dict[str, np.ndarray]] = {}
        if group_col not in league_df.columns:
            return table
        for gval, gdf in league_df.groupby(group_col):
            arrays: Dict[str, np.ndarray] = {}
            for col in _RAW_COLS:
                if col in gdf.columns:
                    arr = pd.to_numeric(gdf[col], errors="coerce").dropna().to_numpy()
                    if arr.size:
                        arrays[col] = np.sort(arr)
            table[str(gval).upper()] = arrays
        return table

    def _ensure_percentile_tables(self) -> None:
        if self._pct_fine is None or self._pct_coarse is None:
            league_df = self._get_league_df()
            self._pct_fine = self._build_percentile_table(league_df, "position_group_fine")
            self._pct_coarse = self._build_percentile_table(league_df, "role_group")

    @staticmethod
    def _pct_of(value: float, sorted_arr: Optional[np.ndarray]) -> float:
        """Percentile (0-100) of ``value`` within a sorted league array."""
        if sorted_arr is None or sorted_arr.size == 0:
            return 50.0
        left = int(np.searchsorted(sorted_arr, value, side="left"))
        right = int(np.searchsorted(sorted_arr, value, side="right"))
        return float(((left + right) / 2.0) / sorted_arr.size * 100.0)

    def _normalise_player(self, rec: Dict) -> None:
        """Attach within-position league percentiles + an honest rating in place.

        The same fine-or-coarse decision drives the rating and every stat axis,
        so a player's card tells one coherent story. ``position_norm`` records
        which basis was used so the UI caption ("vs league CB" / "vs league
        DEF") is truthful.
        """
        fine = str(rec.get("position_group_fine", "") or "").upper()
        coarse = str(rec.get("role_group", "MID") or "MID").upper()

        fine_arrs = (self._pct_fine or {}).get(fine, {})
        perf_fine = fine_arrs.get("performance_score")
        use_fine = perf_fine is not None and perf_fine.size >= _MIN_FINE_GROUP

        table = self._pct_fine if use_fine else self._pct_coarse
        key = fine if use_fine else coarse
        group_arrs = (table or {}).get(key, {})

        for col in _RAW_COLS:
            rec[f"{col}_pct"] = round(
                self._pct_of(float(rec.get(col, 0) or 0), group_arrs.get(col)), 1
            )

        # Honest display rating: within-position percentile of the
        # position-weighted performance score, mapped to a discriminative band
        # (best in a position read high-80s to low-90s, role players 60-72).
        # Shared with the best-by-rating XI through ``_rating_of``.
        rec["rating"] = self._rating_of(rec.get("performance_score", 0), fine, coarse)
        rec["position_norm"] = "FINE" if use_fine else "COARSE"
        # Self-hosted headshot URL (empty when the photo pipeline has not run);
        # the UI falls back to initials. Both the match-preview and predict
        # paths run through here, so photos attach in one place.
        rec["photo_url"] = self._photos.url_for(rec.get("playerId")) or ""

    def _rating_of(self, performance_score, fine: str, coarse: str) -> int:
        """Within-position rating (40-95) from the performance-score percentile.

        Self-contained twin of the rating mapping in ``_normalise_player`` so the
        best-by-rating XI can score the whole squad on the identical basis (same
        fine-or-coarse pool, same ``55 + 40 * percentile`` map).
        """
        fine = (fine or "").upper()
        coarse = (coarse or "MID").upper()
        fine_arrs = (self._pct_fine or {}).get(fine, {})
        perf_fine = fine_arrs.get("performance_score")
        use_fine = perf_fine is not None and perf_fine.size >= _MIN_FINE_GROUP
        table = self._pct_fine if use_fine else self._pct_coarse
        key = fine if use_fine else coarse
        arrs = (table or {}).get(key, {})
        perf_pct = self._pct_of(
            float(performance_score or 0), arrs.get("performance_score")
        ) / 100.0
        return int(max(40, min(95, round(55 + 40 * perf_pct))))

    def _squad_stats(self, xi_df: Optional[pd.DataFrame]) -> Dict:
        """Aggregate the four match-preview squad metrics over an XI DataFrame.

        Operates on the eleven starters only (``xi_df``), not the whole pool, so
        the row under "the 11 most likely starters" actually reflects them. The
        four cells all read on a 0-100 scale:

        * ``avg_performance_score`` / ``avg_recent_form`` — the mean over the XI
          of each player's within-position league percentile (0-100) for
          ``performance_score`` / ``recent_form_score``, using the same
          fine-or-coarse position-group basis as :meth:`_normalise_player` and
          the radar. A percentile index, not the raw composite, so it sits on
          the same scale as the true pass/duel percentages.
        * ``avg_pass_accuracy`` / ``avg_duel_win_rate`` — pooled (volume-weighted)
          team rates, ``100 * sum(successfulPasses)/sum(passes)`` and
          ``100 * sum(duelsWon)/sum(duels)`` over the XI, so a 2-duel sub no
          longer counts the same as a 400-duel centre-back. Falls back to the
          old mean-of-ratios when the raw count columns are absent (older data)
          or the denominator is zero, so the row never breaks.

        Returns zeros for an empty XI.
        """
        zeros = {
            "avg_performance_score": 0.0,
            "avg_recent_form": 0.0,
            "avg_pass_accuracy": 0.0,
            "avg_duel_win_rate": 0.0,
        }
        if xi_df is None or xi_df.empty:
            return dict(zeros)

        self._ensure_percentile_tables()

        # ── Form / Performance → within-position percentile (mirror of
        #    _normalise_player's fine-or-coarse group selection) ───────────────
        perf_pcts: List[float] = []
        form_pcts: List[float] = []
        for _, row in xi_df.iterrows():
            fine = str(row.get("position_group_fine", "") or "").upper()
            coarse = str(row.get("role_group", "MID") or "MID").upper()
            fine_arrs = (self._pct_fine or {}).get(fine, {})
            perf_fine = fine_arrs.get("performance_score")
            use_fine = perf_fine is not None and perf_fine.size >= _MIN_FINE_GROUP
            table = self._pct_fine if use_fine else self._pct_coarse
            key = fine if use_fine else coarse
            group_arrs = (table or {}).get(key, {})
            perf_pcts.append(
                self._pct_of(
                    float(row.get("performance_score", 0) or 0),
                    group_arrs.get("performance_score"),
                )
            )
            form_pcts.append(
                self._pct_of(
                    float(row.get("recent_form_score", 0) or 0),
                    group_arrs.get("recent_form_score"),
                )
            )

        avg_perf = round(float(np.mean(perf_pcts)), 1) if perf_pcts else 0.0
        avg_form = round(float(np.mean(form_pcts)), 1) if form_pcts else 0.0

        # ── Passing / Duels → pooled volume-weighted team rate, with a
        #    mean-of-ratios fallback when the raw counts are unavailable ───────
        def _pooled_rate(num_col: str, den_col: str, ratio_col: str) -> float:
            if num_col in xi_df.columns and den_col in xi_df.columns:
                den = float(
                    pd.to_numeric(xi_df[den_col], errors="coerce").fillna(0).sum()
                )
                if den > 0:
                    num = float(
                        pd.to_numeric(xi_df[num_col], errors="coerce").fillna(0).sum()
                    )
                    return round(100.0 * num / den, 1)
            # Fallback: old behaviour (flat mean of the per-player ratio).
            if ratio_col in xi_df.columns:
                return round(
                    float(pd.to_numeric(xi_df[ratio_col], errors="coerce").fillna(0).mean()),
                    1,
                )
            return 0.0

        return {
            "avg_performance_score": avg_perf,
            "avg_recent_form": avg_form,
            "avg_pass_accuracy": _pooled_rate("successfulPasses", "passes", "pass_accuracy"),
            "avg_duel_win_rate": _pooled_rate("duelsWon", "duels", "duel_win_rate"),
        }

    def _format_records(self, frame: Optional[pd.DataFrame]) -> List[Dict]:
        """Select the player columns and attach percentiles + rating in place."""
        if frame is None or frame.empty:
            return []
        cols = [c for c in _PLAYER_COLS if c in frame.columns]
        records = frame[cols].fillna(0).to_dict(orient="records")
        for rec in records:
            self._normalise_player(rec)
            rec.update(assess_player(rec))
        return records

    def _best_xi_by_rating(
        self, squad_df: Optional[pd.DataFrame], formation: str
    ) -> Dict[str, pd.DataFrame]:
        """The 'ideal' eleven by pure within-position rating (opponent-agnostic).

        The squad is scored by each player's rating, scaled to the same 0..1 band
        as ``predicted_score`` so the predictor's slot penalties still enforce a
        primary-position-first assignment, then the SAME Hungarian slot fill used
        for the predicted XI (``StartingXIPredictor._assign_xi``) places the
        eleven. This contrasts raw quality against the predicted-most-likely
        lineup; ``xi_predictor.py`` itself is not touched.
        """
        empty = {"xi": pd.DataFrame(), "bench": pd.DataFrame()}
        if (
            squad_df is None
            or squad_df.empty
            or self.predictor is None
            or "performance_score" not in squad_df.columns
        ):
            return empty
        self._ensure_percentile_tables()
        pool = squad_df.copy()
        rating = pool.apply(
            lambda r: self._rating_of(
                r.get("performance_score", 0),
                str(r.get("position_group_fine", "") or ""),
                str(r.get("role_group", "MID") or "MID"),
            ),
            axis=1,
        ).astype(float)
        # Overwrite predicted_score on this private copy only (the predicted XI
        # uses its own scored pool, so the selected eleven there do not change).
        pool["predicted_score"] = rating / 100.0
        # ``_assign_xi`` now returns ``(xi_df, total_score)``; the best-by-rating
        # view only needs the XI frame. When ``formation`` is ``"auto"`` resolve
        # it to a concrete curated shape so the rating-based eleven matches the
        # predicted XI's shape (the caller passes the resolved formation in).
        resolved = formation
        if str(formation).lower() == "auto":
            resolved, xi_df, _total, _scores = self.predictor._best_formation(pool)
        else:
            xi_df, _total = self.predictor._assign_xi(pool, formation)
        used = set(xi_df["playerId"].tolist()) if not xi_df.empty else set()
        bench_df = (
            pool[~pool["playerId"].isin(used)]
            .sort_values("predicted_score", ascending=False)
            .head(MAX_BENCH)
        )
        return {"xi": xi_df, "bench": bench_df}

    # ── Public API ───────────────────────────────────────────────────────────

    def predict_xi(
        self,
        formation: str = "auto",
        opponent_team_id: Optional[int] = None,
        home_team_substring: Optional[str] = None,
        home_team_sr_id: Optional[str] = None,
        home_team_short: Optional[str] = None,
        locked: Optional[Dict[int, int]] = None,
    ) -> Dict:
        if not self.predictor:
            raise RuntimeError("XI Model not loaded")

        formation = _normalise_formation(formation)

        home = self._resolve_home_team(
            home_team_substring=home_team_substring,
            home_team_sr_id=home_team_sr_id,
            home_team_short=home_team_short,
        )
        df = self._get_feature_df(home)

        my_team_df = df[df["is_home_squad"]].copy()
        if my_team_df.empty:
            raise RuntimeError(
                f"No players found for home team '{home.short}' "
                f"(empirical squad set is empty for wy_substr={home.wy_substr!r})."
            )

        opp_team_df = (
            df[df["teamId"] == opponent_team_id].copy() if opponent_team_id else None
        )
        # Opponent registry short (for the opponent-aware interaction features),
        # resolved from the fixture-id map; None -> no opponent effect.
        opp_short = None
        if opponent_team_id is not None:
            opp_short = next(
                (s for s, i in FIXTURE_NAME_TO_ID.items() if i == opponent_team_id), None)

        result = self.predictor.predict_xi(
            df=my_team_df,
            formation=formation,
            your_team_id=opponent_team_id,
            opponent_df=opp_team_df,
            locked=locked,
            opponent_short=opp_short,
        )

        # Surface the resolved home team in the response payload so the
        # Flutter app can confirm which team it received.
        out = _format_output(result, FIXTURE_NAME_TO_ID.get(home.short), opponent_team_id)
        out["home_team_short"] = home.short
        out["home_team_sr_id"] = home.sr_id
        # Why-this-shape explainer: formation -> total assignment objective.
        out["formation_scores"] = result.get("formation_scores", {})
        # Attach the honest within-position rating + stat percentiles so the
        # standalone XI screen matches the Match Intelligence card.
        self._ensure_percentile_tables()
        for grp in ("startingXI", "bench"):
            for rec in out.get(grp, []):
                self._normalise_player(rec)
                rec.update(assess_player(rec))
        # The 'ideal' eleven by pure within-position rating, alongside the
        # predicted lineup, for the "best XI" toggle. It is built on the RESOLVED
        # formation so the two elevens share a shape.
        best = self._best_xi_by_rating(my_team_df, result["formation"])
        out["bestXI"] = self._format_records(best["xi"])
        out["bestBench"] = self._format_records(best["bench"])
        return out

    def match_preview(
        self,
        opponent_name: str,
        formation: str = "auto",
        main_df: Optional[pd.DataFrame] = None,
        home_team_substring: Optional[str] = None,
        home_team_sr_id: Optional[str] = None,
        home_team_short: Optional[str] = None,
        locked: Optional[Dict[int, int]] = None,
    ) -> Dict:
        """Return starting XI + team stats + H2H record for an upcoming match."""
        if not self.predictor:
            raise RuntimeError("XI model not loaded")

        formation = _normalise_formation(formation)

        home = self._resolve_home_team(
            home_team_substring=home_team_substring,
            home_team_sr_id=home_team_sr_id,
            home_team_short=home_team_short,
        )
        opp_id = FIXTURE_NAME_TO_ID.get(opponent_name)

        df = self._get_feature_df(home)

        my_team_df = df[df["is_home_squad"]].copy()
        if my_team_df.empty:
            raise RuntimeError(
                f"No players found for home team '{home.short}' "
                f"(empirical squad set is empty for wy_substr={home.wy_substr!r})."
            )

        # Resolve the opponent squad EMPIRICALLY, mirroring the home path, so a
        # stale per-player ``currentTeamId`` snapshot can never zero the
        # opponent row / XI. ``team_by_short`` matches the registry short label
        # that arrives in ``opponent_name`` (diacritic-insensitive), and
        # ``get_team_squad_from_matches`` then identifies the squad by
        # appearance frequency in the opponent's own match files (matched via
        # ``wy_substr``), independent of ``currentTeamId``. Falls back to the
        # legacy ``currentTeamId`` filter only when the registry lookup fails or
        # the empirical squad comes back empty, so nothing currently working
        # breaks.
        opp_ref = team_by_short(opponent_name)
        opp_team_df = None
        opp_team_id = opp_id  # your_team_id passed into the opponent predict_xi
        if opp_ref is not None:
            # Build the opponent's feature frame keyed to the OPPONENT's own squad,
            # through the same path as the home team, so its availability_score is
            # REAL (computed against the opponent's own fixtures). Slicing the
            # opponent out of the home-keyed frame instead would zero every
            # opponent's availability, which flattens the razor-thin per-formation
            # scores and biases the opponent's "auto" shape and its player scores,
            # uniformly across every opponent rather than for isolated cases.
            opp_df = self._get_feature_df(opp_ref)
            squad = opp_df[opp_df["is_home_squad"]].copy()
            if not squad.empty:
                opp_team_df = squad
                # ``predict_xi`` does not filter by team id (the home path proves
                # this); ``your_team_id`` is carried into the payload only. When the
                # legacy fixture map misses the opponent, fall back to the squad's
                # modal ``teamId`` so the field stays populated.
                if opp_team_id is None and "teamId" in opp_team_df.columns:
                    modal = opp_team_df["teamId"].dropna()
                    if not modal.empty:
                        opp_team_id = modal.mode().iloc[0]
        if opp_team_df is None:
            # Legacy fallback: stale ``currentTeamId`` filter on the home-keyed
            # frame (kept so previous behaviour holds when the empirical path
            # cannot resolve the opponent squad).
            opp_team_df = df[df["teamId"] == opp_id].copy() if opp_id else None

        result = self.predictor.predict_xi(
            df=my_team_df,
            formation=formation,
            your_team_id=FIXTURE_NAME_TO_ID.get(home.short),
            opponent_df=opp_team_df,
            locked=locked,
            opponent_short=(opp_ref.short if opp_ref else opponent_name),
        )
        # The resolved shape ("auto" picks one of the curated nine; an explicit
        # key passes through). Every shape-coupled view below uses this so the
        # predicted XI, best XI, and opponent XI all share one formation.
        resolved_formation = result["formation"]

        # Build the within-position league percentile tables once for this call.
        self._ensure_percentile_tables()

        # The 'ideal' eleven by pure within-position rating (opponent-agnostic),
        # for the "Cel mai bun XI" view shown alongside the predicted lineup.
        best = self._best_xi_by_rating(my_team_df, resolved_formation)

        # Team aggregate stats — scoped to the predicted XI (the eleven shown),
        # volume-weighted for pass/duel and 0-100 percentile-normalised for
        # form/performance (see :meth:`_squad_stats`). The top scorer / creator
        # remain whole-squad highlights (separate fields), unchanged.
        all_df = result.get("all_scored", pd.DataFrame())
        team_xi = result.get("xi", pd.DataFrame())
        team_stats: Dict = self._squad_stats(team_xi)
        if not all_df.empty:
            for stat, key in [("per90_goals", "top_scorer"), ("per90_keyPasses", "top_creator")]:
                if stat in all_df.columns:
                    row = all_df.nlargest(1, stat).iloc[0]
                    team_stats[key] = str(row.get("shortName", ""))
                    team_stats[f"{key}_stat"] = round(float(row.get(stat, 0)), 2)

        # Opponent aggregate stats — same XI-scoped basis. The opponent has no
        # XI in ``result`` (only used for opponent adjustments above), so derive
        # its predicted eleven on the same Hungarian path before aggregating.
        opponent_stats: Dict = self._squad_stats(None)
        opponent_xi_records: list = []
        opponent_bench_records: list = []
        opponent_formation: str = ""
        if opp_team_df is not None and not opp_team_df.empty:
            try:
                # Opponent XI picks the opponent's OWN best shape ("auto"), not the
                # home team's formation, so its pitch arrangement is distinct. It is
                # also opponent-aware (it conditions on us). The home team's locks
                # are slot pins for our squad, so they are not passed here.
                opp_result = self.predictor.predict_xi(
                    df=opp_team_df,
                    formation="auto",
                    your_team_id=opp_team_id,
                    opponent_short=home.short,
                )
                opponent_formation = opp_result.get("formation", "") or ""
                opponent_xi = opp_result.get("xi", pd.DataFrame())
                opponent_xi_records = self._format_records(opponent_xi)
                opponent_bench_records = self._format_records(
                    opp_result.get("bench", pd.DataFrame()))
            except Exception:
                opponent_xi = pd.DataFrame()
            opponent_stats = self._squad_stats(opponent_xi)
            for stat, key in [("per90_goals", "top_scorer"), ("per90_keyPasses", "top_creator")]:
                if stat in opp_team_df.columns:
                    row = opp_team_df.nlargest(1, stat).iloc[0]
                    opponent_stats[key] = str(row.get("shortName", ""))
                    opponent_stats[f"{key}_stat"] = round(float(row.get(stat, 0)), 2)
        else:
            opponent_stats.update({
                "top_scorer": "",
                "top_scorer_stat": 0.0,
                "top_creator": "",
                "top_creator_stat": 0.0,
            })

        # Head-to-head from main fixtures CSV (uses the resolved home short label)
        h2h: Dict = {"total": 0, "our_wins": 0, "draws": 0, "their_wins": 0,
                     "our_avg_goals": 0.0, "their_avg_goals": 0.0}
        if main_df is not None and not main_df.empty:
            try:
                our = home.short
                mask = (
                    ((main_df["home_team"] == our) & (main_df["away_team"] == opponent_name))
                    | ((main_df["home_team"] == opponent_name) & (main_df["away_team"] == our))
                )
                h2h_df = main_df[mask].dropna(subset=["home_score", "away_score"]).tail(10)
                if not h2h_df.empty:
                    our_wins = draws = their_wins = our_g_total = their_g_total = 0
                    for _, row in h2h_df.iterrows():
                        hs, as_ = int(row["home_score"]), int(row["away_score"])
                        is_home = row["home_team"] == our
                        og, tg = (hs, as_) if is_home else (as_, hs)
                        our_g_total += og
                        their_g_total += tg
                        if og > tg:
                            our_wins += 1
                        elif og < tg:
                            their_wins += 1
                        else:
                            draws += 1
                    n = len(h2h_df)
                    h2h = {
                        "total": n,
                        "our_wins": our_wins,
                        "draws": draws,
                        "their_wins": their_wins,
                        "our_avg_goals": round(our_g_total / n, 1),
                        "their_avg_goals": round(their_g_total / n, 1),
                    }
            except Exception:
                pass

        return {
            "formation": resolved_formation,
            "formation_scores": result.get("formation_scores", {}),
            "home_team_short": home.short,
            "home_team_sr_id": home.sr_id,
            "opponent_name": opponent_name,
            "opponent_team_id": opp_id,
            "starting_xi": self._format_records(result["xi"]),
            "bench": self._format_records(result["bench"]),
            "best_xi": self._format_records(best["xi"]),
            "best_bench": self._format_records(best["bench"]),
            "team_stats": team_stats,
            "opponent_stats": opponent_stats,
            "opponent_xi": opponent_xi_records,
            "opponent_bench": opponent_bench_records,
            "opponent_formation": opponent_formation,
            "head_to_head": h2h,
        }

    def list_opponents(self, min_players: int = 20,
                       home_team_substring: Optional[str] = None) -> list[dict]:
        """Return opponent options. Iteration L: prefer the team registry
        over the legacy ``currentTeamId`` count."""
        home = self._resolve_home_team(home_team_substring=home_team_substring)

        # Primary path: team registry (returns all sixteen Superliga clubs
        # minus the home team).
        opponents = [
            {
                "id": FIXTURE_NAME_TO_ID.get(t.short),
                "name": t.short,
                "sr_id": t.sr_id,
            }
            for t in SUPERLIGA_TEAMS
            if t.short != home.short
        ]
        return sorted(opponents, key=lambda item: item["name"])

    # ── New Iteration L public method: list all Superliga teams ─────────────
    def list_home_teams(self) -> list[dict]:
        """Return every Romanian Superliga team eligible as the home team."""
        return [
            {
                "short": t.short,
                "wy_substr": t.wy_substr,
                "sr_id": t.sr_id,
            }
            for t in SUPERLIGA_TEAMS
        ]
