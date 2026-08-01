"""Read-time player-photo URL lookup.

Photos are scraped once from SofaScore and uploaded to S3 by the
``backend/scripts/*photo*`` scripts, which write the final S3 URL onto each
record in ``ml/data/wyscout_to_sofascore.json`` (keyed by Wyscout id, with the
SofaScore display name + team). At runtime the backend only reads that
committed JSON, so it never calls SofaScore or AWS and never needs boto3.

Two lookups are supported:

* ``url_for(wy_id)``, direct by Wyscout id, used by the recommended-XI flow
  whose players carry Wyscout ids.
* ``url_for_name(name, team)``, by display name, used by the completed-match
  flow whose players come from Sportradar ("Surname, Firstname") with no
  Wyscout id. Matching is diacritic-insensitive on surname + given name and
  refuses ambiguous matches (returns ``None``) so a wrong face never shows.

When the mapping is missing/empty every lookup returns ``None`` and the UI
falls back to initials.
"""

from __future__ import annotations

import json
import logging
import re
import unicodedata
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)


def _strip_accents(s: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFKD", s or "")
        if not unicodedata.combining(c)
    )


def _tokens(s: str) -> set[str]:
    """Lower-cased, diacritic-free alphabetic tokens of a name."""
    return {t for t in re.split(r"[^a-z]+", _strip_accents(s).lower()) if t}


class PlayerPhotoService:
    def __init__(self, mapping_path: str):
        self._by_wy: dict[int, str] = {}
        # (name_tokens, team_tokens, url) rows for name-based lookup.
        self._by_name: list[tuple[frozenset, frozenset, str]] = []
        try:
            raw = json.loads(Path(mapping_path).read_text(encoding="utf-8"))
            for wy, record in (raw or {}).items():
                url = (record or {}).get("photo_url")
                if not url:
                    continue
                url = str(url)
                try:
                    self._by_wy[int(wy)] = url
                except (TypeError, ValueError):
                    pass
                name_tok = _tokens((record or {}).get("sofascore_name", ""))
                if name_tok:
                    team_tok = _tokens((record or {}).get("sofascore_team", ""))
                    self._by_name.append(
                        (frozenset(name_tok), frozenset(team_tok), url)
                    )
            logger.info(
                "PlayerPhotoService loaded %d photo URLs (%d name-indexed)",
                len(self._by_wy), len(self._by_name),
            )
        except FileNotFoundError:
            logger.info("PlayerPhotoService: no mapping at %s (photos disabled)", mapping_path)
        except Exception:
            logger.warning("PlayerPhotoService: could not read %s", mapping_path, exc_info=True)

    @property
    def count(self) -> int:
        return len(self._by_wy)

    def url_for(self, wy_id) -> Optional[str]:
        try:
            return self._by_wy.get(int(wy_id))
        except (TypeError, ValueError):
            return None

    def url_for_name(self, name: str, team: Optional[str] = None) -> Optional[str]:
        """Resolve a photo by display name.

        ``name`` is the Sportradar form "Surname, Firstname [Middle]". A record
        matches when every surname token is present in its name tokens and (when
        a given name is available) at least one given token overlaps. If several
        records match, the optional ``team`` disambiguates by team-name overlap;
        anything still ambiguous returns ``None`` so a wrong face never shows.
        """
        if not name or not self._by_name:
            return None
        head, sep, tail = name.partition(",")
        if sep:
            surname = _tokens(head)
            given = _tokens(tail)
        else:
            # No comma form: use the whole string and skip given-name filtering.
            surname = _tokens(name)
            given = set()
        if not surname:
            return None

        cands = [
            (team_tok, url)
            for name_tok, team_tok, url in self._by_name
            if surname <= name_tok and (not given or (given & name_tok))
        ]
        uniq = list(dict.fromkeys(url for _, url in cands))
        if len(uniq) == 1:
            return uniq[0]
        if len(uniq) > 1 and team:
            team_q = _tokens(team)
            filtered = list(dict.fromkeys(
                url for team_tok, url in cands if team_q & team_tok
            ))
            if len(filtered) == 1:
                return filtered[0]
        return None
