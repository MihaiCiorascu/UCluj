"""Runtime loader for the committed matchId -> calendar-date bridge.

The Wyscout drive_cache matches carry no date.
``backend/scripts/build_matchid_dates.py`` joins them to the Sportradar 25/26
schedule (by canonical home/away pair, chronological tiebreak) and writes
``matchid_to_date.json``. This module loads that committed map once and exposes a
lookup, so the feature pipeline can compute calendar rest / congestion without any
runtime Sportradar call. Missing entries return ``None``, and callers fall back to
the fixture-window (matches-since) measures.
"""
from __future__ import annotations

import json
import os
from datetime import date, datetime
from typing import Dict, Optional

_PATH = os.path.join(os.path.dirname(__file__), "data", "matchid_to_date.json")
_cache: Optional[Dict[int, str]] = None


def load_match_dates() -> Dict[int, str]:
    """Return {matchId: 'YYYY-MM-DD'}, loaded once and cached. Empty on any error."""
    global _cache
    if _cache is None:
        try:
            with open(_PATH, encoding="utf-8") as f:
                raw = json.load(f)
            _cache = {int(k): str(v)[:10] for k, v in raw.items()}
        except Exception:
            _cache = {}
    return _cache


def date_for(match_id) -> Optional[str]:
    """ISO date string for a Wyscout matchId, or None when unmapped."""
    if match_id is None:
        return None
    try:
        return load_match_dates().get(int(match_id))
    except (TypeError, ValueError):
        return None


def parse_date(s: Optional[str]) -> Optional[date]:
    """Parse 'YYYY-MM-DD' to a date, or None."""
    if not s:
        return None
    try:
        return datetime.strptime(str(s)[:10], "%Y-%m-%d").date()
    except Exception:
        return None
