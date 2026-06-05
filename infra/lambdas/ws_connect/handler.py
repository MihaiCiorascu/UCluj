"""WebSocket $connect authorizer + connection registrar for UmbraRo chat.

This Lambda runs on the API Gateway WebSocket ``$connect`` route. It is the
security boundary for the chat transport, so it must reject any connection that
does not present a valid UmbraRo access token.

CRITICAL AUTH DETAIL
--------------------
The UmbraRo app does NOT authenticate API calls with the Cognito token. The
Flutter client signs in against Cognito, posts the Cognito ID token to the
FastAPI backend once, and the backend then issues its OWN short-lived local
JWT (``backend/core/security.py``):

    * algorithm: HS256
    * secret:    settings.jwt_secret  (the JWT_SECRET env var on App Runner)
    * payload:   {"sub": <user_id>, "email": ..., "role": ..., "type": "access"}

That local access token is what every authenticated request carries, and it is
what the Flutter chat client puts in the ``token`` query-string parameter of the
WebSocket connect URL:

    wss://{apiId}.execute-api.eu-central-1.amazonaws.com/{stage}
        ?channel={channelId}&token={localAccessJwt}

So this authorizer validates THAT token with HS256 + the shared JWT_SECRET. It
deliberately does NOT call Cognito and does NOT accept Cognito ID/access tokens.
The JWT_SECRET configured on this Lambda MUST be byte-for-byte identical to the
JWT_SECRET on the App Runner backend, otherwise signatures will not verify.

On a valid token it writes a connection row into the DynamoDB connections table
so that FastAPI can later fan messages out to this channel via
``apigatewaymanagementapi.post_to_connection``.
"""

from __future__ import annotations

import os
import time

import boto3
import jwt  # PyJWT — verifies the same HS256 token python-jose produces.

# ---------------------------------------------------------------------------
# Configuration (injected as Lambda environment variables by the CFN template).
# ---------------------------------------------------------------------------
JWT_SECRET = os.environ["JWT_SECRET"]
CONNECTIONS_TABLE = os.environ["CONNECTIONS_TABLE"]

# Connections live for 6 hours; covers any realistic chat session. Stale rows
# (tab closed without a clean $disconnect) are reaped by the DynamoDB TTL on the
# ``ttl`` attribute, so the table never accumulates dead connections.
CONNECTION_TTL_SECONDS = 6 * 60 * 60

# Created at module scope so it is reused across warm invocations.
_dynamodb = boto3.resource("dynamodb")
_connections = _dynamodb.Table(CONNECTIONS_TABLE)


def _decode_local_jwt(token: str) -> dict:
    """Validate an UmbraRo local access token. Raises on any problem.

    Mirrors ``core.security.decode_token`` on the backend: HS256, the shared
    secret, and an ``access`` token type. PyJWT validates the ``exp`` claim
    automatically and raises ``ExpiredSignatureError`` / ``InvalidTokenError``.
    """
    payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
    if payload.get("type") != "access":
        raise jwt.InvalidTokenError("expected an access token")
    if not payload.get("sub"):
        raise jwt.InvalidTokenError("token missing subject")
    return payload


def handler(event, context):
    request_context = event.get("requestContext", {})
    connection_id = request_context.get("connectionId")
    params = event.get("queryStringParameters") or {}

    token = params.get("token")
    channel = params.get("channel")

    # The channel identifies the chat room (e.g. a team DM key or "group_<id>").
    # Without it we cannot register the connection for fan-out, so reject.
    if not token or not channel:
        return {"statusCode": 400, "body": "missing token or channel"}

    try:
        payload = _decode_local_jwt(token)
    except jwt.PyJWTError as exc:
        # 401 on $connect makes API Gateway refuse the WebSocket handshake.
        print(f"ws_connect: rejected connection {connection_id}: {exc}")
        return {"statusCode": 401, "body": "invalid token"}

    user_id = payload["sub"]
    team_name = payload.get("team_name")  # not always present; stored if available

    item = {
        "connectionId": connection_id,
        "channel": channel,
        "userId": user_id,
        "ttl": int(time.time()) + CONNECTION_TTL_SECONDS,
    }
    if team_name:
        item["teamName"] = team_name

    _connections.put_item(Item=item)

    print(f"ws_connect: registered {connection_id} user={user_id} channel={channel}")
    return {"statusCode": 200, "body": "connected"}
