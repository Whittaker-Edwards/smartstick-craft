#!/usr/bin/env bash
# Builds the Craft apps in apps.json on this Mac, from the pinned upstream
# releases, using each app's own packaging/macos/package.sh.
#
#   scripts/build-mac-local.sh                 every app in apps.json
#   scripts/build-mac-local.sh wordcraft pdfcraft   just these
#   scripts/build-mac-local.sh --priority      the five must-haves first
#
# Output: out/mac/<App>-<version>-macos-universal.dmg plus out/mac/<App>-licences/
# These are LOCAL copies: ad-hoc signed, not notarized. They open on this Mac
# (right-click > Open the first time). Copies for the stick are signed later by
# scripts/package-stick.sh with the Developer ID.
#
# Needs: Xcode command line tools, rustup (https://rustup.rs), python3, git.
# Each app takes roughly 10-30 minutes the first time; later runs are faster.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${CRAFT_WORK:-$ROOT/work}"
OUT="$ROOT/out/mac"
say() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nStopped: %s\n' "$*" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "run this on a Mac."
command -v rustup >/dev/null || fail "install Rust first: curl https://sh.rustup.rs -sSf | sh"
command -v python3 >/dev/null || fail "install the Xcode command line tools: xcode-select --install"
rustup toolchain install stable --profile minimal >/dev/null
rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null

PRIORITY=0 WANT=()
for a in "$@"; do
  case "$a" in
    --priority) PRIORITY=1 ;;
    -*) fail "unknown option $a" ;;
    *) WANT+=("$a") ;;
  esac
done

# id name repo commit fonts, one app per line, in apps.json order
LIST="$(python3 -I - "$ROOT/apps.json" "$PRIORITY" "${WANT[@]+"${WANT[@]}"}" <<'PY'
import json, sys
apps = json.load(open(sys.argv[1]))["apps"]
prio, want = sys.argv[2] == "1", set(sys.argv[3:])
unknown = want - {a["id"] for a in apps}
if unknown:
    sys.exit(f"not in apps.json: {', '.join(sorted(unknown))}")
for a in apps:
    if (not want or a["id"] in want) and (not prio or a.get("priority")):
        print(a["id"], a["name"], a["repo"], a["commit"], a["craft_fonts"])
PY
)" || fail "couldn't read apps.json."

# Fetch one commit of a repo into a folder (shallow, reused between runs).
fetch() { # repo commit dir
  local repo="$1" commit="$2" dir="$3"
  if [[ ! -d "$dir/.git" ]]; then
    git init -q "$dir"
    git -C "$dir" remote add origin "https://github.com/$repo"
  fi
  if [[ "$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null)" != "$commit" ]]; then
    git -C "$dir" fetch -q --depth 1 origin "$commit"
    git -C "$dir" checkout -q --force FETCH_HEAD
  fi
}

mkdir -p "$WORK" "$OUT"
ok=() failed=()
while read -r id name repo commit fonts; do
  [[ -n "$id" ]] || continue
  say "$name ($repo @ ${commit:0:7})"
  src="$WORK/$id"
  if ! fetch "$repo" "$commit" "$src"; then failed+=("$name (download)"); continue; fi
  fetch storytold/craft-fonts "$fonts" "$WORK/craft-fonts-$fonts" || { failed+=("$name (fonts)"); continue; }
  i18n_dir=""
  if [[ -f "$src/craft-i18n.rev" ]]; then
    rev="$(tr -d '[:space:]' < "$src/craft-i18n.rev")"
    fetch storytold/craft-i18n "$rev" "$WORK/craft-i18n-$rev" || { failed+=("$name (translations)"); continue; }
    i18n_dir="$WORK/craft-i18n-$rev"
  fi
  rm -rf "$src/dist/release"
  if ! (cd "$src" && \
        CRAFT_FONTS_DIR="$WORK/craft-fonts-$fonts" CRAFT_FONTS_REQUIRED=1 \
        CRAFT_I18N_DIR="$i18n_dir" MACOS_SIGN_IDENTITY=- \
        packaging/macos/package.sh --arch universal) < /dev/null > "$WORK/$id.log" 2>&1; then
    failed+=("$name (build: see work/$id.log)"); continue
  fi
  dmg="$(ls "$src"/dist/release/*-macos-universal.dmg 2>/dev/null | grep -v -- -cli- | head -1 || true)"
  [[ -n "$dmg" ]] || { failed+=("$name (no DMG made: see work/$id.log)"); continue; }
  cp "$dmg" "$OUT/"
  lic="$OUT/$name-licences"; rm -rf "$lic"; mkdir -p "$lic"
  for f in LICENSE-MIT LICENSE-APACHE NOTICE ATTRIBUTION.md; do
    if [[ -f "$src/$f" ]]; then cp "$src/$f" "$lic/"; fi
  done
  find "$src/assets" "$WORK/craft-fonts-$fonts" -name 'OFL*.txt' -exec cp {} "$lic/" \; 2>/dev/null || true
  ok+=("$name")
done <<< "$LIST"

say "Done"
printf 'Built (%d): %s\n' "${#ok[@]}" "${ok[*]:-none}"
if [[ ${#failed[@]} -gt 0 ]]; then
  printf 'Not built (%d):\n' "${#failed[@]}"
  printf '  %s\n' "${failed[@]}"
fi
printf 'Your copies are in %s\n' "$OUT"
[[ ${#failed[@]} -eq 0 ]]
