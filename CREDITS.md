# Credits

Every third-party asset Unfplap bundles, with its author and terms. This is the only place the
mod states a credit. The assets are required: they ship inside the `.pck`, and the mod does not
run without them. The pack layout is in `assets/README.md`.

## Anatomy

**PonyPussyParadise** — the teats, the skin strip, the player part mesh with its albedo/AO/normal
maps, and the runtime code ported from it, including the VR standing act. The mare bits mesh is
adapted and modified from the pack's mesh, and its Blender source is
`sources/anatomy/mare_bits_v2.blend`. Redistributed by permission of the author.

Runtime: `assets/anatomy/mare/`, `assets/anatomy/anon/`

## Act audio

**OpenNSFW Sound Pack** — the act foley.

```text
SFX: OpenNSFW Sound Pack | @OpenNSFWSP
Contributors used: @SquishSuccubus, @lehornysfx3d, @pixelcarnagee,
@NyaughtyMeow, @That1LewdDude
Cloth Pillow Impacts: F.M.Audio (freesound.org/s/561141), CC BY 4.0
License: CC BY 4.0, https://creativecommons.org/licenses/by/4.0/
```

The selected files were trimmed, mono-downmixed, resampled to 48 kHz and peak-normalised for
this mod. The flank-smack variants are layered from the pack's flesh-impact and spank sources.
The full source path for every shipped file is in `audio/cue_sources.json`.

The pack is credited as a SFX pack. Do not contact the pack's contributors directly, and do not
redistribute this subset as a standalone sound pack.

## Pantyhose & Panties shaders

**mitty** — the look shaders under `integrations/shaders/` are adapted from Pantyhose & Panties
0.1.1's `hosiery_common.gdshaderinc`, `hosiery_cut.gdshader` and `hosiery_sheer.gdshader`, copied
as `pantyhose_common.gdshaderinc`, `pantyhose_cut.gdshader` and `pantyhose_sheer.gdshader`. The
depth-field hull block and its integration are Unfplap's. The pantyhose pack itself is not bundled;
the copy is pinned to 0.1.1 by `shared/integrations.gd`'s `verified_version`.

## Adding a credit

A new third-party asset gets its entry here in the `docs:` commit that immediately follows the
asset commit: the author, the licence or the permission, and what the mod uses. Do not repeat the
credit anywhere else.
