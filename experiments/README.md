# experiments/

Preserved work that is not part of the active build but should not be lost.

## app_colors_cobalt.dart

The "Iteration N glossy" cobalt-blue colour palette. It was the one unique
valuable file that lived only in the `heuristic-diffie-741cd7` worktree
(branch `deploy-main`) and not in this canonical worktree, so it was copied
here so that `elated-swirles-549361` genuinely contains every valuable file.

### Provenance

- Source worktree: `heuristic-diffie-741cd7`
- Source path: `lib/core/theme/app_colors.dart`
- Theme direction: replaces the U Cluj gold accent with an early-2000s
  sports-broadcast cobalt blue, plus glossy gradient surface fields.

### Why it is not active

The active theme in `lib/core/theme/app_colors.dart` keeps the gold
"Stoic Analyst" palette (`#00132e` surface, `#f2ca50` gold accent), which is
the non-negotiable design identity documented in `CLAUDE.md`. Activating the
cobalt palette would contradict that spec, so this file is preserved as a
reference rather than wired into the build. It also lives outside `lib/` on
purpose: it declares the same `AppColorTokens` / `AppColorsScope` classes as
the active theme, so keeping it inside `lib/` would cause a duplicate-class
analysis error.

### How to activate it (if desired)

The cobalt and gold versions share an identical 31-field `AppColorTokens` API
and the same `light` / `dark` static-const construction sites, and the glossy
widget infrastructure (`lib/core/theme/glossy_widgets.dart`, `app_theme.dart`,
`lib/core/widgets/app_scaffold.dart`) is already present and identical in this
worktree. Activation is therefore a drop-in file swap:

```
copy experiments/app_colors_cobalt.dart -> lib/core/theme/app_colors.dart
```

Before doing so, update `CLAUDE.md` so the documented palette matches the code,
otherwise the active theme and the design spec will disagree.
