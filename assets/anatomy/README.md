# integration: local anatomy assets

This folder holds the optional adult meshes and textures used by the anatomy feature. The
PonyPussyParadise source files are **never committed**; the `.gitignore` here excludes them.
`mare_bits_v2.scn` is the V2 variant and is tracked. A pack always ships the required set:
`scripts/pack_anatomy.sh` writes `dist/unfplap-anatomy.zip`, that archive is uploaded to a plain
URL recorded in the repository variable `ANATOMY_URL`, and `.github/workflows/build.yml`
downloads and unpacks it before a release build.

Redistribution is by permission of the PonyPussyParadise author; `mod.json` credits them.

Expected files:

```text
winking.scn          original PPP mare anatomy mesh (closed/stretch blend shapes)
mare_bits_v2.scn     V2 mare genitals variant (closed/stretch/wink blend shapes)
anal.scn             anal cup (open/stretch blend shapes)
anal_ring.scn        experimental anal ring (feature-gated by anatomy.anal_ring)
teats.scn            skinned teats (mid/full blend shapes, 191 binds)
skin_bridge.scn      skinned midline strip
anon_part.scn        player anatomy mesh (ready blend shape)
anon_part_ao.png     2048^2 baked AO
anon_part_nrm.png    2048^2 normal map
anon_part_albedo.png 2048^2 albedo/detail
```

## Building

```bash
scripts/pack_anatomy.sh                       # -> dist/unfplap-anatomy.zip
./build.sh --anatomy-zip dist/unfplap-anatomy.zip
./build.sh                                    # requires the files to be in this folder
./build.sh --no-anatomy                       # code-only pack, assets left out
```

`build.sh` prints `ANATOMY ok 10/10`, `ANATOMY skipped (--no-anatomy)`, or `ANATOMY_FAIL` with the
missing names. `--no-anatomy` excludes the folder from the pack even when the files are present.

The archive holds exactly the ten files above at its root; the extractor matches them by name
and ignores everything else, so a stray path inside the zip cannot reach the pack. At runtime the
V2 mesh is optional: the Mare bits setting falls back to `winking.scn` when it is absent.

## Recovering the files

`tools/recover_anatomy_assets.gd` regenerates these from a PonyPussyParadise `.pck`:

```bash
godot --headless --xr-mode off --path <game-project> \
  --script res://mods/unfplap/tools/recover_anatomy_assets.gd -- \
  /path/to/<pack>.pck
```

The script writes into this folder and is safe to run again. It also creates a temporary import
remap for the source scene's external texture; that remap lives under `res://mods/` and
`res://.godot/` in the working project, not in this folder.

When the files are absent the anatomy feature logs once and stays off. Nothing else in the mod
depends on them.
