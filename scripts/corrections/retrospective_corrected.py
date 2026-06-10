"""Corrected prescriptive retrospective (post-review).

The thesis retrospective (TheNotebook.ipynb cell 46, Fig 3.9 / Table 3.6) buckets
holdout fixtures by the dimension-normalised L2 distance between a team's actual
rolling averages and the optimiser's recommended blueprint, over SIX variables
that include Home_Goals_5 and Home_Conceded_5. Those two are recent scoring and
defensive FORM, not controllable tactics, so the "hit" cohort is partly just
in-form teams, and the reported +8.7pp gap (79 at 48.1% vs 236 at 39.4%) is
confounded and was never tested for significance.

This script reuses the EXACT notebook pipeline (cells 1, 3, 7, 20, 23, 43) so the
optimiser and model are identical to the thesis, then recomputes the retrospective
two ways and adds significance tests and a bootstrap confidence interval:
  (a) as reported: 6-variable distance (reproduces the +8.7pp);
  (b) corrected: distance over the 4 CONTROLLABLE levers only (possession, shots,
      shots on target, corners), excluding the two form variables.
It also reports the form confound and saves a corrected figure.

Read-only with respect to the notebook and data. Run:
    python scripts/corrections/retrospective_corrected.py
Outputs: figures_corrected/retrospective_corrected.png and
         scripts/corrections/retrospective_corrected.json
"""
from __future__ import annotations

import io
import json
import os
import contextlib
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[2]
DATA_DIR = REPO / "data"
NB = DATA_DIR / "TheNotebook.ipynb"
FIG_DIR = REPO / "figures_corrected"
OUT_JSON = REPO / "scripts" / "corrections" / "retrospective_corrected.json"

ALL_VARS = ["Home_Poss_5", "Home_Shots_5", "Home_SoT_5",
            "Home_Corners_5", "Home_Goals_5", "Home_Conceded_5"]
CONTROLLABLE = ["Home_Poss_5", "Home_Shots_5", "Home_SoT_5", "Home_Corners_5"]
N_RETRO = 5_000
SEED = 42


def _load_cell(src_idx: int) -> str:
    import nbformat
    nb = nbformat.read(NB, as_version=4)
    return "".join(nb.cells[src_idx].source)


def _build_namespace() -> dict:
    """Exec the real notebook setup cells into one namespace and return it."""
    FIG_DIR.mkdir(exist_ok=True)
    ns: dict = {"__name__": "__corr__"}
    # Run from data/ so the notebook's relative 'All_Data.csv' resolves.
    cwd = os.getcwd()
    os.chdir(DATA_DIR)
    try:
        for idx in (1, 3, 7, 20, 23, 43):
            src = _load_cell(idx)
            if idx == 1:
                # Redirect the hardcoded Downloads figure dir to our repo-local one.
                src = src.replace(
                    "r'C:/Users/Mihai/Downloads/Bachelor_Thesis_figures'",
                    repr(str(FIG_DIR)),
                )
            with contextlib.redirect_stdout(io.StringIO()):
                exec(compile(src, f"<cell {idx}>", "exec"), ns)
    finally:
        os.chdir(cwd)
    return ns


def _two_proportion(h_succ: int, h_n: int, m_succ: int, m_n: int):
    """Two-proportion z-test (home-win rate, hit vs miss). Returns (z, p)."""
    from scipy.stats import norm
    p_hit = h_succ / h_n
    p_miss = m_succ / m_n
    p_pool = (h_succ + m_succ) / (h_n + m_n)
    se = np.sqrt(p_pool * (1 - p_pool) * (1 / h_n + 1 / m_n))
    if se == 0:
        return 0.0, 1.0
    z = (p_hit - p_miss) / se
    p = 2 * (1 - norm.cdf(abs(z)))
    return float(z), float(p)


def _bootstrap_ci(hit_labels: np.ndarray, miss_labels: np.ndarray, n_boot=10000):
    """Percentile bootstrap 95% CI on the hit-minus-miss home-win-rate gap (pp)."""
    rng = np.random.default_rng(SEED)
    diffs = np.empty(n_boot)
    for i in range(n_boot):
        h = rng.choice(hit_labels, size=hit_labels.size, replace=True)
        m = rng.choice(miss_labels, size=miss_labels.size, replace=True)
        diffs[i] = h.mean() - m.mean()
    lo, hi = np.percentile(diffs, [2.5, 97.5]) * 100
    return float(lo), float(hi)


def _retrospective(ns: dict):
    """Run the optimiser once per holdout fixture, return distances over each var
    plus the home-win label, reproducing cell 46's loop exactly."""
    cat = ns["cat"]
    model_data = ns["model_data"]
    test_df = ns["test_df"]
    train_df = ns["train_df"]
    feature_cols = ns["feature_cols"]
    imputer = ns["imputer"]
    constrained_optimizer = ns["constrained_optimizer"]

    eligible = test_df.dropna(subset=ALL_VARS).copy()
    train_std = train_df[ALL_VARS].std().values  # per-variable normalisation (as in cell 46)

    rows = []  # (actual_vec, blueprint_vec, home_win)
    for _, row in eligible.iterrows():
        cutoff = row["match_date"]
        past = model_data[model_data["match_date"] < cutoff]
        if len(past) < 50:
            continue
        with contextlib.redirect_stdout(io.StringIO()):
            out = constrained_optimizer(
                row["home_team"], row["away_team"], cat, past, feature_cols,
                imputer, scaler=None, num_simulations=N_RETRO, random_state=SEED)
        if not isinstance(out, dict) or out.get("best_tactic") is None:
            continue
        bp = out["best_tactic"]
        actual = row[ALL_VARS].values.astype(float)
        blueprint = np.asarray([bp[v] for v in ALL_VARS], dtype=float)
        rows.append((actual, blueprint, int(row["home_score"] > row["away_score"]), row))
    return rows, train_std


def _evaluate(rows, train_std, var_names):
    idx = [ALL_VARS.index(v) for v in var_names]
    sub_std = train_std[idx]
    dists = np.array([
        float(np.linalg.norm((a[idx] - b[idx]) / sub_std)) for (a, b, _, _) in rows
    ])
    labels = np.array([hw for (_, _, hw, _) in rows])
    q25 = float(np.percentile(dists, 25))
    hit = dists < q25
    h_lab, m_lab = labels[hit], labels[~hit]
    h_rate, m_rate = float(h_lab.mean()), float(m_lab.mean())
    z, p = _two_proportion(int(h_lab.sum()), h_lab.size, int(m_lab.sum()), m_lab.size)
    lo, hi = _bootstrap_ci(h_lab, m_lab)
    return {
        "vars": var_names, "hit_n": int(hit.sum()), "miss_n": int((~hit).sum()),
        "hit_rate_pct": round(h_rate * 100, 1), "miss_rate_pct": round(m_rate * 100, 1),
        "diff_pp": round((h_rate - m_rate) * 100, 1), "z": round(z, 3),
        "p_value": round(p, 3), "ci95_pp": [round(lo, 1), round(hi, 1)],
        "significant_at_05": bool(p < 0.05), "hit_mask": hit,
    }


def _confound(rows, hit_mask):
    """Mean recent form (Goals_5, Conceded_5, net) in the hit vs miss cohorts."""
    g = np.array([a[ALL_VARS.index("Home_Goals_5")] for (a, _, _, _) in rows])
    c = np.array([a[ALL_VARS.index("Home_Conceded_5")] for (a, _, _, _) in rows])
    net = g - c
    return {
        "hit_net_form": round(float(net[hit_mask].mean()), 3),
        "miss_net_form": round(float(net[~hit_mask].mean()), 3),
        "hit_conceded": round(float(c[hit_mask].mean()), 3),
        "miss_conceded": round(float(c[~hit_mask].mean()), 3),
    }


def main() -> int:
    print("Building the notebook pipeline (cells 1, 3, 7, 20, 23, 43)...")
    ns = _build_namespace()
    print("Running the retrospective optimiser over the holdout fixtures...")
    rows, train_std = _retrospective(ns)
    print(f"Kept {len(rows)} fixtures.\n")

    reported = _evaluate(rows, train_std, ALL_VARS)
    corrected = _evaluate(rows, train_std, CONTROLLABLE)
    conf_reported = _confound(rows, reported["hit_mask"])
    conf_corrected = _confound(rows, corrected["hit_mask"])

    def _show(tag, r, conf):
        print(f"=== {tag} ({len(r['vars'])}-variable distance) ===")
        print(f"  Hit  n={r['hit_n']:3d}  {r['hit_rate_pct']:.1f}% home-win")
        print(f"  Miss n={r['miss_n']:3d}  {r['miss_rate_pct']:.1f}% home-win")
        print(f"  Difference: {r['diff_pp']:+.1f} pp   z={r['z']}  p={r['p_value']}  "
              f"95% CI [{r['ci95_pp'][0]}, {r['ci95_pp'][1]}] pp  "
              f"{'SIGNIFICANT' if r['significant_at_05'] else 'NOT significant'}")
        print(f"  Cohort net recent form (Goals-Conceded): hit {conf['hit_net_form']:+.3f} "
              f"vs miss {conf['miss_net_form']:+.3f}\n")

    _show("As reported", reported, conf_reported)
    _show("Corrected: controllables only", corrected, conf_corrected)

    # Corrected figure.
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(6.5, 4.2))
    bars = ax.bar(["Closest 25%\n(controllables)", "Remaining 75%"],
                  [corrected["hit_rate_pct"], corrected["miss_rate_pct"]],
                  color=["#1E88E5", "#7f7f7f"], width=0.55)
    for b, v in zip(bars, [corrected["hit_rate_pct"], corrected["miss_rate_pct"]]):
        ax.text(b.get_x() + b.get_width() / 2, v + 0.6, f"{v:.1f}%",
                ha="center", fontsize=11, fontweight="bold")
    ax.set_ylabel("Empirical home-win rate (%)")
    ax.set_ylim(0, max(corrected["hit_rate_pct"], corrected["miss_rate_pct"]) + 10)
    ci = corrected["ci95_pp"]
    ax.set_title("Retrospective association (controllables-only distance)\n"
                 f"gap {corrected['diff_pp']:+.1f} pp, not significant "
                 f"(p={corrected['p_value']}, 95% CI [{ci[0]}, {ci[1]}] pp)")
    ax.grid(axis="y", linestyle=":", alpha=0.5)
    plt.tight_layout()
    fig_path = FIG_DIR / "retrospective_corrected.png"
    plt.savefig(fig_path, dpi=200, bbox_inches="tight")
    print(f"Saved figure -> {fig_path}")

    for r in (reported, corrected):
        r.pop("hit_mask", None)
    result = {
        "n_fixtures": len(rows), "n_simulations": N_RETRO, "seed": SEED,
        "as_reported": reported, "corrected_controllables_only": corrected,
        "confound_reported": conf_reported, "confound_corrected": conf_corrected,
    }
    OUT_JSON.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"Saved numbers -> {OUT_JSON}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
