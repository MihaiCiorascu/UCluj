# UmbraRo infrastructure (`infra/`)

Infrastructure-as-code for the two pieces of the UmbraRo platform that AWS App
Runner cannot host itself:

1. **Avatars (Part B)** — durable, multi-device user profile pictures in S3,
   uploaded by the browser straight to a backend-signed presigned PUT URL.
2. **Instant chat (Part C)** — an API Gateway **WebSocket** API with a DynamoDB
   connection registry and two Python Lambdas. App Runner is HTTP-only and
   cannot serve WebSockets, so this stack provides the real-time push transport.
   FastAPI on App Runner stays the brain: it persists messages to RDS and fans
   them out through the API Gateway Management API.

Everything is one CloudFormation/SAM stack: **`template.yaml`**.

- **Region:** `eu-central-1`
- **Account:** `302432776212`
- **App Runner service:** `ucluj-backend`
- **Default stack name:** `umbraro-infra`

This stack creates **no** application code changes. It only provisions AWS
resources and emits the outputs the backend and frontend read. App code in
`lib/` and `backend/` is untouched.

---

## What the stack creates

| Resource | Purpose |
|---|---|
| `AvatarsBucket` (S3, optional) | Stores avatars under `avatars/<user_id>.jpg`. CORS allows `PUT/GET/HEAD` from the Amplify origin; `avatars/*` is public-read for display. Created only when `CreateAvatarsBucket=true`. |
| `ConnectionsTable` (DynamoDB `umbraro-ws-connections`) | PK `connectionId`; GSI `channel-index` on `channel`; attrs `userId`/`teamName`; `ttl` TTL (~6h). On-demand billing. |
| `WsConnectFunction` (Lambda) | `$connect`: validates the **local** HS256 JWT from the `token` query param, reads `channel`, writes `{connectionId, channel, userId, ttl}` to DynamoDB. |
| `WsDisconnectFunction` (Lambda) | `$disconnect`: deletes the row by `connectionId`. |
| `WsDefaultFunction` (Lambda) | `$default`: no-op 200 (the socket is receive-only). |
| `WsLambdaExecutionRole` (IAM) | Lambda exec role: DynamoDB RW on the table + CloudWatch Logs. |
| `WebSocketApi` + routes + `prod` stage | API Gateway WebSocket API with `$connect`, `$disconnect`, `$default`. |
| `AppRunnerAvatarsS3Policy` (IAM managed policy) | For the **App Runner instance role**: `s3:PutObject` + `s3:GetObject` on `avatars/*`. |
| `AppRunnerChatPolicy` (IAM managed policy) | For the **App Runner instance role**: `dynamodb:Query` on the table + `channel-index`, and `execute-api:ManageConnections` on the WS API. |

---

## CRITICAL auth detail — the `$connect` authorizer

UmbraRo does **not** authenticate API calls with the Cognito token. Cognito is
only used for the initial sign-in; the backend then issues its **own** local
JWT (see `backend/core/security.py`):

- algorithm **HS256**
- secret **`JWT_SECRET`** (the same value set on the App Runner backend)
- payload `{"sub": <user_id>, "email", "role", "type": "access"}`

The Flutter chat client puts that **local access token** in the WebSocket
connect URL's `token` query-string parameter. Therefore the `$connect` Lambda
validates **this** token with HS256 + the shared `JWT_SECRET` — it does **not**
call Cognito and does **not** accept Cognito tokens.

> The `JwtSecret` you pass to this stack **must be byte-for-byte identical** to
> the `JWT_SECRET` env var on the App Runner `ucluj-backend` service. If they
> differ, every chat connection is rejected with 401 at `$connect`.

---

## Avatars bucket choice

The plan offers two options. This stack defaults to **a new dedicated bucket
`ucluj-user-avatars`** because it keeps user-generated uploads isolated from the
read-only, build-time `ucluj-player-photos` bucket (different lifecycle, CORS,
and public-read surface), which is cleaner and lower-blast-radius.

- **Default (recommended):** new bucket.
  `AvatarsBucketName=ucluj-user-avatars`, `CreateAvatarsBucket=true`.
  The stack creates the bucket, its CORS, and the `avatars/*` public-read policy.

- **Reuse the existing bucket:** set
  `AvatarsBucketName=ucluj-player-photos` **and** `CreateAvatarsBucket=false`.
  CloudFormation cannot mutate a bucket it does not own, so in this mode the
  stack skips the bucket, its CORS, and its policy — you apply those manually
  (commands in *Manual bucket setup when reusing* below). The App Runner IAM
  policy and the public base URL output still target whatever bucket name you
  pass, so the config contract is identical either way.

Either way the public object URL is
`https://<bucket>.s3.eu-central-1.amazonaws.com/avatars/<user_id>.jpg`.

---

## Prerequisites

- AWS credentials for account `302432776212` with rights to create S3, DynamoDB,
  Lambda, API Gateway v2, and IAM resources.
- One of:
  - **AWS SAM CLI** (`sam`) — preferred; it builds and vendors the Lambda
    dependency (PyJWT) for you, **or**
  - **AWS CLI v2** (`aws`) with the `cloudformation package` + `deploy`
    sub-commands and a staging S3 bucket for Lambda artifacts.

---

## Provisioning — Option 1: AWS SAM (preferred)

```bash
cd infra

# Build vendors each Lambda's requirements.txt (PyJWT for ws_connect).
sam build

# Deploy. Pass JwtSecret inline so it never lands on disk.
sam deploy \
  --stack-name umbraro-infra \
  --region eu-central-1 \
  --capabilities CAPABILITY_NAMED_IAM \
  --resolve-s3 \
  --parameter-overrides \
    "JwtSecret=<the-app-runner-JWT_SECRET>"
```

To reuse the existing bucket instead of creating a new one, add to
`--parameter-overrides`:

```
AvatarsBucketName=ucluj-player-photos CreateAvatarsBucket=false
```

`samconfig.toml` already pins the stack name, region, and capabilities, so after
the first run `sam deploy --parameter-overrides "JwtSecret=..."` is enough.

---

## Provisioning — Option 2: pure AWS CLI (no SAM CLI installed)

`template.yaml` uses the SAM transform, which `aws cloudformation deploy`
expands server-side. You only need a staging bucket so the CLI can upload the
zipped Lambda code and rewrite the local `CodeUri` paths.

```bash
cd infra

# One-time: a private S3 bucket to stage Lambda artifacts (any name you own).
aws s3 mb s3://umbraro-sam-artifacts --region eu-central-1

# 1) Package: zip + upload Lambda code, emit a deployable template.
#    NOTE: this does NOT vendor PyJWT. Either add a Lambda layer with PyJWT,
#    or `pip install -t lambdas/ws_connect/ PyJWT==2.9.0` before packaging so
#    the dependency ships inside the function zip. (sam build does this for you.)
pip install -t lambdas/ws_connect/ -r lambdas/ws_connect/requirements.txt

aws cloudformation package \
  --template-file template.yaml \
  --s3-bucket umbraro-sam-artifacts \
  --output-template-file packaged.yaml \
  --region eu-central-1

# 2) Deploy the packaged template.
aws cloudformation deploy \
  --template-file packaged.yaml \
  --stack-name umbraro-infra \
  --region eu-central-1 \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --parameter-overrides \
    "JwtSecret=<the-app-runner-JWT_SECRET>"
```

---

## Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `JwtSecret` | *(required, NoEcho)* | The HS256 secret the backend signs local access tokens with. Must equal the App Runner `JWT_SECRET`. |
| `AvatarsBucketName` | `ucluj-user-avatars` | Bucket holding `avatars/*`. |
| `CreateAvatarsBucket` | `true` | `true` = stack creates the bucket; `false` = bucket already exists (skip bucket/CORS/policy). |
| `AmplifyOrigin` | `https://umbraro.d2j9yfctr6ipf6.amplifyapp.com` | Origin allowed to PUT avatars from the browser. |
| `WebSocketStageName` | `prod` | WebSocket stage; embedded in the WSS + management URLs. |
| `ConnectionsTableName` | `umbraro-ws-connections` | DynamoDB connections table. |

---

## After deploy — attach the App Runner INSTANCE ROLE

App Runner runs your container under an **instance role** (distinct from the
*access* role that pulls the ECR image). FastAPI uses the instance role's
credentials to sign avatar presigned URLs, query DynamoDB, and call
`post_to_connection`. This stack **creates** the two managed policies but cannot
attach them to App Runner's instance role automatically, so do it once:

```bash
# Read the policy ARNs from the stack outputs.
aws cloudformation describe-stacks \
  --stack-name umbraro-infra --region eu-central-1 \
  --query "Stacks[0].Outputs[?OutputKey=='AppRunnerAvatarsS3PolicyArn' || OutputKey=='AppRunnerChatPolicyArn'].[OutputKey,OutputValue]" \
  --output table

# If the ucluj-backend service has no instance role yet, create one:
aws iam create-role \
  --role-name umbraro-apprunner-instance \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "tasks.apprunner.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach both managed policies (substitute the ARNs printed above):
aws iam attach-role-policy --role-name umbraro-apprunner-instance \
  --policy-arn <AppRunnerAvatarsS3PolicyArn>
aws iam attach-role-policy --role-name umbraro-apprunner-instance \
  --policy-arn <AppRunnerChatPolicyArn>
```

Then set this role as the **instance role** on the `ucluj-backend` App Runner
service: AWS console -> App Runner -> `ucluj-backend` -> *Configuration* ->
*Security* -> **Instance role** -> `umbraro-apprunner-instance` -> deploy. (Or
`aws apprunner update-service --service-arn <arn>
--instance-configuration InstanceRoleArn=<role-arn>`.)

---

## Manual bucket setup when reusing `ucluj-player-photos`

Only needed if you set `CreateAvatarsBucket=false`. Apply CORS and the
`avatars/*` public-read policy yourself:

```bash
# CORS — allow the Amplify origin to PUT/GET.
aws s3api put-bucket-cors --bucket ucluj-player-photos --region eu-central-1 \
  --cors-configuration '{
    "CORSRules": [{
      "AllowedOrigins": ["https://umbraro.d2j9yfctr6ipf6.amplifyapp.com"],
      "AllowedMethods": ["PUT", "GET", "HEAD"],
      "AllowedHeaders": ["*"],
      "ExposedHeaders": ["ETag"],
      "MaxAgeSeconds": 3000
    }]
  }'

# Public-read on avatars/* (merge into the bucket's existing policy if it
# already has a players/* statement — do not overwrite it).
aws s3api put-bucket-policy --bucket ucluj-player-photos --region eu-central-1 \
  --policy '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "PublicReadAvatars",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::ucluj-player-photos/avatars/*"
    }]
  }'
```

---

## Stack OUTPUTS the app consumes

After deploy, read them with:

```bash
aws cloudformation describe-stacks \
  --stack-name umbraro-infra --region eu-central-1 \
  --query "Stacks[0].Outputs" --output table
```

| Output | Example value | Consumed by |
|---|---|---|
| `WebSocketConnectUrl` | `wss://{apiId}.execute-api.eu-central-1.amazonaws.com/prod` | **Frontend** — `config.json` key `wsConnectUrl`. Client appends `?channel={channelId}&token={localAccessJwt}`. |
| `WebSocketManagementEndpoint` | `https://{apiId}.execute-api.eu-central-1.amazonaws.com/prod` | **Backend** — `WS_API_MANAGEMENT_ENDPOINT` (FastAPI `post_to_connection`). |
| `ConnectionsTableName` | `umbraro-ws-connections` | **Backend** — `WS_CONNECTIONS_TABLE`. |
| `AvatarsBucket` | `ucluj-user-avatars` | **Backend** — `AVATARS_S3_BUCKET`. |
| `AvatarsPublicBaseUrl` | `https://ucluj-user-avatars.s3.eu-central-1.amazonaws.com` | Backend builds the public avatar URL (`<base>/avatars/<id>.jpg`). |
| `AppRunnerAvatarsS3PolicyArn` | `arn:aws:iam::302432776212:policy/umbraro-apprunner-avatars-s3` | Ops — attach to App Runner instance role. |
| `AppRunnerChatPolicyArn` | `arn:aws:iam::302432776212:policy/umbraro-apprunner-chat` | Ops — attach to App Runner instance role. |
| `WebSocketApiId` | `{apiId}` | Ops — raw API id for building URLs. |

---

## CONFIG CONTRACT

These are the exact names the application code uses. Set them after deploy.

### Backend (App Runner `ucluj-backend` environment variables)

| Env var | Value (from stack output) | Meaning |
|---|---|---|
| `AVATARS_S3_BUCKET` | `AvatarsBucket` (e.g. `ucluj-user-avatars`) | Bucket the backend signs presigned PUTs against and stores avatars in. |
| `AVATARS_S3_REGION` | `eu-central-1` | Region of the avatars bucket. |
| `WS_API_MANAGEMENT_ENDPOINT` | `WebSocketManagementEndpoint` | `https://{apiId}.execute-api.eu-central-1.amazonaws.com/prod`. Endpoint URL for the `apigatewaymanagementapi` boto3 client (`post_to_connection`). |
| `WS_CONNECTIONS_TABLE` | `ConnectionsTableName` (`umbraro-ws-connections`) | DynamoDB table the backend `Query`s on `channel-index` to find connections to fan out to. |
| `JWT_SECRET` | *(already set)* | Unchanged — but **the same value must be passed to this stack** as `JwtSecret` so the `$connect` Lambda validates the identical token. |

> The backend already reuses the `AWS_REGION` / instance-role credentials of App
> Runner for boto3; no access keys are needed.

### Lambda (set by the stack, listed for reference)

| Lambda env var | Source | Meaning |
|---|---|---|
| `JWT_SECRET` | `JwtSecret` parameter | HS256 secret to validate the chat token in `$connect`. |
| `CONNECTIONS_TABLE` | `ConnectionsTableName` | Connections table the Lambdas write/delete. |

### Frontend (Amplify-served `config.json` / dart-define)

| Config key | Value (from stack output) | Meaning |
|---|---|---|
| `wsConnectUrl` | `WebSocketConnectUrl` | `wss://{apiId}.execute-api.eu-central-1.amazonaws.com/prod`. The chat client appends `?channel={channelId}&token={localAccessJwt}`. Loaded at runtime via `AppConfig.load()` alongside `apiBaseUrl`, so it can change without a Flutter rebuild. |

Example `web/config.json` after deploy:

```json
{
  "apiBaseUrl": "https://b7fukv3pxv.eu-central-1.awsapprunner.com/api/v1",
  "wsConnectUrl": "wss://{apiId}.execute-api.eu-central-1.amazonaws.com/prod"
}
```

---

## Auth: Cognito + SES + PreSignUp trigger (`infra/auth/`)

A separate, smaller set of templates provisions authentication. They are **not**
part of `template.yaml`.

| File | Creates |
|---|---|
| `auth/cognito.yml` | `AWS::Cognito::UserPool` (`umbraro-user-pool`, email sign-in, emailed 6-digit confirmation via Cognito's own mailer by default, or SES in `DEVELOPER` mode) + `UserPoolClient` (`umbraro-web-client`, SRP, no secret). No IAM. |
| `auth/lambdas-auth-presignup.yml` | A Python Lambda (`umbraro-auth-pre-signup`) + its IAM role + the Cognito invoke permission. Optional, recommended. Deletes a still-`UNCONFIRMED` duplicate before each sign-up so a user who abandoned verification can sign up again with the same email. |
| `auth/lambdas/auth_pre_signup/handler.py` | Canonical source for the Lambda (the template embeds the same code inline). |

The two stacks have a one-way dependency the other way round (the pool needs the
Lambda ARN; the Lambda needs the pool id), so deploy in this order:

```bash
# 0) Only for DEVELOPER mode: verify the SES sender identity (then click the link
#    AWS emails). Skip this when keeping the COGNITO_DEFAULT mailer (the default).
aws ses verify-email-identity --email-address mihaiciorascu11@gmail.com --region eu-central-1

# 1) Create the pool WITHOUT the trigger. No IAM, so no --capabilities.
aws cloudformation deploy --template-file infra/auth/cognito.yml \
  --stack-name umbraro-auth --region eu-central-1
aws cloudformation describe-stacks --stack-name umbraro-auth --region eu-central-1 \
  --query "Stacks[0].Outputs"   # note UserPoolId + UserPoolClientId

# 2) (Recommended) Deploy the PreSignUp Lambda, passing the pool id from step 1.
aws cloudformation deploy --template-file infra/auth/lambdas-auth-presignup.yml \
  --stack-name umbraro-auth-presignup \
  --parameter-overrides UserPoolId=<UserPoolId> \
  --capabilities CAPABILITY_NAMED_IAM --region eu-central-1
aws cloudformation describe-stacks --stack-name umbraro-auth-presignup --region eu-central-1 \
  --query "Stacks[0].Outputs"   # note PreSignUpLambdaArn

# 3) Re-deploy the pool WITH the trigger attached.
aws cloudformation deploy --template-file infra/auth/cognito.yml \
  --stack-name umbraro-auth \
  --parameter-overrides PreSignUpLambdaArn=<PreSignUpLambdaArn> \
  --region eu-central-1
```

### Config contract

The two pool outputs feed both ends:

| Output | Frontend (`web/config.json`) | Backend (App Runner `ucluj-backend` env) |
|---|---|---|
| `UserPoolId` | `cognitoUserPoolId` | `COGNITO_USER_POOL_ID` |
| `UserPoolClientId` | `cognitoAppClientId` | `COGNITO_APP_CLIENT_ID` |
| (region) | (implicit) | `COGNITO_REGION=eu-central-1` |

While both `web/config.json` values are blank, the Flutter client runs the local
email/password fallback instead of Cognito.

### Verification email delivery

`EmailConfiguration` defaults to `COGNITO_DEFAULT` (`EmailSendingMode`): Cognito
sends the confirmation code through its own mail service, which reaches **any**
recipient even while SES is in the sandbox, but is capped at ~50 emails/day and
uses a generic Amazon `From` address. This is the default so the committee's test
addresses receive codes without any SES setup.

For branded, high-volume sending, set `EmailSendingMode` to `DEVELOPER`, which
routes the code through your SES identity (`SesFromAddress`) instead. That gives
your own sender and far higher volume, but while the account is in the SES sandbox
only **verified** recipient addresses receive the email, so verify the test
addresses, or request SES production access (~24h), before relying on arbitrary
user emails.

### PreSignUp trigger

Without step 2, re-signing-up an email that is still `UNCONFIRMED` returns
"account already exists" until the stale entry expires. The trigger (step 2)
removes that friction. To detach it later, re-deploy `cognito.yml` with an empty
`PreSignUpLambdaArn`.

---

## Teardown

```bash
aws cloudformation delete-stack --stack-name umbraro-infra --region eu-central-1
```

The avatars bucket has `DeletionPolicy: Retain`, so it (and its objects) survive
stack deletion. Empty and delete it manually if you truly want it gone. The
App Runner instance-role attachments are out-of-band; detach them separately.
```
