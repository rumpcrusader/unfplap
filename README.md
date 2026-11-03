# Unfplap

Do your mares.

## how

Copy `.pck` from releases into your mod folder.

Requires Home: Equestria `0.1.1-maredev`.

Desktop only for now

## Controls

| Input       | Action                                                            |
| ----------- | ----------------------------------------------------------------- |
| `Y`         | Start an available encounter                                      |
| Mouse ↕     | Thrust during the act                                               |
| `W` / `S`   | Lean the act camera forward / back                                |
| `Q` / `E`   | Lean diagonally; also cue a kiss or shoulder reach                |
| `A` / `D`   | Caress her left / right flank in horse pose, including afterglow   |
| `F` (hold)  | Kiss while fully shoulder-leaning in horse pose                   |
| Mouse right | Smack her flank during the act                                    |
| Hold `Y`    | Afterglow after her first climax / stop early / end afterglow     |

## Features

- **Relationship-gated encounters** — Adult mares and stallions only, with consent and refusals
  for both player forms.
- **Two poses** — Supports missionary on a bed or couch and standing horse.
- **Proactive mares** — A ready mare may ask for sex herself. In private she asks directly; answer yes to let her take the standing position and invite you, or no to turn her down. `Y` still starts the act immediately.
- **Mouse thrust readiness** — Build her arousal with real thrusts; she can climax repeatedly while you keep thrusting.
- **Per-mare taste** — Each mare has intensity, rhythm, touch, talk, warmth and recovery.
- **Act settings** — Tune mouse thrust, camera thrust, per-pose presentation, caress palm distance/scale and body-part ignores, plus each pony's taste in `Settings → Unfplap`.
- **Reactive dialogue** — Her cues react to mood, rhythm, touch and what you say to her.
- **HUD** — Shows the act controls list, readiness meter, optional mood cues and climax count.
- **Act camera** — Offers a controlled lean camera with speed-driven thrust surge and bob.
- **Act actions** — Leaning cues kisses and shoulder reaches; A/D caress a flank, Z/C pause or resume each caress oval, F kisses at a full shoulder lean, and right-click smacks one.
- **Cuddle override** — Lets an encounter begin while a cuddle is active.
- **Presentation** — Adds blush, eyes, ears, tail, rump jiggle, audio and wing motion; an optional flag adds the dock and tail base to the thrust wobble.
- **Act audio** — `Act foley` adds pack thrust, bed, fabric and kiss sounds; `Act vocals` adds only the optional pack climax moan; `Wet climax layer` is separate and off by default. All off restore the original kiss-sample plap.
- **Aftermath** — Ends with a held afterglow for either pose; normal dialogue resumes with the just-intimate context, she may choose to get up after a while, and asking to stay longer holds the moment. In horse afterglow, staying close and caressing earns a small extra reward, then short aftercare. A warm, relaxed "satisfied" mood and expression last for five minutes afterward.
- **Memory and witnesses** — Intimacy is remembered, and nearby awake adults can witness it.

## Build

Requires Godot 4.5.x and `python3`.

```sh
./build.sh
# -> dist/unfplap.pck

./build.sh --no-extends   # release pack for games that ship compiled .gdc scripts
./build.sh --out /tmp/unfplap.pck
GODOT=/path/to/godot ./build.sh
```

`build.sh` stages the runtime tree selected by `.pckignore` in a temporary Godot project, imports
the audio under `audio/`, and packs each `.import` sidecar plus Godot's imported data. Repository
docs, tests, scripts, tools, `.git`, `dist/` and `*.uid` do not enter the pack. `AUDIO_CREDITS.md`
does, for credit.

`--no-extends` removes the parked `ext/shared_bed.gd` extension and the `extends` entry from the
packed `mod.json`; source runs keep it. The official
`tools/modding/build_mod.gd` command still works for quick builds, but packs the whole folder.

On GitHub, `.github/workflows/build.yml` builds on pushes and pull requests, and on a `v*` tag it
builds with `--no-extends` and attaches `dist/unfplap.pck` to a GitHub release.
