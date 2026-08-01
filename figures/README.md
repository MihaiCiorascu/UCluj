# Figures

Every image referenced by the thesis (`docs/UmbraRo-Thesis.pdf`) and by the root `README.md`. Filenames
match the `\includegraphics{figures/<name>}` calls in the thesis chapters exactly. Numbers below are
quoted from the final submitted thesis, not estimated.

## Team-level model (Chapter 3: predictive and prescriptive pipeline)

| File | Depicts |
|---|---|
| `tsne.png` | Two-dimensional t-SNE projection of the engineered pre-match feature space, coloured by the binary target. |
| `multi_seed_boxplot.png` | Holdout accuracy distribution across five independent random seeds for the three stochastic classifiers (Random Forest, CatBoost, MLP). |
| `confusion_matrix.png` | Confusion matrix of the calibrated CatBoost model on the 2024-2025 holdout season (133 correct Not Home Win, 62 correct Home Win, 124 misclassifications; accuracy 61.13%). |
| `reliability_diagram.png` | Reliability diagram for calibrated Logistic Regression and calibrated CatBoost on the holdout season. |
| `feature_importance_catboost.png` | Top-fifteen feature importances reported by the CatBoost model (gain). |
| `shap_summary.png` | SHAP summary plot for the raw CatBoost model on the 2024-2025 holdout. |
| `N_scaling.png` | Constrained Monte Carlo optimiser scaling on the UTA Arad vs. FCSB fixture: mean wall-clock per call and standard deviation of the returned best probability, across N from 1,000 to 100,000. |
| `retrospective_check.png` | Empirical home-win rate on the 2024-2025 holdout, split by whether the home team closely matched the optimiser's recommended blueprint (48.1% hit vs. 39.4% miss, a +8.7pp lift). |
| `sensitivity.png` | Tactical-lever sensitivity of the two calibrated models on the UTA Arad vs. FCSB fixture: each panel sweeps one controllable lever across its 5th-95th training percentile, holding the others fixed. |

## Supplementary (not in the final compiled thesis; kept for reference)

| File | Depicts |
|---|---|
| `importance_lr_pure_tactical.png` | Logistic Regression feature importance restricted to pure tactical features (no Elo / head-to-head / rest days). |
| `importance_rf_pure_tactical.png` | Random Forest feature importance under the same pure-tactical restriction. |
| `feature_importance_initial.png` | An earlier feature-importance ranking kept as a reference snapshot. |

## Starting XI (Chapter 4: player-level model)

| File | Depicts |
|---|---|
| `xi_validation.csv` | Per-fixture Starting XI validation data underlying Chapter 4's Jaccard@11 tables (rolling-origin one-fixture-out validation, league-wide mean 0.6227 across 428 held-out cells). |

Chapter 4 reports its results in tables only; it has no image figures of its own.

## Application screenshots (Chapter 5: the UmbraRo app)

| File | Depicts |
|---|---|
| `dashboard.png` | Dashboard: the user's club next fixture with its calibrated win probability and verdict tag, above the week's remaining fixtures. |
| `match_sheet_a.png`, `match_sheet_b.png` | Match Analysis sheet for an upcoming fixture (FCSB vs. Universitatea Cluj): (a) win chance, verdict, and key drivers, and (b) the optimal tactical plan and levers above the recommended XI. |
| `completed_stats.png`, `completed_lineup.png` | Completed-match view (Universitatea Cluj vs. Oțelul Galați): (a) the official statistics, and (b) the real starting eleven with substitution minutes and goal indicators. |
| `recommended_xi.png`, `player_sheet.png` | The lineup pitch: (a) the recommended starting eleven for an upcoming fixture, each chip showing the player's position, rating, and selection score, and (b) a per-player detail sheet with a within-position percentile radar, efficiency bars, an overall rating and selection score, and a physical-state panel. |
| `FIFA_lineup.png` | The FIFA-style pitch card view of a club's starting eleven. |
| `standings.png` | League standings: the Superliga table with the user's club lifted into a highlighted header card showing rank, points, goal difference, and record. |
| `chat.png` | Team communication: the club's general channel, with the group-creation control and the message composer. |

## System diagrams (Chapter 5: architecture)

| File | Depicts | Editable source |
|---|---|---|
| `use_case.png` | UML use-case diagram: one actor (the coaching and technical staff) and ten use cases. | (none; drawn directly for the thesis) |
| `db_schema.png` | Relational schema in AWS RDS PostgreSQL (`users`, `messages`, `chat_groups`); links are enforced in the application layer, since the database declares no foreign keys. | `design/diagrams/db_schema.dbml` |
| `auth_sequence.png` | Cognito-mediated sign-up and local-JWT exchange for a first-time user. | `design/diagrams/auth_sequence.puml` |
| `mi_sequence.png` | Request flow behind the Match Analysis sheet, from the cached dashboard-load computation to the on-tap fetch for an upcoming or completed match. | `design/diagrams/mi_sequence.puml` |

`../docs/architecture.png` (not in this folder) is the high-level three-tier architecture diagram embedded
at the top of the root `README.md`.
