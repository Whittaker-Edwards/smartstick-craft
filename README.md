# smartstick-craft

Builds the ArtCraft team's Craft apps (github.com/storytold) for the Smart Stick's `SmartSuite/` folder.
Windows builds run on GitHub Actions (Actions > Build > Run workflow). Mac builds run on Ryan's Mac (BUILD-ON-YOUR-MAC.md); the workflow can do them too, at 10x minutes on this private repo.

- `apps.json`: the pinned upstream releases (tag + commit + craft-fonts commit).
- `.github/workflows/build.yml`: per app, upstream's own packaging scripts with no signing secrets → unsigned Windows x64 portable zip (and optionally Mac universal DMG), plus licence files, as workflow artifacts.
- `scripts/build-mac-local.sh`: local Mac copies (BUILD-ON-YOUR-MAC.md).
- `scripts/package-stick.sh` (next; kit PR #7 merged): on Ryan's Mac, download the artifacts, `sign-windows.sh` every exe/dll, `sign-mac.sh` the .app, build both starters, `make-manifest.sh --per-platform` for each half, `sign-release.sh`, giving `SmartSuite/<App>/` folders.

Licences: each app is MIT OR Apache-2.0 with OFL fonts; the licences/ folder ships inside each app folder. The ArtCraft name and logo are trademarks: never use them in our marketing, and remove them from any build we change.
