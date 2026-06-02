"""Read-time Wyscout-id to player-photo URL lookup.

The photos are scraped once from SofaScore and uploaded to S3 by the two
``backend/scripts/*photo*`` scripts, which write the final S3 URL onto each
record in ``ml/data/wyscout_to_sofascore.json``. At runtime the backend only
reads that committed JSON, so it never calls SofaScore or AWS and never needs
boto3. When the mapping is missing or empty the service degrades silently and
every lookup returns ``None``, so the UI falls back to initials.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)


class PlayerPhotoService:
    def __init__(self, mapping_path: str):
        self._by_wy: dict[int, str] = {}
        try:
            raw = json.loads(Path(mapping_path).read_text(encoding="utf-8"))
            for wy, record in (raw or {}).items():
                url = (record or {}).get("photo_url")
                if url:
                    try:
                        self._by_wy[int(wy)] = str(url)
                    except (TypeError, ValueError):
                        continue
            logger.info("PlayerPhotoService loaded %d photo URLs", len(self._by_wy))
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
