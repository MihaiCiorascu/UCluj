"""Leakage-free Starting-XI per-team table (post-review).

The thesis headline league Jaccard 0.6227 (Table 3.8 / Table 4.2 and the per-team
table) was produced with nine full-season static player columns that include
matches at and after each held-out fixture, so it is leakage-inflated. The
committed deployment bundle (xi_lineup_model_league.joblib) was retrained with
those columns recomputed strictly point-in-time and stores the leakage-free
result. This script emits the leaky-vs-clean comparison from the committed
artifacts (no retraining), and flags which teams fall below the top-by-minutes
reference once the leakage is removed.

Read-only. Run:
    python scripts/corrections/xi_leakage_free_table.py
Outputs: scripts/corrections/xi_leakage_free_table.{json,csv}
"""
from __future__ import annotations

import json
from pathlib import Path

import joblib

REPO = Path(__file__).resolve().parents[2]
BUNDLE = REPO / "backend" / "ml" / "xi_lineup_model_league.joblib"
LEAKY_JSON = REPO / "backend" / "scripts" / "_iter_s_results.json"
OUT_JSON = REPO / "scripts" / "corrections" / "xi_leakage_free_table.json"
OUT_CSV = REPO / "scripts" / "corrections" / "xi_leakage_free_table.csv"

TOP_BY_MINUTES = 0.520  # the trivial baseline reference (Table 3.9)


def _leaky_per_team():
    """Per-team and league-mean Jaccard for the leaky LogisticReg arm, plus the
    top-by-minutes baseline, from the committed _iter_s_results.json."""
    data = json.loads(LEAKY_JSON.read_text(encoding="utf-8"))
    # The file stores per-model cell records; find the LogisticReg arm.
    recs = None
    for key in ("per_model_records", "records", "results"):
        if isinstance(data.get(key), dict):
            for arm in ("LogisticReg", "LR", "LR-full", "logreg"):
                if arm in data[key]:
                    recs = data[key][arm]
                    break
        if recs is not None:
            break
    if recs is None and isinstance(data, dict):
        # fall back: any list-of-dicts with 'jaccard' and a team key
        for v in data.values():
            if isinstance(v, dict):
                for arm, rows in v.items():
                    if isinstance(rows, list) and rows and isinstance(rows[0], dict) \
                            and "jaccard" in rows[0]:
                        recs = rows
                        break
            if recs:
                break
    if recs is None:
        raise SystemExit("Could not locate LogisticReg cell records in the leaky JSON; "
                         "inspect its structure.")
    team_key = next(k for k in ("team_short", "team", "club") if k in recs[0])
    by_team: dict[str, list] = {}
    for r in recs:
        if r.get("jaccard") is None:
            continue
        by_team.setdefault(r[team_key], []).append(float(r["jaccard"]))
    per_team = {t: sum(v) / len(v) for t, v in by_team.items()}
    league = sum(x for v in by_team.values() for x in v) / sum(len(v) for v in by_team.values())
    return per_team, league


def _norm(name: str) -> str:
    return (name.replace("Universitatea Cluj", "U Cluj").strip())


def main() -> int:
    b = joblib.load(BUNDLE)
    clean = {_norm(k): v for k, v in b["per_team_mean_jaccard"].items()}
    clean_league = b["league_mean_jaccard"]
    clean_n = {_norm(k): v for k, v in b["per_team_n"].items()}

    leaky, leaky_league = _leaky_per_team()
    leaky = {_norm(k): v for k, v in leaky.items()}

    teams = sorted(set(clean) | set(leaky),
                   key=lambda t: clean.get(t, 0), reverse=True)
    rows = []
    for t in teams:
        lk = leaky.get(t)
        cl = clean.get(t)
        rows.append({
            "team": t, "n": clean_n.get(t),
            "leaky": round(lk, 4) if lk is not None else None,
            "leakage_free": round(cl, 4) if cl is not None else None,
            "delta": round(cl - lk, 4) if (lk is not None and cl is not None) else None,
            "below_top_by_minutes": (cl is not None and cl < TOP_BY_MINUTES),
        })

    below = [r["team"] for r in rows if r["below_top_by_minutes"]]
    below_leaky = [t for t in teams if leaky.get(t, 1) < TOP_BY_MINUTES]

    print(f"League mean Jaccard: leaky {leaky_league:.4f}  ->  leakage-free {clean_league:.4f}  "
          f"(inflation {(leaky_league - clean_league) * 100:+.2f} pp)")
    print(f"Top-by-minutes reference: {TOP_BY_MINUTES}\n")
    print(f"{'Team':22} {'n':>3}  {'leaky':>7}  {'clean':>7}  {'delta':>7}  below?")
    for r in rows:
        flag = "  <-- below 0.520" if r["below_top_by_minutes"] else ""
        print(f"{r['team']:22} {str(r['n']):>3}  {r['leaky']:>7.4f}  "
              f"{r['leakage_free']:>7.4f}  {r['delta']:>+7.4f}{flag}")
    print(f"\nTeams below the {TOP_BY_MINUTES} top-by-minutes baseline:")
    print(f"  leaky run:        {len(below_leaky)} -> {below_leaky}")
    print(f"  leakage-free run: {len(below)} -> {below}")
    print(f"  => the 'exceeds top-by-minutes on all sixteen' claim holds for "
          f"{16 - len(below)} of 16 teams once leakage is removed.")

    result = {
        "league_leaky": round(leaky_league, 4),
        "league_leakage_free": round(clean_league, 4),
        "league_std": round(b["league_std_jaccard"], 4),
        "league_n": b["league_n"],
        "inflation_pp": round((leaky_league - clean_league) * 100, 2),
        "top_by_minutes": TOP_BY_MINUTES,
        "teams_below_clean": below,
        "teams_below_leaky": below_leaky,
        "exceeds_on": 16 - len(below),
        "per_team": rows,
    }
    OUT_JSON.write_text(json.dumps(result, indent=2), encoding="utf-8")
    cols = ["team", "n", "leaky", "leakage_free", "delta", "below_top_by_minutes"]
    OUT_CSV.write_text(
        ",".join(cols) + "\n"
        + "\n".join(",".join(str(r[c]) for c in cols) for r in rows) + "\n",
        encoding="utf-8")
    print(f"\nSaved -> {OUT_JSON}\nSaved -> {OUT_CSV}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
