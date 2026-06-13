<p align="center">
  <img src="design/logos/Umbraro_Name.png" alt="UmbraRo" width="200"/>
</p>

<p align="center">
  An AI tactical intelligence assistant for professional Romanian Superliga football coaches.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-web%20%2B%20Android-02569B?logo=flutter&logoColor=white" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Python-3.11%2B-3776AB?logo=python&logoColor=white" alt="Python"/>
  <img src="https://img.shields.io/badge/FastAPI-async-009688?logo=fastapi&logoColor=white" alt="FastAPI"/>
  <img src="https://img.shields.io/badge/AWS-Amplify%20%7C%20App%20Runner-FF9900?logo=amazonwebservices&logoColor=white" alt="AWS"/>
  <img src="https://img.shields.io/badge/License-MIT-3DA639" alt="MIT License"/>
</p>

<p align="center">
  <b>Live demo:</b> <a href="https://umbraro.d2j9yfctr6ipf6.amplifyapp.com">umbraro.d2j9yfctr6ipf6.amplifyapp.com</a>
</p>

<p align="center">
  <b>Thesis:</b> <a href="docs/UmbraRo-Thesis.pdf">Read the full bachelor thesis (PDF)</a>
</p>

---

## Table of Contents

- [Overview](#overview)
- [Thesis](#thesis)
- [Architecture](#architecture)
- [Features](#features)
- [Machine learning](#machine-learning)
- [Tech stack](#tech-stack)
- [Project structure](#project-structure)
- [Getting started (local)](#getting-started-local)
- [Deployment](#deployment)
- [Authentication](#authentication)
- [Design system](#design-system)
- [License](#license)
- [Author](#author)

## Overview

UmbraRo operationalises a Babes-Bolyai University bachelor thesis into a deployed product. It turns
predictive match analytics into prescriptive tactical guidance for coaching staff, answering not only
what is likely to happen but also what the staff should do to improve the outcome. The system runs as
a single cross-platform Flutter client backed by a Python FastAPI service, fully hosted on AWS.

The intelligence pipeline has four stages:

1. **Predict.** A calibrated CatBoost classifier estimates the binary home-win probability of a
   fixture (Home Win versus Not Home Win).
2. **Explain.** SHAP attributions surface the strongest positive drivers and the strongest negative
   risks behind that probability.
3. **Prescribe.** A constrained Monte Carlo optimiser searches thousands of realistic tactical
   permutations and returns a feasible tactical blueprint that raises the win probability, reported
   with the measured uplift.
4. **Select.** A separate supervised model predicts each club's likely starting eleven, combining
   per-90 player metrics, availability, an opponent-style profile, and a Hungarian assignment to fill
   the formation.

## Thesis

UmbraRo is the deployed artefact of the bachelor thesis *UmbraRo: From Match Forecasting to Tactical
Prescription and Lineup Selection for the Romanian Superliga*, submitted to the Faculty of Mathematics
and Computer Science, Babes-Bolyai University Cluj-Napoca, under the supervision of Asist. dr. Briciu
Anamaria.

The thesis develops the full predictive-to-prescriptive pipeline, the constrained Monte Carlo tactical
optimiser, and the player-level Starting XI predictor, and reports their evaluation on roughly 1,600
Romanian Superliga matches across five seasons (2020 to 2025).

- **Read the thesis:** [docs/UmbraRo-Thesis.pdf](docs/UmbraRo-Thesis.pdf)
- **Reproducible analysis:** the canonical numbers come from the notebooks in
  [`data/`](data/) (`TheNotebook.ipynb` for the team-level pipeline, `TheXIBook.ipynb` for the
  Starting XI layer).
- **Diagram sources:** the thesis figures (ER schema, sequence) are kept render-ready in
  [`design/diagrams/`](design/diagrams/).

## Architecture

<p align="center">
  <img src="docs/architecture.png" alt="UmbraRo system architecture" width="560"/>
</p>

- **Frontend.** A Flutter app with a feature-first layout under `lib/features/` and shared
  infrastructure in `lib/core/`. State management uses `ChangeNotifier` with a repository pattern. The
  web build is hosted on AWS Amplify, and a native Android target ships as a release APK. The runtime
  API URL and Cognito identifiers are read from `web/config.json` on web, so they can change without a
  rebuild. On mobile, the same values are compiled in at build time.
- **Backend.** A layered async FastAPI service (`api/v1/endpoints/` to `services/` to `data/`),
  packaged as a Docker image in Amazon ECR and served by AWS App Runner. The machine learning bundle
  loads once at startup through a lifespan hook.
- **Data and identity.** Persistent state (users, profiles, and chat) lives in AWS RDS PostgreSQL
  through async SQLAlchemy over asyncpg. Authentication is handled by AWS Cognito, which sends the email
  verification code through its managed mailer by default, with Amazon SES configurable as the sender. Avatars use presigned Amazon S3 uploads, and instant chat fans out
  over an API Gateway WebSocket backed by a DynamoDB connections table.

## Features

- **Win probability**, shown as the probability of a home win in the binary formulation.
- **Key drivers**, the top positive contributions and the top risks behind the current probability.
- **Tactical blueprint**, the optimiser's recommended target values for possession, shots, shots on
  target, and corners, together with the baseline probability, the optimised probability, and the
  uplift.
- **Starting eleven prediction** for each club, with availability and opponent context.
- **Standings** in an editorial, premium league table.
- **Command chat**, a direct, operational tactical interface rather than a social messenger.

## Machine learning

The model is trained on roughly 1,600 Romanian Superliga matches across five seasons, from 2020 to
2025. A central finding of the thesis is that predictive accuracy and prescriptive usefulness are
distinct criteria. Logistic Regression is in fact the most accurate engineered model, yet inside the
optimiser it concentrates almost its entire response in a single tactical lever and exaggerates the
effect of changing it. The production engine is therefore **calibrated CatBoost**: marginally less
accurate, but it spreads its sensitivity across the controllable variables and saturates rather than
extrapolating, giving the bounded, realistic responses a tactical optimiser needs. Logistic Regression
is kept as an interpretable forecasting benchmark. A one-feature Elo-only baseline is already as
accurate as any engineered model, so the added features contribute mainly through calibration,
explanation, and prescription rather than through raw predictive power.

**Supported inputs** (rolling five-match aggregates and pre-match context): Elo difference,
head-to-head record, rest days, possession, shots, shots on target, corners, goals scored, and goals
conceded.

**Prescriptive optimiser.** A constrained Monte Carlo search (N = 25,000) explores four controllable
levers (possession, shots, shots on target, and corners) while goals scored and conceded stay frozen.
It stays within historically plausible tactical ranges so that every recommendation is both
statistically useful and football-plausible.

**What the model does not use.** To keep every output grounded in the training data, UmbraRo does not
include biometrics, GPS or wearable tracking, player-level running load, expected-threat pipelines,
passing-network models, three-way home/draw/away classification, or any betting-odds framing.

## Tech stack

| Layer | Technology |
|---|---|
| Client | Flutter (Dart), `ChangeNotifier` + repository pattern, Amplify Auth |
| Backend | FastAPI (async Python 3.11+), SQLAlchemy over asyncpg |
| Machine learning | CatBoost, SHAP, constrained Monte Carlo optimisation |
| Identity | AWS Cognito (managed email by default, Amazon SES configurable), short-lived local JWT |
| Hosting | AWS Amplify Hosting (web), AWS App Runner and Amazon ECR (backend) |
| Data | AWS RDS PostgreSQL, Amazon S3, API Gateway WebSocket and DynamoDB |

## Project structure

```text
lib/            Flutter client (feature-first under features/, shared core/)
backend/        FastAPI service: api/v1/endpoints, services, data loaders, ml bundle
android/        Native Android target (release APK)
web/            Web entrypoint and runtime config.json
data/           Research dataset and notebooks (canonical thesis numbers)
design/         Design system, product specification, and diagram sources
docs/           Final bachelor thesis (PDF)
infra/          Infrastructure templates (Cognito, WebSocket, Lambdas)
scripts/        Developer and data-pipeline utilities
```

## Getting started (local)

### Backend

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate          # Windows, use source .venv/bin/activate on macOS or Linux
pip install -r requirements.txt
cp .env.example .env            # then set JWT_SECRET, DATABASE_URL, and the COGNITO_* values
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

The committed `.env.example` defaults `DATABASE_URL` to a local SQLite file, so the backend runs with
no external services. Point it at the PostgreSQL URL to mirror production.

### Flutter (web)

```bash
flutter pub get
flutter run -d chrome --web-port 8080 \
  --dart-define=APP_ENV=development \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

### Android (release APK)

Because `web/config.json` is read only on web, a mobile build must bake the production values in at
build time:

```bash
flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://<app-runner-host>/api/v1 \
  --dart-define=COGNITO_USER_POOL_ID=<pool-id> \
  --dart-define=COGNITO_APP_CLIENT_ID=<app-client-id>
```

### Tests

```bash
flutter test
flutter drive --target=integration_test/app_test.dart
```

## Deployment

- **Frontend.** Pushing to the `umbraro` branch triggers AWS Amplify Hosting, which builds the Flutter
  web app and serves it.
- **Backend.** A GitHub Actions workflow builds the Docker image, pushes it to Amazon ECR, and starts
  an AWS App Runner deployment.

## Authentication

Sign-up and sign-in go through AWS Cognito using Amplify. On first sign-up the client requests a
six-digit confirmation code, which Cognito delivers through its managed mailer by default (Amazon SES
can be configured as the sender). An account that has not
confirmed its email cannot sign in. After confirmation the client exchanges the Cognito ID token for a
short-lived local JWT bound to the Cognito subject, and subsequent API calls present that JWT. A local
email and password path remains available as a fallback when no Cognito pool is configured.

## Design system

The visual language is "The Stoic Analyst": a severe, editorial, data-minimalist aesthetic built for
elite coaching staff. It uses a deep navy surface (`#0A1929`), a cobalt accent (`#1E88E5`), and
off-white text (`#F2F6FB`), the Epilogue and Inter typefaces, sharp corners with zero border radius,
and depth through tonal layering rather than gradients, glows, or shadows.

## License

Released under the MIT License. See [LICENSE](LICENSE).

## Author

Built by Mihai Ciorascu as a bachelor thesis at Babes-Bolyai University, under the supervision of
Asist. dr. Briciu Anamaria.
