# Thesis diagrams

Source files for three UmbraRo thesis figures. All are generated from the real system, so they stay
accurate and read as standard engineering artifacts rather than quick exports.

## Files

| File | Diagram | Render with |
|---|---|---|
| `db_schema.dbml` | Database ER diagram (`users`, `messages`, `chat_groups`) | [dbdiagram.io](https://dbdiagram.io) |
| `auth_sequence.puml` | Cognito sign-up and local-JWT exchange sequence | [plantuml.com](https://www.plantuml.com/plantuml) or the LaTeX `plantuml` package |
| `mi_sequence.puml` | Match Analysis request flow (dashboard-load compute and cache, then on-tap XI or match-details) | [plantuml.com](https://www.plantuml.com/plantuml) or the LaTeX `plantuml` package |

## How to render

- **DB schema.** Paste `db_schema.dbml` into dbdiagram.io and export the image. For the most
  authentic look, you can instead reverse-engineer the same ERD straight from the live RDS Postgres
  with DBeaver or pgAdmin (View Diagram / ERD); the result matches this file.
- **Sequences.** Paste `auth_sequence.puml` and `mi_sequence.puml` into plantuml.com (or embed them with
  the LaTeX `plantuml` package). Export **Light + transparent** (or PDF), not the dark canvas. The two
  share the same `skinparam` block so they look consistent in the thesis.

## Accuracy notes

- The schema lives in `backend/db/models.py`. The database declares no foreign keys, so the ERD shows
  `author_id` and `member_ids` as application-level links, and `team_name` is a tenant string rather
  than a `teams` table.
- The auth sequence matches the client (`lib/data/auth/auth_session_repository.dart`,
  `lib/core/services/auth_service.dart`) and the backend (`backend/api/v1/endpoints/auth.py`,
  `backend/services/auth_service.py`, `backend/services/cognito_id_token.py`).
- The Match Analysis flow (`mi_sequence.puml`) matches `backend/api/v1/endpoints/week.py` (the
  `/week-fixtures` compute plus the ~6 h `_PRED_CACHE`) and `backend/api/v1/endpoints/match_details.py`
  (the 24 h disk cache); the recommended XI is served by the `/xi` router.

## Tip

Keep one consistent visual style across all thesis figures (same font, stroke weight, and palette).
Mixed default styles across figures is the main giveaway that diagrams came from different quick tools.
