"""
PreSignUp Cognito trigger, cleans up UNCONFIRMED duplicates before a new sign-up.

When a user starts sign-up with email X, never enters the emailed verification
code, and abandons, Cognito leaves the record in ``UserStatus: UNCONFIRMED``.
Without this trigger X is effectively reserved: re-signing-up with X fails with
``UsernameExistsException`` and signing in fails because the account was never
confirmed.

This trigger fires before every ``signUp``. If an UNCONFIRMED user with the same
username already exists it is deleted, so the new ``signUp`` proceeds with
whatever password the user just typed. CONFIRMED users are left untouched, so a
real existing account still surfaces "this email already has an account" through
the normal ``UsernameExistsException`` path.

The pool id is read from the trigger event (``event['userPoolId']``), which
Cognito always includes, with the ``USER_POOL_ID`` environment variable as a
fallback. The function's IAM policy is scoped to that one pool.

This is the canonical source. The same code is embedded inline (``ZipFile``) in
``infra/auth/lambdas-auth-presignup.yml`` so the stack deploys without packaging.
Keep the two copies in sync.
"""

import os

import boto3
from botocore.exceptions import ClientError

client = boto3.client("cognito-idp")


def handler(event, context):
    pool_id = event.get("userPoolId") or os.environ.get("USER_POOL_ID", "")
    username = (event.get("userName") or "").strip()
    if not pool_id or not username:
        return event

    try:
        existing = client.admin_get_user(UserPoolId=pool_id, Username=username)
        if existing.get("UserStatus") == "UNCONFIRMED":
            client.admin_delete_user(UserPoolId=pool_id, Username=username)
    except client.exceptions.UserNotFoundException:
        pass  # first sign-up attempt, nothing to clean up
    except ClientError:
        # Defensive: never block sign-up because of a trigger error. Worst case
        # the user hits the original UsernameExistsException (the pre-fix
        # behaviour), which the frontend already handles.
        pass

    return event
