"""
Single source of truth for the sixteen Romanian Superliga 2024-25 clubs.

For each team the registry stores:

* ``short``, the display label used in the Flutter UI and the
                      retrospective-validation tables.
* ``wy_substr``, the substring used to identify the team's Wyscout
                      match files in ``backend/ml/data/drive_cache/``.
                      Match files follow the ``"{home} - {away}, {score}_players_stats.json"``
                      naming convention, so a substring search against the
                      filename is sufficient.
* ``sr_id``, the team's Sportradar competitor ID, as populated
                      by ``backend/scripts/sync_sportradar_squad.py`` into
                      the ``sr_teams`` table.
* ``aliases``, optional alternative names sometimes used by the
                      same team (e.g. ``"FCSB"`` vs ``"FCS Bucureşti"``).
* ``country``, kept for completeness; always ``"Romania"`` here.

The registry is the foundation of the Superliga-wide generalisation.
Every script that previously hardcoded ``"Universitatea
Cluj"`` / ``11571`` / ``sr:competitor:7734`` now iterates over
:data:`SUPERLIGA_TEAMS` and uses :func:`team_by_short`,
:func:`team_by_wy_substr`, or :func:`team_by_sr_id` to resolve a team
from any one of its identifiers.

If the Sportradar competitor IDs drift in a future season (e.g. a club
is rebranded or relegated), regenerate this file via the small helper
``backend/scripts/refresh_team_registry.py`` which reads the current
``sr_teams`` table and prints a fresh ``SUPERLIGA_TEAMS`` block to
stdout for manual review.
"""

from __future__ import annotations

import unicodedata
from dataclasses import dataclass, field
from typing import List, Optional


def normalise(text: str) -> str:
    """Return ``text`` lower-cased and with all diacritics stripped.

    Romanian club names appear in the data sources under different
    diacritic conventions: Wyscout filenames use ``ş`` (U+015F, Latin
    Small Letter S With Cedilla) for "Botoşani" but might equally use
    ``ş`` (U+0219, Latin Small Letter S With Comma Below); Sportradar
    sometimes returns the ASCII transliteration ("Botosani"). Stripping
    diacritics via NFD decomposition and removing the combining marks
    collapses every representation to a single key suitable for
    substring matching.
    """
    if not text:
        return ""
    decomposed = unicodedata.normalize("NFD", text)
    stripped = "".join(c for c in decomposed if not unicodedata.combining(c))
    # Also handle a few characters not decomposable via NFD (e.g. the
    # Romanian letters s-comma-below and t-comma-below).
    replacements = {
        "ș": "s", "ț": "t",  # Romanian s-comma-below, t-comma-below
        "ş": "s", "ţ": "t",  # Romanian s-cedilla, t-cedilla
        "Ș": "S", "Ț": "T",  # uppercase variants
        "Ş": "S", "Ţ": "T",
    }
    out = []
    for c in stripped:
        out.append(replacements.get(c, c))
    return "".join(out).lower()


@dataclass(frozen=True)
class TeamRef:
    short: str
    wy_substr: str
    sr_id: str
    aliases: tuple = field(default_factory=tuple)
    country: str = "Romania"

    @property
    def wy_substr_normalised(self) -> str:
        """Diacritic-stripped, lower-cased Wyscout substring for matching."""
        return normalise(self.wy_substr)


# Sixteen Romanian Superliga 2024-25 clubs.
#
# The ``sr_id`` values come from the production ``sr_teams`` table after
# the Sportradar sync (see ``backend/scripts/sync_sportradar_squad.py``).
# The ``wy_substr`` values are verified against the drive_cache filenames
# (every team has at least 30 match files under its substring; the
# registry boots clean).
SUPERLIGA_TEAMS: List[TeamRef] = [
    TeamRef(short="U Cluj",                wy_substr="Universitatea Cluj",
            sr_id="sr:competitor:7734",   aliases=("FC Universitatea Cluj", "Uni Cluj")),
    TeamRef(short="CFR Cluj",              wy_substr="CFR Cluj",
            sr_id="sr:competitor:5287",   aliases=("FC CFR 1907 Cluj",)),
    TeamRef(short="FCSB",                  wy_substr="FCS Bucureşti",
            sr_id="sr:competitor:3301",   aliases=("Fotbal Club FCSB", "FCS Bucuresti")),
    TeamRef(short="Dinamo Bucureşti",      wy_substr="Dinamo Bucureşti",
            sr_id="sr:competitor:3292",   aliases=("FC Dinamo Bucuresti 1948", "Dinamo Bucuresti")),
    TeamRef(short="Rapid Bucureşti",       wy_substr="Rapid Bucureşti",
            sr_id="sr:competitor:3302",   aliases=("Rapid Bucuresti 1923", "Rapid Bucuresti")),
    TeamRef(short="Botoşani",              wy_substr="Botoşani",
            sr_id="sr:competitor:24798",  aliases=("FC Botosani", "Botosani")),
    TeamRef(short="Oţelul Galaţi",         wy_substr="Oţelul",
            sr_id="sr:competitor:3291",   aliases=("ASC Otelul Galati", "Otelul Galati")),
    TeamRef(short="Hermannstadt",          wy_substr="Hermannstadt",
            sr_id="sr:competitor:342922", aliases=("AFC Hermannstadt",)),
    TeamRef(short="Petrolul Ploieşti",     wy_substr="Petrolul",
            sr_id="sr:competitor:25856",  aliases=("FC Petrolul Ploiesti", "Petrolul Ploiesti", "Petrolul 52")),
    TeamRef(short="UTA Arad",              wy_substr="UTA Arad",
            sr_id="sr:competitor:221210", aliases=("FC Uta Arad", "Uta Arad")),
    TeamRef(short="Csikszereda",           wy_substr="Csikszereda",
            sr_id="sr:competitor:391688", aliases=("AFK Csikszereda Miercurea Ciuc", "Csikszereda Miercurea Ciuc", "Csikszereda M. Ciuc")),
    TeamRef(short="FC Argeş",              wy_substr="Argeș",
            sr_id="sr:competitor:116221", aliases=("ACS Champions FC Arges", "FC Arges")),
    TeamRef(short="U Craiova",             wy_substr="Universitatea Craiova",
            sr_id="sr:competitor:116223", aliases=("CS Universitatea Craiova", "Univ. Craiova", "Universitatea Craiova 1948")),
    TeamRef(short="Farul Constanţa",       wy_substr="Farul Constanţa",
            sr_id="sr:competitor:3294",   aliases=("FC Farul Constanta", "Farul Constanta")),
    TeamRef(short="Unirea Slobozia",       wy_substr="Unirea Slobozia",
            sr_id="sr:competitor:44259",  aliases=("FC Unirea 2004 Slobozia",)),
    TeamRef(short="Metaloglobus",          wy_substr="Metaloglobus",
            sr_id="sr:competitor:79081",  aliases=("Metaloglobus Bucureşti", "Metaloglobus Bucuresti")),
]


# Lookup helpers

def team_by_short(short: str) -> Optional[TeamRef]:
    """Return the registry entry matching ``short`` (diacritic-insensitive)."""
    key = normalise(short)
    for t in SUPERLIGA_TEAMS:
        if normalise(t.short) == key:
            return t
    return None


def team_by_wy_substr(substr: str) -> Optional[TeamRef]:
    """Return the registry entry whose Wyscout substring equals ``substr``
    (diacritic-insensitive)."""
    key = normalise(substr)
    for t in SUPERLIGA_TEAMS:
        if normalise(t.wy_substr) == key:
            return t
    return None


def team_by_sr_id(sr_id: str) -> Optional[TeamRef]:
    """Return the registry entry whose Sportradar competitor ID matches."""
    key = (sr_id or "").strip()
    for t in SUPERLIGA_TEAMS:
        if t.sr_id == key:
            return t
    return None


def team_by_alias(name: str) -> Optional[TeamRef]:
    """Return the registry entry whose short, substring or alias matches
    ``name`` (diacritic-insensitive)."""
    key = normalise(name)
    for t in SUPERLIGA_TEAMS:
        if normalise(t.short) == key or normalise(t.wy_substr) == key:
            return t
        for a in t.aliases:
            if normalise(a) == key:
                return t
    return None


def files_for_team(file_paths: List[str], team: TeamRef) -> List[str]:
    """Return the file paths whose basename contains ``team.wy_substr``
    (diacritic-insensitive). The intended caller passes the full
    ``backend/ml/data/drive_cache/*.json`` list.
    """
    needle = team.wy_substr_normalised
    out: List[str] = []
    for fp in file_paths:
        import os
        if needle in normalise(os.path.basename(fp)):
            out.append(fp)
    return out


def all_wy_substrings() -> List[str]:
    """Return every team's Wyscout substring, in registry order."""
    return [t.wy_substr for t in SUPERLIGA_TEAMS]


def all_sr_ids() -> List[str]:
    """Return every team's Sportradar competitor ID, in registry order."""
    return [t.sr_id for t in SUPERLIGA_TEAMS]
