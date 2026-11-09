# Anatomy assets

This folder holds the optional adult meshes and textures used by the anatomy feature. The
PonyPussyParadise assets are tracked here and every build, including CI, packs them. The feature
itself remains optional in the settings.

Redistribution is by permission of the PonyPussyParadise author; `mod.json` credits them.

Required files:

```text
winking.scn          original PPP mare anatomy mesh (closed/stretch blend shapes)
mare_bits_v2.scn     V2 mare genitals (closed/stretch/wink + anal_open/anal_stretch/
                     anal_overstretch/anal_extreme/ponut_scale blend shapes)
teats.scn            skinned teats (mid/full blend shapes, 191 binds)
skin_bridge.scn      skinned midline strip
anon_part.scn        player anatomy mesh (ready blend shape)
anon_part_ao.png     2048^2 baked AO
anon_part_nrm.png    2048^2 normal map
anon_part_albedo.png 2048^2 albedo/detail
```

## Building

```bash
./build.sh
```

`build.sh` reads the required runtime list from `scripts/build_manifest.py` and `pack.gd`
verifies the packed anatomy files. It writes a `.sha256` beside the pack. Local Blender and
backup files are ignored by `.gitignore` and `.pckignore`.

At runtime the V2 mesh is optional: the Mare bits setting falls back to `winking.scn` when it is
absent.

## Recovering the files

`tools/recover_anatomy_assets.gd` can regenerate them from a PonyPussyParadise `.pck`:

```bash
godot --headless --xr-mode off --path <game-project> \
  --script res://mods/unfplap/tools/recover_anatomy_assets.gd -- \
  /path/to/<pack>.pck
```

The script writes into this folder and is safe to run again. It also creates a temporary import
remap for the source scene's external texture; that remap lives under `res://mods/` and
`res://.godot/` in the working project, not in this folder.
