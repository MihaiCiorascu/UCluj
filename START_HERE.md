# START HERE: this is the canonical worktree

> **If you are a new session continuing the UmbraRo thesis and app work, continue from HERE.**
> Do not work from `main`, `umbraro`, `strange-gauss-4b272c`, or `heuristic-diffie-741cd7`.
> Those are outdated. This worktree is the single source of truth.

## Canonical location

| Anchor | Value |
|---|---|
| Worktree path | `C:\Users\Mihai\OneDrive\Desktop\Facultate\Thesis\UHack\.claude\worktrees\elated-swirles-549361` |
| Branch | `claude/elated-swirles-549361` |
| Last commit | `846a5bc` (this commit predates all recent work, see the warning below) |

## CRITICAL: the source of truth is the UNCOMMITTED working tree

Every piece of recent work lives in this worktree as uncommitted working-tree
changes (around 44 changed entries: 31 modified or deleted tracked files plus
13 new untracked items). The last commit `846a5bc` does NOT contain any of it.

**Do not run `git reset --hard`, `git checkout -- .`, or `git stash drop`.**
Any of those would destroy the work. If you intend to commit, branch first and
commit the working tree as it stands. The user has not authorised a push to
`main`, so do not push to the default branch without asking.

## What is already done in this worktree

- **Thesis chapters re-styled to the author's voice** under `thesis/style_adapted/`
  (`chapter1_introduction.txt`, `chapter2.txt`, `chapter3.txt`, `chapter4.txt`,
  `chapter6_conclusions.txt`, `main.txt`): no em-dashes, no prose semicolons,
  British spelling, and the stale Abstract uplift numbers corrected to the
  canonical values.
- **`thesis/chapter_3.tex`** is the locked chapter with the audited numbers
  (Brier fixes, F1 paragraph, Table 3.5 refreshed). It is the newest version,
  strictly ahead of `strange-gauss`.
- **Notebooks re-executed and consolidated** in `data/`: `TheNotebook.ipynb`
  and `TheNotebook.executed.ipynb` (62 cells, vectorised optimiser at
  N = 25,000, F1 cell, N-sweep, retrospective, top-K, iteration labels stripped,
  no XGBoost `use_label_encoder` warning), plus `TheXIBook.ipynb` and its
  executed snapshot. Every Chapter 3 and Chapter 3.6 number traces to a cell
  output or a committed result file.
- **Backend migrated from Firebase to AWS Cognito + AWS Amplify / App Runner**
  (`backend/api/v1/endpoints/auth.py`, `backend/core/models.py`,
  `backend/services/cognito_id_token.py`, `backend/app/config.py`,
  research-locked `build_catboost_bundle.py` and `optimizer_service.py`). All
  Firebase / Crashlytics files were removed from `backend/` and `lib/`.
- **`asyncpg 0.31.0`** installed so the backend auth path imports cleanly.
- **Research result files** present: `backend/scripts/_iter_s_results.json`,
  `_m10_results.json`, `backend/ml/data/position_cross_check_league.csv`,
  `figures/xi_validation.csv`, plus `figures/` and `citations/`.
- **Cobalt theme preserved** in `experiments/app_colors_cobalt.dart`
  (see `experiments/README.md`). It is the one unique file that previously
  lived only in `heuristic-diffie`. It is preserved, not active, because the
  gold "Stoic Analyst" palette in `CLAUDE.md` remains canonical.

## Open items for the next session

- **Commit and push are still pending.** The user blocked a direct push to
  `main`. Ask before pushing. A feature branch plus PR is the safer path.
- **Chapter 6 "first published" claim.** `chapter6_conclusions.tex` still has
  "This layer is the first published starting-XI predictor for the Romanian
  Superliga." The user earlier flagged this kind of priority claim as unsuitable
  for a BSc thesis. Offer to soften or remove it.
- **Cobalt vs gold theme.** Decide whether to activate the preserved cobalt
  palette (drop-in swap, see `experiments/README.md`) or keep the gold spec.
- **Legacy notebook.** `data/TheNotebook_figures.ipynb` is the superseded
  May-19 variant and is safe to delete.

## Other worktrees (all outdated, do not use)

| Worktree | Branch | Why outdated |
|---|---|---|
| `strange-gauss-4b272c` | `claude/strange-gauss-4b272c` | Thesis behind (old Table 3.5, no `style_adapted/`), notebooks behind, no Cognito migration. Everything valuable was consolidated into this worktree. |
| `heuristic-diffie-741cd7` | `deploy-main` | Still on Firebase, has a `research/` reorg with an older notebook. Its only unique file (the cobalt theme) is now preserved here in `experiments/`. |
| `UHack` (main repo) | `umbraro` | Oldest (May 7). No thesis content. Nothing unique-and-valuable. |

## Deeper records

- Full session audit trail and every decision: the plan file at
  `C:\Users\Mihai\.claude\plans\delete-the-outdated-worktrees-peaceful-swan.md`.
- Research-lock facts sheet: `HANDOFF.md` in this worktree root.
- Run `orient.ps1` from this worktree to print the canonical banner and confirm
  you are in the right place.
