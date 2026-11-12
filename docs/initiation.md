# Proactive requests

The proactive-request service is the one controller that lets a mare ask Anon for sex. It never
starts the act: `Y` remains the only act-start path. This file is the single technical contract;
other docs link here.

## Scope

This contract covers:

- the quiet gate that decides when an automatic request may begin;
- admission: the per-mare cooldown, the heat shortening, the short retry and the scan interval;
- candidate discovery for a cuddle, a bed and a standing offer, and the weighted pick;
- the offer privacy rule and the public-offer override;
- the walk to Anon or to the bed front, and the arrival settle;
- the ask line, the two reminders and the deadlines;
- the private consent classification, the one clarification and the decline;
- the standing presentation, the invitation and its give-up line;
- the cooldown/retry split on every closing phase and the shared cancellation path;
- the world-context situations, the debug actions and the lab path.

It does not cover act eligibility (see `docs/eligibility.md`), act readiness or thrust
(`PREFERENCES.md`), pose or camera (`ROTATION.md`), or the act's own dialogue cues and prompts.

## Architecture

| File | Role |
|---|---|
| `initiation.gd` | facade: scan, admission, candidate assembly, the live episode, phase dispatch, cooldown IO and the typed `Episode`/`Candidate`/`ForceResult` |
| `initiation/facts.gd` | pure typed `Request`: the plain values the rules and wording read |
| `initiation/policy.gd` | pure rules: timers, cooldowns, privacy, wording mode, prompt schedule, pose choice, weighted pick and the phase tables |
| `initiation/prompts.gd` | pure wording: ask, reminders, clarification, invitation, give-up lines and the situation texts |
| `initiation/conversation.gd` | scene adapter: the only reader of the conversation director, the consent classifier and the world context |
| `initiation/venue.gd` | scene adapter: the only reader of navigators, posture, the bed search and the privacy scan |
| `docs/initiation.md` | this contract |
| `tests/initiation/` | pure rules, facts and wording suites, plus the facade API suite |

The purity boundary is deliberate:

- `facts.gd`, `policy.gd` and `prompts.gd` have no `Node`, tree, time, file, `Settings`, scene or
  game preload. They take plain values and return plain values or strings.
- `conversation.gd` owns `director._player_text`, `_held_text`, `_now`, `characters`, `speech`,
  `player_approaches`, `group`, the `transcript` connection, the classifier calls and
  `world_context.record`.
- `venue.gd` owns `Navigator` fields (`command_owner`, `wander_enabled`, `command_speed_limit`,
  `command_pace_target`, `reserved_by`, `_has_target`), `request_posture`/`posture_status`, the
  bed rest (`_front_for`, `_mare_fits`, `_guest`, `_sleeper`, `accept`), the player seat and
  `couch_sleeping`, the house lookup, the `couches` group and `WorldLayout`.
- The facade is the only file that preloads `eligibility.gd`, `act_history.gd`, `cycle.gd`,
  `settings.gd`, `memory.gd`, `relationship_cue.gd`, `act_face.gd` and `rest_control.gd`.
- No file outside `initiation.gd` and `initiation/` preloads `initiation/*`.
- `main.gd` creates the service (`setup(self)`) and drives it: `tick`, `reset`, `cancel_for`,
  `force` and `offer_target()`. `runtime.gd` exposes `cuddle_active()` for the scan.

## Internal API

`main.initiation`:

```gdscript
enum Phase { NONE, APPROACH, ARRIVE, ASK, PRESENT, INVITE, BED_APPROACH, BED_LEAD, BED_WAIT }

class Candidate:   id, runtime, pony, pose, source, bed, rest, front, private, cuddle,
                   bed_invite, weight, forced
class Episode:     serial, phase, candidate fields, timers, consent/reply/nav blocks
class ForceResult: ok, id, pose, reject

func setup(main_node: Node) -> void
func tick(delta: float) -> void
func reset() -> void
func cancel_for(pony: Node) -> void
func force(runtime: Node, pose := "") -> ForceResult
```

`force()` is the debug/lab entry: it keeps the paused-tree bypass and the eligibility and scene
gates, and returns the comma-joined reject reason in `ForceResult.reject`.

Adapters (internal, called by the facade):

```gdscript
conversation: hook, unhook, quiet, idle, player_reacted, last_player_text, player_name,
              pony_speaking, begin_greeting, queue, cancel_keys, classify_offer,
              cancel_key, cancel_scope, record_situation
venue:        player, mares, pony_id, region_of, camera_forward, private_at_player,
              cuddle_privacy, privacy_report, can_approach, stand, ensure_stand,
              claim_nav, nav_owned, nav_has_target, stay, release_nav, find_bed_for,
              rest_front, accept_bed, player_in_bed
```

## Data ownership

| Data | Stored where | Owner |
|---|---|---|
| Request cooldown (`request_times`) | `Mods.state("unfplap")` | this facade |
| Live episode, cuddle edge, one-ask-per-cuddle, retry deadlines | memory only | this facade |
| Lover bond | `Mods.state("unfplap").sex_bonds` | `sex_bond.gd` |
| Act history and its offer cooldown | `Mods.state("unfplap").act_history` | `act_history.gd` |
| Cycle phase | runtime, derived from the day | `cycle.gd` |
| Per-mare consent and public-offer flag | resolved verdict | `docs/eligibility.md` |
| Relationship, stage, love, willingness | game save | base game |

Rules:

- No eligibility block and no request block is written to `settings.json`.
- The cooldown is the only persisted value, and only the facade reads or writes it.
- The episode never survives a world close; `reset()` closes it and clears the session maps.

## Episode

One episode at a time. Each phase waits on its own condition:

| Phase | Waits for | Moves to |
|---|---|---|
| `APPROACH` | arrival within `2.8 m`; cancels on quiet loss, region change, Anon moving `5 m`, nav ownership loss or `35 s` | `ARRIVE` |
| `ARRIVE` | `2 s` settle with Anon still in range | `ASK` |
| `BED_APPROACH` | bed front within `1.4 m` or the navigator finishing its path; `25 s` cap | `ASK` |
| `ASK` | the deadline, an answer, or a physical yes | `PRESENT`, `BED_LEAD`, `INVITE`, or closed |
| `PRESENT` | the runtime's presentation and its settled check; `5 s` turn cap | `INVITE` |
| `BED_LEAD` | the bed front; `25 s` cap | `BED_WAIT` |
| `BED_WAIT` | Anon reclined on the offered bed and the native rest accepting her | `INVITE` |
| `INVITE` | `Y`, a lost presentation/bed, or `60 s` | closed, with a give-up line on timeout |

Timers come only from `initiation/policy.gd`; `tests/initiation/test_policy.gd` locks every value.

## Admission

An automatic scan runs every `0.5 s` and needs a quiet moment:

- not paused, no menu panel with a free cursor, Anon not locked, flying or knocked down;
- the director idle, not in a group exchange or an approach, not hearing, and background AI
  allowed (`AI_CONFIG.background_allowed`, i.e. AI usage Full);
- no character chat in the last `45 s`.

Per mare, the scan then requires:

- the runtime idle (`state == 0`) and a stable id;
- the eligibility offer verdict (`Mode.OFFER`);
- the cooldown: `ACT_HISTORY.offer_cooldown()` since `request_times[id]`, quartered in heat;
- the `30 s` retry deadline left by a failed walk-over or an unavailable ask.

A cuddle rising edge clears that mare's cooldown and permits one ask per cuddle. The debug
actions bypass the quiet, cooldown, retry and AI-usage checks but keep the eligibility and scene
gates.

## Candidates

| Candidate | Requires |
|---|---|
| Cuddle | an active cuddle, the bed under her, the offer gate, and `main.offer_target()` naming her |
| Bed | a free bed within `10 m` on the same floor and region, a finite front spot, the offer gate |
| Standing | the offer gate, a free navigator in Anon's region, and Anon within `24 m` |

Weight is `verdict.offer_weight` from act history. Cuddle candidates are preferred outright;
otherwise the pick is weighted. When both poses fit a non-cuddle offer, the pose is a coin flip;
one fitting pose is used. A bed invite walks to the bed front, not to Anon.

## Privacy

```text
offer_private  = public_offer or house_alone or not others_near
cuddle_private = house_alone if indoors else not others_near
public_offer   = heat or (features.act_public_offer and consent.public)
```

"House alone" excludes the offering mare and counts every other mare in the house; outdoors,
`others_near` counts every other mare within `30 m`. A public offer is still an offer; the act
itself does not require privacy. The throttled `request privacy ...` log prints the player
position, the house, every mare in the house, every mare within `30 m`, the target label, the
public-offer flag and the resolved result.

## Ask

The initial line uses `begin_player_greeting` when the director has it, otherwise one
`queue_generated_intent` row keyed `unfplap:request:<id>:<serial>:ask`. It records the
`situation` world-context event and, for a private standing offer, sets the request face.

- Reminders are queued at `12 s` and `24 s`, one each, and never repeat a key.
- The no-reply deadline is `60 s`; after an answer it is `45 s`; after a clarification `30 s`.
  A pending classifier or a speaking mare extends it by `5 s` instead of closing.
- Lying down on the offered bed after the `2.5 s` grace counts as a physical yes.
- The ask closes when the player moves past `8 m` or `can_offer()` turns false.

## Consent

A private offer waits for Anon's answer. `CONSENT.local_intent()` resolves clear yes/no first;
anything else becomes one bounded classifier request (`offer:<id>:<serial>`) that starts only
when the director is idle again, so it never runs beside the reply to the same line. An unclear
answer gets exactly one clarification line and then gives up. A decline records the declined
situation and closes with the full cooldown.

An accept records the accepted situation, then:

- standing: `present_standing()` and the presentation phase;
- cuddle: the invitation line in the existing bed;
- bed: the walk to the bed (`BED_LEAD`) and the wait for Anon to lie down.

## Presentation and invite

The standing presentation is turned with `present_standing()`; the invitation waits for
`presentation_settled()` or the `5 s` cap. If movement breaks the present, the controller
re-presents twice before ending an offer the player already accepted. The invitation is queued
once and is valid only while the phase is still `present`, `invite` or `bed_wait`, the
presentation/bed state holds and `can_show_start()` passes. A `60 s` invitation timeout queues
one short give-up line and closes with the full cooldown.

## Cancellation

`_cancel_episode(set_cooldown, reason, keep_rest)` is the one close path:

1. cancel the `offer:` classifier scope;
2. clear the request face and the presentation;
3. release the bed rest unless `keep_rest` (a `Y` start keeps it);
4. hand the navigator back with its saved owner, wander, speed and pace;
5. set the full cooldown or the `30 s` retry from the phase tables;
6. cancel every queued director row for the episode;
7. clear the episode.

`cancel_for()` runs before a normal `Y` start and keeps the bed rest; `force()` closes any live
episode first; `reset()` closes it and clears the session maps on a world close.

## Prompts

`initiation/prompts.gd` builds every line from a `FACTS.Request`. The facade supplies
`relation_note` (from `memory.cue_facts` + `relationship_cue`), `history_note` (from
`act_history.ask_note`) and `face_note` (`act_face.prompt_note("ask"|"invite")`, only with
`features.act_faces`). Wording mode is decided once per builder by
`policy.wording_mode(private)`: `free` speaks plainly and asks clearly, `indirect` hints while
other ponies are around. The heat line is appended only in heat and is empty otherwise. Prompts
never suggest `[mood:...]`; the face hint is the only expression guidance.

## Debug and lab

- **Trigger bed offer** / **Trigger standing offer** call `force()` and report the reject reason.
  They need the settings page closed to advance.
- `request force ...`, `request ask ...`, `request privacy ...`, `request consent ...`,
  `request reminder ...`, `request invite ...` and `request end ... phase=... reason=...` are the
  debug log lines.
- The lab runs with `ai_usage=talk`, so automatic offers do not fire; use the debug actions.

## Tests

- `tests/initiation/test_policy.gd`: the timer lock, cooldowns, heat, retry, privacy, wording
  mode, prompt schedule, pose choice, weighted picks and the phase tables.
- `tests/initiation/test_facts.gd`: the typed request defaults and independence.
- `tests/initiation/test_prompts.gd`: ask, public/private wording, heat, notes, face hint,
  invitation, reminders, give-up lines and the situation texts.- `tests/initiation/test_initiation_api.gd`: the facade's privacy gathering, heat override, the
  local yes/no consent flow, the typed `ForceResult`, `cancel_for` and `reset`.
- `tests/test_consent_classifier.gd`: the shared classifier's local and strict reply parsing.
- `tests/test_source_hygiene.gd`: the pure-core boundary, the facade-only preload rule, the
  adapter private-access boundary and this contract's presence.

## Known limits

- The conversation adapter reads stock director fields (`_player_text`, `_held_text`, `_now`,
  `characters`) and the venue adapter reads stock navigator and bed-rest fields. A game change can
  remove them; every read is guarded and the offer simply stops.
- `SharedBed.accept()` is the stock invitation path; it can refuse for up to five one-second
  retries before the offer gives up.
- A classifier that is unavailable resolves as `unclear`, which costs the one clarification.
- A request is not persisted: a save during an episode resumes with no episode and no navigator
  lease.
- Automatic offers need AI usage Full; the lab's debug actions are the supported way to see one.
- The standing offer requires an adult mare who is an eligibility target and a free navigator;
  another pony's task or lease is a reason to skip her, not to wait.
