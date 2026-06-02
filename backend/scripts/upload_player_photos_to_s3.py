"""Download SofaScore player headshots and upload them to S3.

Reads the Wyscout -> SofaScore mapping built by
``build_player_photo_mapping.py``, fetches each player's headshot from
``https://api.sofascore.app/api/v1/player/<id>/image``, and uploads it to
``s3://ucluj-player-photos/players/<wy_id>.jpg`` with public-read.

When a player's photo is successfully uploaded, the mapping JSON is
updated with the final S3 URL on the same record. The backend reads
``photo_url`` straight from this file at runtime, so the wy_id -> URL
lookup never needs to leave the process.

Rate-limit: 0.5 s between SofaScore calls by default. SofaScore's image
endpoint is more permissive than the search API but we stay polite.

Run from backend/ with:
    python scripts/upload_player_photos_to_s3.py
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import boto3
import httpx


SOFASCORE_IMAGE = "https://api.sofascore.app/api/v1/player/{id}/image"
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36"
)


def _save_progress(path: Path, mapping: dict[str, dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(mapping, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mapping",
        default="ml/data/wyscout_to_sofascore.json",
        help="Path to the wyscout_to_sofascore mapping JSON.",
    )
    parser.add_argument(
        "--bucket",
        default="ucluj-player-photos",
        help="S3 bucket name. Must already exist with public-read on /players/*.",
    )
    parser.add_argument(
        "--prefix",
        default="players",
        help="S3 key prefix. Final key shape is <prefix>/<wy_id>.jpg.",
    )
    parser.add_argument(
        "--region",
        default="eu-central-1",
        help="AWS region of the S3 bucket.",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.5,
        help="Seconds to wait between SofaScore calls.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-upload even if the mapping already has a photo_url.",
    )
    args = parser.parse_args()

    mapping_path = Path(args.mapping)
    if not mapping_path.exists():
        print(f"[fatal] mapping not found: {mapping_path}", file=sys.stderr)
        return 2
    mapping: dict[str, dict] = json.loads(mapping_path.read_text(encoding="utf-8"))

    s3 = boto3.client("s3", region_name=args.region)
    base_url = f"https://{args.bucket}.s3.{args.region}.amazonaws.com"

    uploaded = 0
    skipped = 0
    failed = 0

    with httpx.Client(timeout=httpx.Timeout(20.0)) as client:
        for idx, (wy_id, record) in enumerate(mapping.items(), start=1):
            sofascore_id = record.get("sofascore_id")
            if not sofascore_id:
                continue
            if record.get("photo_url") and not args.force:
                skipped += 1
                continue

            url = SOFASCORE_IMAGE.format(id=sofascore_id)
            try:
                resp = client.get(url, headers={"User-Agent": USER_AGENT})
            except httpx.HTTPError as exc:
                print(f"[{idx}] wy={wy_id} sr={sofascore_id} http-error: {exc}", file=sys.stderr)
                failed += 1
                continue

            if resp.status_code != 200 or not resp.content:
                print(
                    f"[{idx}] wy={wy_id} sr={sofascore_id} http {resp.status_code} (size {len(resp.content)})",
                    file=sys.stderr,
                )
                failed += 1
                time.sleep(args.delay)
                continue

            content_type = resp.headers.get("content-type", "image/jpeg")
            key = f"{args.prefix}/{wy_id}.jpg"
            try:
                s3.put_object(
                    Bucket=args.bucket,
                    Key=key,
                    Body=resp.content,
                    ContentType=content_type,
                    CacheControl="public, max-age=31536000, immutable",
                )
            except Exception as exc:
                print(f"[{idx}] wy={wy_id} s3-error: {exc}", file=sys.stderr)
                failed += 1
                continue

            record["photo_url"] = f"{base_url}/{key}"
            uploaded += 1
            print(f"[{idx}] wy={wy_id} sr={sofascore_id} uploaded -> {key}")

            if idx % 25 == 0:
                _save_progress(mapping_path, mapping)
            time.sleep(args.delay)

    _save_progress(mapping_path, mapping)
    print(f"\nuploaded={uploaded} skipped={skipped} failed={failed}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
