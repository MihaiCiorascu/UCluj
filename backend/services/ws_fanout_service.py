"""Instant-chat fan-out over the API Gateway WebSocket (Part C).

App Runner is HTTP-only and cannot serve WebSockets, so the real-time transport
lives in API Gateway (see infra/template.yaml). FastAPI stays the brain: it
persists each message to RDS, then looks up the live connections on the channel
in DynamoDB and pushes the message JSON to each one via the API Gateway
Management API ``post_to_connection``. This mirrors the Brezn
``backend/shared/ws.py::push_to_channel`` pattern.

DynamoDB item shape (written by the $connect Lambda, infra/lambdas/ws_connect):
    {connectionId, channel, userId, ttl[, teamName]}
queried through the ``channel-index`` GSI on ``channel``.

Config (app.config.Settings; env vars WS_API_MANAGEMENT_ENDPOINT /
WS_CONNECTIONS_TABLE):
    settings.ws_api_management_endpoint  https://{apiId}.execute-api.<region>.amazonaws.com/prod
    settings.ws_connections_table        umbraro-ws-connections

When ``ws_api_management_endpoint`` is unset (e.g. local dev without the infra),
fan-out is a no-op so persistence + the history endpoint still work.
"""

from __future__ import annotations

import asyncio
import json
import logging

import boto3
from boto3.dynamodb.conditions import Attr, Key

from app.config import settings

logger = logging.getLogger(__name__)

CHANNEL_INDEX = "channel-index"

# Created lazily and reused across requests. On App Runner these pick up the
# instance-role credentials automatically (no access keys configured).
_dynamodb = None
_connections_table = None
_apigw_client = None


def _connections():
    global _dynamodb, _connections_table
    if _connections_table is None:
        # The whole stack lives in eu-central-1 (same region as the avatars
        # bucket); on App Runner boto3 also reads AWS_REGION automatically.
        _dynamodb = boto3.resource("dynamodb", region_name=settings.avatars_s3_region)
        _connections_table = _dynamodb.Table(settings.ws_connections_table)
    return _connections_table


def _apigw():
    global _apigw_client
    if _apigw_client is None:
        _apigw_client = boto3.client(
            "apigatewaymanagementapi",
            endpoint_url=settings.ws_api_management_endpoint,
        )
    return _apigw_client


def _push_sync(channel: str, payload: dict) -> int:
    """Blocking fan-out. Returns the number of connections delivered to.

    Queries the channel-index for live connections and posts the JSON-encoded
    payload to each. Stale connections (GoneException) are deleted so the table
    never accumulates dead rows beyond their TTL.
    """
    table = _connections()
    response = table.query(
        IndexName=CHANNEL_INDEX,
        KeyConditionExpression=Key("channel").eq(channel),
    )
    items = response.get("Items", [])
    if not items:
        return 0

    data = json.dumps(payload, default=str).encode("utf-8")
    apigw = _apigw()
    delivered = 0
    stale: list[str] = []

    for item in items:
        connection_id = item.get("connectionId")
        if not connection_id:
            continue
        try:
            apigw.post_to_connection(ConnectionId=connection_id, Data=data)
            delivered += 1
        except apigw.exceptions.GoneException:
            stale.append(connection_id)
        except Exception:  # noqa: BLE001 - never let one bad socket abort the rest
            logger.warning("ws fan-out: post_to_connection failed for %s", connection_id, exc_info=True)

    for connection_id in stale:
        try:
            table.delete_item(Key={"connectionId": connection_id})
        except Exception:  # noqa: BLE001
            logger.warning("ws fan-out: failed to delete stale connection %s", connection_id, exc_info=True)

    if stale:
        logger.info("ws fan-out: cleaned up %d stale connections on channel %s", len(stale), channel)
    return delivered


async def push_to_channel(channel: str, payload: dict) -> int:
    """Async wrapper around the blocking boto3 fan-out.

    Runs in a worker thread so it never blocks the event loop (matching the
    repo's ``asyncio.to_thread`` convention). Fan-out failures are swallowed so a
    transport hiccup never fails the caller's REST request: the message is
    already persisted and will be back-filled via the history endpoint.
    """
    if not settings.ws_api_management_endpoint:
        logger.debug("ws fan-out skipped: WS_API_MANAGEMENT_ENDPOINT unset")
        return 0
    try:
        return await asyncio.to_thread(_push_sync, channel, payload)
    except Exception:  # noqa: BLE001
        logger.warning("ws fan-out failed for channel %s", channel, exc_info=True)
        return 0


def _push_to_users_sync(user_ids: list[str], payload: dict) -> int:
    """Blocking fan-out to every live connection owned by the given users.

    Used for events that target people rather than a channel (e.g. a new group
    appearing for its members), so they arrive whatever channel each member is
    currently viewing. The connections table is small (one row per live socket,
    TTL-expired), so a filtered scan is acceptable and avoids adding a userId GSI
    just for this. Returns the number of connections delivered to.
    """
    targets = [u for u in dict.fromkeys(user_ids) if u]
    if not targets:
        return 0
    table = _connections()
    data = json.dumps(payload, default=str).encode("utf-8")
    apigw = _apigw()
    delivered = 0
    stale: list[str] = []
    scan_kwargs: dict = {"FilterExpression": Attr("userId").is_in(targets)}
    while True:
        response = table.scan(**scan_kwargs)
        for item in response.get("Items", []):
            connection_id = item.get("connectionId")
            if not connection_id:
                continue
            try:
                apigw.post_to_connection(ConnectionId=connection_id, Data=data)
                delivered += 1
            except apigw.exceptions.GoneException:
                stale.append(connection_id)
            except Exception:  # noqa: BLE001
                logger.warning("ws user fan-out: post_to_connection failed for %s", connection_id, exc_info=True)
        last_key = response.get("LastEvaluatedKey")
        if not last_key:
            break
        scan_kwargs["ExclusiveStartKey"] = last_key

    for connection_id in stale:
        try:
            table.delete_item(Key={"connectionId": connection_id})
        except Exception:  # noqa: BLE001
            logger.warning("ws user fan-out: failed to delete stale connection %s", connection_id, exc_info=True)
    return delivered


async def push_to_users(user_ids: list[str], payload: dict) -> int:
    """Async wrapper around :func:`_push_to_users_sync`.

    Mirrors :func:`push_to_channel`: runs the blocking boto3 work in a worker
    thread and swallows transport failures so a hiccup never fails the caller's
    REST request (the data is already persisted and back-fills on next load).
    """
    if not settings.ws_api_management_endpoint:
        logger.debug("ws user fan-out skipped: WS_API_MANAGEMENT_ENDPOINT unset")
        return 0
    try:
        return await asyncio.to_thread(_push_to_users_sync, list(user_ids), payload)
    except Exception:  # noqa: BLE001
        logger.warning("ws user fan-out failed", exc_info=True)
        return 0
