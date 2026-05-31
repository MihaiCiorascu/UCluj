# UmbraRo Thesis — Session Handoff

> **Read this first.** Self-contained orientation for any Claude session continuing work on the UmbraRo Bachelor thesis and mobile app. Designed so a successor session can reach productive state in **under 60 seconds** without re-deriving project history. Last updated 2026-05-19; consult `git log --oneline` for any commits after that date.

---

## §1 — Project identity

**UmbraRo** is an AI tactical-intelligence assistant for Romanian Superliga football coaches. It operationalises a Bachelor thesis (Babeș-Bolyai University, Computer Science / Informatică) into a deployed Flutter web + mobile application backed by a Python FastAPI service.

Three scientific pillars, all locked:
1. **Win-probability prediction** — calibrated CatBoost binary classifier (Home Win vs Not Home Win) on ~1,600 Superliga matches across the 2020–21 to 2024–25 seasons.
2. **Prescriptive tactical optimiser** — constrained Monte Carlo search (`N=25,000` samples) over six rolling-5 decision variables, returning tactical blueprints with measurable probability uplift.
3. **Starting XI predictor** — supervised logistic regression on per-90 KPIs + availability + opponent-style features, combined with Hungarian assignment to fill formation slots.

> **Canonical worktree (updated):** the source of truth is now
> `elated-swirles-549361`, not `strange-gauss-4b272c`. All thesis, notebook, and
> Cognito/AWS work was consolidated into elated-swirles and lives there as an
> UNCOMMITTED working tree. Read `START_HERE.md` first and do not run
> `git reset --hard` / `git checkout -- .`. The strange-gauss anchors below are
> retained only as historical reference.

| Anchor | Value |
|---|---|
| Repo path (CANONICAL) | `C:\Users\Mihai\OneDrive\Desktop\Facultate\Thesis\UHack\.claude\worktrees\elated-swirles-549361` |
| Active branch (CANONICAL) | `claude/elated-swirles-549361` |
| Source of truth | the uncommitted working tree (last commit `846a5bc` predates the work) |
| Prior research-lock worktree | `strange-gauss-4b272c` / `claude/strange-gauss-4b272c` (now outdated) |
| Research-lock tag | `research-lock-v1.0` at commit `c6a8b27` |
| Author | Ciorăscu Mihai |
| Supervisor | Asist. Dr. Briciu Anamaria |

---

## §2 — Repo layout

| Directory | Purpose | Status |
|---|---|---|
| `thesis/` | LaTeX manuscript files (chapter_3.tex, references.bib) — the worktree's chapter is the canonical Overleaf-paste source | ⚠️ paste-ready, but user must paste into Overleaf manually |
| `citations/` | Local PDF archive of every cited paper, with INDEX.md manifest. 39 ✅ PDFs + 1 🌐 web snapshot + 4 🔒 paywalled + 2 📚 books = 42 entries | ✅ complete |
| `figures/` | 14 image files + xi_validation.csv + README.md = 16 files; the user's Overleaf folder has the 15 user-content files (no README) | ✅ mirrored |
| `design/` | Meta-docs: research-inventory.md, scientific-validity.md, ref-verification.md, methodology-analysis.md, agents-spec.md | ✅ canonical |
| `backend/` | Python FastAPI + ML pipeline. **Research-locked at `c6a8b27`** — do not edit `build_catboost_bundle.py`, `optimizer_service.py`, `xi_predictor.py`, or `train_lineup_classifier_league.py`. Other backend files (api endpoints, services) are fair game for app-readiness work. | 🔒 research-locked |
| `lib/` | Flutter mobile/web app | 🟢 active development OK |
| `data/` | `TheNotebook.ipynb` (research notebook) + `TheNotebook.executed.ipynb` (May 17 12:27 snapshot — the canonical source for all reported numbers) + `All_Data.csv` (~1,600 fixtures × ~60 columns) | 🔒 research-locked |
| `scripts/` | `harvest_iter_q_metrics.py` (extracts metrics from executed notebook). Other utility scripts. | utility |
| `.claude/worktrees/.../` | This worktree itself (you're inside it) | — |

---

## §3 — Status: done vs open

### ✅ Done (DO NOT redo)
- Research pipeline locked at `research-lock-v1.0`. Every numerical claim in Ch3 traces to either the executed notebook or a committed JSON result file.
- `thesis/chapter_3.tex` — all five research-lock fixes applied (LR Brier 0.2256, MLP Brier 0.2276, LightGBM row dropped, wider-grid CatBoost row dropped, λ proximity-penalty sentences dropped), Lago-Peñas 2009→2010 swap applied, five internal-file references dropped (per BSc-thesis style).
- `thesis/references.bib` — 42 entries, deduplicated, BibTeX corrections applied (Naryanaswamy→Narayanaswamy, year/number/page corrections per ACM/JMLR canonical), Lago entry swapped to 2010 Apunts.
- Citation archive (`citations/`) — 39 PDFs downloaded from publisher OA / arXiv / author repos / Wayback / institutional libraries. **No Sci-Hub.** INDEX.md has per-entry status + DOI.
- Figure archive (`figures/`) — 14 images + xi_validation.csv mirroring Overleaf's 15-asset folder.
- Reference verification — every Ch2 §2.2.1 + §2.3 citation cross-checked against the source paper, including Piza Volio (read from the PDF the user provided), summarised in `design/ref-verification.md`.

### ⚠️ Open Overleaf paste-edits (the user must apply manually)

These 7 edits live in plan items #13 and #16 (in `C:\Users\Mihai\.claude\plans\got-it-let-me-humble-quilt.md`). The blocks are paste-ready LaTeX in that file.

1. **`main.tex` abstract paragraph 2** — change *"Eight supervised classifiers..."* enumeration: drop "LightGBM," → "Seven."
2. **`main.tex` abstract paragraph 3** — replace UTA Arad / CFR Cluj uplift numbers with the post-vectorisation versions (26.65→38.44, +11.8pp; 41.80→55.94, +14.1pp). Block A in plan #13.
3. **`chapters/chapter1_introduction.tex` §1.1** — consolidate ¶2-3 to remove three-times repetition of "transition from prediction to prescription". Block B in plan #13.
4. **`chapters/chapter1_introduction.tex` §1.5** — add explicit `\ref{chap:conclusions}` for Chapter 5. Block C in plan #13.
5. **`chapters/chapter2.tex` line 3** — delete the magenta `\textcolor{magenta}{...}` supervisor TODO comment. Block D in plan #13.
6. **`chapters/chapter2.tex` §2.3** — split the 600-word Monte Carlo paragraph into 3 (add brief Bayesian-Poisson definition). Block E in plan #13.
7. **`chapters/chapter3.tex`** — paste the worktree's `thesis/chapter_3.tex` wholesale. Replaces the user's pre-research-lock Overleaf version.
8. **`references.bib`** — paste the worktree's `thesis/references.bib` wholesale. 42 entries; Lago is the 2010 Apunts entry now.

### 🟡 Optional polish (strongly recommended but not blocking)

From `design/ref-verification.md`:
- Add a one-sentence Taspinar footnote (evaluation-protocol caveat — the 89.63% is numerically correct but their protocol differs from rolling-origin holdout)
- Confirm or drop Ruiz et al.'s −10.7 xGA differential (unverified in secondary sources; would need a page reference from the KDD 2017 paper)
- Confirm or drop Haruna's "75% benchmark" comparison clause
- Hedge or confirm Kozak's "Bayesian networks" classifier-family mention
- Add "2020" to the Blanco Chilean Premier League citation in §2.3

### ⏳ Pending / blocked

- **`ch3_pipeline.png`** — Ch3 §3.3 references `fig:method_pipeline` with `\includegraphics{figures/ch3_pipeline.png}` (commented out) and a `\fbox{}` placeholder. User to generate the pipeline diagram (Excalidraw / Figma / draw.io) and drop into `figures/`. Then uncomment the `\includegraphics` line and delete the `\fbox{}` block.
- **Chapter 4** (UmbraRo App — Implementation) and **Chapter 5** (Conclusions) — drafted; user may want a strict-reviewer pass similar to the one Ch3 received (see plan #12 for the reviewer template).
- **Rodrigues & Pinto 2022 league verification** — the `design/ref-verification.md` flagged a possible EPL vs La Liga mismatch. User to open ScienceDirect abstract (DOI 10.1016/j.procs.2022.08.057) and confirm; one-sentence edit in Ch2 §2.2.1 if it's La Liga.

### 🟢 Mobile app development — fair game

Touch `lib/`, `backend/api/`, `backend/services/` (except the research-locked four), `backend/app/`. Anything not flagged 🔒 above.

---

## §4 — Read these first (priority-ordered)

```
1. C:\Users\Mihai\OneDrive\Desktop\Facultate\Thesis\UHack\.claude\worktrees\strange-gauss-4b272c\HANDOFF.md      ← you are here
2. design/research-inventory.md                              ← canonical artefact list (§2 sections list every committed file with status)
3. design/scientific-validity.md §1.2.1, §3.5.1, §3.10       ← canonical numbers (Q.3 results + Iter-S XI + M-10 leakage)
4. design/ref-verification.md                                ← every cited paper verified against source
5. design/methodology-analysis.md                            ← higher-level critique of the three pillars
6. citations/INDEX.md                                        ← citation archive manifest with DOI + status per entry
7. figures/README.md                                         ← figure manifest with chapter cross-references
8. thesis/chapter_3.tex                                      ← the methodology chapter (~80 KB, ~650 lines)
9. thesis/references.bib                                     ← bibliography (42 entries)
10. C:\Users\Mihai\.claude\plans\got-it-let-me-humble-quilt.md ← full plan history (items #1–#22)
```

For mobile-app work, also read:
- `CLAUDE.md` (project instructions, top of repo)
- `AGENTS.md` (product bible — read before touching anything UI-/feature-/data-shape-related)
- `lib/` structure (feature-first under `lib/features/`, shared core in `lib/core/`)

---

## §5 — Facts sheet (the numbers an examiner might ask about)

### Dataset
- ~1,600 Romanian Superliga matches, 2020–21 through 2024–25 (5 seasons)
- Chronological split at **2024-07-01** — pre-split is train+val, post-split is the 2024-25 holdout test
- Binary target: **Home Win vs Not Home Win** (Home Win rate on holdout ≈ 41%)
- Feature set: 20 features (4 Elo + 14 rolling-5 tactical + 2 rest-day) per the production model

### Win-probability model results (from `TheNotebook.executed.ipynb` Cell 52 Q.3.a + Cell 55 Q.3.d + Cell 48 bootstrap)
| Model | Holdout accuracy | Calibrated Brier | ECE | Notes |
|---|---|---|---|---|
| Always-Home-Win baseline | 41.38% | — | — | trivial |
| Elo-only LR | 65.20% | 0.2241 | — | single-feature; ROC-AUC 0.6699 |
| **LR** (predictive winner) | **64.89%** | 0.2256 | 0.0529 | best raw accuracy |
| Random Forest | 64.45% | 0.2267 | — | competitive ensemble |
| **CatBoost** (production prescriptive) | 62.95% | **0.2329** | **0.0517** | smoother under tactical perturbation |
| XGBoost | 61.44% | 0.2371 | — | underperforms on this dataset |
| SVM (RBF) | 63.95% | — | — | single-seed |
| MLP | 63.07% | **0.2276** | **0.0312** | best ECE in Q.3.a |
| Naive Bayes | 61.76% | — | — | single-seed |

- **Confusion matrix (CatBoost holdout):** TN=143, FP=44, FN=71, TP=61 — recall on positive class 0.46, precision 0.58
- **3-fold rolling-CV (CatBoost):** accuracy 0.6254, log-loss 0.6650, Brier 0.2354
- **Bootstrap 95% CI for accuracy:** [0.5862, 0.6897]
- **F1-optimal threshold collapse:** at $t^\star=0.220$, validation F1=0.631 but holdout accuracy collapses to 41.4% (always-home-win baseline) — Lipton et al. 2014 mechanism

### Optimiser (constrained Monte Carlo)
- Production `N=25,000`, MC default (trust-constr opt-in available)
- Six decision variables: rolling-5 averages of Possession, Shots, SoT, Corners, Goals, Conceded
- Bounds: 5th–95th percentile of training distribution
- Hard constraint: SoT ≥ 0.2 × Shots
- N-scaling (from Fig 6): 14 ms @ N=1k → 111 ms @ N=100k; std of best probability 0.0073 @ N=1k → 0.0011 @ N=50k
- Example uplifts (5-seed mean): UTA Arad 26.65% → 38.44 ± 0.14% (+11.8 pp); CFR Cluj 41.80% → 55.94 ± 0.39% (+14.1 pp)
- Retrospective check (317 holdout fixtures): hit-blueprint 51.2%, not-hit 38.0%, +13.3 pp empirical lift

### Starting XI predictor (from `_iter_s_results.json` + `_m10_results.json`)
- Iter-S: 10-model comparison on 428 (team, fixture) cells across all 16 Romanian Superliga 2024-25 clubs
- **Per-team Jaccard (LR-full, rolling-origin CV):** Dinamo Bucureşti 0.7253 (top); FCSB 0.5443 (bottom); league mean **0.6227 ± 0.157**
- M-10 ablation:
  - LR-full: 0.6227 Jaccard, NDCG@11 0.811
  - LR-no-availability: 0.5195 (collapses to TopByMinutes baseline 0.520)
  - Heuristic Composite: 0.4476, NDCG@11 0.620
  - **Leakage delta: +10.32 pp** attributable to autoregressive availability features
- Methodological progression on U Cluj: 0.283 (composite no-avail) → 0.425 (with availability) → 0.482 (top-by-minutes) → 0.575 (supervised single-club) → 0.5802 (supervised league-wide)
- Position weights: 10 fine groups (GK, CB, FB, WB, DM, CM, AM, W, WF, ST), EB shrinkage k=3, tanh squash [0.25, 0.75], availability scalar α=0.6/β=0.4/γ=0.3, exponential decay half-life 30 days
- Position cross-check (Wyscout vs Sportradar coarse): 263 of 350 matched players agree = **75.14%**

---

## §6 — Decisions locked in — don't re-litigate

| Decision | Rationale | Locked in |
|---|---|---|
| Binary target (Home Win vs Not) | Scope reduction for prescriptive coupling | `build_catboost_bundle.py` |
| CatBoost = production prescriptive engine | Won Iter-Q.3 composite rank (rank-sum 20) | Audit §1.2 |
| LR = predictive benchmark | Highest holdout accuracy (64.89%) | Audit §1.2 |
| N = 25,000 samples | Std below 0.002 in absolute prob; sub-ms after vectorisation | §3.4 N-scaling |
| Calibration via Platt sigmoid + TimeSeriesSplit | Niculescu-Mizil & Caruana 2005 sigmoid distortion result | Audit §1.5 |
| Rolling-origin CV (time-aware) | Bergmeir & Benítez 2018 | Audit §1.6 |
| Hungarian assignment for XI selection | Kuhn 1955 | `xi_predictor.py` |
| Empirical-Bayes shrinkage k=3 for XI | Brown 2008 | `xi_predictor.py` |
| LR + class_weight='balanced' for XI supervised | Iter-S empirical winner by Jaccard@11 + NDCG@11 | `train_lineup_classifier_league.py` |
| Availability features kept in production | Past-availability is observable at inference; not strict leakage | M-10 ablation framing |
| **λ proximity penalty DROPPED from chapter** | Not implemented in `optimizer_service.py`; cleaner to drop than implement | Plan #11 → commit `c6a8b27` |
| **LightGBM DROPPED from Iter-Q.3 narrative** | Was in Q.2 but not Q.3 multi-seed comparison; cleaner to drop | Plan #11 → commit `c6a8b27` |
| **Lago-Peñas 2010 Apunts swaps 2009 J Sports Sciences** | 2009 paywalled, 2010 same scientific claim + locally available | Plan #18 → commit `cb38294` |
| **Robert & Casella 1998 draft Ch 1 covers 2004 2nd ed citation** | Same lineage; full 2004 textbook gated; Ch 1 covers the foundational claim | Plan #18 → commit `cb38294` |
| **No internal file paths in chapter prose** | BSc-thesis style; user's explicit request | Plan #19 → commit `95d09cc` |
| **No Sci-Hub for citation archive** | Legal risk; open-access only | Plan #15 |

---

## §7 — Recent commit history (most recent first)

```
f05570d  docs(figures): add xi_validation.csv (15th figures/ asset to match Overleaf)
bc9ae0b  docs(figures): consolidate thesis image assets into figures/ folder
95d09cc  docs(thesis): drop internal file/path references from chapter_3.tex per BSc-thesis style
8b585da  docs(citations): drop unused 📥 legend entry now that all 3 ScienceDirect PDFs are present
2bb951a  docs(citations): add 3 user-downloaded ScienceDirect PDFs; close manual-action gap
cb38294  docs(citations): +4 user-provided PDFs; swap Lago-Peñas 2009→2010 for local verifiability
a1e5674  docs(citations): local archive of all 42 referenced papers
a8d3851  docs(research): Piza Volio claims verified against PDF — paragraph mostly correct
3164642  docs(research): live verification of Ch2 §2.2.1 + §2.3 cited papers
c6a8b27  docs(research): research-lock-v1.0 — final Ch3 edits aligned with canonical notebook
87bffc2  docs(research): research asset inventory + lock manifest
abd439a  docs(thesis): apply 4 BibTeX corrections from live verification pass
e949c96  docs(thesis): merge Overleaf bib content into references.bib
b48da94  docs(thesis): Chapter 3 patches + complete BibTeX
8611613  docs: scientific-validity §3.10 + §3.5.1 + §8 — close M-10
a1d0687  research: M-10 expanded ablation — availability leakage + fresh Heuristic Composite
4c79005  research: Iter-S — XI scoring multi-model comparison
c6d6ac1  feat(optimizer): M-5+M-3 hybrid — seeded MC as default, trust-constr opt-in
34b488b  fix: deployment reconciliation (M-11) — chronological split + sigmoid+TimeSeriesSplit calibration
```

Tag: `research-lock-v1.0` at `c6a8b27`.

---

## §8 — DON'Ts (preventable mistakes)

1. **Don't re-execute `TheNotebook.ipynb`.** The `TheNotebook.executed.ipynb` snapshot from May 17 12:27 is the canonical source for every reported number. Re-executing would invalidate the lock and force re-derivation of Brier / ECE / confusion / rolling-CV / bootstrap / N-scaling / retrospective claims.
2. **Don't touch Ch3 numbers.** Every value is verified. If a future agent flags a "discrepancy," check `design/scientific-validity.md` §1.2.1 + the executed notebook first — there has been past confusion between holdout-single-seed vs rolling-CV-multi-seed, between calibrated vs uncalibrated Brier, and between J-iteration vs L-iteration data.
3. **Don't archive legacy backend scripts.** The 12 LEGACY scripts in `research-inventory.md §5` are explicitly deferred to the post-thesis backlog. Keeping them in place preserves git history and reproducibility traces.
4. **Don't use Sci-Hub** for additional citation PDFs. Open-access, arXiv, author preprints, Wayback, and institutional library are the only allowed sources.
5. **Don't re-add file paths or commit hashes** to the chapter prose (user explicitly removed these in `95d09cc`). Keep methodology abstract; cite library APIs (`CalibratedClassifierCV`, `TimeSeriesSplit`, `scipy.optimize.linear_sum_assignment`) but not project internal paths.
6. **Don't ship XI without availability features.** The M-10 ablation showed LR-no-availability collapses to the trivial top-by-minutes baseline. Production correctly uses LR-full. The leakage discussion is a methodological observation, not a deployment recommendation.
7. **Don't introduce 3-class classification.** Binary target is locked (scope reduction + prescriptive coupling argument). Adding draws as a separate class would require redesigning the optimiser objective.
8. **Don't touch `backend/scripts/build_catboost_bundle.py`, `backend/services/optimizer_service.py`, `backend/ml/xi_predictor.py`, or `backend/scripts/train_lineup_classifier_league.py`.** These four files are research-locked. Mobile-app and api-endpoint work is fair game everywhere else in `backend/`.

---

## §9 — How to update this handoff

When significant new work lands, append a dated section near the bottom of §3 ("Status: done vs open") with the change. Don't rewrite this file from scratch — successor sessions rely on its stability. If the project state diverges meaningfully (e.g., Ch4 polished, Ch5 reviewed, ch3_pipeline.png landed), update §3 + §7 (commit history) + §10 (last-touched) only.

---

## §10 — Last-touched user request (2026-05-19)

The previous turn confirmed `xi_validation.csv` is the 15th file in `figures/` (mirrors the Overleaf folder). Before that, the user had been:
- Receiving the strict-reviewer Ch1/Ch2 audit and the 5 paste-ready Overleaf blocks (R1–R5)
- Reviewing the Piza Volio re-verification (PDF read; 8/9 claims confirmed)
- Saving 4 user-provided PDFs into `citations/` (Hvattum, Haruna, Robert-Casella draft, Lago-Peñas 2010)
- Consolidating 14 figures + xi_validation.csv into `figures/`

**Pending decisions the next session should surface:**
- Has the user pasted any of the 7 Overleaf edits in §3 ⚠️? If not, walk through them as a single batched paste.
- Did the user verify Rodrigues & Pinto's league (EPL vs La Liga) via the ScienceDirect abstract?
- Should `ch3_pipeline.png` be generated now, or stays as `\fbox{}` placeholder?
- Does Ch4 (UmbraRo App) or Ch5 (Conclusions) need a strict-reviewer pass?
- Is the next focus thesis writing, mobile-app development, or both in parallel?

---

## §11 — Quick-start for a successor session

```
1. Open this file. Read §1–§3 (project + status). 30 seconds.
2. Skim the priority-ordered §4 reading list. Decide which docs to open based on the user's first message.
3. If the user asks about a number, look it up in §5 first (facts sheet). If not there, grep TheNotebook.executed.ipynb or the JSON results.
4. If the user asks "what's left to do," reference §3 (status) and §10 (last-touched).
5. If the user asks for a code/text edit, check §8 (DON'Ts) before touching anything.
6. If unsure about a decision, check §6 (locked-in decisions) — don't re-litigate.
```

The plan file at `C:\Users\Mihai\.claude\plans\got-it-let-me-humble-quilt.md` has the full 22-item history if any decision needs context. Items #11 onward are the most relevant for recent state.

---

*End of handoff. Successor session: you are now oriented. Proceed with the user's request.*
