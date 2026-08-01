"""
Google Drive data loader for the Starting XI ML pipeline.
Downloads training data from a shared Drive folder and discovers
match-stats files and player-profile JSON automatically.
"""

import json
from collections import Counter
from pathlib import Path
from typing import Optional, Tuple

DRIVE_FOLDER_ID = "1BhS83Q927byfmE0biY2F59wHuIfhlu30"
DEFAULT_CACHE_DIR = Path(__file__).parent / "data" / "drive_cache"


def _require_gdown():
    try:
        import gdown
        return gdown
    except ImportError:
        raise ImportError(
            "gdown is required to download from Google Drive.\n"
            "Install it with:  pip install gdown"
        )


def download_drive_folder(
    folder_id: str = DRIVE_FOLDER_ID,
    output_dir: Optional[str] = None,
    force_redownload: bool = False,
) -> Path:
    """
    Download a public Google Drive folder to a local cache directory.
    Skips the download if JSON files are already present (unless force_redownload).
    Returns the local cache Path.
    """
    gdown = _require_gdown()

    cache = Path(output_dir) if output_dir else DEFAULT_CACHE_DIR
    cache.mkdir(parents=True, exist_ok=True)

    existing = list(cache.rglob("*.json"))
    if existing and not force_redownload:
        print(f"[Drive] Cache hit - {len(existing)} JSON file(s) in {cache}")
        return cache

    print(f"[Drive] Downloading folder {folder_id} -> {cache} ...")
    try:
        gdown.download_folder(
            id=folder_id,
            output=str(cache),
            quiet=False,
            use_cookies=False,
        )
    except Exception as exc:
        msg = str(exc).lower()
        if "retrieve" in msg or "permission" in msg or "403" in msg:
            raise RuntimeError(
                "\n[Drive] *** Permission denied or access restricted ***\n"
                "The Google Drive folder might not be fully public or rate-limited.\n"
                "Fix:\n"
                "  1. Ensure the folder is shared as 'Anyone with the link' -> Viewer.\n"
                "  2. If the error persists, download the folder manually as a ZIP.\n"
                "  3. Extract JSON files to: " + str(cache) + "\n"
                f"Folder link: https://drive.google.com/drive/folders/{folder_id}"
            ) from exc
        raise

    downloaded = list(cache.rglob("*.json"))
    if not downloaded:
        raise RuntimeError(
            f"Download finished but no JSON files found in {cache}.\n"
            "Make sure the Drive folder contains JSON files and is shared as "
            "'Anyone with the link'."
        )
    print(f"[Drive] Downloaded {len(downloaded)} JSON file(s).")
    return cache


def discover_data_paths(cache_dir: Path) -> Tuple[str, Optional[str]]:
    """
    Scan the downloaded folder and identify:
      - match_stats_dir  : directory that contains match-stat JSON files
      - player_profiles  : path to the player-profiles JSON (or None)

    Heuristic:
      - A file is treated as a player-profile if it contains a list of objects
        with a "wyId" key, OR a dict whose values have "currentTeamId" / "role".
      - Everything else is treated as match-stat data.
    """
    all_jsons = list(cache_dir.rglob("*.json"))
    if not all_jsons:
        raise FileNotFoundError(f"No JSON files found under {cache_dir}")

    player_profiles_path: Optional[str] = None

    profile_name_hints = ("profile", "player", "players", "squad", "roster")
    candidates = [
        f for f in all_jsons
        if any(kw in f.name.lower() for kw in profile_name_hints)
    ]

    for candidate in candidates:
        try:
            with open(candidate, encoding="utf-8") as fh:
                data = json.load(fh)
            if isinstance(data, list) and data and "wyId" in data[0]:
                player_profiles_path = str(candidate)
                break
            if isinstance(data, dict):
                # Check for nested 'players' list (common in profiles)
                if "players" in data and isinstance(data["players"], list) and data["players"]:
                    if "wyId" in data["players"][0]:
                        player_profiles_path = str(candidate)
                        break
                # Fallback to checking top-level values
                sample = next(iter(data.values()), {})
                if isinstance(sample, dict) and any(
                    k in sample for k in ("wyId", "currentTeamId", "role")
                ):
                    player_profiles_path = str(candidate)
                    break
        except Exception:
            continue

    match_files = [
        f for f in all_jsons
        if player_profiles_path is None or str(f) != player_profiles_path
    ]

    if match_files:
        parent_counts = Counter(str(f.parent) for f in match_files)
        match_stats_dir = parent_counts.most_common(1)[0][0]
    else:
        match_stats_dir = str(cache_dir)

    return match_stats_dir, player_profiles_path
