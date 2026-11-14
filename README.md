# Unfplap

Do your mares.

## how

Copy `.pck` from releases into your mod folder.

Requires Home: Equestria `0.3.1-maredev`.

Desktop first. The optional VR standing act is experimental and gated by the anatomy master.

## Build

Requires Godot 4.5.x on `PATH`, `python3`, `git`, and `curl` for the asset fetch. Release checks
require Godot 4.5.2.

A fresh checkout needs the external runtime assets once:

```sh
scripts/fetch_assets.sh
```

```sh
./build.sh
# -> dist/unfplap-<version>.pck and .pck.sha256

./build.sh --out /tmp/unfplap.pck
```

`build.sh` stages the tracked runtime tree plus the fetched resource runtime in a temporary Godot
project, imports the assets under `assets/` and `audio/`, and packs each `.import` sidecar plus
Godot's imported data. The packer then verifies the packed files against the runtime manifest
(tracked files plus the resource pack manifest), rejects development files and broken import data,
and writes a `.sha256` beside the pck; a failed check removes the pack. Repository docs, tests,
scripts, tools, skills, `.git`, `dist/`, `sources/` and `*.uid` do not enter the pack.
`CREDITS.md` does, for credit.

The anatomy meshes, textures and act audio are listed in `scripts/asset_pack.json` and fetched
before the build; they are not tracked. Every build includes all seven anatomy files and the
complete audio catalogue; the anatomy feature itself remains optional in the settings. See
`assets/README.md` for the archive layout and the asset-change workflow.
