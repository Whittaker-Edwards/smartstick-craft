# Building

These steps build the Craft apps (by the ArtCraft team and contributors, MIT OR Apache-2.0; see [README](README.md#licences)) from the releases pinned in `apps.json`. Nothing in the apps' code is changed.

## On GitHub (Windows and Mac)

Go to Actions > **Build** > Run workflow. Leave the app list empty to build every app, or enter ids such as `wordcraft,pdfcraft`. When the run finishes, each app has two artifacts:

- `<id>-windows`: the portable zip and `SOURCE.txt` (the upstream repo, tag and commit)
- `<id>-mac`: the DMG, `SOURCE.txt` and `licences/`

The Mac jobs only run while the repository is public.

Download them with the GitHub CLI:

```sh
gh run download <run id> -R Whittaker-Edwards/smartstick-craft -D in
```

Or download them from the run's page and unzip each one into `in/`.

These builds are unsigned on Windows and ad-hoc signed on Mac. They run on your own computer, but Windows SmartScreen and macOS Gatekeeper will warn the first time you open them. On a Mac, right-click the app, choose Open, then Open again.

## On your own Mac

Windows builds need Windows, so use GitHub for those.

### One-time setup

1. Install the Xcode command line tools: `xcode-select --install`
2. Install Rust from https://rustup.rs (take the defaults), then reopen Terminal.
3. Clone this repository.

### Build

```sh
scripts/build-mac-local.sh                # every app in apps.json
scripts/build-mac-local.sh wordcraft      # just these
scripts/build-mac-local.sh --priority     # only the apps marked priority
```

- The first build of each app takes roughly 10 to 30 minutes. `caffeinate -i scripts/build-mac-local.sh` keeps the Mac awake while it runs.
- Each app needs about 3 to 5 GB free while it builds, in `work/`. Delete `work/` afterwards to get the space back.
- The DMGs go to `out/mac/`. Each app's licence files go to `out/mac/<App>-licences/`.
- If an app fails, the script carries on with the rest and lists the failures at the end. Each app's log is `work/<id>.log`.

## Packaging for the Smart Stick (signed)

This step needs our private signing kit (`smartstick-desktop-kit`, cloned next to this repo) and our signing keys. Without them it can't run, except in test mode.

1. Put the builds in place: Windows zips under `in/`, and Mac DMGs under `in/` (from GitHub) or `out/mac/` (local builds). If both exist, the local Mac build is used.
2. Test run, with a throwaway key and no OS signing: `scripts/package-stick.sh --test wordcraft`. This writes `dist-stick-test/SmartSuite/WordCraft/`. Copy it to a USB drive and open `WordCraft.app` on a Mac or `WordCraft.exe` on a PC. Never ship a test build.
3. Real run: `scripts/package-stick.sh`, with the offline release key available. It does five things:
   - signs every Windows program (Authenticode)
   - signs the Mac app and its starter with the Developer ID, then notarises them
   - writes `manifest-windows.json` and `manifest-mac.json`
   - signs both manifests with the release key
   - copies each app's licence files into its folder

   The output goes to `dist-stick/SmartSuite/<App>/`.
