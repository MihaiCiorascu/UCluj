"""
Re-fetch all sixteen Romanian Superliga club crests from Wikipedia at
high resolution and normalise them to a 1024x1024 transparent square
canvas in ``assets/teams/<slug>.png``.

Why: the existing crests are 300-960 px sources that look pixelated when
displayed at any size beyond a tiny dropdown thumbnail (the user flagged
this on the register screen's team-picker).

How:
  1. For each team's (slug, Wikipedia-page-name) pair, hit Wikipedia's
     REST summary endpoint ``/api/rest_v1/page/summary/{page}``.
  2. Prefer ``originalimage.source`` (the full-resolution PNG); fall back
     to ``thumbnail.source`` (320 px) when originalimage is missing.
  3. Download the image bytes via urllib.
  4. Open in PIL, paste-centred onto a transparent 1024x1024 RGBA canvas
     (Lanczos resampling), save with ``optimize=True``.
  5. Print a friendly summary so the user can spot teams that fell back
     to a thumbnail or that need a manual replacement.

Re-run after a season's promotion/relegation cycle by editing the TEAMS
list below and running ``python scripts/fetch_team_crests.py`` from the
repo root.

Licensing note: each crest is uploaded to Wikipedia under a fair-use
rationale for use *as the team's identifying mark*. The UmbraRo app uses
them for the same purpose (identifying the team in the squad picker,
fixtures dashboard, etc.). Same posture as the previous low-resolution
versions already in the repo, replacing with higher-resolution versions
of the same logos does not change the licensing posture.
"""

from __future__ import annotations

import io
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "teams"
OUT_SIZE = 1024
DELAY_S = 1.5
UA = "UmbraRoBot/1.0 (research; thesis project; contact mihaiciorascu11@gmail.com)"

# (slug, primary Wikipedia page, optional fallback page)
TEAMS: list[tuple[str, str, str | None]] = [
    ("universitatea_cluj",    "FC_Universitatea_Cluj",     None),
    ("cfr_cluj",              "CFR_Cluj",                   None),
    ("fcsb",                  "FCSB",                       None),
    ("dinamo_bucuresti",      "FC_Dinamo_București",        "Dinamo_București"),
    ("rapid_bucuresti",       "FC_Rapid_București",         "Rapid_București"),
    ("botosani",              "FC_Botoșani",                None),
    ("otelul_galati",         "ASC_Oțelul_Galați",          "Oțelul_Galați"),
    ("hermannstadt",          "AFC_Hermannstadt",           None),
    ("petrolul_ploiesti",     "FC_Petrolul_Ploiești",       "Petrolul_Ploiești"),
    ("uta_arad",              "FC_UTA_Arad",                "UTA_Arad"),
    ("csikszereda",           "FK_Csíkszereda",             "FK_Csíkszereda_Miercurea_Ciuc"),
    ("arges_pitesti",         "FC_Argeș",                   "ACS_Campionii_FC_Argeș"),
    ("universitatea_craiova", "CS_Universitatea_Craiova",   "Universitatea_Craiova"),
    ("farul_constanta",       "FCV_Farul_Constanța",        "Farul_Constanța"),
    ("unirea_slobozia",       "AFC_Unirea_Slobozia",        "Unirea_Slobozia"),
    ("metaloglobus",          "CS_Metaloglobus_București",  "Metaloglobus_București"),
]


def _wiki_summary(page: str) -> dict | None:
    url = (
        "https://en.wikipedia.org/api/rest_v1/page/summary/"
        + urllib.parse.quote(page, safe="")
    )
    req = urllib.request.Request(
        url,
        headers={"User-Agent": UA, "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read())
    except Exception as exc:
        print(f"  ! /summary/{page}: {exc}")
        return None


_THUMB_RE = __import__("re").compile(r"/thumb/(.+?)/(\d+)px-([^/]+?)$")


def _maybe_upgrade_to_2048(url: str) -> str:
    """Wikipedia stores thumbnails at predictable URLs:
        https://upload.wikimedia.org/.../thumb/<h>/<HASH>/<filename>/<N>px-<filename>
    For SVG-sourced logos any N can be requested and Wikimedia renders on
    demand. Substitute N=2048 so we get a genuinely high-res raster instead
    of the 320 px default that the summary endpoint returns.
    """
    m = _THUMB_RE.search(url)
    if not m:
        return url
    prefix, _n, filename = m.group(1), m.group(2), m.group(3)
    return url[: m.start()] + f"/thumb/{prefix}/2048px-{filename}"


def _resolve_image_url(page: str, fallback: str | None) -> tuple[str | None, str]:
    """Return (image_url, source_label), upgraded to a 2048 px thumbnail
    whenever the URL pattern allows it."""
    for candidate in (page, fallback):
        if candidate is None:
            continue
        data = _wiki_summary(candidate)
        time.sleep(DELAY_S)
        if data is None:
            continue
        orig = data.get("originalimage", {}).get("source")
        if orig:
            return _maybe_upgrade_to_2048(orig), f"2048-upgrade via {candidate}"
        thumb = data.get("thumbnail", {}).get("source")
        if thumb:
            return _maybe_upgrade_to_2048(thumb), f"2048-upgrade (from thumb) via {candidate}"
    return None, "no Wikipedia image"


def _download_bytes(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def _download_with_size_fallback(url: str) -> tuple[bytes, str]:
    """Try the URL as-is; if the 2048px upgrade is rejected (the file is a
    raster PNG that Wikipedia won't enlarge), step down through 1024 / 800 /
    500 px, and finally fall back to the *raw source file* (no /thumb/
    segment, no /Npx- prefix) which always works."""
    candidates = [url]
    if "/2048px-" in url:
        for n in (1024, 800, 500):
            candidates.append(url.replace("/2048px-", f"/{n}px-"))
        # Raw source: strip /thumb and the trailing /Npx-... segment.
        m = _THUMB_RE.search(url)
        if m:
            prefix = m.group(1)   # like "8/8c/CFR_Cluj_logo.png"
            raw = url[: m.start()] + "/" + prefix
            candidates.append(raw)
    last_err: Exception | None = None
    for c in candidates:
        try:
            return _download_bytes(c), c
        except urllib.error.HTTPError as exc:
            last_err = exc
            if exc.code not in (400, 404):
                raise
            continue
    if last_err is not None:
        raise last_err
    raise RuntimeError("no candidates tried")


def _normalise_to_canvas(im: Image.Image, size: int) -> Image.Image:
    """Resize ``im`` keeping aspect, paste onto a transparent ``size`` x ``size``
    canvas. Result is always RGBA, exactly ``size`` x ``size``."""
    im = im.convert("RGBA")
    w, h = im.size
    scale = size / max(w, h)
    nw, nh = int(round(w * scale)), int(round(h * scale))
    resized = im.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(resized, ((size - nw) // 2, (size - nh) // 2), resized)
    return canvas


def _fallback_upscale(slug: str) -> tuple[bool, str]:
    """If Wikipedia gives us nothing, upscale the existing local PNG."""
    local = OUT_DIR / f"{slug}.png"
    if not local.exists():
        return False, "no local fallback"
    try:
        im = Image.open(local)
        canvas = _normalise_to_canvas(im, OUT_SIZE)
        canvas.save(local, optimize=True)
        return True, "PIL Lanczos upscale of existing local PNG"
    except Exception as exc:
        return False, f"local fallback failed: {exc}"


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Target dir: {OUT_DIR.relative_to(ROOT)}")
    print(f"Output size: {OUT_SIZE}x{OUT_SIZE} (transparent canvas)")
    print()

    n_ok = 0
    n_fallback = 0
    n_fail = 0
    results = []

    for slug, page, fallback_page in TEAMS:
        print(f"{slug:24s}  -> ", end="", flush=True)
        img_url, source = _resolve_image_url(page, fallback_page)

        # --- happy path: Wikipedia gave us a URL ---
        if img_url:
            try:
                raw, served_url = _download_with_size_fallback(img_url)
                im = Image.open(io.BytesIO(raw))
                canvas = _normalise_to_canvas(im, OUT_SIZE)
                out = OUT_DIR / f"{slug}.png"
                canvas.save(out, optimize=True)
                size_kb = os.path.getsize(out) // 1024
                note = source
                if "/2048px-" not in served_url and "/2048px-" in img_url:
                    note += " (downgraded to 800px)"
                print(f"OK  {note}  ({im.size[0]}x{im.size[1]} -> {OUT_SIZE}x{OUT_SIZE}, {size_kb} KB)")
                n_ok += 1
                results.append((slug, "ok", note, im.size, size_kb))
                continue
            except Exception as exc:
                print(f"FAIL downloading/processing: {exc}")

        # --- fallback: upscale existing local file ---
        ok, msg = _fallback_upscale(slug)
        if ok:
            print(f"WARN  fallback to {msg}")
            n_fallback += 1
            results.append((slug, "fallback", msg, None, None))
        else:
            print(f"FAIL  {msg}")
            n_fail += 1
            results.append((slug, "fail", msg, None, None))

    print()
    print(f"Summary: {n_ok} from Wikipedia, {n_fallback} fallback-upscaled, {n_fail} failed.")
    print()
    print("Per-team result:")
    for slug, status, detail, orig_size, kb in results:
        flag = {"ok": "[OK]  ", "fallback": "[WARN]", "fail": "[FAIL]"}[status]
        print(f"  {flag} {slug:24s} {detail}")
    return 0 if n_fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
