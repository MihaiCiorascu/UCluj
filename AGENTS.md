# UmbraRo Agent Guide

This file is the main source of truth for product intent, backend limits, design constraints, screen behavior, and implementation decisions for UmbraRo.

---

## 1. Product Identity

UmbraRo is a premium AI tactical assistant for professional football coaches and technical staff.

It is **not**:
- a betting app
- a fan app
- a fantasy product
- a generic score-tracking app

UmbraRo is a serious football intelligence and decision-support system built on top of a machine learning backend. Its purpose is to support:
- prediction
- explanation
- prescription

The thesis framing is essential:
- predictive analytics answers **what is likely to happen**
- prescriptive analytics answers **what should be done**
- UmbraRo operationalizes this transition for coaching workflows

---

## 2. Thesis Context

Thesis title:

**UmbraRo: A Model-Based Tactical Blueprint System for Romanian Superliga Football Management**

The project has two connected parts:
1. the academic thesis
2. the commercial-grade Flutter mobile app

The app is the operational interface over the thesis methodology.

---

## 3. Data Scope and Supported Features

The backend is based on about 1,600 Romanian Superliga matches across five seasons, roughly 2020–2021 to 2024–2025.

The main supported pre-match feature families are:
- computed Elo difference / team strength context
- head-to-head context
- rest days
- 5-match rolling tactical aggregates:
  - possession
  - shots
  - shots on target
  - corners
  - goals scored
  - goals conceded

Do not invent unsupported features.

Unless explicitly added later, the product does **not** support:
- biometrics
- GPS tracking
- player wearable data
- player-level running load
- player heart-rate data
- xThreat pipelines
- passing network models
- event-camera tracking features
- any fake advanced metrics not grounded in the notebook

All outputs must stay tied to supported team-level tactical aggregates and contextual pre-match features.

---

## 4. Target Variable

The target is strictly:

**Binary classification: Home Win vs Not Home Win**

This is non-negotiable unless explicitly changed later.

Do not redesign the system around:
- home win / draw / away win
- 3-way probabilities
- betting odds framing

Whenever the app shows win probability by default, it refers to the probability of a **home win** in the binary formulation.

---

## 5. Analytical Evolution

The methodology evolved through these prescriptive stages:
1. rule-based averages
2. single-variable sweeps
3. manual tactical profiles
4. constrained Monte Carlo optimizer

The final accepted prescriptive engine is the **constrained Monte Carlo optimizer**.

Its purpose is to generate thousands of realistic tactical permutations and evaluate them with the production model while preserving football realism.

Important optimizer principles:
- use realistic bounds
- stay within historically plausible tactical ranges
- preserve football logic
- avoid unrealistic tactical boosts
- produce interpretable tactical targets
- recommendations must be actionable and credible

A tactical recommendation is valid only if it is both:
- statistically useful
- football-plausible

---

## 6. Model Positioning

Two models matter conceptually:

### Logistic Regression
Use as:
- interpretable predictive baseline
- benchmark for pure forecasting
- useful for explaining simple feature directionality

Do **not** use as the final production engine.

### CatBoost
CatBoost is the final production model for UmbraRo.

Why:
- better handles non-linear tactical interactions
- produces smoother behavior inside the tactical optimization loop
- avoids unrealistic linear extrapolations
- better captures tactical synergies
- more realistic for prescriptive analytics

Always defend CatBoost as the final production engine because UmbraRo is not just a predictor. It is a prescriptive tactical assistant.

---

## 7. Product Philosophy

UmbraRo should feel like:
- elite
- sharp
- severe
- analytical
- premium
- professional
- tactical
- editorial
- expensive

It must not feel:
- playful
- soft
- rounded
- gimmicky
- fan-oriented
- gambling-oriented
- consumer-casual

The product language should sound appropriate for technical staff and coaches.

Preferred domain language:
- match intelligence
- tactical blueprint
- key drivers
- probability uplift
- tactical diagnosis
- opposition weakness
- fixture analysis
- command channel
- season status
- squad load
- simulation
- structured pressure
- compact transition
- wide overload

---

## 8. Design System: “The Stoic Analyst”

This is the mandatory design language.

### Core visual identity
The style is:
- Brutalist Precision
- Modern Athletic Heritage
- Data Minimalism

### Core colors
Use these as brand anchors:
- background / surface: `#00132e`
- accent / primary: `#f2ca50`
- primary text / on-surface: `#d6e3ff`
- negative data: `#ffbfb2`
- positive data: subdued green

### Mandatory styling rules
- sharp corners only
- zero border radius on cards, buttons, panels, sheets, and modules
- no gradients
- no glow
- no drop shadows
- no glassmorphism
- no neumorphism
- no soft fintech SaaS styling
- depth only through tonal layering

### Surface logic
Use darker and lighter blue surfaces to separate sections.
Prefer tonal layering over borders.

### Typography
Typography should feel editorial and premium:
- oversized hero numbers
- condensed or assertive headlines
- all-caps section labels
- strong scale contrast
- lots of negative space
- left-aligned long-form text

### Spacing
Use strong negative space.
Avoid clutter.
Keep layouts breathable and structured.

### Icons
Icons should be:
- minimal
- sharp
- thin stroke
- serious
- non-cartoonish

---

## 9. Figma / Mockup Interpretation Rules

The Figma screens are the visual source of truth for the frontend.

Implementation priorities:
1. match layout hierarchy
2. match spacing
3. match tonal layering
4. match sharp-edged geometry
5. match typography scale
6. match information density and rhythm

Do not “improve” the design by making it softer.

Do not replace the visual language with generic mobile dashboard patterns.

Observed Figma language includes:
- oversized hero metrics like 74, 78.4, 88, +28, 46 PTS
- bold screen titles like LEAGUE STANDINGS, MANAGER CHAT, RANK #3
- dark navy background with gold accents
- sharp rectilinear cards
- compact bottom nav with all-caps labels
- minimal, tactical, executive-style information blocks
- large hero areas followed by structured data cards
- flat visual style without decorative effects

---

## 10. Core Screens

At minimum, the app supports these core screens.

### Dashboard / Home
Purpose:
- show next fixture
- show hero win probability
- show key drivers
- show recent and upcoming fixtures
- show quick status metrics

Typical elements:
- dominant win probability display
- fixture identity like VS FCSB
- competition + venue line
- key drivers section
- fixture analysis cards
- quick metrics like squad load and efficiency
- standings snapshot or season trend

### Standings
Purpose:
- display league table in an editorial premium format
- highlight the tracked club
- show summary metrics like points to top, efficiency, or contextual forecast

### Match Intelligence
Purpose:
- show baseline probability vs AI-optimized probability
- present tactical blueprint values
- explain why uplift happens

Typical elements:
- baseline probability
- optimized probability
- uplift
- tactical targets
- diagnosis summary
- actions like generate brief or run simulation

### Tactical Blueprint
Purpose:
- expose the optimizer’s recommended tactical targets
- present exact target values needed to improve probability

### Analytics
Purpose:
- explain feature influence
- show tactical form trends
- show active recommendations
- provide match-level interpretation

### Command Chat
Purpose:
- provide a tactical communication interface
- support prompts like:
  - explain win probability
  - generate tactical brief
  - summarize key drivers
  - explain uplift
  - summarize rest-day impact

This must feel like a command interface, not a social messenger.

### Team / Squad
Important constraint:
do not invent unsupported player metrics.
If a team screen exists, keep it visually aligned but honest about backend support.

---

## 11. UX Principles

Every screen should help answer at least one of these:
- What is our chance of winning?
- Why is that the current probability?
- What tactical conditions would improve it?
- What should the staff do next?

UX goals:
- instant scanability
- high trust
- premium seriousness
- low visual clutter
- executive readability
- tactical clarity

Avoid:
- playful onboarding fluff
- celebratory gimmicks
- casual sports-fan language
- fake complexity
- unexplained metrics

---

## 12. Flutter Implementation Direction

Use production-grade Flutter structure.

Preferred characteristics:
- reusable design tokens
- centralized theme
- feature-first structure
- strongly typed models
- clean separation of presentation and data concerns
- modular widgets
- scalable state management

A good target structure is:

```text
lib/
  app/
  core/
    constants/
    theme/
    routing/
    widgets/
    utils/
  data/
    models/
    repositories/
    services/
  features/
    dashboard/
    standings/
    match_intelligence/
    tactical_blueprint/
    analytics/
    chat/
    team/

Acceptable choices:
- Riverpod or Bloc
- Dio or http
- freezed / json_serializable if useful

Do not write tutorial-style toy code.

## 13. Backend Expectations

The Python backend should support product-facing outputs such as:
- baseline win probability
- optimized win probability
- uplift
- key drivers
- tactical blueprint targets
- tactical diagnosis summary
- fixture context

Do not expose fantasy outputs that the notebook cannot support.

Reasonable endpoint directions include:
- dashboard data
- fixture detail
- predict
- optimize
- explain
- standings
- chat query

But endpoint names may evolve later.

### Authentication and email verification

Auth is Cognito + Amplify + SES (provisioned by `infra/auth/cognito.yml`). Sign-up emails a 6-digit confirmation code; an unconfirmed account is blocked from sign-in (the client shows an `EmailVerificationScreen`). After confirmation the client exchanges the Cognito ID token for a local JWT via `POST /auth/cognito` or `POST /auth/register_with_cognito` (the latter carries the chosen club). Field validation is intentionally permissive but real: a full name (letters, spaces, diacritics, hyphens, apostrophes, no digits), a well-formed email, and a password of at least 8 characters with a letter and a digit. The club picker still feeds `register_with_cognito`. A local bcrypt path (`/auth/register` + `/auth/login`) stays as a fallback when no Cognito pool is configured.

## 14. Tactical Blueprint Contract

A tactical blueprint is not vague advice.  
It is the optimizer’s recommended target profile for the next match.

A valid tactical blueprint should include:
- baseline probability
- optimized probability
- uplift
- exact target tactical values
- concise tactical diagnosis
- optional rationale summary

Example supported target fields:
- target possession
- target shots
- target shots on target
- target corners
- target goals
- target conceded

Do not add unsupported tactical dimensions unless explicitly introduced later.

## 15. Explanation Layer

Explanations must stay grounded in supported features.

Valid explanation sources include:
- Elo difference
- head-to-head context
- rest days
- rolling possession
- rolling shots
- rolling shots on target
- rolling corners
- rolling goals scored
- rolling goals conceded

The explanation layer may present:
- top positive drivers
- top risks
- comparison vs opponent
- coach-friendly narrative summary

Do not invent unsupported reasons.

## 16. Chat / Command Tone

The command channel must sound:
- direct
- concise
- operational
- tactical
- professional

Not:
- chatty
- playful
- emoji-heavy
- consumer-like

The AI should respond like a tactical assistant for staff.

## 17. What Must Never Be Added Without Explicit Approval

Do not add any of the following unless explicitly approved:
- 3-way target design
- betting-style framing
- fake biometrics
- GPS tracking
- player wearable outputs
- unsupported advanced metrics
- rounded cards
- soft SaaS styling
- gradients
- glows
- drop shadows
- random design flourishes that conflict with the brand
- fake backend fields just to fill the UI

## 18. Default Working Mode for the Agent

Before implementing anything, check:
1. Is it supported by the thesis/backend?
2. Is it aligned with the Stoic Analyst design system?
3. Does it help a coach make a decision?

If the answer is no, do not invent it.

When implementing:
- prefer realism over decoration
- prefer sharp clarity over visual noise
- prefer product truth over generic best practices
- prefer reusable code over quick hacks
- prefer exact supported data over speculative analytics

## 19. Source Priority

When making implementation decisions, use this priority order:
1. explicit user instruction
2. Figma/mockup screens
3. this AGENTS.md file
4. project docs such as `docs/design-system.md`, `docs/product-spec.md`, `docs/backend-contract.md`
5. generic framework defaults

If something conflicts, do not guess. Surface the ambiguity.