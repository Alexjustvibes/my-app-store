#!/usr/bin/env python3
"""Re-stamp Maintrix integrity hashes so index.html (SRI) and sw.js (precache
INTEGRITY) always match the actual committed bundle bytes.

Why this exists
---------------
Maintrix's app.js / app.css are built by an *external* project (see
apps/maintrix/CLAUDE.md). That build is supposed to stamp the matching SRI
hashes into index.html and the SHA-256 map into sw.js — but it has repeatedly
shipped bundles whose hashes were NOT regenerated. When the SRI hash doesn't
match, the browser blocks app.js entirely: the app never boots and never talks
to Supabase. Builds 39 and 40 both went out dead for exactly this reason.

This script makes that failure impossible from this repo's side. After you copy
new bundles into apps/maintrix/, run:

    python tools/stamp_maintrix.py            # rewrite the hashes to match

or, in CI / a pre-deploy check:

    python tools/stamp_maintrix.py --check    # exit 1 if anything is stale

What it does
------------
* index.html : recompute the sha384 SRI for app.css and app.js and rewrite the
  two `integrity="sha384-..."` attributes. The `?v=<id>` version tag is READ
  from index.html and left untouched (app.js references assets by that id
  internally, so changing it would desync the bundle).
* sw.js      : recompute the sha256 of every asset listed in the INTEGRITY map
  (index.html's hash is taken over the freshly re-stamped bytes) and rewrite the
  map, then set CACHE to `maintrix-<id>-<content6>` where content6 is derived
  from all asset hashes — so the cache name changes iff any precached byte
  changes, forcing installed PWAs to re-precache, and stays identical when
  nothing changed (the script is idempotent).

It only ever edits index.html and sw.js. It never touches the bundles.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent.parent / "apps" / "maintrix"
INDEX = APP_DIR / "index.html"
SW = APP_DIR / "sw.js"

# Assets that index.html loads with Subresource Integrity (sha384, base64).
SRI_ASSETS = ("app.css", "app.js")

INTEGRITY_RE = re.compile(r"const INTEGRITY = (\{.*?\});", re.S)
CACHE_RE = re.compile(r"const CACHE = '([^']*)';")
VERSION_RE = re.compile(r"app\.js\?v=([0-9A-Za-z]+)")


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
    ext = re.escape(asset)  # 'app.css' / 'app.js'
    return re.compile(
        r'((?:href|src)="' + ext + r'\?v=[0-9A-Za-z]+"[^>]*?integrity=")sha384-[^"]+(")'
    )


class StampError(RuntimeError):
    pass


def compute(index_bytes: bytes, sw_text: str):
    """Return (new_index_bytes, new_sw_text, report) for the current on-disk
    bundles, without writing anything. `report` lists per-asset (name, ok)."""
    m = VERSION_RE.search(index_bytes.decode("utf-8"))
    if not m:
        raise StampError("could not find an `app.js?v=<id>` version tag in index.html")
    version = m.group(1)

    m_int = INTEGRITY_RE.search(sw_text)
    if not m_int:
        raise StampError("could not find `const INTEGRITY = {...}` in sw.js")
    old_map = json.loads(m_int.group(1))

    report = []

    # 1) Re-stamp index.html SRI for app.css / app.js.
    index_text = index_bytes.decode("utf-8")
    for asset in SRI_ASSETS:
        f = APP_DIR / asset
        if not f.exists():
            raise StampError(f"missing bundle: {f}")
        want = sha384_b64(f.read_bytes())
        pat = sri_attr_re(asset)
        cur = pat.search(index_text)
        if not cur:
            raise StampError(f"could not find SRI integrity attribute for {asset} in index.html")
        had = re.search(r'integrity="(sha384-[^"]+)"', cur.group(0)).group(1)
        report.append((f"index.html:{asset}", had == want))
        index_text = pat.sub(lambda mm: mm.group(1) + want + mm.group(2), index_text, count=1)
    new_index_bytes = index_text.encode("utf-8")

    # 2) Recompute the sw.js INTEGRITY map (index.html hashed AFTER its SRI edit).
    new_map = {}
    for key in old_map:  # preserve declared asset set & order
        if key == "index.html":
            digest = sha256_hex(new_index_bytes)
        else:
            f = key_to_path(key)
            if not f.exists():
                raise StampError(f"asset listed in sw.js INTEGRITY is missing: {f}")
            digest = sha256_hex(f.read_bytes())
        new_map[key] = digest
        report.append((f"sw.js:{key}", old_map[key] == digest))

    # 3) Content-addressed cache name: changes iff any precached byte changes.
    content6 = hashlib.sha256(
        "\n".join(f"{k}:{v}" for k, v in sorted(new_map.items())).encode()
    ).hexdigest()[:6]
    new_cache = f"maintrix-{version}-{content6}"
    m_cache = CACHE_RE.search(sw_text)
    if not m_cache:
        raise StampError("could not find `const CACHE = '...'` in sw.js")
    report.append(("sw.js:CACHE", m_cache.group(1) == new_cache))

    new_map_json = json.dumps(new_map, separators=(",", ":"))
    new_sw = CACHE_RE.sub(f"const CACHE = '{new_cache}';", sw_text, count=1)
    new_sw = INTEGRITY_RE.sub(lambda _m: f"const INTEGRITY = {new_map_json};", new_sw, count=1)

    return new_index_bytes, new_sw, report, new_cache


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Re-stamp Maintrix SRI/SW integrity hashes.")
    ap.add_argument(
        "--check",
        action="store_true",
        help="verify only; write nothing; exit 1 if any hash is stale",
    )
    args = ap.parse_args(argv)

    if not INDEX.exists() or not SW.exists():
        print(f"error: expected {INDEX} and {SW}", file=sys.stderr)
        return 2

    index_bytes = INDEX.read_bytes()
    # Byte-level I/O (no text-mode newline translation) so CRLF/LF survive untouched.
    sw_text = SW.read_bytes().decode("utf-8")

    try:
        new_index, new_sw, report, new_cache = compute(index_bytes, sw_text)
    except StampError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    stale = [name for name, ok in report if not ok]

    if args.check:
        if stale:
            print("STALE - these hashes do not match the bundle bytes:")
            for name in stale:
                print(f"  [x] {name}")
            print("\nRun `python tools/stamp_maintrix.py` to fix.")
            return 1
        print(f"OK - all {len(report)} hashes match the bundles (CACHE {new_cache}).")
        return 0

    changed = []
    if new_index != index_bytes:
        INDEX.write_bytes(new_index)
        changed.append("apps/maintrix/index.html")
    if new_sw != sw_text:
        SW.write_bytes(new_sw.encode("utf-8"))
        changed.append("apps/maintrix/sw.js")

    if not changed:
        print(f"Already consistent — nothing to change (CACHE {new_cache}).")
        return 0

    print("Re-stamped:")
    for f in changed:
        print(f"  - {f}")
    if stale:
        print("Corrected hashes:")
        for name in stale:
            print(f"  [fixed] {name}")
    print(f"CACHE = {new_cache}")
    print("\nRemember to bump the app's REGISTRY entry in the root index.html if this is a new build.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
