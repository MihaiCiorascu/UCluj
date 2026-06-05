"""Avatar storage on S3 via backend-signed presigned PUT URLs (Part B).

App Runner's local disk is ephemeral, so uploaded avatars must not be written to
disk. Instead the browser PUTs the image bytes straight to S3 using a short-lived
presigned URL that FastAPI signs with the App Runner instance-role credentials
(see infra/template.yaml -> AppRunnerAvatarsS3Policy). The object key is stable
per user (``avatars/<user_id>.jpg``, overwrite-in-place), so the public display
URL carries a ``?v=<ts>`` cache-buster to defeat browser/CDN caching after a
re-upload.

Config (app.config.Settings, env vars AVATARS_S3_BUCKET / AVATARS_S3_REGION):
    settings.avatars_s3_bucket   e.g. ucluj-user-avatars
    settings.avatars_s3_region   e.g. eu-central-1

Public object URL shape (matches the infra AvatarsPublicBaseUrl output):
    https://<bucket>.s3.<region>.amazonaws.com/avatars/<user_id>.jpg
"""

from __future__ import annotations

import time

import boto3

from app.config import settings

# Avatars are always stored as JPEG under this prefix, one object per user.
AVATAR_PREFIX = "avatars"
AVATAR_CONTENT_TYPE = "image/jpeg"
# ~5 minutes: long enough for the browser to PUT the bytes, short enough that a
# leaked URL is useless almost immediately.
PRESIGN_EXPIRY_SECONDS = 300

# Created lazily and reused. On App Runner this picks up the instance-role
# credentials automatically; no access keys are configured.
_s3_client = None


def _client():
    global _s3_client
    if _s3_client is None:
        _s3_client = boto3.client("s3", region_name=settings.avatars_s3_region)
    return _s3_client


def avatar_key(user_id: str) -> str:
    return f"{AVATAR_PREFIX}/{user_id}.jpg"


def public_avatar_url(user_id: str, *, cache_bust: bool = True) -> str:
    """Public https URL for a user's avatar object.

    The key is stable (overwrite-in-place), so a ``?v=<unix_ts>`` cache-buster is
    appended by default to force clients to refetch after a re-upload.
    """
    base = (
        f"https://{settings.avatars_s3_bucket}.s3."
        f"{settings.avatars_s3_region}.amazonaws.com/{avatar_key(user_id)}"
    )
    if cache_bust:
        return f"{base}?v={int(time.time())}"
    return base


def generate_presigned_put_url(user_id: str) -> str:
    """Sign a presigned S3 PUT URL for the user's avatar object.

    The browser PUTs the raw JPEG bytes to this URL with
    ``Content-Type: image/jpeg``. ContentType is pinned into the signature so the
    upload must declare the same type.
    """
    return _client().generate_presigned_url(
        "put_object",
        Params={
            "Bucket": settings.avatars_s3_bucket,
            "Key": avatar_key(user_id),
            "ContentType": AVATAR_CONTENT_TYPE,
        },
        ExpiresIn=PRESIGN_EXPIRY_SECONDS,
    )
