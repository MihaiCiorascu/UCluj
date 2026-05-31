# experiments/

Holding area for theme-related work that is not part of the active build.

This folder previously contained `app_colors_cobalt.dart`, a copy of the
"Iteration N glossy" cobalt blue palette. That file has been removed,
because it was byte-identical to the live theme at
`lib/core/theme/app_colors.dart` and therefore provided no additional
information while creating a maintenance hazard: a future edit to the
live palette would silently diverge from the duplicate.

## Current state of the live theme

- Active palette: cobalt blue, defined in `lib/core/theme/app_colors.dart`,
  introduced as the production theme in commit `a025264` (2026-05-16,
  "feat: Iteration L + N -- Superliga-wide XI predictor + UmbraRo glossy
  theme").
- Canonical design spec: `design/design-system.md`. The Stoic Analyst
  language (sharp edges, tonal depth, editorial typography, no shadows or
  gradients) is preserved verbatim; only the colour tokens moved from the
  earlier Trophy Gold to cobalt blue.

## Restoring the earlier "Trophy Gold" Stoic Analyst palette

The gold palette is no longer present anywhere in the active code. To
bring it back, recover the pre-2026-05-31 revision of
`design/design-system.md` via `git log --all -p -- design/design-system.md`,
write a new `lib/core/theme/app_colors.dart` from those Color Tokens, and
update `design/design-system.md` and `CLAUDE.md` to describe the gold
palette once more.
