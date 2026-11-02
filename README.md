# Unfplap

Adult intimacy mod for **Home: Equestria** (`0.1.1-maredev`). It adds a consensual,
relationship-gated intimacy scene for adult ponies, with two poses, a mouse-driven pump
minigame, per-character preferences, reactive dialogue, and aftercare.

> **Adults only.** Every participant is an adult. Encounters require Marefriend/Coltfriend or
> higher. No pregnancy, heat, estrus, or conception content. There is no content warning or
> toggle.

## Features

- **Relationship-gated encounters** — Adult mares and stallions only, for both human Anon and
  AnonPony. Consent can be refused. The AI can make a strictly private, indoors-only offer when
  no one else is present.
- **Two poses** — `missionary` on a bed or couch, and `horse` standing. Each has its own camera,
  presentation, and aftermath.
- **Mouse pump minigame** — Vertical mouse movement controls depth; `F` remains flight. Completed
  strokes earn satisfaction from travel distance, depth preference, speed, and stroke shape. `Q`
  stops before climax.
- **Per-mare preferences** — Depth profiles (`steady`, `deep`, `shallow`, `peak`), speed windows,
  liked/disliked acceleration shapes, and private attitude notes. Satisfaction-window phases can
  change preferences mid-act; Fluttershy, for example, becomes more demanding above 75%.
- **Reactive dialogue** — Lines are scheduled across the act and generated on demand, with
  reactions to speed, depth, stroke shape, and prolonged slow pumping. Climax, early-stop, and
  pose-2 finish reactions always queue. Generated moans are not used; only a cached “Mm.”
- **HUD** — Three vertical meters for penetration, satisfaction (debug only), and stamina.
  Stamina starts at 400 and drains one per pump.
- **Camera and motion** — Depth-driven forward/back travel with no artificial bob, eased spring
  motion, and reduced look sensitivity while the act owns the mouse.
- **Presentation** — Blush, half-lidded eyes, pinned ears, tail movement and flicks, flank jiggle,
  pump audio, and spread/droop/jitter wing motion for winged ponies.
- **Aftermath** — Pose 1 cuddle afterglow; pose 2 automatic withdrawal with a spoken reaction.
  A short aftercare state holds the pony in place with a raised, gently flicking tail. Rewards
  are granted only at climax.
- **Memory and witnesses** — Intimacy is recorded in the game’s second-person memory style, and
  nearby awake adults remember witnessing it.

## Controls

| Input | Action |
|---|---|
| `L` | Start an available encounter |
| Mouse ↕ | Pump during the act |
| `Q` | Stop before climax / end afterglow |
| `F` | Flight (never pumps) |
| `Ctrl+Shift+D` | Toggle DEBUG LOGS (also gates the satisfaction meter) |
| `F8` | Print offer, gate, and bed debug report |
| `F9` | Preview the pose-1 presentation |

## Requirements

- Home: Equestria `0.1.1-maredev`.
- Desktop only; VR is deferred.

## More detail

- [`PREFERENCES.md`](PREFERENCES.md) — pump, scoring, depth/speed/shape, phases, and boredom rules.
- [`ROTATION.md`](ROTATION.md) — camera, pose, and restore ordering.

The full design and status record lives outside this mod repo at `../../unfplap.md` in the game
project.
