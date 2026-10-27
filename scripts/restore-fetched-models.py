#!/usr/bin/env python3
"""Points an app's build at a working copy of any model it downloads at build time.

Some Craft apps (PDFCraft's OCR) download model files during packaging, from the
URLs in their ATTRIBUTION.toml ([[fetched]] entries, each with a SHA-256). If a
URL has stopped working, this takes the identical file from the app's own
published release package for the same tag, checks its SHA-256, and points the
URL in ATTRIBUTION.toml at that local copy (file://). The app's build still
verifies the SHA-256 itself, so it can only ever use the exact same bytes.

Usage: restore-fetched-models.py <app source dir> <owner/repo> <tag> <app id> <cache dir>
"""
import hashlib
import io
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path


def fetched_entries(text: str) -> list:
    """The [[fetched]] tables of ATTRIBUTION.toml (simple key = "value" lines; no
    tomllib, so this runs on the python3 that comes with macOS too)."""
    entries = []
    for block in re.split(r"^\[\[", text, flags=re.M)[1:]:
        if not block.startswith("fetched]]"):
            continue
        entries.append(dict(re.findall(r'^(\w+) = "([^"]*)"', block, flags=re.M)))
    return entries


def reachable(url: str) -> bool:
    if url.startswith("file:"):  # restored on an earlier run
        return Path(urllib.request.url2pathname(urllib.parse.urlparse(url).path)).is_file()
    req = urllib.request.Request(url, method="HEAD")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status == 200
    except (urllib.error.URLError, TimeoutError):
        return False


def main() -> None:
    src, repo, tag, app_id, cache = sys.argv[1:6]
    src, cache = Path(src), Path(cache)
    toml_path = src / "ATTRIBUTION.toml"
    if not toml_path.is_file():
        return
    fetched = fetched_entries(toml_path.read_text(encoding="utf-8"))
    broken = [f for f in fetched if not reachable(f["url"])]
    if not broken:
        print(f"{app_id}: build-time downloads all reachable")
        return

    version = tag.lstrip("v")
    asset = f"{app_id}-{version}-windows-x64-portable.zip"
    url = f"https://github.com/{repo}/releases/download/{tag}/{asset}"
    print(f"{app_id}: {len(broken)} build-time download(s) no longer work; taking them from {url}")
    with urllib.request.urlopen(url, timeout=300) as r:
        package = zipfile.ZipFile(io.BytesIO(r.read()))
    names = {Path(n).name: n for n in package.namelist()}

    cache.mkdir(parents=True, exist_ok=True)
    text = toml_path.read_text(encoding="utf-8")
    for f in broken:
        member = names.get(f["file"])
        if member is None:
            sys.exit(f"{app_id}: {f['file']} isn't in {asset}")
        data = package.read(member)
        if hashlib.sha256(data).hexdigest() != f["sha256"]:
            sys.exit(f"{app_id}: {f['file']} in {asset} doesn't match ATTRIBUTION.toml's SHA-256")
        local = (cache / f["file"]).resolve()
        local.write_bytes(data)
        quoted = f'"{f["url"]}"'
        if text.count(quoted) != 1:
            sys.exit(f"{app_id}: can't find {f['url']} once in ATTRIBUTION.toml")
        text = text.replace(quoted, f'"{local.as_uri()}"')
        print(f"{app_id}: {f['file']} OK (SHA-256 matches), using {local}")
    toml_path.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
