"""WebSocket $default handler for UmbraRo chat.

The chat socket is receive-only: the client subscribes on $connect and then
only receives messages that FastAPI fans out via post_to_connection. It never
sends frames up the socket (it sends via the REST POST /chat/{channel}/send
endpoint instead).

$default catches any stray client-to-server frame. We simply acknowledge it
with a 200 so API Gateway keeps the connection open. We deliberately do NOT
re-register the connection or touch DynamoDB here.
"""

from __future__ import annotations


def handler(event, context):
    return {"statusCode": 200, "body": "ignored"}
