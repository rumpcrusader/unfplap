# Unfplap

Do your mares.

## How

Copy `.pck` from releases into your mod folder.

Requires Home: Equestria `0.3.2-maredev`.

Desktop-first, VR is untested.

## Build

Requires Godot 4.5.x on `PATH`, `python3`, `git`, and `curl` for the asset fetch. Release checks require Godot 4.5.2.

A fresh checkout needs the external runtime assets once:

```sh
scripts/fetch_assets.sh
```

```sh
./build.sh
# -> dist/unfplap-<version>.pck and .pck.sha256
./build.sh --out /tmp/unfplap.pck
```

Next, explore the `AGENTS.md` and `docs/` to get more context.
