"""Read-time per-player MATCH grade for a completed fixture.

Wyscout ships no ready-made player rating, but the thesis already defines a
composite player score (:func:`ml.feature_engineering.compute_performance_score`,
the position-weighted per-90 KPI sum used to rank the recommended XI). This
service applies that SAME methodology to a single completed match's per-player
Wyscout stats, producing a per-player MATCH grade on a 0-10 scale.

Pipeline
--------
1. The displayed (Sportradar) match is joined to its Wyscout per-match stats
   file in ``backend/ml/data/drive_cache/*_players_stats.json``. Those files
   are named ``"{Home} - {Away}, {HomeScore}-{AwayScore}[_{matchId}]_players_stats.json"``;
   we match on the home/away team (resolved through the shared team registry,
   diacritic-insensitive) plus the final score, and optionally the Wyscout
   ``matchId`` carried in the stats block.
2. Each lineup player (a Sportradar "Surname, Firstname") is resolved to a
   Wyscout id through the committed ``wyscout_to_sofascore.json`` mapping with
   the same diacritic-insensitive name match the photo resolver uses.
3. The player's ``total`` block from that match is scored with
   :func:`compute_performance_score` (fine-position-weighted when the per-match
   ``positions`` array is present, else the coarse role-group weights), and the
   raw composite is mapped to 0-10 through per-position-group empirical anchors
   calibrated against the full drive-cache corpus.

When a player can not be matched (no Wyscout id, or no stats row in the matched
file, or no minutes), the grade is ``None`` and the client renders no rating.
The whole module is read-only: no Sportradar call, no AWS, no scraping.
"""

from __future__ import annotations

import json
import logging
import re
import unicodedata
from pathlib import Path
from typing import Optional

from ml.feature_engineering import (
    FINE_GROUP_TO_COARSE,
    compute_performance_score,
    derive_primary_fine_position,
)
from sportradar.team_registry import normalise, team_by_alias

logger = logging.getLogger(__name__)

# ── Grade calibration ────────────────────────────────────────────────────────
# The raw composite score from ``compute_performance_score`` is unbounded and
# strongly position-dependent (a ball-playing centre-midfielder routinely scores
# an order of magnitude higher than a striker on the same weighting scheme), so
# a single global linear map would be unfair across positions. Instead we map a
# player's raw score within its OWN fine-position-group's empirical [p10, p90]
# band onto the [4.0, 9.0] match-rating band, then clamp to [1.0, 10.0]. The
# anchors below are the per-group 10th/90th percentiles measured across every
# qualifying appearance (>= 20 minutes) in the committed drive-cache corpus, so
# the median appearance lands near a conventional 6.x match rating.
_GRADE_ANCHORS: dict[str, tuple[float, float]] = {
    "GK": (6.67, 25.9),
    "CB": (45.4, 118.18),
    "FB": (28.79, 90.4),
    "WB": (4.29, 61.46),
    "DM": (54.93, 152.51),
    "CM": (39.49, 154.92),
    "AM": (4.39, 44.18),
    "W": (-11.74, 13.0),
    "WF": (2.93, 33.55),
    "ST": (0.0, 31.03),
}
# Fallback band when a fine group has no anchor (should not happen for the ten
# canonical groups, but keeps the mapping total).
_DEFAULT_ANCHOR = (0.0, 100.0)
_GRADE_LOW, _GRADE_HIGH = 4.0, 9.0   # rating band the [p10, p90] anchors map to
_GRADE_MIN, _GRADE_MAX = 1.0, 10.0   # hard clamp


def _scale_to_grade(raw: float, fine_group: str) -> float:
    """Map a raw composite score to the 0-10 grade for its position group."""
    lo, hi = _GRADE_ANCHORS.get(fine_group, _DEFAULT_ANCHOR)
    span = hi - lo
    if span <= 0:
        frac = 0.5
    else:
        frac = (raw - lo) / span
    grade = _GRADE_LOW + frac * (_GRADE_HIGH - _GRADE_LOW)
    grade = max(_GRADE_MIN, min(_GRADE_MAX, grade))
    return round(grade, 1)


# ── Filename / match join ────────────────────────────────────────────────────
# "{Home} - {Away}, {HomeScore}-{AwayScore}[_{matchId}]_players_stats.json"
_FILENAME_RE = re.compile(
    r"^(?P<home>.*?) - (?P<away>.*?), (?P<hs>\d+)-(?P<as>\d+)(?:_(?P<mid>\d+))?_players_stats\.json$"
)


def _strip_accents(s: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFKD", s or "")
        if not unicodedata.combining(c)
    )


def _name_tokens(s: str) -> frozenset[str]:
    """Lower-cased, diacritic-free alphabetic tokens of a name."""
    return frozenset(t for t in re.split(r"[^a-z]+", _strip_accents(s).lower()) if t)


class GradeService:
    """Compute per-player match grades for a completed fixture (cached load)."""

    def __init__(self, drive_cache_dir: str, mapping_path: str):
        self._dir = Path(drive_cache_dir)
        self._mapping_path = Path(mapping_path)
        # Lazily built indices.
        self._file_index: Optional[dict[tuple[str, str, int, int], list[Path]]] = None
        self._name_to_wy: Optional[list[tuple[frozenset[str], frozenset[str], int]]] = None

    # ── Index builders (cached) ──────────────────────────────────────────────
    def _ensure_file_index(self) -> None:
        if self._file_index is not None:
            return
        index: dict[tuple[str, str, int, int], list[Path]] = {}
        try:
            files = list(self._dir.glob("*_players_stats.json"))
        except Exception:
            files = []
        for fp in files:
            m = _FILENAME_RE.match(fp.name)
            if not m:
                continue
            th = team_by_alias(m.group("home"))
            ta = team_by_alias(m.group("away"))
            if not th or not ta:
                continue
            key = (th.short, ta.short, int(m.group("hs")), int(m.group("as")))
            index.setdefault(key, []).append(fp)
        self._file_index = index
        logger.info("GradeService indexed %d drive-cache match files", len(files))

    def _ensure_name_index(self) -> None:
        if self._name_to_wy is not None:
            return
        rows: list[tuple[frozenset[str], frozenset[str], int]] = []
        try:
            raw = json.loads(self._mapping_path.read_text(encoding="utf-8"))
            for wy, rec in (raw or {}).items():
                try:
                    wy_id = int(wy)
                except (TypeError, ValueError):
                    continue
                name_tok = _name_tokens((rec or {}).get("sofascore_name", ""))
                if not name_tok:
                    continue
                team_tok = _name_tokens((rec or {}).get("sofascore_team", ""))
                rows.append((name_tok, team_tok, wy_id))
        except FileNotFoundError:
            logger.info("GradeService: no mapping at %s (grades disabled)", self._mapping_path)
        except Exception:
            logger.warning("GradeService: could not read %s", self._mapping_path, exc_info=True)
        self._name_to_wy = rows

    # ── Public API ───────────────────────────────────────────────────────────
    def grades_for_match(
        self,
        home_team: str,
        away_team: str,
        home_score: Optional[int],
        away_score: Optional[int],
        wy_match_id: Optional[int] = None,
    ) -> dict[int, float]:
        """Return ``{wyscout_player_id: grade}`` for the matched completed fixture.

        Resolves the drive-cache file from the Sportradar home/away team and
        final score (with an optional Wyscout ``matchId`` tiebreak when several
        meetings share the same score), then grades every player with minutes.
        Returns an empty dict when the fixture can not be located.
        """
        if home_score is None or away_score is None:
            return {}
        self._ensure_file_index()
        assert self._file_index is not None

        th = team_by_alias(home_team)
        ta = team_by_alias(away_team)
        if not th or not ta:
            return {}
        candidates = self._file_index.get(
            (th.short, ta.short, int(home_score), int(away_score)), []
        )
        if not candidates:
            return {}
        path = self._select_file(candidates, wy_match_id)
        if path is None:
            return {}
        return self._grade_file(path)

    def grade_for_player_name(
        self,
        name: str,
        grades_by_wy: dict[int, float],
        team: Optional[str] = None,
    ) -> Optional[float]:
        """Resolve a Sportradar "Surname, Firstname" to its match grade.

        Reuses the same diacritic-insensitive name match the photo resolver
        uses: every surname token must be present and (when a given name is
        available) at least one given token must overlap. Ambiguous matches are
        disambiguated by team and otherwise refused (returns ``None``).
        """
        if not name or not grades_by_wy:
            return None
        self._ensure_name_index()
        assert self._name_to_wy is not None

        head, sep, tail = name.partition(",")
        if sep:
            surname = _name_tokens(head)
            given = _name_tokens(tail)
        else:
            surname = _name_tokens(name)
            given = frozenset()
        if not surname:
            return None

        cands = [
            (team_tok, wy_id)
            for name_tok, team_tok, wy_id in self._name_to_wy
            if surname <= name_tok and (not given or (given & name_tok))
        ]
        # Keep only resolvable ids that actually have a grade in this match.
        graded = [(team_tok, wy_id) for team_tok, wy_id in cands if wy_id in grades_by_wy]
        uniq = list(dict.fromkeys(wy_id for _, wy_id in graded))
        if len(uniq) == 1:
            return grades_by_wy[uniq[0]]
        if len(uniq) > 1 and team:
            team_q = _name_tokens(team)
            filtered = list(dict.fromkeys(
                wy_id for team_tok, wy_id in graded if team_q & team_tok
            ))
            if len(filtered) == 1:
                return grades_by_wy[filtered[0]]
        return None

    # ── Internals ────────────────────────────────────────────────────────────
    @staticmethod
    def _select_file(candidates: list[Path], wy_match_id: Optional[int]) -> Optional[Path]:
        if wy_match_id is not None:
            for fp in candidates:
                m = _FILENAME_RE.match(fp.name)
                if m and m.group("mid") and int(m.group("mid")) == int(wy_match_id):
                    return fp
        # Deterministic pick when several files share the score (rare: two
        # meetings ended identically). Sorted by name so the choice is stable.
        return sorted(candidates, key=lambda p: p.name)[0]

    @staticmethod
    def _grade_file(path: Path) -> dict[int, float]:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            logger.warning("GradeService: could not read %s", path, exc_info=True)
            return {}
        grades: dict[int, float] = {}
        for entry in data.get("players", []) or []:
            pid = entry.get("playerId")
            if pid is None:
                continue
            total = entry.get("total") or {}
            minutes = total.get("minutesOnField", 0) or 0
            if minutes <= 0:
                continue
            # Fine position from this match's own ``positions`` array (falls
            # back to MID inside the helper when codes are absent), then the
            # coarse group so the weight table is always defined.
            fine = derive_primary_fine_position([entry])
            coarse = FINE_GROUP_TO_COARSE.get(fine, "MID")
            raw = compute_performance_score(total, coarse, fine_group=fine)
            try:
                grades[int(pid)] = _scale_to_grade(float(raw), fine)
            except (TypeError, ValueError):
                continue
        return grades
