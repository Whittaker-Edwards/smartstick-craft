#!/usr/bin/env bash
# Makes the Craft app folders for the Smart Stick, on a Mac that holds our
# signing setup (the build steps are public; the signing kit and keys aren't):
#
#   dist-stick/SmartSuite/WordCraft/
#     WordCraft.exe            Windows starter (double-click)
#     WordCraft.app            Mac starter (double-click)
#     app-windows/             upstream's Windows portable build, Authenticode-signed
#     app-mac/WordCraft.app    upstream's Mac build, Developer ID signed + notarised
#     manifest-windows.json(.minisig)  manifest-mac.json(.minisig)
#     licences/                LICENSE-MIT, LICENSE-APACHE, NOTICE, ATTRIBUTION.md, OFL-*.txt
#
# The starters copy their platform's half to the computer, check every file
# against the signed manifest and open it (smartstick-desktop-kit
# stick-starter, per-platform manifests from kit #7). Order (kit
# signing/README.md): OS-sign, then the manifest, then the offline release key.
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
  local vars=(STICK_STARTER_APP_ID="$id" STICK_STARTER_APP_NAME="$name"
    STICK_STARTER_PUBKEYS="$PUBKEYS" STICK_STARTER_CACHE_NS="Smart Stick")
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
  dir="$OUT/SmartSuite/$name"
  mkdir -p "$dir/app-windows" "$dir/app-mac" "$dir/licences"

  # Licences: the files upstream ships with the app, plus its font licences.
  for f in LICENSE-MIT LICENSE-APACHE NOTICE ATTRIBUTION.md; do
    [[ -f "$src/$f" ]] || fail "$name: upstream $f is missing; the licence needs it on the stick."
    cp "$src/$f" "$dir/licences/"
  done
  for lic in "$ROOT/out/mac/$name-licences" "$(dirname "$dmg")/licences"; do
    if [[ -d "$lic" ]]; then find "$lic" -name 'OFL*.txt' -exec cp {} "$dir/licences/" \;; fi
  done

  # Windows half: upstream's portable zip, every program Authenticode-signed.
  unzip -q "$zip" -d "$WORK/win-$id"
  inner="$(find "$WORK/win-$id" -name "$id.exe" -print -quit)"
  [[ -n "$inner" ]] || fail "$name: $id.exe isn't in $(basename "$zip")."
  ditto "$(dirname "$inner")" "$dir/app-windows"
  ico="$(find "$src/assets" -name "$id.ico" -print -quit 2>/dev/null || true)"
  starter="$(build_starter "$id" "$name" "$ico" x86_64-pc-windows-msvc cargo xwin).exe"
  cp "$starter" "$dir/$name.exe"
  if [[ $TEST == 0 ]]; then
    progs=()
    while IFS= read -r -d '' p; do progs+=("$p"); done \
      < <(find "$dir/app-windows" -type f \( -iname '*.exe' -o -iname '*.dll' \) -print0)
    "$KIT/signing/sign-windows.sh" "${progs[@]}" "$dir/$name.exe"
  fi
  "$KIT/signing/make-manifest.sh" --app-id "$id" --version "$version" \
    --platform windows-x86_64 --files app-windows --per-platform \
    --entry "app-windows/$id.exe" "$dir"
  sign_manifest "$dir" manifest-windows.json

  # Mac half: the app from upstream's DMG, re-signed with our Developer ID.
  MOUNT="$WORK/mnt-$id"
  mkdir -p "$MOUNT"
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$dmg"
  app="$(find "$MOUNT" -maxdepth 1 -name '*.app' -print -quit)"
  [[ -n "$app" ]] || fail "$name: no .app in $(basename "$dmg")."
  appname="$(basename "$app")"
  ditto "$app" "$dir/app-mac/$appname"
  hdiutil detach -quiet "$MOUNT"; MOUNT=""
  icns="$(find "$dir/app-mac/$appname/Contents/Resources" -name '*.icns' -print -quit)"
  for t in aarch64-apple-darwin x86_64-apple-darwin; do build_starter "$id" "$name" "" "$t" cargo >/dev/null; done
  lipo -create -output "$WORK/stick-starter-$id" \
    "$KIT/target/aarch64-apple-darwin/release/stick-starter" \
    "$KIT/target/x86_64-apple-darwin/release/stick-starter"
  # Drop the linker's ad-hoc signature so sign-mac.sh always signs the starter
  # with the Developer ID (it skips an .app that already verifies).
  codesign --remove-signature "$WORK/stick-starter-$id"
  "$KIT/crates/stick-starter/make-mac-app.sh" --name "$name" \
    --bundle-id "com.smartstick.craft.$id.starter" --version "$version" \
    --binary "$WORK/stick-starter-$id" ${icns:+--icon "$icns"} "$dir"
  if [[ $TEST == 0 ]]; then
    # Upstream's own hardened-runtime entitlements. Passing them also makes
    # sign-mac.sh replace the local (ad-hoc) signature with the Developer ID.
    ent="$src/packaging/macos/entitlements.plist"
    [[ -f "$ent" ]] || fail "$name: upstream packaging/macos/entitlements.plist is missing."
    "$KIT/signing/sign-mac.sh" "$dir/app-mac/$appname" --entitlements "$ent"
    "$KIT/signing/sign-mac.sh" "$dir/$name.app"
  else
    codesign --force --deep --sign - "$dir/app-mac/$appname" "$dir/$name.app"
  fi
  exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$dir/app-mac/$appname/Contents/Info.plist")"
  "$KIT/signing/make-manifest.sh" --app-id "$id" --version "$version" \
    --platform macos-universal --files app-mac --per-platform \
    --entry "app-mac/$appname/Contents/MacOS/$exe" "$dir"
  sign_manifest "$dir" manifest-mac.json

  if [[ $TEST == 1 ]]; then
    printf 'TEST BUILD signed with a throwaway key. Never put this on a stick for customers.\n' \
      > "$dir/TEST-ONLY.txt"
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
