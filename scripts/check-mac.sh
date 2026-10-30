#!/usr/bin/env bash
# Checks the Mac half of packaged Craft apps the way a customer's Mac will:
# both chips (Apple silicon + Intel), a valid Developer ID signature with the
# hardened runtime, Gatekeeper's verdict and the stapled notarisation ticket.
#
#   scripts/check-mac.sh                       every app in dist-stick/SmartSuite
#   scripts/check-mac.sh path/to/SmartSuite    another folder (e.g. on the stick)
#
# Each .app gets a line per check; it ends with "all good" or the list of
# problems. A --test build fails the signing checks by design.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUITE="${1:-$ROOT/dist-stick/SmartSuite}"
[[ "$(uname)" == "Darwin" ]] || { echo "Run this on a Mac." >&2; exit 2; }
[[ -d "$SUITE" ]] || { echo "No such folder: $SUITE" >&2; exit 2; }

problems=()
check() { # label, command...
  local label="$1"; shift
  if out="$("$@" 2>&1)"; then
    printf '  ok    %s\n' "$label"
  else
    printf '  FAIL  %s\n%s\n' "$label" "$(sed 's/^/        /' <<<"$out")"
    problems+=("$app: $label")
  fi
}
universal() { # binary
  local archs; archs="$(lipo -archs "$1")" || return 1
  echo "$archs"
  [[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]]
}
developer_id() { # app
  local info; info="$(codesign -dvv "$1" 2>&1)" || { echo "$info"; return 1; }
  grep -E '^(Authority|TeamIdentifier|CodeDirectory)' <<<"$info"
  grep -q '^Authority=Developer ID Application' <<<"$info" && grep -q 'flags=.*runtime' <<<"$info"
}

shopt -s nullglob
for app in "$SUITE"/*/*.app "$SUITE"/*/app-mac/*.app; do
  echo "$app"
  exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null)"
  check "Apple silicon + Intel (lipo)" universal "$app/Contents/MacOS/$exe"
  check "signature valid (codesign --verify)" codesign --verify --deep --strict "$app"
  check "Developer ID + hardened runtime" developer_id "$app"
  check "Gatekeeper accepts (spctl)" spctl --assess --type execute "$app"
  check "notarisation stapled (stapler)" xcrun stapler validate "$app"
done

echo
if [[ ${#problems[@]} -eq 0 ]]; then
  echo "All good."
else
  printf 'Problems (%d):\n' "${#problems[@]}"
  printf '  %s\n' "${problems[@]}"
  exit 1
fi
