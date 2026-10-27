# Build the Craft apps on your Mac

Local copies for you to try. They are not the stick copies: those get signed with the Developer ID later.

## One-time setup (about 5 minutes)

1. Open Terminal.
2. Install the Xcode command line tools if you don't have them: `xcode-select --install`
3. Install Rust if you don't have it: `curl https://sh.rustup.rs -sSf | sh`, press Enter for the defaults, then close and reopen Terminal.

## Build

```sh
cd ~/Documents/work/smartstick/smartstick-craft
scripts/build-mac-local.sh --priority     # the five must-haves: Word, Photo, Film, PDF, Grid
scripts/build-mac-local.sh                # all 11
scripts/build-mac-local.sh cadcraft       # just one
```

- Each app takes roughly 10-30 minutes the first time. Leave the Mac plugged in and awake (`caffeinate -i scripts/build-mac-local.sh` keeps it awake).
- It needs about 3-5 GB of free space per app while building (in `work/`). Delete `work/` afterwards to get it back.
- Your apps land in `out/mac/` as `.dmg` files. Open one and drag the app to Applications, or run it from the DMG.
- First launch: right-click the app, choose Open, then Open again. These local copies aren't notarized, so macOS asks once.
- If an app fails, the script keeps going and lists it at the end. Its log is `work/<app>.log`. Send me that file and I'll fix it.

## What it does

For each app in `apps.json`, it downloads the pinned release from github.com/storytold, plus the fonts and translations that release used. Then it runs the app's own Mac packaging script, which builds Apple silicon + Intel (universal), and copies the DMG and licence files to `out/mac/`. Nothing is changed in their code.

## Windows

Windows builds need Windows (upstream's script uses PowerShell and WiX). They run on GitHub's Windows machines: on github.com open smartstick-craft > Actions > Build > Run workflow (empty app list = all 11). Download the artifacts when it finishes; you sign them on this Mac with `sign-windows.sh` (the stick packaging script does that for you).
