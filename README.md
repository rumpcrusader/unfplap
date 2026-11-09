# Unfplap

Do your mares.

## how

Copy `.pck` from releases into your mod folder.

Requires Home: Equestria `0.3.0-maredev`.

Desktop first. The optional VR standing act is experimental and gated by the anatomy master.

## Controls

| Input       | Action                                                            |
| ----------- | ----------------------------------------------------------------- |
| `Y`         | Make love with an available pony (standing: stand behind her rump)  |
| Mouse ↕     | Thrust during the act (manual mode)                               |
| Mouse wheel | Auto-thrust pace while auto is on                                  |
| `X`         | Toggle auto thrust during the act                                  |
| `W` / `S`   | Lean the act camera forward / back                                |
| `Q` / `E`   | Lean diagonally; standing also cues a shoulder reach              |
| `A` / `D`   | Caress her left / right flank in standing pose, including afterglow   |
| `F` (hold)  | Kiss at a full shoulder lean (standing) or full forward lean        |
| Mouse right | Smack her flank during the act                                    |
| `G`         | Smack her flank during the act                                    |
| Hold `X`    | Auto settings: `Q`/`A` min depth, `W`/`S` max depth, `E`/`D` pace, `Z` stroke shape |
| `V`         | Switch hole during the act (optional anatomy)                     |
| `N`         | Oral in the standing pose (optional anatomy)                      |
| `B`         | Choose finish in or out (optional anatomy)                        |
| `Enter`     | Open chat during the act                                          |
| Hold `Y`    | End early before her first climax, or end the act/afterglow     |

## Features

- **Relationship-gated encounters** — Adult mares and stallions only, with a lover bond agreed
  in conversation and real refusals for both player forms.
- **Relationship settings** — `Promiscuity` sets the lowest relationship level for a lover bond
  and sex; `Starting Sex` decides whether Anon needs that bond before he can try.
- **Two poses** — Supports missionary on a bed or couch and standing.
- **Optional anatomy** — Adds hole, oral, finish and fluid controls, separate teats and skin-strip switches, genital tone plus Anon girth, head, length and throb tuning, and optional VR, each behind its own toggle. One Anatomy switch picks Never, only while an act runs, or Always. The PPP anatomy assets are tracked in the repository and packed for release; the V2 mare bits variant is also tracked.
- **Mare bits** — Choose the original PPP genitals or the V2 variant in the Anatomy settings; the V2 choice falls back to the original when its asset is absent.
- **Play-bow stance** — Optional standing stance with her front legs stretched forward, chest down and head low.
- **Proactive mares** — A ready mare may ask for sex herself. She may invite you to bed or turn her back and invite you from behind; answer yes and take the position. Standing `Y` appears when you stand behind her rump.
- **Estrus cycle** — Optional 30-day cycle: a week of heat makes her warm faster, ask sooner, and wink and discharge while she idles, two days of diestrus turn her off, then normal. Off by default.
- **Mouse thrust readiness** — Build her arousal with real thrusts; she can climax repeatedly while you keep thrusting.
- **Climax limit** — `Climax limit` sets how many times she can climax in one act; `0` is unlimited.
- **Auto thrust** — Press `X` to hand Anon the rhythm; the wheel sets pace, and holding `X` sets the bottom, peak, pace and stroke shape by hand.
- **Per-mare preference** — Each mare has intensity, rhythm, touch, talk, warmth, and how much she tolerates before she warns or stops.
- **Act settings** — `Settings → Unfplap` has General, Anatomy, World and Characters tabs; an **Enable debug** switch adds an extra Debug section at the bottom of General, Anatomy and World for pose, camera, cue and history tuning.
- **Reactive dialogue** — Her cues react to mood, rhythm, touch and what you say to her; `Act lines` can be turned off while normal dialogue and the HUD cue stay.
- **HUD** — Shows the act controls list, optional mood cues and climax count.
- **Act camera** — Offers a controlled lean camera with speed-driven thrust surge and bob.
- **Act actions** — Leaning cues kisses and shoulder reaches; A/D caress a flank, Z/C pause or resume each caress oval, F kisses at a full shoulder lean in standing or a full forward lean in missionary, and right-click smacks one.
- **Cuddle override** — Lets an encounter begin while a cuddle is active.
- **Presentation** — Adds blush, eyes, ears, tail, rump jiggle, audio and wing motion.
- **Act audio** — Pack thrust, slide, bed/fabric, kiss and flank-smack sounds are always on; `Act vocals` adds only the optional pack climax moan; `Wet climax layer` is separate and off by default.
- **Aftermath** — Ends with a held afterglow for either pose; normal dialogue resumes with the just-intimate context, she may choose to get up after a while, and asking to stay longer holds the moment. In standing afterglow, staying close and caressing earns a small extra reward, then short aftercare. A warm, relaxed "satisfied" mood and expression last for five minutes afterward.
- **Memory and witnesses** — Intimacy is remembered, and nearby awake ponies can witness it and talk about it later.
- **Long-term history** — Good sex builds trust and desire, while repeated neglect or disliked handling makes a mare reluctant; she may stop asking, complain, or gently refuse until things improve. No break-up.

## Build

Requires Godot 4.5.x on `PATH`, `python3`, and a git checkout. Release checks require Godot 4.5.2.

```sh
./build.sh
# -> dist/unfplap-<version>.pck and .pck.sha256

./build.sh --out /tmp/unfplap.pck
```

`build.sh` stages the tracked runtime tree in a temporary Godot project, imports the assets under
`assets/` and `audio/`, and packs each `.import` sidecar plus Godot's imported data. The packer
then verifies the packed files against the tracked runtime manifest, rejects development files and
broken import data, and writes a `.sha256` beside the pck; a failed check removes the pack.
Repository docs, tests, scripts, tools, skills, `.git`, `dist/` and `*.uid` do not enter the pack.
`AUDIO_CREDITS.md` does, for credit.

The PPP anatomy meshes and textures are tracked in `assets/anatomy/`. Every build includes all
eight files; the anatomy feature itself remains optional in the settings.

The official `tools/modding/build_mod.gd` command still works for quick builds, but packs the
whole folder.
