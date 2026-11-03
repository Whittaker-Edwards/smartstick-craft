#!/usr/bin/env bash
# Makes the Craft app folders for the Smart Stick, on a Mac that holds our
# signing setup (the build steps are public; the signing kit and keys aren't):
#
#   dist-stick/PC/.apps/WordCraft/
#     WordCraft.exe            Windows starter
#     app-windows/             upstream's Windows portable build, Authenticode-signed,
#                              plus craft-versions.json
#     manifest-windows.json(.minisig)
#     licences/                LICENSE-MIT, LICENSE-APACHE, NOTICE, ATTRIBUTION.md, OFL-*.txt
#   dist-stick/Mac/.apps/WordCraft/
#     WordCraft.app            Mac starter
#     app-mac/WordCraft.app    upstream's Mac build, Developer ID signed + notarised
#     app-mac/craft-versions.json
#     manifest-mac.json(.minisig)
#     licences/                (same files)
#
# Each platform's folder is its own update package. The Smart Stick Suite opens
# the starter, which copies the app to the computer, checks every file against
# the signed manifest and opens it (smartstick-desktop-kit stick-starter,
# per-platform manifests from kit #7). Order (kit signing/README.md): OS-sign,
# then the manifest, then the offline release key.
#
# craft-versions.json pins the app to the version we ship
# ({"apps":{"<id>":{"Pinned":"<version>"}}}). Newer upstream releases read it
# (craft-update's version-choice file, via CRAFT_VERSIONS_FILE, which the
# starter sets) and then never offer an update of their own or contact GitHub,
# so updates come only from the Smart Stick updater. Older releases have no
# update check and ignore it.
#
# Inputs, from the Build workflow (Windows, and Mac while the repo is public):
#   in/**/<id>-<version>-windows-x64-portable.zip
#   in/**/<id>-<version>-macos-universal.dmg  (+ licences/ next to it)
#       gh run download <run id> -R Whittaker-Edwards/smartstick-craft -D in
#       (or download the artifacts on github.com and unzip each into in/)
#   or Mac from scripts/build-mac-local.sh: out/mac/*.dmg + out/mac/<App>-licences/
#   (a local build in out/mac wins over a downloaded one)
#
# Needs: smartstick-desktop-kit next to this repo (with signing.env set up),
# rustup, cargo-xwin + LLVM (Windows starter), minisign, python3, the offline
# release drive (not with --test).
#
# Usage:
#   scripts/package-stick.sh                 every app in apps.json that has both builds
#   scripts/package-stick.sh wordcraft       just these
#   scripts/package-stick.sh --test [ids]    throwaway key, no OS signing, output in
#                                            dist-stick-test/ with TEST-ONLY.txt. Never ship it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$(cd "$ROOT/.." && pwd)/smartstick-desktop-kit"
cd "$ROOT"

say() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nStopped: %s\n' "$*" >&2; exit 1; }

TEST=0 WANT=()
for a in "$@"; do
  case "$a" in
    --test) TEST=1 ;;
    -*) fail "unknown option $a" ;;
    *) WANT+=("$a") ;;
  esac
done
[[ "$(uname)" == "Darwin" ]] || fail "run this on a Mac (it builds the Mac starter and signs the Mac apps)."
[[ -x "$KIT/signing/make-manifest.sh" ]] || fail "smartstick-desktop-kit must sit next to this repo."
grep -q -- "--per-platform" "$KIT/signing/make-manifest.sh" \
  || fail "update smartstick-desktop-kit (git pull): it needs kit #7 (per-platform manifests)."
grep -q "STICK_STARTER_ENV_FILES" "$KIT/crates/stick-starter/src/main.rs" \
  || fail "update smartstick-desktop-kit (git pull): its starter must set CRAFT_VERSIONS_FILE."
command -v minisign >/dev/null || fail "minisign isn't installed (brew install minisign)."
command -v cargo-xwin >/dev/null || fail "cargo-xwin isn't installed (cargo install --locked cargo-xwin)."
if [[ -z "${RC:-}" ]] && ! command -v llvm-rc >/dev/null && command -v brew >/dev/null; then
  export RC="$(brew --prefix llvm)/bin/llvm-rc"
fi

WORK="$(mktemp -d)"
cleanup() {
  [[ -n "${MOUNT:-}" ]] && hdiutil detach -quiet "$MOUNT" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

if [[ $TEST == 1 ]]; then
  OUT="$ROOT/dist-stick-test"
  say "TEST build: throwaway key, no OS signing"
  minisign -G -W -p "$WORK/test.pub" -s "$WORK/test.key" >/dev/null
  PUBKEYS="$(tail -n 1 "$WORK/test.pub")"
else
  OUT="$ROOT/dist-stick"
  # shellcheck source=/dev/null
  source "$KIT/signing/lib.sh"
  load_signing_env
  [[ -n "${RELEASE_PUBKEYS:-}" ]] || fail "RELEASE_PUBKEYS isn't set (smartstick-desktop-kit/signing/signing.env.example)."
  PUBKEYS="$RELEASE_PUBKEYS"
fi
[[ ! -e "$OUT" ]] || fail "$OUT already exists. Move it away first."

# id name repo commit version, one app per line
LIST="$(python3 -I - "$ROOT/apps.json" "${WANT[@]+"${WANT[@]}"}" <<'PY'
import json, sys
apps = json.load(open(sys.argv[1]))["apps"]
want = set(sys.argv[2:])
unknown = want - {a["id"] for a in apps}
if unknown:
    sys.exit(f"not in apps.json: {', '.join(sorted(unknown))}")
for a in apps:
    if not want or a["id"] in want:
        print(a["id"], a["name"], a["repo"], a["commit"], a["tag"].lstrip("v"))
PY
)" || fail "couldn't read apps.json."

# Upstream source for the icons and Mac entitlements (build-mac-local.sh
# leaves it in work/; otherwise fetch just that commit).
source_of() { # id repo commit
  local dir="$ROOT/work/$1"
  if [[ "$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null)" != "$3" ]]; then
    dir="$WORK/src-$1"
    git init -q "$dir"
    git -C "$dir" fetch -q --depth 1 "https://github.com/$2" "$3"
    git -C "$dir" checkout -q FETCH_HEAD
  fi
  printf '%s\n' "$dir"
}

# A starter with the app's id, name and the trusted keys baked in.
build_starter() { # id name icon target [cargo subcommand...]
  local id="$1" name="$2" icon="$3" target="$4"; shift 4
  # The starter points CRAFT_VERSIONS_FILE at the checked copy of the pin file.
  local half=app-mac
  [[ "$target" != *windows* ]] || half=app-windows
  local vars=(STICK_STARTER_APP_ID="$id" STICK_STARTER_APP_NAME="$name"
    STICK_STARTER_PUBKEYS="$PUBKEYS" STICK_STARTER_CACHE_NS="Smart Stick"
    STICK_STARTER_ENV_FILES="CRAFT_VERSIONS_FILE=$half/craft-versions.json")
  [[ -z "$icon" ]] || vars+=(STICK_STARTER_ICON="$icon")
  (cd "$KIT" && env -u STICK_STARTER_ICON "${vars[@]}" \
    "$@" build --release --locked -p stick-starter --target "$target" >&2)
  printf '%s\n' "$KIT/target/$target/release/stick-starter"
}

sign_manifest() { # folder name
  local folder="$1" name="$2"
  if [[ $TEST == 1 ]]; then
    minisign -S -s "$WORK/test.key" -m "$folder/$name" >/dev/null
  else
    "$KIT/signing/sign-release.sh" "$folder/$name" --root "$folder"
  fi
}

# Pins the app to the version we ship, so it never offers its own update.
craft_versions() { # id version
  python3 -I -c 'import json, sys; print(json.dumps({"apps": {sys.argv[1]: {"Pinned": sys.argv[2]}}}, indent=2))' "$1" "$2"
}

rustup target add x86_64-pc-windows-msvc aarch64-apple-darwin x86_64-apple-darwin >/dev/null
done_apps=() skipped=()
while read -r id name repo commit version; do
  [[ -n "$id" ]] || continue
  dmg="$(ls "$ROOT"/out/mac/"$id"-"$version"-macos-universal.dmg 2>/dev/null | head -1 || true)"
  [[ -n "$dmg" ]] || dmg="$(find "$ROOT/in" -name "$id-$version-macos-universal.dmg" 2>/dev/null | head -1 || true)"
  zip="$(find "$ROOT/in" -name "$id-$version-windows-x64-portable.zip" 2>/dev/null | head -1 || true)"
  if [[ -z "$dmg" || -z "$zip" ]]; then
    missing=""
    [[ -n "$dmg" ]] || missing="Mac build ($id-$version-macos-universal.dmg in in/ or out/mac)"
    [[ -n "$zip" ]] || missing="${missing:+$missing and }Windows build (in/)"
    skipped+=("$name: no $missing")
    continue
  fi
  say "$name $version"
  src="$(source_of "$id" "$repo" "$commit")"
  pc="$OUT/PC/.apps/$name" mac="$OUT/Mac/.apps/$name"
  mkdir -p "$pc/app-windows" "$pc/licences" "$mac/app-mac" "$mac/licences"

  # Licences, in both packages: the files upstream ships with the app, plus
  # its font licences.
  for f in LICENSE-MIT LICENSE-APACHE NOTICE ATTRIBUTION.md; do
    from="$src/$f"
    # ATTRIBUTION.md is at the root in most apps, in assets/ in some (LightCraft).
    [[ -f "$from" || "$f" != ATTRIBUTION.md ]] || from="$src/assets/$f"
    [[ -f "$from" ]] || fail "$name: upstream $f is missing; the licence needs it on the stick."
    cp "$from" "$pc/licences/"
  done
  for lic in "$ROOT/out/mac/$name-licences" "$(dirname "$dmg")/licences"; do
    if [[ -d "$lic" ]]; then find "$lic" -name 'OFL*.txt' -exec cp {} "$pc/licences/" \;; fi
  done
  cp "$pc/licences/"* "$mac/licences/"

  # Windows half: upstream's portable zip, every program Authenticode-signed.
  unzip -q "$zip" -d "$WORK/win-$id"
  inner="$(find "$WORK/win-$id" -name "$id.exe" -print -quit)"
  [[ -n "$inner" ]] || fail "$name: $id.exe isn't in $(basename "$zip")."
  ditto "$(dirname "$inner")" "$pc/app-windows"
  craft_versions "$id" "$version" > "$pc/app-windows/craft-versions.json"
  ico="$(find "$src/assets" -name "$id.ico" -print -quit 2>/dev/null || true)"
  starter="$(build_starter "$id" "$name" "$ico" x86_64-pc-windows-msvc cargo xwin).exe"
  cp "$starter" "$pc/$name.exe"
  if [[ $TEST == 0 ]]; then
    progs=()
    while IFS= read -r -d '' p; do progs+=("$p"); done \
      < <(find "$pc/app-windows" -type f \( -iname '*.exe' -o -iname '*.dll' \) -print0)
    "$KIT/signing/sign-windows.sh" "${progs[@]}" "$pc/$name.exe"
  fi
  "$KIT/signing/make-manifest.sh" --app-id "$id" --version "$version" \
    --platform windows-x86_64 --files app-windows --per-platform \
    --entry "app-windows/$id.exe" "$pc"
  sign_manifest "$pc" manifest-windows.json

  # Mac half: the app from upstream's DMG, re-signed with our Developer ID.
  MOUNT="$WORK/mnt-$id"
  mkdir -p "$MOUNT"
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$dmg"
  app="$(find "$MOUNT" -maxdepth 1 -name '*.app' -print -quit)"
  [[ -n "$app" ]] || fail "$name: no .app in $(basename "$dmg")."
  appname="$(basename "$app")"
  ditto "$app" "$mac/app-mac/$appname"
  # Some DMGs (PhotoCraft) mark every file with Finder info; codesign refuses
  # to sign while such extended attributes are there.
  xattr -cr "$mac/app-mac/$appname"
  craft_versions "$id" "$version" > "$mac/app-mac/craft-versions.json"
  hdiutil detach -quiet "$MOUNT"; MOUNT=""
  icns="$(find "$mac/app-mac/$appname/Contents/Resources" -name '*.icns' -print -quit)"
  for t in aarch64-apple-darwin x86_64-apple-darwin; do build_starter "$id" "$name" "" "$t" cargo >/dev/null; done
  lipo -create -output "$WORK/stick-starter-$id" \
    "$KIT/target/aarch64-apple-darwin/release/stick-starter" \
    "$KIT/target/x86_64-apple-darwin/release/stick-starter"
  # Drop the linker's ad-hoc signature so sign-mac.sh always signs the starter
  # with the Developer ID (it skips an .app that already verifies).
  codesign --remove-signature "$WORK/stick-starter-$id"
  "$KIT/crates/stick-starter/make-mac-app.sh" --name "$name" \
    --bundle-id "com.smartstick.craft.$id.starter" --version "$version" \
    --binary "$WORK/stick-starter-$id" ${icns:+--icon "$icns"} "$mac"
  if [[ $TEST == 0 ]]; then
    # Upstream's own hardened-runtime entitlements. Passing them also makes
    # sign-mac.sh replace the local (ad-hoc) signature with the Developer ID.
    ent="$src/packaging/macos/entitlements.plist"
    [[ -f "$ent" ]] || fail "$name: upstream packaging/macos/entitlements.plist is missing."
    "$KIT/signing/sign-mac.sh" "$mac/app-mac/$appname" --entitlements "$ent"
    "$KIT/signing/sign-mac.sh" "$mac/$name.app"
  else
    codesign --force --deep --sign - "$mac/app-mac/$appname" "$mac/$name.app"
  fi
  exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$mac/app-mac/$appname/Contents/Info.plist")"
  "$KIT/signing/make-manifest.sh" --app-id "$id" --version "$version" \
    --platform macos-universal --files app-mac --per-platform \
    --entry "app-mac/$appname/Contents/MacOS/$exe" "$mac"
  sign_manifest "$mac" manifest-mac.json

  if [[ $TEST == 1 ]]; then
    for d in "$pc" "$mac"; do
      printf 'TEST BUILD signed with a throwaway key. Never put this on a stick for customers.\n' \
        > "$d/TEST-ONLY.txt"
    done
  fi
  done_apps+=("$name")
done <<< "$LIST"

if [[ $TEST == 1 && -d "$OUT" ]]; then cp "$WORK/test.pub" "$OUT/test-key.pub"; fi
say "Done: $OUT"
printf 'Packaged (%d): %s\n' "${#done_apps[@]}" "${done_apps[*]:-none}"
if [[ ${#skipped[@]} -gt 0 ]]; then
  printf 'Skipped (%d):\n' "${#skipped[@]}"
  printf '  %s\n' "${skipped[@]}"
fi
