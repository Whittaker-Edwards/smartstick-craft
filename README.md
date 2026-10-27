# smartstick-craft

Build recipes for shipping the **Craft apps** on the Smart Stick, a USB drive that comes with free desktop programs for Windows and Mac.

The Craft apps (WordCraft, PhotoCraft, PDFCraft and the rest) are free, open-source desktop programs written by the **ArtCraft team and contributors** ([github.com/storytold](https://github.com/storytold), [getartcraft.com](https://getartcraft.com)). **We did not write them.** This repository holds only what we need to build their published releases unchanged and package them to run from the stick. It contains none of their source code.

This repository is not made, endorsed or supported by the ArtCraft team. For anything about the apps themselves, go to the ArtCraft team's own repositories.

## Licences

### The apps we ship

Each app is copyright (c) 2026 ArtCraft Team and that app's contributors. Each one is licensed under the **MIT License or the Apache License 2.0**, at your option. We redistribute them under those terms.

| App | Upstream | Release we build | Licence |
|---|---|---|---|
| WordCraft | [storytold/wordcraft](https://github.com/storytold/wordcraft) | [v0.11.0](https://github.com/storytold/wordcraft/tree/e31f2f06a5f8004ceaa88f68c00b47908e321aa4) | MIT OR Apache-2.0 |
| PhotoCraft | [storytold/photocraft](https://github.com/storytold/photocraft) | [v0.16.0](https://github.com/storytold/photocraft/tree/b1794c6e0608ccfc887213dcf58398977c5cb75e) | MIT OR Apache-2.0 |
| FilmCraft | [storytold/filmcraft](https://github.com/storytold/filmcraft) | [v0.13.0](https://github.com/storytold/filmcraft/tree/30536bc5d0ddf690f2181b7b97182db8658a6038) | MIT OR Apache-2.0 |
| PDFCraft | [storytold/pdfcraft](https://github.com/storytold/pdfcraft) | [v0.14.0](https://github.com/storytold/pdfcraft/tree/5a78b223871add8e3883856205cc653d741e0e94) | MIT OR Apache-2.0 |
| GridCraft | [storytold/gridcraft](https://github.com/storytold/gridcraft) | [v0.12.1](https://github.com/storytold/gridcraft/tree/f86aec12dabc744b5f75e1033f87bfe685e78481) | MIT OR Apache-2.0 |
| DeckCraft | [storytold/deckcraft](https://github.com/storytold/deckcraft) | [v0.11.1](https://github.com/storytold/deckcraft/tree/9ec39267931c0163dd5648c879043edcb9603cb8) | MIT OR Apache-2.0 |
| FigCraft | [storytold/figcraft](https://github.com/storytold/figcraft) | [v0.11.2](https://github.com/storytold/figcraft/tree/d4a303d4708602a9df1738960852d18b185a616b) | MIT OR Apache-2.0 |
| CadCraft | [storytold/cadcraft](https://github.com/storytold/cadcraft) | [v0.13.0](https://github.com/storytold/cadcraft/tree/1fcf654ea8414ea2ef052ca2b3b77411f2026f78) | MIT OR Apache-2.0 |
| EffectCraft | [storytold/effectcraft](https://github.com/storytold/effectcraft) | [v0.17.0](https://github.com/storytold/effectcraft/tree/362474a843ddb67555d4c2d19ad6a590388aad0e) | MIT OR Apache-2.0 |
| VectorCraft | [storytold/vectorcraft](https://github.com/storytold/vectorcraft) | [v0.17.0](https://github.com/storytold/vectorcraft/tree/43313f9451de7ab5b909801006b8881458f2bf04) | MIT OR Apache-2.0 |
| LightCraft | [storytold/lightcraft](https://github.com/storytold/lightcraft) | [v0.14.0](https://github.com/storytold/lightcraft/tree/03c88c166c054c009db2a47187d59991f6232b85) | MIT OR Apache-2.0 |

Each app also bundles third-party material under its own licence. This is mainly fonts under the **SIL Open Font License 1.1**. Some apps also include word lists or hyphenation patterns (public domain, CC0, MIT or BSD-3-Clause). PDFCraft includes the Ocrs OCR models by Robert Knight under **CC BY-SA 4.0**; their licence and credits ship in its `models/` folder. Each app lists this material in its `NOTICE` and `ATTRIBUTION.md`.

What we ship with every app on the stick (`SmartSuite/<App>/licences/`):

- `LICENSE-MIT` and `LICENSE-APACHE`
- `NOTICE`
- `ATTRIBUTION.md`
- the `OFL-*.txt` text for every font the build includes

The build copies these from the exact upstream commit, and packaging stops if an app's `LICENSE-*`, `NOTICE` or `ATTRIBUTION.md` is missing.

### Trademarks

"ArtCraft", its wordmark and its logos are trademarks of the ArtCraft Team. They are not open source, and the licences above do not cover them (see each app's `docs/brand/LICENSE-brand.txt`). We build the apps unchanged from their release tags, so the apps look as their authors made them. We never use the ArtCraft name or logo to name, advertise or market our own product. If we ever ship a modified build, we will remove the ArtCraft marks from it as that licence requires.

### This repository

The scripts and workflow in this repository are our own work, under the [MIT License](LICENSE). That licence covers only these files, not the apps they build.

## What's here

| Path | What it is |
|---|---|
| `apps.json` | The upstream releases we build, pinned by tag **and** commit, plus the `craft-fonts` commit each release used. |
| `.github/workflows/build.yml` | GitHub Actions. Builds each app with the app's **own** packaging scripts, giving an unsigned Windows x64 portable zip and an ad-hoc signed Mac universal DMG, plus the licence files. No signing keys or secrets live here. |
| `scripts/build-mac-local.sh` | The same Mac build, run on your own Mac. |
| `scripts/restore-fetched-models.py` | Some apps download files during their build (PDFCraft's OCR models). If one of those links stops working, this takes the identical file, checked by SHA-256, from the app's own published release for the same version. |
| `scripts/package-stick.sh` | Turns the builds into the stick's folder layout, then signs them. Signing needs our private signing kit and keys, so only we can run the signing part. |
| [`BUILDING.md`](BUILDING.md) | Step-by-step build instructions. |

## How it works

1. **Pin.** `apps.json` names each app's GitHub repo, release tag and the commit behind that tag. To update an app, change the tag and commit together.
2. **Build.** For each app, the workflow (or `build-mac-local.sh`) checks out that exact commit, along with the fonts and translations the release used. Then it runs the app's own `packaging/windows/package.ps1` or `packaging/macos/package.sh`. We change nothing in the apps' code.
3. **Package.** `package-stick.sh` lays each app out as:

   ```
   SmartSuite/<App>/
     <App>.exe, <App>.app           small starters that check the files, then open the app
     app-windows/, app-mac/         the upstream builds
     manifest-windows.json, manifest-mac.json  (+ .minisig)
     licences/
   ```

   It signs the Windows programs with Authenticode and the Mac apps with an Apple Developer ID. Each manifest lists every file with its checksum and is signed with an offline key. The starter only opens the app if every file matches.

You can use steps 1 and 2 to build the Craft apps for yourself. Step 3's signing is specific to the Smart Stick.

## Running the build on GitHub

Go to Actions > **Build** > Run workflow. Leave the app list empty to build all of them, or enter ids such as `wordcraft,pdfcraft`. Each app's builds come out as workflow artifacts: `<id>-windows` and `<id>-mac`.

Mac jobs only run while this repository is public. On a private repository, GitHub bills Mac runners at 10x, so the jobs skip themselves and the run shows a warning saying why. A pull request that changes `apps.json` or the workflow builds WordCraft for Windows as a check.
