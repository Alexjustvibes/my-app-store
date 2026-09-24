#!/usr/bin/env python3
"""Verify (and, if needed, repair) Maintrix's integrity hashes so index.html
(Subresource Integrity) and sw.js (service-worker precache INTEGRITY) match the
actual bundle bytes that get served.

Why this exists
---------------
Maintrix's app.js / app.css are built by an *external* project (see
apps/maintrix/CLAUDE.md) that stamps SRI hashes into index.html and a SHA-256
map into sw.js. If those hashes don't match the bytes GitHub Pages serves, the
browser blocks app.js via SRI: the app never boots and never reaches Supabase.

Two ways that mismatch can happen:
  1. The build emits new bundles but forgets to regenerate the hashes.
  2. Line-ending conversion. Git stores these assets as LF (that's what Pages
     serves), but a checkout with core.autocrlf=true rewrites them to CRLF in the
     working tree — different bytes, different hash. .gitattributes now pins the
     assets to LF to prevent (2); this script's CRLF guard catches any regression.

Usage
-----
    python tools/stamp_maintrix.py            # repair index.html/sw.js to match bytes
    python tools/stamp_maintrix.py --check    # verify only; exit 1 if any hash is stale

Run the stamper (or at least --check) after copying new bundles in, and before
committing/deploying. It only ever edits index.html and sw.js — never the bundles.

IMPORTANT: it hashes the working-tree bytes, which are only the served bytes when
line endings are preserved. Keep .gitattributes in place. If a bundle contains
CRLF, the script refuses to run rather than stamp a hash that won't match the
server.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent.parent  # Maintrix is served from the site root
INDEX = APP_DIR / "index.html"
SW = APP_DIR / "sw.js"

# Assets index.html loads with Subresource Integrity (sha384, base64).
SRI_ASSETS = ("app.css", "app.js")
# Text bundles whose bytes must be LF to match the server; guarded against CRLF.
EOL_SENSITIVE = ("app.js", "app.css", "pow-worker.js", "manifest.json")

INTEGRITY_RE = re.compile(r"const INTEGRITY = (\{.*?\});", re.S)
CACHE_RE = re.compile(r"const CACHE = '([^']*)';")
VERSION_RE = re.compile(r"app\.js\?v=([0-9A-Za-z]+)")


class StampError(RuntimeError):
    pass


def sha384_b64(data: bytes) -> str:
    return "sha384-" + base64.b64encode(hashlib.sha384(data).digest()).decode()


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def key_to_path(key: str) -> Path:
    """Map an INTEGRITY key ('app.js?v=abc', 'fonts/x.woff2') to a file path."""
    return APP_DIR / key.split("?", 1)[0]


def sri_attr_re(asset: str) -> re.Pattern:
    """Match the integrity="sha384-..." attribute attached to a given asset ref
    in index.html, tolerant of other attributes (e.g. `defer`) in between."""
    return re.compile(
        r'((?:href|src)="' + re.escape(asset) + r'\?v=[0-9A-Za-z]+"[^>]*?integrity=")sha384-[^"]+(")'
    )


def read_bytes(path: Path) -> bytes:
    if not path.exists():
        raise StampError(f"missing asset: {path}")
    return path.read_bytes()


def guard_eol(path: Path, data: bytes) -> None:
    if b"\r\n" in data:
        raise StampError(
            f"{path.name} contains CRLF line endings — its hash will NOT match the LF "
            f"bytes GitHub Pages serves. Fix your checkout before stamping:\n"
            f"    git rm --cached apps/maintrix/{path.name} && git checkout -- apps/maintrix/{path.name}\n"
            f"and make sure .gitattributes (which pins these assets to LF) is present."
        )


def compute():
    """Return everything needed to verify/repair, computed from working-tree bytes.

    -> (new_index_bytes, new_sw_text, integrity_stale, cache_current, version)
    integrity_stale is the list of (name, ok) for SRI + INTEGRITY entries only;
    CACHE is intentionally NOT part of it (the build owns the cache name).
    """
    index_bytes = read_bytes(INDEX)
    sw_text = read_bytes(SW).decode("utf-8")

    m = VERSION_RE.search(index_bytes.decode("utf-8"))
    if not m:
        raise StampError("could not find an `app.js?v=<id>` version tag in index.html")
    version = m.group(1)

    m_int = INTEGRITY_RE.search(sw_text)
    if not m_int:
        raise StampError("could not find `const INTEGRITY = {...}` in sw.js")
    old_map = json.loads(m_int.group(1))

    m_cache = CACHE_RE.search(sw_text)
    if not m_cache:
        raise StampError("could not find `const CACHE = '...'` in sw.js")
    cache_current = m_cache.group(1)

    stale = []  # (name, ok)

    # 1) index.html SRI for app.css / app.js.
    index_text = index_bytes.decode("utf-8")
    for asset in SRI_ASSETS:
        data = read_bytes(APP_DIR / asset)
        guard_eol(APP_DIR / asset, data)
        want = sha384_b64(data)
        pat = sri_attr_re(asset)
        cur = pat.search(index_text)
        if not cur:
            raise StampError(f"could not find SRI integrity attribute for {asset} in index.html")
        had = re.search(r'integrity="(sha384-[^"]+)"', cur.group(0)).group(1)
        stale.append((f"index.html:{asset}", had == want))
        index_text = pat.sub(lambda mm: mm.group(1) + want + mm.group(2), index_text, count=1)
    new_index_bytes = index_text.encode("utf-8")

    # 2) sw.js INTEGRITY map (index.html hashed AFTER its SRI edit).
    new_map = {}
    for key in old_map:
        if key == "index.html":
            digest = sha256_hex(new_index_bytes)
        else:
            f = key_to_path(key)
            data = read_bytes(f)
            if f.name in EOL_SENSITIVE:
                guard_eol(f, data)
            digest = sha256_hex(data)
        new_map[key] = digest
        stale.append((f"sw.js:{key}", old_map[key] == digest))

    integrity_changed = any(not ok for _, ok in stale)

    # 3) Only touch CACHE when the integrity actually changed, so a correctly
    #    built input (nothing to fix) keeps the build's own cache name.
    if integrity_changed:
        content6 = hashlib.sha256(
            "\n".join(f"{k}:{v}" for k, v in sorted(new_map.items())).encode()
        ).hexdigest()[:6]
        base = re.sub(r"-[0-9a-f]{6}$", "", cache_current) or f"maintrix-{version}"
        new_cache = f"{base}-{content6}"
    else:
        new_cache = cache_current

    new_map_json = json.dumps(new_map, separators=(",", ":"))
    new_sw = CACHE_RE.sub(f"const CACHE = '{new_cache}';", sw_text, count=1)
    new_sw = INTEGRITY_RE.sub(lambda _m: f"const INTEGRITY = {new_map_json};", new_sw, count=1)

    return new_index_bytes, new_sw, stale, cache_current, new_cache, index_bytes, sw_text


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Verify/repair Maintrix SRI + SW integrity hashes.")
    ap.add_argument("--check", action="store_true",
                    help="verify only; write nothing; exit 1 if any hash is stale")
    args = ap.parse_args(argv)

    if not INDEX.exists() or not SW.exists():
        print(f"error: expected {INDEX} and {SW}", file=sys.stderr)
        return 2

    try:
        new_index, new_sw, stale, cache_cur, cache_new, old_index, old_sw = compute()
    except StampError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    bad = [name for name, ok in stale if not ok]

    if args.check:
        if bad:
            print("STALE - these hashes do not match the bundle bytes:")
            for name in bad:
                print(f"  [x] {name}")
            print("\nRun `python tools/stamp_maintrix.py` to fix.")
            return 1
        print(f"OK - all {len(stale)} SRI/INTEGRITY hashes match the bundles (CACHE {cache_cur}).")
        return 0

    changed = []
    if new_index != old_index:
        INDEX.write_bytes(new_index)
        changed.append("apps/maintrix/index.html")
    if new_sw != old_sw:
        SW.write_bytes(new_sw.encode("utf-8"))
        changed.append("apps/maintrix/sw.js")

    if not changed:
        print(f"Already consistent - nothing to change (CACHE {cache_cur}).")
        return 0

    print("Re-stamped:")
    for f in changed:
        print(f"  - {f}")
    for name in bad:
        print(f"  [fixed] {name}")
    if cache_new != cache_cur:
        print(f"CACHE {cache_cur} -> {cache_new}")
    print("\nRemember to bump the app's REGISTRY entry in the root index.html if this is a new build.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
