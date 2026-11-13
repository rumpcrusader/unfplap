# Runtime assets

The adult audio and anatomy files are not tracked in this repository. They live in one
compile-time resource archive on pone.rs. The release workflow fetches that archive and packs its
`runtime/` tree into the mod `.pck`; players still install one file.

```bash
scripts/fetch_assets.sh            # runtime files into assets/
scripts/fetch_assets.sh --sources  # also sources/ for editing
scripts/fetch_assets.sh --force    # overwrite local changes
```

Run the fetch once in a fresh checkout, before `--mod-src`, `scripts/test_all.sh`,
`scripts/smoke.sh`, a lab or `build.sh`. The download is verified against the archive hash and
per-file manifest in `scripts/asset_pack.json`; a missing, stale or extra runtime file fails
`build.sh` with the fetch hint. The runtime files are required: the mod has no missing-asset
fallback. An unuploaded asset edit uses the ignored local contract described under
[Local testing before upload](#local-testing-before-upload).

## Two roots

- `assets/` is fetched data. It ships, and it is never edited in place.
- `sources/` is editable originals. It is never tracked and never packed.

The pack decides what ships by the tree alone: everything under `assets/` with a runtime suffix,
nothing under `sources/` except what is archived. `sources/work/` is local scratch and is not
archived either.

## Archive layout

```text
unfplap-assets-<hash>.zip
  manifest.json
  runtime/
    assets/audio/<group>/  .wav files and their .import sidecars
    assets/anatomy/mare/   mare meshes and textures, with .import sidecars
    assets/anatomy/anon/   player mesh and textures, with .import sidecars
  sources/
    anatomy/mare_bits_v2.blend
    voice/rarity/          46 archived wavs; not shipped
```

- `runtime/` is the only tree packed into the mod. Paths are repository-relative.
- `sources/` is editable material. `build.sh` and CI never stage or pack it.
- `audio/cues.gd`, `audio/smack_cues.gd` and `audio/cue_sources.json` stay in git: they are code
  and credit metadata, not audio data.
- `assets/audio/` is flat by cue group: `plap/`, `slide/`, `fabric/`, `mouth/`, `climax/` and
  `smack/`. The pool split (foley/climax) lives in `audio/cues.gd`, not in the directory names.
- The V2 Blender source is the only Blender file archived under `sources/anatomy/`. Winking
  iterations, `.blend1` files, `backups/` and reference renders stay local under `sources/work/`
  and out of the archive.

## Changing assets

1. Edit the original under `sources/` (or the archived `sources/anatomy/mare_bits_v2.blend`).
2. Write the runtime file into `assets/`; the import pass writes its `.import` sidecar.
3. Build and upload the archive:

   ```bash
   scripts/pack_assets.sh --upload
   ```

   This prints the archive hash, uploads it to pone.rs, verifies the served bytes and rewrites
   `scripts/asset_pack.json` with the URL, archive hash and per-file manifest.
4. Commit `scripts/asset_pack.json` with the asset change.
5. Run `scripts/fetch_assets.sh` in a clean checkout or let CI fetch it before the build.

An unchanged asset set reuses the existing archive; do not re-upload it for every release.

### Local testing before upload

An unuploaded runtime edit can be tested without changing the release contract:

```bash
scripts/pack_assets.sh --local
UNFPLAP_ASSET_CONTRACT=dist/asset_pack.local.json scripts/test_all.sh
UNFPLAP_ASSET_CONTRACT=dist/asset_pack.local.json ./build.sh
```

`--local` writes `dist/asset_pack.local.json` beside the archive. Both live under the ignored
`dist/`. The variable is explicit: without it every gate keeps reading `scripts/asset_pack.json`.
`fetch` and `--upload` always use the release contract, and `check_release.sh` clears the variable,
so a local contract cannot reach a release.

The import pass is `godot --headless --xr-mode off --path <project> --import`. The Blender
importer's headless check aborts the whole pass when the project contains `.blend` files, so move
`sources/` out of the project for the run and put it back afterwards. Never hand-edit an
`.import` sidecar: it carries a source path, a UID and a destination hash derived from the path.

## Anatomy files

```text
mare/mare_bits_v2.scn     mare genitals (closed/stretch/wink + anal_open/anal_stretch/
                          anal_overstretch/anal_extreme/ponut_scale blend shapes)
mare/teats.scn            skinned teats (mid/full blend shapes, 191 binds)
mare/skin_bridge.scn      skinned midline strip
anon/anon_part.scn        player anatomy mesh (ready blend shape)
anon/anon_part_ao.png     2048^2 baked AO
anon/anon_part_nrm.png    2048^2 normal map
anon/anon_part_albedo.png 2048^2 albedo/detail
```

These runtime files are required: `build.sh` and `smoke.sh` refuse a set that does not match the
active contract (`scripts/asset_pack.json`, or a local contract explicitly selected with
`UNFPLAP_ASSET_CONTRACT`), and the mod has no missing-asset fallback. The anatomy feature itself
is optional in the settings.

## Recovering or replacing the files

`scripts/fetch_assets.sh` restores the exact set recorded in `scripts/asset_pack.json`. If a local
file was edited, the fetch refuses to overwrite it; `scripts/fetch_assets.sh --force` discards the
local copy and restores the archived one. To keep intentional asset edits for local testing, use
the local contract above; to keep them for a release, repack and upload them. The downloaded files
are ignored; only `scripts/asset_pack.json` is committed.

Redistribution is by permission of the author; `CREDITS.md` names the source.
