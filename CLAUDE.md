# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

**UmbraRo** — an AI tactical intelligence assistant for professional Romanian Superliga football coaches. The product operationalises an academic thesis: CatBoost win-probability prediction + constrained Monte Carlo optimisation for prescriptive tactical recommendations.

Before implementing anything, consult **`/AGENTS.md`** (product bible) and **`/design/backend-contract.md`** (supported feature scope). These are non-negotiable constraints, not suggestions.

## Architecture

Two-part system:

**Flutter frontend** (`lib/`) — mobile/web app. Feature-first structure under `lib/features/`; shared infrastructure in `lib/core/`. State management: `ChangeNotifier` + Repository pattern (no Riverpod/Bloc). Runtime API URL loaded from `/config.json` on web. Can run in legacy JWT mode or Firebase Auth mode (controlled by `USE_FIREBASE_AUTH` dart-define).

**FastAPI backend** (`backend/`) — async Python 3.11+. Layered: `api/v1/endpoints/` → `services/` → `data/` loaders. ML bundle (`ml/umbraro_catboost_bundle.joblib`) loaded once at startup via lifespan hook. SQLite with aiosqlite for auth/chat data. Supports dual auth: JWT email/password or Firebase ID tokens.

**Data flow:** `All_Data.csv` (~1600 Romanian Superliga matches, 2020–2025) → feature engineering → CatBoost prediction → Monte Carlo optimizer → tactical blueprint with probability uplift.

### Key design files

| File | Purpose |
|---|---|
| `/AGENTS.md` | Product identity, ML methodology, what must never be added |
| `/design/backend-contract.md` | Supported input features and API data scope |
| `/design/design-system.md` | "Stoic Analyst" visual language rules |
| `/design/product-spec.md` | Feature roadmap |

## Commands

### Backend

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate          # Windows
pip install -r requirements.txt
cp .env.example .env            # Then fill in JWT_SECRET, FIREBASE_PROJECT_ID
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

### Flutter (Web)

```bash
flutter pub get

# Legacy auth (no Firebase):
flutter run -d chrome --web-port 8080 \
  --dart-define=USE_FIREBASE_AUTH=false \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1

# Firebase auth:
flutter run -d chrome --web-port 8080 \
  --dart-define=USE_FIREBASE_AUTH=true \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

### Tests

```bash
flutter test                                                    # unit tests
flutter drive --target=integration_test/app_test.dart          # integration tests
```

### Deploy

```bash
firebase deploy --only hosting           # frontend
firebase deploy --only firestore:rules   # Firestore rules
```

## Configuration

**Backend `.env`:**

```
UMBRARO_ENV=development
JWT_SECRET=<change-me>
DATABASE_URL=sqlite+aiosqlite:///./umbraro.db
CORS_ORIGINS=http://localhost:3000,http://localhost:8080,http://127.0.0.1:8080
FIREBASE_PROJECT_ID=uhack26-8050e
FIREBASE_CREDENTIALS_PATH=backend/secrets/service-account.json
SPORTRADAR_API_KEY=<optional>
```

**Flutter dart-defines:** `USE_FIREBASE_AUTH`, `APP_ENV`, `API_BASE_URL`

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

## Auth Flows

Two parallel auth paths share the same JWT infrastructure:

1. **Legacy:** `POST /auth/login` → access + refresh tokens → stored via `TokenStore` (flutter_secure_storage) → auto-refreshed by `AuthSessionRepository`
2. **Firebase:** Firebase Auth → ID token → `POST /auth/firebase` → same JWT pair issued

`AuthState` (ChangeNotifier) is the single source of truth for the current user across the Flutter app.
