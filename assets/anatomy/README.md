# integration: local anatomy assets

This folder holds the optional adult meshes and textures used by the anatomy feature. They are
**kept out of git** by `.gitignore`; never commit them. A local `build.sh` packs them into the
`.pck` when they are present in the working tree.

Expected files:

```text
winking.scn          mare anatomy mesh (closed/stretch blend shapes)
anal.scn             anal cup (open/stretch blend shapes)
teats.scn            skinned teats (mid/full blend shapes, 191 binds)
skin_bridge.scn      skinned midline strip
anon_part.scn        player anatomy mesh (ready blend shape)
anon_part_ao.png     2048^2 baked AO
anon_part_nrm.png    2048^2 normal map
anon_part_albedo.png 2048^2 albedo/detail
```

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
