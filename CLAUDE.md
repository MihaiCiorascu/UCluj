# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

**UmbraRo** — an AI tactical intelligence assistant for professional Romanian Superliga football coaches. The product operationalises an academic thesis: CatBoost win-probability prediction + constrained Monte Carlo optimisation for prescriptive tactical recommendations.

Before implementing anything, consult **`/AGENTS.md`** (product bible) and **`/design/backend-contract.md`** (supported feature scope). These are non-negotiable constraints, not suggestions.

## Architecture

Two-part system, fully hosted on AWS:

**Flutter frontend** (`lib/`) — mobile/web app, deployed on **AWS Amplify Hosting** from the `umbraro` branch (live at `umbraro.d2j9yfctr6ipf6.amplifyapp.com`). Feature-first structure under `lib/features/`; shared infrastructure in `lib/core/`. State management: `ChangeNotifier` + Repository pattern (no Riverpod/Bloc). The runtime API URL is loaded from `web/config.json` (read by `lib/core/config/app_config.dart`) so it can change without a Flutter rebuild.

**FastAPI backend** (`backend/`) — async Python 3.11+, packaged as a Docker image stored in **Amazon ECR** (`302432776212.dkr.ecr.eu-central-1.amazonaws.com/ucluj-backend`) and served by **AWS App Runner** at `https://b7fukv3pxv.eu-central-1.awsapprunner.com`. Layered: `api/v1/endpoints/` → `services/` → `data/` loaders. The ML bundle (`ml/umbraro_catboost_bundle.joblib`) is loaded once at startup via a lifespan hook. Persistent state (users, profiles, chat) lives in **AWS RDS PostgreSQL** through async SQLAlchemy over `asyncpg`; a local `sqlite+aiosqlite` database is the default for development. Client-side authentication goes through **AWS Cognito**, with the backend verifying the Cognito ID token and issuing a short-lived local JWT bound to the Cognito subject. User avatars use presigned **S3** uploads, and instant chat fans out over an **API Gateway WebSocket** with a DynamoDB connections table; both are provisioned by `infra/template.yaml`.

**Data flow:** `All_Data.csv` (~1600 Romanian Superliga matches, 2020–2025) → feature engineering → CatBoost prediction → Monte Carlo optimizer → tactical blueprint with probability uplift.

### Key design files

| File | Purpose |
|---|---|
| `/AGENTS.md` | Product identity, ML methodology, what must never be added |
| `/design/backend-contract.md` | Supported input features and API data scope |
| `/design/design-system.md` | "Stoic Analyst" visual language rules |
| `/design/product-spec.md` | Feature roadmap |

## Commands

### Backend (local development)

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate          # Windows
pip install -r requirements.txt
cp .env.example .env            # Then fill in JWT_SECRET, DATABASE_URL, COGNITO_*, SPORTRADAR_API_KEY
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

The committed `.env.example` defaults `DATABASE_URL` to a local `sqlite+aiosqlite` file so the backend runs with no external services; point it at the `postgresql+asyncpg://...` RDS URL to mirror production.

### Flutter (Web)

```bash
flutter pub get
flutter run -d chrome --web-port 8080 \
  --dart-define=APP_ENV=development \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

### Tests

```bash
flutter test                                                    # unit tests
flutter drive --target=integration_test/app_test.dart          # integration tests
```

### Deploy

- **Frontend:** push to the `umbraro` branch; Amplify Hosting auto-builds and serves the Flutter web app.
- **Backend:** the `deploy-backend.yml` GitHub Actions workflow builds the Docker image, pushes it to ECR, and triggers an App Runner deployment. To do it by hand:

```bash
docker build -t ucluj-backend .
docker tag ucluj-backend:latest 302432776212.dkr.ecr.eu-central-1.amazonaws.com/ucluj-backend:latest
docker push 302432776212.dkr.ecr.eu-central-1.amazonaws.com/ucluj-backend:latest
# Then start a deployment on the ucluj-backend App Runner service.
```

## Configuration

**Backend `.env`:**

```
UMBRARO_ENV=development
JWT_SECRET=<change-me>
DATABASE_URL=postgresql+asyncpg://postgres:<password>@<host>:5432/postgres   # sqlite+aiosqlite:///./umbraro.db for local dev
CORS_ORIGINS=http://localhost:3000,http://localhost:8080,http://127.0.0.1:8080
COGNITO_REGION=eu-central-1
COGNITO_USER_POOL_ID=eu-central-1_REPLACE_ME
COGNITO_APP_CLIENT_ID=REPLACE_ME
SPORTRADAR_API_KEY=<optional>
```

**Flutter dart-defines:** `APP_ENV`, `API_BASE_URL`

## ML and Supported Features

**Supported model inputs** (rolling 5-match aggregates): Elo difference, head-to-head record, rest days, possession %, shots, shots on target, corners, goals scored, goals conceded.

**Model:** CatBoost (production). Logistic Regression is baseline only — never present it as the main model.

**Outputs:** baseline win probability, optimised win probability, probability uplift, tactical targets, key drivers (top positive/negative), plain-English tactical diagnosis.

**Never invent or add:** biometrics, GPS, xThreat, pass networks, player-level tracking, 3-way classification (home/draw/away), betting-odds framing, or any metric not in the training feature set.

## Design Constraints

**"Stoic Analyst" visual language (non-negotiable):**
- Palette: `#0A1929` (surface), `#1E88E5` (cobalt accent), `#F2F6FB` (primary text); pale-blue light theme available with `#EBF3FF` surface and `#0047AB` accent
- Typography: Epilogue (headers), Inter (body)
- Zero border radius, zero gradients, zero glows, zero shadows
- Depth via tonal layering only
- High-contrast typographic scale (2rem next to 0.6875rem)
- Tone: elite, severe, analytical, editorial — not consumer

Any UI change that softens the aesthetic, adds decorative elements, or dilutes the premium severity violates product identity.

## Auth Flow

Single Cognito-mediated path (provisioned by `infra/auth/cognito.yml`):

1. On first sign-up the Flutter client calls Amplify `signUp` against the **AWS Cognito** user pool. Cognito emails a 6-digit confirmation code through **Amazon SES**; the user enters it on the `EmailVerificationScreen` (`confirmSignUp`). An account that is not confirmed cannot sign in, so registration is gated by email verification.
2. After confirmation (or for a returning user) the client signs in via Amplify and obtains a Cognito ID token, which it posts to the backend (`POST /auth/cognito`, or `POST /auth/register_with_cognito` with the chosen team on first sign-up).
3. The backend verifies the token against Cognito, looks up or creates a row in the `users` table on RDS, and issues a short-lived local JWT pair (access + refresh) bound to the Cognito subject.
4. Subsequent API calls present the local JWT; `AuthSessionRepository` refreshes it automatically when needed.

The `COGNITO_USER_POOL_ID` / `COGNITO_APP_CLIENT_ID` values are read by both the backend (`backend/app/config.py`) and the Flutter client (`web/config.json` via `app_config.dart`). When they are blank, the app falls back to a local email/password path (`POST /auth/register` + `/auth/login`, bcrypt in RDS). Client-side validation (full name, email, password ≥ 8 with a letter and a digit) lives in `lib/features/auth/validation/auth_validators.dart`.

`AuthState` (ChangeNotifier) is the single source of truth for the current user across the Flutter app, and `AuthState.stage` drives the logged-out gate (login / register / verify).
