"""WebSocket $disconnect handler for UmbraRo chat.

Runs on the API Gateway WebSocket ``$disconnect`` route. It simply removes the
connection row that the ``$connect`` Lambda created, so FastAPI never tries to
push a message to a socket that has already gone away.

No authentication is required here: API Gateway only invokes ``$disconnect`` for
a connection it previously accepted, and the connectionId comes from the trusted
request context, not from the client.
"""

from __future__ import annotations

import os

import boto3

CONNECTIONS_TABLE = os.environ["CONNECTIONS_TABLE"]

_dynamodb = boto3.resource("dynamodb")
_connections = _dynamodb.Table(CONNECTIONS_TABLE)


def handler(event, context):
    connection_id = event.get("requestContext", {}).get("connectionId")
    if not connection_id:
        return {"statusCode": 400, "body": "missing connectionId"}

    _connections.delete_item(Key={"connectionId": connection_id})

    print(f"ws_disconnect: removed {connection_id}")
    return {"statusCode": 200, "body": "disconnected"}
