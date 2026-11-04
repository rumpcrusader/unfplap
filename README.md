# Unfplap

Do your mares.

## how

Copy `.pck` from releases into your mod folder.

Requires Home: Equestria `0.3.0-maredev`.

Desktop only for now

## Controls

| Input       | Action                                                            |
| ----------- | ----------------------------------------------------------------- |
| `Y`         | Make love with an available pony (standing: aim at her flank)       |
| Mouse ↕     | Thrust during the act                                               |
| `W` / `S`   | Lean the act camera forward / back                                |
| `Q` / `E`   | Lean diagonally; also cue a kiss or shoulder reach                |
| `A` / `D`   | Caress her left / right flank in standing pose, including afterglow   |
| `F` (hold)  | Kiss while fully shoulder-leaning in standing pose                   |
| Mouse right | Smack her flank during the act                                    |
| Hold `Y`    | Afterglow after her first climax / stop early / end afterglow     |

## Features

- **Relationship-gated encounters** — Adult mares and stallions only, with consent and refusals
  for both player forms.
- **Two poses** — Supports missionary on a bed or couch and standing.
- **Proactive mares** — A ready mare may ask for sex herself. She may invite you to bed or turn her back and invite you from behind; answer yes and take the position. You can also ask her in dialogue: a clear “yes, now, here” leaves the encounter available. Standing `Y` appears when you aim at her flank; the feature flag can restrict `Y` to asks, verbal agreements and bed contexts.
- **Mouse thrust readiness** — Build her arousal with real thrusts; she can climax repeatedly while you keep thrusting.
- **Per-mare taste** — Each mare has intensity, rhythm, touch, talk, warmth and recovery.
- **Act settings** — `Settings → Unfplap` splits player settings (audio toggles, thrust, per-mare taste) from pose tuning and feature flags in a Debug tab.
- **Reactive dialogue** — Her cues react to mood, rhythm, touch and what you say to her.
- **HUD** — Shows the act controls list, readiness meter, optional mood cues and climax count.
- **Act camera** — Offers a controlled lean camera with speed-driven thrust surge and bob.
- **Act actions** — Leaning cues kisses and shoulder reaches; A/D caress a flank, Z/C pause or resume each caress oval, F kisses at a full shoulder lean, and right-click smacks one.
- **Cuddle override** — Lets an encounter begin while a cuddle is active.
- **Presentation** — Adds blush, eyes, ears, tail, rump jiggle, audio and wing motion.
- **Act audio** — `Act foley` adds pack thrust, slide, bed/fabric, kiss and flank-smack sounds; `Act vocals` adds only the optional pack climax moan; `Wet climax layer` is separate and off by default. Wooden bed creaks are off by default and can be re-enabled separately. All off restore the original kiss-sample plap and stock flank slap.
- **Aftermath** — Ends with a held afterglow for either pose; normal dialogue resumes with the just-intimate context, she may choose to get up after a while, and asking to stay longer holds the moment. In standing afterglow, staying close and caressing earns a small extra reward, then short aftercare. A warm, relaxed "satisfied" mood and expression last for five minutes afterward.
- **Memory and witnesses** — Intimacy is remembered, and nearby awake adults can witness it.
- **Tail bow** — Give a mare a satin tail bow in conversation and she wears it at the base of her
  tail from then on, through every pose and act.

## Build

Requires Godot 4.5.x and `python3`.

```sh
./build.sh
# -> dist/unfplap-<version>.pck

./build.sh --out /tmp/unfplap.pck
GODOT=/path/to/godot ./build.sh
```

`build.sh` stages the runtime tree selected by `.pckignore` in a temporary Godot project, imports
the audio under `audio/`, and packs each `.import` sidecar plus Godot's imported data. Repository
docs, tests, scripts, tools, `.git`, `dist/` and `*.uid` do not enter the pack. `AUDIO_CREDITS.md`
does, for credit.

The official `tools/modding/build_mod.gd` command still works for quick builds, but packs the
whole folder.

On GitHub, `.github/workflows/build.yml` builds on pushes and pull requests, and on a `v*` tag it
attaches `dist/unfplap-<version>.pck` to a GitHub release.
