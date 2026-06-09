"""Read-only XI-predictor smoke test: run the U Cluj recommended XI and print it,
so the recommended eleven can be compared before vs after the goalkeeper reweight.

    python backend/scripts/validate_xi.py
"""
from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # backend/
sys.path.insert(0, ROOT)
os.chdir(ROOT)  # so the relative model/data paths resolve as in the app

from services.xi_service import XiService  # noqa: E402


def _fields(p: dict):
    pos = (p.get("officialPosition") or p.get("position") or p.get("slot") or "?")
    name = (p.get("name") or p.get("playerName") or p.get("shortName") or "?")
    for k in ("predicted_score", "selScore", "sel", "score", "rating"):
        if p.get(k) is not None:
            return pos, name, k, p.get(k)
    return pos, name, "-", ""


def main() -> int:
    svc = XiService(model_path="ml/xi_model.pkl", data_dir="ml/data/drive_cache")
    out = svc.predict_xi(home_team_short="U Cluj", formation="auto")
    xi = out.get("startingXI", [])
    print("resolved home:", out.get("home_team_short"), "| formation:", out.get("formation"))
    print("startingXI count:", len(xi))
    for p in xi:
        pos, name, sk, sv = _fields(p)
        print(f"  {pos:6} {name:24} {sk}={sv}")
    gk = next((p for p in xi
               if (p.get("officialPosition") or p.get("position") or "").upper().startswith("G")), None)
    if gk:
        flat = {k: v for k, v in gk.items() if isinstance(v, (str, int, float))}
        print("GK record:", json.dumps(flat, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
