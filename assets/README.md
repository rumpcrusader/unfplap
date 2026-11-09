# Runtime assets

The adult audio and anatomy files are not tracked in this repository. They live in one
compile-time resource archive on pone.rs. The release workflow fetches that archive and packs its
`runtime/` tree into the mod `.pck`; players still install one file.

```bash
scripts/fetch_assets.sh            # runtime files into audio/ and assets/anatomy/
scripts/fetch_assets.sh --sources  # also sources/ for editing
scripts/fetch_assets.sh --force    # overwrite local changes
```

Run the fetch once in a fresh checkout, before `--mod-src`, `scripts/test_all.sh`,
`scripts/smoke.sh`, a lab or `build.sh`. The download is verified against the archive hash and
per-file manifest in `scripts/asset_pack.json`; a missing, stale or extra runtime file fails
`build.sh` with the fetch hint.

## Archive layout

```text
unfplap-assets-<hash>.zip
  manifest.json
  runtime/
    assets/anatomy/        meshes, textures and their .import sidecars
    audio/act/             .wav files and their .import sidecars
  sources/
    anatomy/mare_bits_v2.blend
```

- `runtime/` is the only tree packed into the mod. Paths are repository-relative.
- `sources/` is editable material and is never staged or packed.
- `audio/act/catalogue.gd`, `audio/act/smack/catalogue.gd` and `audio/act/sources.json` stay in
  git: they are code and credit metadata, not audio data.
- The V2 Blender source is the only Blender file included in the archive. Winking iterations,
  `.blend1` files and `backups/` stay local and out of the archive.

## Changing assets

1. Edit the runtime files under `assets/anatomy/` and `audio/`.
2. Put the V2 Blender source at `sources/anatomy/mare_bits_v2.blend`.
3. Build and upload the archive:

   ```bash
   scripts/pack_assets.sh --upload
   ```

   This prints the archive hash, uploads it to pone.rs, verifies the served bytes and rewrites
   `scripts/asset_pack.json` with the URL, archive hash and per-file manifest.
4. Commit `scripts/asset_pack.json` with the asset change.
5. Run `scripts/fetch_assets.sh` in a clean checkout or let CI fetch it before the build.

An unchanged asset set reuses the existing archive; do not re-upload it for every release.

## Anatomy files

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

At runtime the V2 mesh is optional: the Mare bits setting falls back to `winking.scn` when it is
absent. The anatomy feature itself is optional in the settings.

## Recovering the files

`tools/recover_anatomy_assets.gd` regenerates them from a PonyPussyParadise `.pck`:

```bash
godot --headless --xr-mode off --path <game-project> \
  --script res://mods/unfplap/tools/recover_anatomy_assets.gd -- \
  /path/to/<pack>.pck
```

The script writes into the ignored `assets/anatomy/` folder. Run the Godot import afterward and
repack and upload the resource archive; do not commit the regenerated files directly.

Redistribution is by permission of the PonyPussyParadise author; `mod.json` credits them.
