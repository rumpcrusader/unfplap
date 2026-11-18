# Poses and skeleton

This is the contract for the act's pose system: the pose document and its static capability table,
the live session state machine, the authored edges and their per-channel tracks, the v7 authored
assets and their placement, the per-pose settings and the post-act posture. The act camera and shot
are `docs/camera.md`; the anatomy part is `docs/anatomy.md`;
the caress paths and palm holders are `docs/hands.md`. The pose tuning rows are the **Poses**
settings tab's Debug block; its two player rows are **Enable Oral** and **Enable Anal**; see
`docs/settings.md`.

## Ownership

`poses/service.gd` is the pose session facade. It owns the live state machine (`IDLE`/`ENTERING`/
`STEADY`/`TRANSITIONING`/`EXITING`), the active edge and its clock, the per-pose configs and the
target snapshot, the skeleton pose modifier, the authored bases, the bed and ground frames and their
follow, the extra modifiers (tail, tail lay, body sway, prone sway, ear twitch), the pony bone
snapshots, the pose rig check, the pose diagnostics, the retarget hook and the pose-scope teardown
steps. The runtime owns the act state, the start ordering and the one teardown ledger; it binds the
session and reads its `pose()`, `pose_config` and `bed_frame` for
the start/teardown and the standing gap, not as the consumer contract. Presentation modules read
the pose view through `shared/act_facts.gd`.

`poses/pose_rig.gd` is the bone cache and body-relative axes. `poses/tail_chain.gd` resolves the
visible tail chain: the devkit hair chain `mTail1..mTail6` when present, otherwise the fitted body
chain `pony_tail_01..pony_tail_05`. `poses/authored_pose.gd` loads a
pose spec row's `asset` document (version 7 with the version 6 migration path); the missionary and
standing rows own their files and a base row supplies the asset to its internal inheritors.
`poses/oral_turn.gd` is the pose-owned standing oral actor/frame turn,
`poses/standing_oral_recipe.gd` its procedural delta and `poses/face_contact.gd` the bed face-sit
contact driver. `shared/pose_catalog.gd` owns the pose ids
and the `POSE_KEYS` schema; the shipped per-pose values live under `default.poses` in
`settings/defaults.json`.
`poses/service.gd` owns the live pose. `shared/act_motion.gd` is pure lean-travel and pose-action
math; `camera/service.gd` owns the camera and lean state.

`shared/pose_specs.gd` is the static pose capability table: family, frame, driver, settings group,
the ten profiles, forms, views, the scene block, the `start` block and the public/offerable flags.
The scene gate and
the request service enforce those rows; a pose is offered only when `offerable`, supported by the
live form and view, and its `scene.sources` allows the act source. `poses/pose_spec.gd` is its typed
wrapper and validator,
`poses/transition_spec.gd` the typed edge wrapper and its one validator, and `poses/registry.gd`
the cache and catalog check for both; all three are private to `poses/`. `shared/pose_view.gd`
is the scene-free read model for one pose: the identity, the spec profiles, the live config and the
contact and facing mirrors.

## Pose assets

A pose row's `asset` names its authored document under `poses/`; an internal row may leave it empty
and inherit it through its `base` chain, or own its asset. The shipped internal rows inherit. The
scene gate's `pose_asset`/`pose_rig` rows read the resolved
document. `poses/authored_pose.gd` is the one loader; it reads version 7 and the version 6 bed-space
migration path, and never converts a pose per frame. The two offerable assets are parsed at world
ready, under the loading cover, so the idle hint's `pose_asset` row does not load them inside its
first scan.

Version 7 stores `space: "local_rest"`, the pose's `frame` (`bed` or `ground`), the `rig` name,
version and bone count, the bake `reference` (`size`, `body_scale`, the config the base was authored
at), one `anchor` (the `pony_hips` global pose in frame space, a `contact` point in the hips frame
and the `support` height), the armature `root`, the body bone deltas, and optional `anon`, `shots`,
`bed` and `variants` blocks.

- **`local_rest` bones.** A bone entry is a delta from the bone's rest local transform:
  `delta = rest.affine_inverse() * pose`, and the runtime writes `pose = rest * delta`. At rest the
  delta is identity, and every body bone is present in the file, including the ones left at rest.
  The head is not one of the 30: the live pose's recipe owns it. The standing recipe applies the
  reference bow and chin; the missionary recipe resets it and the gaze solve aims it at Anon.
- **Placement.** The frame is placed from the hips anchor and the contact, not from a scaled asset
  origin. At body scale `s` the root is scaled about the anchor and lifted so the contact stays on
  the support; the live body scale is applied once at the world root, so the skeleton-space root
  pose stays orthonormal. `place_origin()` is the same rule for the Anon act body and the authored
  shots.
- **Variants.** A variant is keyed by `size_name` with its own `body_scale`; an unknown name snaps to
  the nearest variant scale. It replaces `anchor`, `root`, `anon` and `shots` and merges
  `pony.bones` per bone. `space`, `frame`, `rig` and `reference` belong to the base and may not be
  changed by a variant. v1 ships no variants.
- **Version 6.** Bed space with absolute local bone poses and the uniform `bed_frame * (pony_frame ×
  body_scale)` placement. It is read for one release and is refused for a ground pose; nothing new
  is authored in it.

## Authoring and the bake

`tools/pose_lab.gd` is the authoring scene. `pose_id` derives the shipped `poses/<id>_pose.json`
path, `frame_kind` selects a bed or ground pose, and `anon_mode` selects whether the Anon act body
is exported. Ground mode adds a floor and a `Contact` marker, hides the bed and the shot nodes and
derives the frame from the pony root. **Save pose** exports the hand-posed scene as v7;
**Bake v7** applies the reference recipe at the effective reference config and writes the standing
asset; **Compare baked vs recipe** prints the worst joint error. A preview other than 1.0 refuses
to save.

`tools/pose_export.gd` is the command-line twin: it round-trips the shipped asset, runs the moved
bed-frame apply and the four-size body check, and prints PASS/FAIL. `--out <path>` writes a scratch
asset, `--check` leaves the shipped file alone and `--pose <id>` selects another shipped pose
(`missionary` is the default).

`tools/pose_bake.gd` is the standing bake. `capture_pose()` records the current pose as a v7
document, `capture_asset()` applies `apply_reference()` at the reference config to the rig's rest
pose first, `write_asset()` writes the deterministic JSON (test and fixture paths are refused), and
`compare()` applies the baked asset and reports the worst error against the recipe.

`tools/pose_runtime_check.gd` runs the missionary recipe on the real body rig against one shipped
asset in a moved bed frame and checks that the overlays preserve the authored joints; `--pose <id>`
selects the asset and `missionary` is the default. Its shape checks are per pose: the missionary
rests low with her head toward the pillow, and the bed face-sit rides above the mattress with her
shins down and her head over his chest.

## Bed face-sit

`poses/bed_facesit_pose.json` is the internal bed face-sit asset. It is authored in the bed frame;
its bone entries are v7 `local_rest` deltas. It is kept out of offers, settings and
`CATALOG.all()`; the debug **Pose: face-sit** action is its only trigger. The arrangement is Anon
on his back with his head under her hips; she kneels astride his head with her knees and shins on
the mattress and her vulva on his mouth, and leans forward over his chest. The `anchor` is her
`pony_hips` pose, its `contact` is the shin/knee support on the mattress, and `support` is the
mattress top, so the v7 anchor/contact rule carries the four Pony size presets. The `anon` block is
the full `Anon3` block: the bed-frame placement and the v7 local-rest bones; the five authored
shots frame Anon's eye under her and are read by the existing bed camera. There are no variants
and no `provisional` flag. The asset's `--pose bed_facesit --check` round-trip and the
`pose_runtime_check` face-sit case are the automated proof; the arrangement is authored through
`tools/pose_lab.gd` and saved as this asset.

- The bake input is the **body rig's rest pose**, plus `apply_reference()` at the reference config.
  The game's own settled standing pose is `pony_gait_profile.gd`'s `standing`, bound from the same
  rest (`standing = rest.duplicate()`, returned at zero gait blend), so this is exactly the pose the
  act's old procedural recipe was applied to. The bake never reads a live capture: at `begin()` the
  gait is still blending, and a mid-step frame would be frozen into the base.
- `--write` writes `poses/standing_pose.json`; `--check` re-bakes in memory and fails when the
  checked-in asset is stale. The asset is tracked; there is no fixture.

## Typed view

The body wrappers that move with the pose (`poses/missionary_anon.gd`, `poses/standing_anon.gd`,
`poses/standing_presentation.gd`) and the pose modifiers the session installs (`poses/skeleton_pose.gd`,
`poses/tail_pose.gd`, `poses/tail_lay.gd`, `poses/body_sway.gd`, `poses/prone_sway.gd`, `poses/ear_twitch.gd`) read
`shared/act_facts.gd`, never the runtime node. The view carries the pose config, the presentation config,
the per-mare profile, the pose id and state, the live depth and bed frame, the scene handles, the
lean and thrust values and the callbacks they call back through. `pose_config` is one live
dictionary for the session: `set_pose_config()`, `sync_standing_config()` and
`sync_missionary_config()` merge into it in place, so the pose modifier, `view.pose_config` and
the standing camera's cached config all alias the same object. `poses/body_sway.gd` publishes its
world-space sway through `facts.standing_sway_offset`; that field is the one owner and the
standing Anon controller reads it from there. The session binds `facts`, `perf` and
`log` for the modifiers. The field and callback contract is `docs/act_facts.md`; a pose module
that reaches into the runtime fails `tests/test_source_hygiene.gd`.

`shared/pose_view.gd` is the pose read model the session fills and clears. It holds the identity
and support fields from the registry, the ten spec profiles by reference, the live config (the same
object as `view.pose_config`) and the per-tick contact and facing values. `pose_state` is `STEADY`
while the pose is live, `TRANSITIONING` while an edge runs, and `EXITING`/`IDLE` on release; the
pose-scope leave steps keep it `STEADY`. During an edge, `from_id`/`to_id`, `edge_id`, `edge_t`,
`weight`, `from_config` and `to_config` carry the transition: `from_config` is the live config, the
to side is the session's target snapshot. `contact_kind` is the one contact source (`opening`,
`mouth`, `face` or `none`); it starts at the spec's base kind, moves on an edge's `contact` switch
and settles on the target's kind. The `face` kind's provider is the act body's `mouth_point()` on
the anatomy bridge; its driver is `poses/face_contact.gd` and the anatomy act parks her part. `contact_target` is the
pose turn's live anchor, and `facing`/`facing_amount` its live frame; the standing camera reads
both every physics tick. The
view carries no compatibility fields: `id`, `family`, `frame`, `settings_group`, the profiles, the
live config and `contact_kind` are the whole pose source.

## State machine and edge math

`poses/pose_state.gd` is the pure state and edge module. It is not a service: it holds no scene,
reads no settings or files and preloads only `shared/pose_view.gd` for the state constants. It
supplies the transition table and the edge clock the session's request and tick paths use (wired in
the session).

The transition table is:

| From | Event | To |
|---|---|---|
| `IDLE` | `begin` | `ENTERING` |
| `ENTERING` | `entered` | `STEADY` |
| `STEADY` | `request` | `TRANSITIONING` |
| `TRANSITIONING` | `complete` | `STEADY` |
| `ENTERING`, `STEADY`, `TRANSITIONING` | `exit` | `EXITING` |
| `EXITING` | `released` | `IDLE` |

Every other pair is a no-op: `begin` outside `IDLE`, `entered` outside `ENTERING`, `request`
outside `STEADY`, `complete` outside `TRANSITIONING`, `exit` in `IDLE`/`EXITING`, `released` outside
`EXITING`, and any unknown event. The service reports the refusal; the table only owns the state.

A request returns the first refusal in this exact order: `same`, `bad_phase` (the act is not
`ACTIVE`), `busy` (a transition is running), `not_steady`, `no_edge`, `unsupported_form`,
`unsupported_view`, `refused` (features or consent), `missing_asset`, `locked`, then `ok`.
`same` is checked before the phase, so a no-op target is never reported as `busy`.

One edge is a `Run`: per-channel tracks, one clock and the interrupt policy. A channel is `hold`
(weight 1, settled), `blend`/`delta` (eased 0→1 over its own window, or the edge duration),
`switch` (fires once at its `at`, reported by name) or `lock` (a policy signal, weight 1). `path` is
accepted as `blend` until an edge authors it. The `base` channel owns the view weight; an absent or
held base is 1.0. A constraint `"channel after other@seconds"` is a floor on the channel's start
(`other.start + seconds`), never a shift of the other channel; a cycle refuses the edge. The edge
duration is the base and a longer channel or switch extends it.

`Run.tick()` reuses the `events` and `switches` arrays and the channel records: the caller drains
them after a tick and before the next one. The `at: 0` events and switches fire on `tick(0.0)`.
Each event fires once, in authored order. `complete()` is true only after every channel settles and
the clock reaches the duration; a tick after completion does not fire anything again. The module
copies `interrupt.climax`/`interrupt.teardown` (`hold`/`abort` by default) but never acts on them.

`start_edge()`/`Run.start()` accept only an edge whose `id`, `from`, `to` and `channels` are
present, whose endpoints match the requested pair, whose channel kinds and constraint references
are known, and whose timing resolves; anything else returns null.

## Typed edges and the registry

A pose transition is an authored document at `poses/transitions/<from>__<to>.json`, imported only
through `poses/transition_spec.gd` and cached by `poses/registry.gd`. The filename stem is the edge
id and must equal the document's `id`, which is exactly `<from>__<to>`; both endpoints name spec
rows in the same family and `from` and `to` differ. The document's `version` is 1.

Top-level fields: `id`, `from`, `to`, `phases` (the act phases the edge may start in: `active`,
`climax`, `afterglow`), optional `requires`, optional `duration`, optional `easing` (`linear` or
`smoothstep`), `channels`, optional `constraints`, optional `events` and optional `interrupt`.
Unknown top-level keys are additive and ignored.

`requires` holds only `features`, `consent`, `forms` and `views`. `features` is a list of
non-empty strings; the session checks them when the state machine is wired. `consent` is a string,
and an empty string means none. `forms` and `views` are lists of the spec table's values, each
supported by both endpoints when the endpoint rows declare those lists. There is no settings or
eligibility vocabulary check here: the validator never reads `Settings`.

`channels` is non-empty, and its names are `base`, `anon`, `contact`, `camera`, `controls`, `audio`
and `presentation`. Each channel has a `kind`:

- `hold` settles at weight 1 from the start.
- `blend`, `delta` and `path` ease from 0 to 1 over their own duration or the edge duration. `path`
  is accepted as `blend` until an edge authors it.
- `switch` fires once at its required `at` and reports its channel name. Its optional `set`,
  `profile` and `to` payload strings are data for the consumer.
- `lock` is a policy signal at weight 1, with optional `allow`/`block` string lists and `set`.

An absent channel means `hold`. Unknown extra payload keys are additive and ignored.

`constraints` are `"channel after other@seconds"` start floors: the channel may not start before
the other channel's start plus the delay. A reference outside the edge or a cycle refuses it.

`events` are dictionaries with `at`, `kind` (`status`, `speech_stop`, `viseme`) and, for `status`
and `viseme`, a non-empty `value`. They are sorted by `at`, because `Run.tick()` stops at the first
future event and an out-of-order list would hide the later events.

`interrupt.climax` is `hold`; `interrupt.teardown` is `abort` or `finish`. The module exposes the
policy and never acts on it.

`poses/transition_spec.gd` is the one edge validator. It checks the filename/id rule, the endpoints
and their family, the phases, the `requires` block, the duration and each channel payload, the
constraints, the events and the interrupt policy, and it collects every problem instead of stopping
at the first. Only after every structural check passes does it ask `pose_state.gd` to start the
document; a null start is one generic error that the channel timing or an `after` constraint does
not resolve.

`poses/registry.gd` reads the directory once, on the first `spec()`, `edge()` or `validate()` call,
and never on a tick: sorted `DirAccess` listing, one `FileAccess` read and one `JSON` parse per
document, the validator, then one cached wrapper per edge id. A bad document stays out of the cache;
`validate()` returns its filename-prefixed errors after the spec/table errors. The registry is
private to `poses/`, and the session facade has no file access.

The shipped debug pair is `standing__standing_test.json` and `standing_test__standing.json`. Both
hold `base`, `anon`, `contact`, `camera` and `audio`, switch `controls` and `presentation` at the
start, and fire one `status` event (`test` forward, `standing` back). Both switches spell out
`at: 0`; `pose_state.gd` refuses a switch without `at`. The held channels are deliberate: the pair
is the current proof of the state machine, the channel records, the switch firing and the
no-full-teardown rule, and no channel moves the body.

The oral pair is `standing__standing_oral.json` and `standing_oral__standing.json`. The forward
edge requires the `anatomy_oral` feature, `consent: "oral"`, both forms and views; it runs for
`1.6 s` with the base delta easing over the whole edge, switches
`contact` to `mouth` at `0.9` (floored by `contact after base@0.55`), switches `audio` to `oral` at
`0.0`, locks `controls` to `oral`/`pose_back`/`end`, and fires `speech_stop`, `viseme D` and a final
`status oral`. The reverse edge requires only the feature, both forms and both views, returns
`contact` to `opening` at `0.0` and `audio` to `standing`, allows only `end` during the lock, and
fires `status standing` at its end. The reverse edge has no consent, so a return is always
allowed. Neither edge calls an act exit; the interrupt policy is `climax: hold` and
`teardown: abort`.

`standing_oral` is the matching internal spec row. It inherits `standing` (a base, no driver of its
own), carries the procedural delta `poses/standing_oral_recipe.gd`, uses the standing settings
group and presentation, is `public: false` and `offerable: false`, and has no `default.poses` block.
The session starts the oral turn on the forward request, keeps it through the settled pose, and
restores the captured root and facing on the reverse completion or the one act exit.

The bed face-sit pair is `missionary__bed_facesit.json` and `bed_facesit__missionary.json`. The
forward edge requires human and desktop, runs for `1.6 s`, blends the base and
the authored Anon block over the whole edge, switches `contact` to `face` at `0.9` (floored by
`contact after base@0.55`), holds the source camera shots, locks `controls` to `end`, keeps the
missionary presentation and fires one final `status facesit`. The reverse edge runs for `1.2 s`,
returns `contact` to `opening` and `presentation` to `missionary` at `0.0`, locks `controls` to
`end` and fires `status missionary` at its end. It requires only human and desktop, so the return is
always available. Neither edge calls an act exit; the interrupt policy is `climax: hold` and
`teardown: abort`.

`bed_facesit` is the third internal spec row. It owns `poses/bed_facesit_pose.json`, reuses
`poses/missionary_recipe.gd` and the missionary settings group, presentation, modifier, hands,
audio and camera profiles, has its own `facesit` control set (`thrust`, `lean`, `caress`, `end`),
contacts `face`, is `public: false` and `offerable: false`, and has no `default.poses` block. Its
HUD label is `Face-sit`; it appears in `CATALOG.every()` only.

`standing_test` is the debug internal spec row. It inherits `standing` (a base, no driver of its
own, no delta asset), is `public: false` and `offerable: false`, has no `default.poses` block, and
appears in `CATALOG.every()` only: it is not in `CATALOG.all()`, the API, the offers or the settings
templates. The spec base rule allows an empty `driver` only when a base owns the geometry. A base
must not be the row itself; when the table is supplied it must exist in the same family, and its
chain must not revisit a row.

The spec table and the edges are data. The session builds `missionary` and `standing` in `begin()`
and starts an authored edge only on a request; the debug pair's player-visible proof is the Debug
**Pose: test variant** action.

## Start block

Every row declares `start`, the pose's act-start contract:

```gdscript
"start": {"mode": "key", "setup": "bed_stand_up"},
```

`mode` is `key` or `auto`. `key` waits for the act key; `auto` lets a trigger call the same start
path without it. Every shipped row is `key`. The `auto` flag is stored on the offer, never acted on
by the start path: the trigger owns its timing.

`setup` is the closed placement vocabulary `bed_stand_up`, `bed_keep_lying` or `standing_place`.
`runtime.start()` dispatches on this name (`_run_start_setup`) and never on a pose id, so a new pose
adds a row, an asset and a recipe, not a start branch. The adapters and the start order are
`docs/runtime.md`.

| Pose | mode | setup |
|---|---|---|
| `missionary` | `key` | `bed_stand_up` |
| `standing` | `key` | `standing_place` |
| `standing_test` | `key` | `standing_place` |
| `standing_oral` | `key` | `standing_place` |
| `bed_facesit` | `key` | `bed_stand_up` |

`bed_keep_lying` has no shipped consumer yet: the riding pose is its first intended user. The
focused `tests/poses/test_start_setup.gd` proves the vocabulary, the validator, the helpers and the
runtime dispatcher with a synthetic `auto`/`bed_keep_lying` row; that row stays out of the shipped
table and the catalog. `poses/pose_spec.gd` rejects a missing block, an unknown mode or an unknown
setup, and `poses/registry.gd`'s `check_table()` covers every shipped row.

## Session requests and ticks

`poses/service.gd` owns the live state machine, one running `Run` and the target snapshot.
`begin()` enters `ENTERING`, fills the start view and settles `STEADY`; `release_pose()` exits
through `EXITING` to `IDLE`; the pose-scope leave steps keep `STEADY`. A failed `begin()` leaves the
state unchanged. For a ground view, `begin()` captures the pony root's ground frame before it
installs the modifier; `leave_pose_start()` and `release_pose()` clear it. `sync_ground_frame()`
follows the root's position and rotation each tick.

`request_pose(target_id, trigger, context)` returns the `PoseResult` `{ok, code, edge, reason}`. It
checks the target against the act phase, the player's form/view, the edge requirements and the edge
lock in the state module's order: `same`, `bad_phase`, `busy`, `not_steady`, `no_edge`,
`unsupported_form`, `unsupported_view`, `refused`, `missing_asset`, `locked`, `ok`. A refused
request changes nothing. The request context supplies `act_state` (the runtime passes its state),
`features`, `consent`, `forms`, `views` and `locked`; absent values default to the act's live facts
and the player's form/display.

The checks, against the target spec and the edge:

| Key | Rule |
|---|---|
| `form_ok` | the target's `forms` intersects the player's forms; a non-empty `requires.forms` also must |
| `view_ok` | the same for `views` |
| `features_ok` | every `requires.features` entry is on in the request features |
| `consent_ok` | `requires.consent` is empty, or the request consent equals it |
| `asset_ok` | the target spec exists and at least one of `base`/`delta`/`driver` is non-empty |
| `locked` | the request's `locked` flag |

On an accepted request the session caches the target spec and its settings snapshot by the spec's
`settings_group` (`standing_test` and `standing_oral` use the standing pose and presentation blocks
and must never be passed to the settings read as a group of their own), builds the target config
from that group plus the presentation, starts the edge, enters `TRANSITIONING` and fills the view:
`fill()` carries the target identity and profiles, then `from_id`/`to_id`, `edge_id`, `edge_t`,
`weight`, `from_config` (the live config) and `to_config` (the target snapshot) make the transition
explicit. `view.id` follows the filled target; the runtime's `pose_id` is only the act's start
identity for the start sequence, logs and teardown.

`tick(delta)` advances the run, writes `edge_t`/`weight`, drives the oral turn from the same weight,
hands the weight to the pose evaluator, applies each fired `contact` switch and each `speech_stop`/
`viseme`/`status` event, and on completion returns to `STEADY`, sets the target's base contact kind,
adopts the target snapshot into the live `pose_config`, points both sides of the config and the pose
node at it, clears the edge fields and drops the target. The steady tick allocates nothing: no
duplicate, no settings read and no file access, and a tick after completion is a no-op. The oral
turn's steady tick also allocates nothing: it reuses its vectors and writes fields.

`shared/act_commands.gd` is the command vocabulary, and `shared/pose_specs.gd`'s `CONTROL_SETS`
maps each pose's `controls.set` profile to its allowed ids:

| Pose | Allowed ids |
|---|---|
| `missionary` | `thrust`, `lean`, `caress`, `kiss`, `hole`, `finish`, `end` |
| `standing` | `thrust`, `lean`, `caress`, `kiss`, `oral`, `hole`, `finish`, `pose_back`, `pose_forward`, `end` |
| `standing_test` | `end` |
| `standing_oral` | `oral`, `pose_back`, `end` |
| `bed_facesit` | `thrust`, `lean`, `caress`, `end` |

`request_command(command_id)` is the one allow check: an empty or unknown id is refused, `end` is
reserved and always allowed, and otherwise the id must be in the active view's `controls.set`
profile. A missing set allows only `end`. A lock channel's `block` list denies its commands and a
non-empty `allow` list denies anything outside it; the lock is checked only inside the profile and
cannot deny `end`. `pose_back`/`pose_forward` are reserved for pose navigation and no key emits them
yet. `runtime.command("oral")` requests `standing_oral` from `standing` and the reverse edge from
`standing_oral` through `request_pose`; it passes `consent: "oral"` only when the anatomy service's
per-mare consent is true, and its refusal reason reaches the anatomy status label.

`apply_live_settings()` refreshes the target snapshot in place on a live settings edit: the same
`to_config` object is re-merged from the target's settings group, and the presentation block is
re-read. The session reads settings only on a request and on this call, never per frame.

The debug pair holds `base`, `anon`, `contact`, `camera` and `audio`, and switches `controls` and
`presentation` at the start, so a request never rebuilds the pose, releases the pose or restores
bones and the body does not move. The Debug **Pose: test variant** action is the proof; the pair is
the evaluator's single path. A transition never calls
`_free_pose()`, `release_pose()`, `_end_session()` or any act exit; `runtime._end_session()` aborts
a live edge through the one pose teardown.

### The standing oral turn

`poses/oral_turn.gd` is the session-owned actor/frame driver for the oral pair. It preloads
nothing; the session binds the pony and the host callbacks `mouth_point`, `opening_point`,
`oral_kiss`, `oral_speech_stop`, `oral_viseme` and `oral_status`.

- **Capture.** The first forward request reads her root position, her orthonormal facing, the live
  opening and the mouth point. The target is the old mirrored anchor: the mouth point in her local
  frame, scaled, turned 180° about UP and subtracted from the opening, with her current Y kept.
- **Tick.** The base weight is the whole clock: forward maps `0 → 1`, reverse maps the same weight
  to `1 → 0` in its own direction. The module writes `pony.global_position` between the captured
  root and the mirrored target, and `view.facing`/`facing_amount` as the UP turn of the captured
  basis. It never rotates the physics capsule and never moves the player.
- **Contact target.** While she turns the `contact_target` is the captured opening, so the part
  does not chase her rump through the arc. Once settled and in mouth contact it eases to the live
  mouth at `ORAL_ANCHOR_RATE`. A released contact points back at the opening.
- **Style and voice.** The style sequence follows the auto pace and writes `oral_pitch`,
  `oral_yaw` and `oral_roll` into the live config and, during an edge, the target snapshot, so the
  delta's to side sees them. The soft-kiss timer calls the host cue on an idle interval.
  `speech_stop` and `viseme` come from the edge events, not from the turn.
- **Release.** Reverse completion and the one act exit call `restore()` once: the captured root and
  facing go back, the oral keys are erased from both config sides, and the turn clears. The
  afterglow calls `release_mouth_contact()` instead, which keeps the turned frame and the neck
  pose, clears the viseme and points the contact back at the opening.

### The face contact driver

`poses/face_contact.gd` is the session-owned contact driver for the bed face-sit. It preloads
nothing; the session binds the pony, the act body's `face_point()`, her `opening_point()` and the
log. It never calls the camera, hands, anatomy or kiss.

- **Begin.** On the contact switch to `face` (or a pose row whose base contact is `face`) it
  captures the live bed frame, his mouth and her opening. It stores the frame-space `mouth -
  opening` residual and the captured opening-to-mouth direction. A missing frame or point leaves
  the driver active but uncaptured, so a later tick can recover.
- **Tick.** In face contact only, it reads the live mouth into the current bed frame and eases
  `base_offset + (mouth_frame - captured_mouth) + press + rock` at a fixed rate. The press points
  from her opening toward his mouth, the rock is a small lateral sway, and both scale by the live
  `depth`. It writes the world-space offset to the pose node's `contact_offset` and the live mouth
  to the view's `contact_target`. The offset is frame-space, so a moving bed carries it. The depth
  comes from the act facts; the driver reads no settings and allocates nothing per tick. A missing
  or non-finite provider holds the last valid offset and logs one diagnostic line.
- **Restore.** The reverse contact switch, the reverse completion and the one act exit zero the
  pose node's offset and clear the view target once. The afterglow keeps the contact until that one
  exit. `poses/missionary_recipe.gd` applies the offset to her armature root after the authored
  base, scaled by the recipe weight; the missionary offset is zero, so the recipe stays generic.

## Pose evaluator and per-pose configs

`poses/skeleton_pose.gd` is the one `SkeletonModifier3D` the session installs. It evaluates one
pose pair rather than one string mode: `mode` is `MODE_SINGLE` or `MODE_BLEND`, and
`set_pose(from_driver, to_driver, from_delta, to_delta, from_config, to_config)` stores the pair
while `set_weight(weight)` carries the live edge weight. The session resolves the effective driver
and delta from the spec: `driver` when the row has one, else the base chain's driver
(`standing_test` resolves to `standing`), and `delta` for the procedural delta. A driver is a
`RefCounted` with optional `apply()` (whole pose), `apply_base()` (base only; false when the pose
owns no base on this rig), `apply_overlay()` (the moveable head/neck) and `apply_delta()` (the
procedural delta). A missing method is a no-op. The shipped recipes implement `apply`,
`apply_base` and `apply_overlay`; `apply_delta` is optional, for a pose that carries a procedural
delta.

The single fast path is the same effective driver and delta with equal configs and the same
authored asset on both sides (two null assets count as the same, and the presentation node carries
none). It calls the driver's `apply()` with the pose ramp (`smoothstep(amount)`), exactly as the
one-recipe node did, so
the begin ramp, the normal missionary and standing acts and the diagnostics are unchanged. A standing `apply_base()` reads `authored` and `ground_frame` from the
state and returns false without them; the shipped act never falls back to the procedural stance. A pose that carries a delta uses `apply_base()` → `apply_delta()` →
`apply_overlay()` in that order; `standing_oral`'s settled pose runs that form with the standing
driver and the oral recipe. The debug `standing ↔ standing_test` pair takes the single fast path:
both effective drivers are the standing driver, both deltas are empty and the target snapshot is
the standing group with the same presentation, so the body holds. The oral pair takes
`MODE_BLEND` in both directions because only one side carries the delta; it is a real two-base
edge, not the fast path. The pair is the current proof of the state machine's single path. The
offer presentation pose (`poses/standing_presentation.gd`, now driven by the act start rather than
the proactive request) is the same evaluator with the standing
pair and its own config. The single path is the compatibility path: the shipped poses keep their
own asset on both sides.

The evaluator also holds the authored pair: `set_pose()` takes optional trailing `from_authored`
and `to_authored` assets, and a pair of different assets is a blend even when the drivers, the
deltas and the configs are equal. A null side falls back to the node's live `authored`. During the
two-base form, `_write_blend()` sets `state["authored"]` to each side's asset before that side's
base runs, so each recipe reads its own document; the overlay pass runs with the state on the to
side, and the live asset is restored after it for the post-write diagnostics.

The two-base form captures the game's pre-pose, evaluates the from side at full base weight,
captures it, restores the pre-pose, evaluates the to side the same way, restores again, and blends
the two captured local transforms at the edge weight: rotation by `Basis.slerp`, scale and origin by
`lerp`. A non-finite result is skipped rather than written. The overlays run after the blend, from
then to, with `1 - weight` and `weight`. A false base skips that side's delta; the overlay still
runs and the recipe guards its own base precondition. The three capture buffers are resized
once per bone count and reused, the node is the only modifier and it allocates nothing per frame.
The blend sets `diag_last_base = "blend"` and skips the authored-asset trace. `apply_render()` and
the modifier pass call the same evaluator with the same pair and weight.

The session owns the configs. `begin()` sets the start pair, `request_pose()` the edge pair and the
completing tick the target pair; each also calls `set_weight()` (1.0, the run weight, 1.0).
`begin()`, the request, the completion, `reload_authored()` and `release_pose()` are the only
owners of the authored asset: `begin()` resolves the start asset, the request caches `_from_asset`
(the live wrapper) and `_target_asset`, and completion adopts the target asset on both sides. The
settings syncs (`sync_standing_config()`, `sync_missionary_config()`) and `_adopt_target_config()`
only merge the config, so a live settings edit cannot reset the live asset to a file named by the
settings group. `live_authored()` and `authored_asset()` return the live rendered wrapper, so the
shot camera holds the source asset through an edge and reads the target's after completion.
`_config_for_group(group, presentation)` builds the target: the standing group plus the
presentation chin/neck/tail values (the values `sync_standing_config()` writes), the missionary
block, or `SETTINGS.pose()` for another group. The group comes from the target spec, never from
its id: `standing_test` and `standing_oral` use the standing block and have no `default.poses` row
or `POSE_KEYS` schema of their own. `request_pose()` caches it as `_target_config`,
`apply_live_settings()` re-merges it in place, and the complete tick adopts it into the live
`pose_config` with `_adopt_target_config()` before it drops the target. The live object survives:
`view.pose_config`, the pose node and the standing camera see the same dictionary. During an edge `view.from_config` is the live config and `view.to_config` the
target; at rest both point at the live config.

The standing camera caches its pose config by the view's settings group and pose id, so the debug
pair keeps the standing config when the target settles and the glance/tail values do not snap. The
afterglow holds the current pose: its presentation row has no pose mode and no afterglow pose id,
and the runtime only re-asserts the pose weight, the tail, the HUD state and the wings.

## Retarget hooks and the pose change

`runtime._pose_fanout()` runs after the pose tick and the facts sync in every act phase above
`IDLE`, in one fixed order: the pose service, the camera, the hands, the kiss, the anatomy bridge
and the audio. The pose service reconciles its modifier profile and applies the `act_body`/`anon`
channel; each following owner implements `pose_changed(view)` and caches the last id/profile/
family/contact, so an unchanged view is a cheap no-op. The face, dialogue and HUD read the view
through the facts and have no hook. The fan-out is a retarget seam, not a second teardown: it never
calls `release_pose()`, `leave_pose_start()`, `leave_pose_body()`, `_end_session()`, `_free_pose()`
or any act-scope restore. The eye-camera tick stays on the render write, after the pose write.

`refresh_modifiers(feature_flags)` is the live settings edit's entry into the session's reconcile:
it replaces the session's feature flags and runs the same `pose_changed(view)` pass with the
unchanged view, so a live `standing_body_sway`, `missionary_body_motion` or `thrust_ear_twitch`
change installs or removes its owner. The view supplies the profile; the call carries no pose id.
The runtime calls it from its own live settings path.

The `contact` channel is the one contact change: the forward oral edge switches `opening` to
`mouth` at `0.9`, the reverse switches back at `0.0`, and completion settles the target row's base
kind. The hands read `view.contact_kind` for the mouth path and the oral caress blend; the anatomy
act reads it for the part target and the hole gate; the camera reads it for the oral lean lock; the
dialogue and HUD read it through the facts. The `face` kind is the bed face-sit edge: the forward
missionary edge switches to it at `0.9` and the reverse returns to `opening` at `0.0`. The anatomy
act parks the part and reports a zero hip offset, the anatomy bridge refuses
`hole_ready`, and `poses/face_contact.gd` follows the bridge's `face_point()`.
The standing camera reads `view.facing`/
`facing_amount` directly each physics tick; the pose turn writes them, so no service carries a
facing copy. The running lean kiss is ended by the oral lean tick; the kiss release still advances
through its own `tick`, so no second kiss state exists.

The modifier profile table is `shared/pose_specs.gd`'s `MODIFIER_PROFILES`: `missionary` owns
`prone_sway` and `tail_lay`; `standing` owns `body_sway`, `ear_twitch` and the standing tail. An
unknown or missing profile is the empty set. On a pose change the session keeps the owners shared
by the from/to profiles and calls their `pose_changed(view)`, installs the target-only owners behind
their feature gates and removes the source-only owners after restoring their bones. `standing_test`
uses the standing profile, so the debug pair shares every owner and the body does not move. The
`leave_pose_body()` act-exit step remains the full extra-modifier removal; the reconcile never calls
it.

The pose service owns the missionary `act_body` adapter (`poses/missionary_anon.gd`): it creates the
node on the runtime host as `UnfplapMissionaryAnon`, installs it through the `anon` channel,
binds the service's authored asset pair, applies it from `render_write()` and frees it once in
`release_pose()`. The anatomy bridge receives
only an opaque handle: it uses the body's `refresh_palm`/`diag_row` and eye reads and calls
`remove()` at the act end; it never creates, installs, applies, frees or re-parents it. The adapter
exists only for a view whose `anon.mode` is `act_body` and desktop human Anon; the `player_body`
specs (`standing`, `standing_test`) keep the runtime's standing Anon controller. The `anon` channel
accepts `hold` (keep the adapter), `blend` (carry the live edge weight) and `switch` (name an
authored profile); the adapter caches the last profile and weight. Outside an edge the service
binds the live asset on both sides, so the adapter keeps its single placement and bone-block path.
On a blend it evaluates both authored placements and both v7 local-rest bone blocks and mixes
them at the edge weight; a v6 or mixed pair keeps the live side's single path. A switch binds the
target asset twice. The completion tick also binds the adopted asset before the next fan-out, so
there is no one-frame source pose. A pose change never frees the
adapter; the one act exit does.

The audio impact profile follows the view's `audio.impact`: `missionary` keeps the bed/fabric layer,
`standing` and `standing_test` play none. The impact and withdraw calls read the view, not the
act's start `pose_id`.

The presentation wrappers (`poses/standing_anon.gd`, `poses/wing_control.gd`, the standing camera
and the kiss) read the view's family, profiles and config. The runtime's `pose_id` is the act's
start identity for `start()`, the gate and the teardown; `view.id` is the live pose. The session
keeps no start id of its own.

A body swap rebuilds the live pose on the new skeleton at `view.id`; it is not a pose transition
and not a new act. The runtime stages the settings pose config, calls `begin()` with the same
context shape as the start, then `settle()` sets the pose and standing-tail amounts straight to 1
inside the flame. The session's start ramp and the runtime's `POSING_IN` fade stay for a real
entrance, so a resumed act does not visibly enter twice.

## Spaces and axes

- Bone writes use `Skeleton3D` skeleton space via `get_bone_global_pose` /
  `set_bone_global_pose`.
- Axes are body-relative:
  - `right = sk.global_basis.inverse() * pony.global_basis.x`
  - `up = sk.global_basis.inverse() * pony.global_basis.y`
  - `forward = sk.global_basis.inverse() * -pony.global_basis.z`
- `up` is world gravity, not the pony's rolled dorsal axis.
- `bed_frame` is the live mattress top and the bed's axes; it follows a moving bed. `ground_frame`
  is the pony root's orthonormal basis and position at pose start, and it follows the root's
  position and yaw each physics tick. A ground asset is authored in that frame; the bed and the
  ground never mix.
- Never use raw world axes for bone posing.
- `pony_head.basis.z` is **not** the face axis. The head must not be rotated by straight-chain
  alignment; keep it in the bone list only as a direction target for `pony_neck2`. The head
  follows neck2 through its rest offset.

## Missionary

The pose is the **hand-authored asset** in `poses/missionary_pose.json`, placed in the real bed's
space, with the nuzzle and gaze overlays on top. There is no second implementation. The nuzzle
scale, period and duration come from the pose config (`default.poses.missionary`); the recipe has
no constants for them.

### Act state

Missionary is its own state, not the game's bed rest:

- **Anon stands** before the act owns the camera (`force_stand_up()`, then the start snapshot and
  the player lock), and the game's desktop presentation is parked. His own `AnonBody` is placed
  from the asset's `anon` transform about her hips anchor and the mattress contact, and posed from
  the `anon` local-rest deltas by `poses/missionary_anon.gd`, at render time. His body IK and
  desktop pose driver are switched off for
  the act.
- **She stands.** The bed rest is released and she is asked to `stand`, so the solver and the clip
  tier hold a neutral pose instead of `lie_down`; the act poses her body from the asset.
- **The bed is only a frame**: `bed_frame` (mattress top and axes) plus the offer/eligibility path.
- **The bed frame follows the bed.** The session's `bed_frame` (`facts.bed_frame` for
  presentation modules) is updated each tick by the bed's rigid delta; a moving bed (the
  Cloudominium's CloudDrift) carries the authored pose, the act body and the shot instead of
  leaving them at the world transform where the act started. The mattress top is not re-measured.
- **The end restores the scene relative to the bed** (`restore_scene()`: player, pony and camera
  snapshot plus the bed transform) and stands her. A moving bed applies the same rigid delta to all
  three, so the cuddle rejoin starts beside the current bed. A normal end of a bed act then returns
  to the cuddle: Anon sits on the bed's player seat and lies back, and she is invited into its guest
  seat, where the stock `CuddleSession` picks her up. A forced stop, a bad summary or a stock
  closeness refusal leaves her standing. The snapshot is re-read once the pose settles
  (`resnapshot()` at ACTIVE): taken at `prepare()` it catches Anon mid stand-up and restores the
  reclined eye height. `resnapshot()` refreshes only the game camera's transform, never the act's
  own view.

### Base pose

- **Asset.** `poses/authored_pose.gd` reads version 7 of the JSON once per process and caches it.
  The file stores `local_rest` bone deltas, the hips anchor and contact, the armature root and the
  optional anon/shots/bed blocks; the asset's **frame** is bed space: origin at the middle of the
  mattress top, the bed's own axes, `+Z` the direction her head points. The runtime maps the frame
  onto the real bed with
  `bed_frame = Transform3D(bed basis * Basis(UP, PI), Vector3(bed x, drawn mattress top, bed z))`,
  so the pillow end (the shared bed frame's `-Z`) is where her head points. The bones are not bed
  space: the loader applies `rest * delta`, and the anchor/contact rule places the root. Version 6
  remains the one-release read path.
- **The act owns the render.** The game re-poses the rig after our modifier pass (the clip tier's
  `enter`/`leave`, the posture and the terrain solver), so the modifier's write is not what the
  renderer sees. The runtime therefore applies the same recipe once more from `_process`, after
  every physics and process writer of the frame: `skeleton_pose.apply_render()`, same weight, no
  extra ramp and no clock advance. The active sway then replays its current offset on the same
  skeleton, because the pose write owns the body bones it moves: `body_sway` for standing and
  `prone_sway` for the bed. The springs only advance in the modifier pass. The physics-pass write
  stays because the game's own contacts and pose layers read the skeleton during the tick.
- **What is written.** The 30 body bones in `PONY_BONES` (`tools/pose_lab.gd`) — hips, spine1–3,
  neck1–2, flanks, femurs, tibias, legLowers, tarsals, hooves, shoulders, upper/lower arms, wrists,
  hands and fingers — plus the skeleton **root** (the armature bone) for placement. The actor node
  is never moved or rotated, so the capsule, bed support and posture recovery are untouched. The
  head bone, lids, eyes, ears, wings, feathers, mane and tail are never baked: the game and the act
  own them.
- **The file carries every one of those bones, including the ones left at rest.** The runtime
  writes only what the file holds and never resets the rig, so a bone missing from the file keeps
  the game's own pose and breaks the chain it hangs from. Version 7 stores every bone as a
  `local_rest` delta, including the ones left at rest; the loader applies `rest * delta`. The lab
  reads a v7 file as `local_rest` and only the v6 migration as bed space, so an older file is never
  applied as lab world.
- **Own the scale too.** `FillyProportions` and the part hiders *multiply* a bone's pose scale
  every modifier pass (`set_bone_pose_scale(..., get_bone_pose_scale(...) * factor)`) and rely on
  the animation resetting it to rest each frame. The act replaces the animation, so every bone it
  writes also gets its rest scale back: without that the factor compounds (0.92^N collapses, >1^N
  explodes) and the neck, head or whole body stretches to `inf`. Parts the game hides stay hidden
  through its own hiders, never by leaving a bone collapsed in the asset.
- **Never invert a scaled parent basis.** The stock hiders collapse a bone by scaling it to
  `0.001`, and `set_bone_global_pose()` inverts the parent's *full* basis for every write — a
  1000× multiplier that compounds each frame until the pose is `inf` (the body pulled away, then
  flickering) and the anatomy part follows it. Every act write goes through `pose_rig.set_global()`,
  which builds the local pose from the parent's **orthonormalized** rotation and origin only, and
  rejects a non-finite target. The stock hiders stay on: they only hide parts, and `BodyIK` (the
  standing pose driver, not a hider) is the one modifier parked for the act.
- **Anon's own process is parked.** `missionary_anon.install()` stops `AnonBody._process`: it
  drives `LegHide` from the height of the act camera (the mattress-height eye reads as `seated`,
  so the game collapses his legs), rewrites the authored fingers every frame (`_update_fists`), and
  feeds `model_scale` from that camera. `LegHide.influence` is set to zero for the act (the
  modifier stays active), the desktop pose driver is nulled and the desktop presentation's own
  `advance()` is stopped, so only the act writes his bones. The skeleton and the rest of its
  modifiers keep updating.
- **The head mesh is never hidden.** `head_smd` is the head **and the hands**; hiding it is what
  removes the palms. The game's `HeadHide` collapses only the head bone, which hides the head
  vertices. `apply()` caches the authored eye right after the bone write and the lean, before
  `HeadHide` runs, so `eye_transform()` never reads the collapsed bone.
- **His palms are planted.** `_place_hands()` holds both wrists at the authored world height and
  lets only their X/Z follow the stroke and lean: the hands slide along the mattress instead of
  lifting. A two-bone arm solve reaches each wrist; the hand keeps its authored world orientation
  so the palm stays flat on the bed. Caress: see `docs/hands.md`.
- **The exit restores the avatar.** The act writes his world placement every frame; `remove()` puts
  back `avatar.transform`, its process state, `process_mode`, visibility, the pose driver, `BodyIK`,
  the `LegHide` influence and every bone's pre-act local transform (the authored pose deliberately
  stretched positions, which the game does not re-pose for every bone).
- **The part and the pony are reset too.** `anon_part.reset_state()` clears its aim, hip offsets,
  penetration seed, bend/squash, shader and placement at both encounter start and end. The pose
  session's `snapshot_bones()` / `restore_bones()` put every body and hair bone back after the
  act's pose is freed, so the game animation resumes from a sane rig.
- **Space rule.** Every act-space rotation is applied to a bone's **global pose** with the axis
  converted once into skeleton space (`pose_rig.rotate_free`). Pre-multiplying a bone's *local*
  pose applies the axis in the parent's frame — his hips are rotated ~90° here, and doing that made
  the W/S lean yaw the view instead of nodding it.
- **Positions are authored too.** A body bone stores a position next to its rotation, and it is
  applied: a lengthened neck or a displaced flank root is a deliberate part of the pose. Only the
  skeleton root carries the absolute placement; every other position is relative to its parent.
- **Placement** is the anchor/contact rule: the hips land at the asset's anchor, the root is scaled
  about it by `body_scale`, and the whole base is lifted so the contact stays on the mattress. The
  live body scale is applied once at the world root; the asset's bone translations are never
  multiplied. Canon is unchanged; Canon, JRHNBR, Same Height and the stallion multiplier render at
  their own size, and the four-size lab covers Hoers.
- **The Anon and the shots** use the same rule (`place_origin`): their origins scale about the hips
  anchor and follow the contact lift; their authored bases are unchanged.
- **The shots** are authored frame-space transforms; `camera/missionary_camera.gd` reads only their
  origins through `shot_origin()` and aims them at her live face and vulva. A missing shot falls
  back to a fixed bed-relative point placed by the same anchor/lift rule.
- **Weight** comes from the pose modifier's `amount` ramp: each bone slerps from whatever the game's
  `lie_down` settle left to the authored rotation, and the root blends with `interpolate_with`, so
  POSING_IN still eases her in.
- **The head bone is reset to rest** on this path. The runtime owns the face: the gaze solve then
  aims `pony_head`'s frame (plus `HybridNeckLink`'s offset) at Anon. Baked head rotations were
  rejected because the pose lab has no head mesh.
- **Upright by default.** After the aim, `_level_head()` rolls the neck chain about its own forward
  axis (shares 0.30/0.36/0.34, so the neck does not kink at one joint) until her up matches the
  world's. The shortest-arc aim only sets the face *direction*; a pose that rolls the neck otherwise
  leaves her staring at Anon sideways. The settled `MISSIONARY` dump prints `head aim=…° roll=…°`
  and `body up=…°` (the pelvis up against the world up) so a sideways gaze or a rolled pose is
  measurable.
- **Overlays skip the joint-limit clamp** (`rig.rotate_free`). The authored pose can sit outside
  the limits the game derives from its own motion library, and `constrain()` would snap it back on
  the first gaze correction.
- The shot's camera positions are bed-relative, so the body and the eye move together on any bed.
- **No fallback.** There is no second missionary pose. A missing/invalid asset, a version below 6
  or no bed frame (the floating pose preview) means no pose is applied, and the act's `pose_asset`
  gate refuses the start with `missionary pose unavailable: <reason>` in the log.
- **Reload.** The asset is shared for the process; the **Reload posed base** Debug block action
  re-reads the file in place, so the lab export → game reload loop works mid-act.

## Standing

The standing body pose and placement. The camera, lean, glance and shot are `docs/camera.md`.

- Facing lock every physics tick at priority 100:
  `pony.global_transform.basis = _facing_basis.scaled(scale)`. `stay()` alone does not stop
  conversation facing, so `face_point`/conversation target are cleared late each tick and
  `face_turn_rate` is held at `0` for the act; locomotion and emotions keep running.
  Conversation attention is not a stop condition: another character addressing Anon can talk
  while `_keep_act_attention()` clears her listener each tick.
- Act start keeps her where she stands. For desktop human Anon, `_begin_standing_placement()`
  builds the act transform from her current facing and places him at
  `pony_position - forward * _standing_gap()`, then sets his yaw along her forward so a standing
  act after a missionary restore does not inherit the old view. The 2 m Y cone bounds that
  correction. The act end leaves him there and leaves his yaw/pitch at the last act aim; it
  does not snap the pre-act view back. AnonPony and headset/VR still move her in front of the
  camera rig with `_standing_transform()`, because their rig is the camera or another body, and
  the player is never moved for them.
- `apply_anon_lean()` pins both foot targets at their live stepping pose while a lean moves the
  hip and camera/head forward, sideways or down, so the torso hinges over her instead of walking
  through the lean. With no lean the game's stepping feet are left alone; the capture clears on
  the next non-leaning frame.
- `standing_oral` is the standing frame's oral arrangement: the same stance and ground placement,
  turned about UP by the pose-owned oral turn, with `poses/standing_oral_recipe.gd` as its
  procedural delta. The delta swings the two neck bones with `oral_pitch`/`oral_yaw` and rolls the
  head, counter-rotating it so her muzzle stays along the shaft. The three keys are written by the
  turn and absent otherwise. The normal standing base never owns an oral overlay. The standing
  camera reads the view's facing while the turn runs; the normal facing lock resumes when the
  reverse edge or the act exit restores the capture.
- Standing gaps: the per-size `default.poses.standing.gaps` values, keyed by size name. The game's
  Same Height preset follows Anon's `player/height_cm`, so that gap, the lean scale and the
  caress offsets follow `Settings.anon_height_scale()` as described in `docs/hands.md`.
  For desktop human Anon the gap is measured from her root along her backward axis after he is
  placed behind her. The runtime keeps no gap table: `_standing_gap()` reads the pose config's
  `gaps`, then `SETTINGS.pose(id, "standing")` when the session has none.
- The idle invitation (`poses/standing_presentation.gd`) builds its own standing config. The
  presentation chin/neck and tail values, the glance keys and the two tail angles are read by key
  from the complete block, with no fallback literals. It keeps that config when the pose session has
  none, so the next process frame does not erase the values it just attached.
- A footstool may raise Anon's player root before the standing pose; the camera, feet and hips
  follow the raised floor. The rule, prop and supply are in `docs/stool.md`.
- `poses/body_sway.gd` translates `pony_hips` with an inverted damped spring: back on inward depth,
  forward on outward depth. All four limb-root origins are preserved so the hooves stay planted.
  The same world offset is added to Anon's pinned hip so the contact rocks together. The spring
  ticks in the modifier pass; `render_write()` replays the current offset after
  `skeleton_pose.apply_render()`, because that write owns the 30 body bones and would otherwise
  erase the pelvis motion before the frame renders. `BODY_SWAY_MAX_M = 0.035`. While
  `facts.pose_view.contact_kind == "mouth"` (the standing oral segment), the spring target, offset
  and published world offset stay at zero, so the pelvis holds its recipe base; with oral off the
  spring runs unchanged.
- Strong thrusts build a subtle rump blush decal up to `0.375` albedo mix (smack uses `0.8`).
  The reaction facade and the jiggle values are in `docs/reactions.md`.
- `poses/ear_twitch.gd` flicks both ear roots together on a thrust: a shared forward/back pitch and a
  sideways twitch that sends both ears outward or both toward the head. The per-ear sign comes
  from the root's lateral offset, with an eased envelope and cooldown.
- The standing base is the v7 asset `poses/standing_pose.json`, baked from the body rig's rest pose
  with `apply_reference()` at the effective reference config. The live recipe applies only the
  difference from that reference; the default stance is the baked pose and matches the old
  procedural stance on every owned bone. The asset carries the 30 body bones, not `pony_head`, so
  the live base applies the head's full reference bow and chin itself; the neck bones are the baked
  difference. Both recipes read their config by index: `_value(key)` has no fallback, and every
  caller passes a complete block (`SETTINGS.pose(...)`, `reference_config()` or the shipped
  defaults). The six `STANDING_*` constants in the recipe are the live delta baseline and the bake
  reference, not copies of the shipped pose block.
- `standing_oral` runs the procedural delta on that baked base, after it and before the overlay,
  in both the single and two-base forms. The neck/head and the mouth anchor match the reference
  recipe plus the same delta at all four sizes (the oral parity in `test_pose_bake`).
- `chin_up_deg` and `neck_down_deg` come from the presentation block, and their effective defaults
  are the presentation values. `foreleg_spread` is the absolute outward half-angle; the recipe
  measures the **baked** fore limb line at the finger tip, so the reference value adds zero and a
  changed value adds only the difference.
- Tail aside/lift/flick runs on the visible tail chain (`poses/tail_chain.gd`): the devkit hair
  chain `mTail1..mTail6` when present, otherwise the fitted body chain
  `pony_tail_01..pony_tail_05`. The princess exports weight the tail into the body and skip the
  devkit hair, so their body chain is the one moved; a devkit mare keeps its hair tail. Side
  randomized per act. `presentation.standing.tail.yaw_deg` (aside) and `pitch_deg` (lift) are
  the live amounts, in degrees. A damped spring driven by raw `depth` also rocks the
  tail with the thrust: sagittal `ROCK_PITCH = 0.12` and lateral `ROCK_YAW = 0.08`. Each thrust
  adds a short decaying wave (`JIGGLE_DECAY = 3.6`, `JIGGLE_FREQ = 18`, `JIGGLE_PITCH = 0.16`,
  `JIGGLE_YAW = 0.08`) at the same strength as the rump shader, strongest at the tail root and
  lagging down the chain. A smack adds the same wave through `reactions/service.gd` at
  `1.0 × _jiggle_size_scale() × smack_intensity`; the thrust wave scales with `jiggle.intensity`.
  The `jiggle` radius, intensity and smack amount, the stock-mark clear and the body-coat target
  are in `docs/reactions.md`. Stock marks are hidden and aged at act start, so a mark from an
  earlier regular smack cannot linger as a stale jiggle point. The game's tail anchor pins the
  first 12–67 mm of the `DevkitTail` root cap to the hair `mPelvis`, so the `mTail1..6` wave alone
  cannot move the base; on the hair chain `tail_pose` also translates `mPelvis` by
  `JIGGLE_BASE_M = 0.02 m` using the rump shader's thrust wave and restores the mane bones. The
  body chain has no such pinned hair base, so it rotates from `pony_tail_01` and never translates
  the hips.
- A visible tail that is not on either game skeleton names a `tail_pose_root` `Node3D` through pony
  metadata. `poses/tail_chain.gd` resolves it, and `tail_pose`/`tail_lay` rotate that node about the
  same lift/aside sign and bed target as the bone path, then restore its saved local transform at
  the act's pose exit. The game's bone chain stays untouched. The anatomy tail seat may put a
  placement wrapper above that root; the act modifiers still rotate and restore the root itself,
  so the wrapper's placement survives an act. The changelings adapter names the chain under Queen
  Chrysalis's game rig `Hair_tail` attachment; a missing node falls back to the bone path, so
  every other pony behaves as before.
- Standing wings start at `WING_STANDING_HOLD = 0.65` (about `60°` above the ground), then open by
  `WING_STANDING_SPREAD = 0.25` as satisfaction rises. Missionary keeps the stock spread progression.
  A mod-owned `poses/wing_sweep.gd` runs last and yaws `pony_WingBase_L/R` by `WING_SWEEP_DEG = 10°`
  in opposite directions, sweeping the spread wings slightly backwards. Entering afterglow
  releases the hold and drives the same `WingTuck` blend to a full fold over
  `WING_AFTERGLOW_RETURN_SECONDS = 6.0`; early afterglow exit lets the node finish immediately.
- Standing enters a held `AFTERGLOW`: the tail lifts and flicks twice. Lean and A/D caress remain
  live; holding the act key ends it. The close-window caress time is in `docs/hands.md`.
  Missionary afterglow stays passive. `standing_oral` uses the passive afterglow row: the turned
  frame, the facing and the neck keys stay, the mouth contact and viseme are released, and no
  standing close window opens.

### Missionary kiss

`kiss_control.lean_kiss_tick()` runs for the two base poses, missionary and standing. Missionary
kisses when F is held and
`lean_forward >= MISSIONARY_KISS_LEAN` (0.90) **and** W is held: `lean_targets` adds `|side|` to
the forward lean, so without the W test a pure side lean would pull the kiss. The kiss itself uses
the custom head-aim path (the stock pose is authored for a standing pony); `Q`/`E` no longer kiss,
and `lean_action_kind()` only fires the standing shoulder reach. Instead of aiming at his mouth on
the first frame, the look point blends from his eyes to his mouth by the kiss's own `0.35 s` fade, so
her head leans in with the kiss rather than snapping. The solve still follows the moving point each
frame, but the base-game contact target is his authored mouth (`mouth_point()`).

## Aftercare

- No head lowering.
- Tail held raised straight (`aside_angle = 0`), with `flick_amplitude = 0.55` and a
  one-cycle flick every `1.4–2.4 s` on the hair skeleton.
- Navigator held for 10 s.

The aftercare lifetime, positive tail-up rule and the held mood face are in `docs/afterglow.md` and
`docs/face.md`.

## Timing domains

- `runtime._process`: view-depth travel, lean, climax wave, breath, look point, pose climax flag.
  `_process_tick` calls `poses/service.gd`'s `render_write()`, which owns the render-time order:
  for the bed family, park the game presentation and place the act's Anon body, write her pose,
  replay the prone sway, then the eye-shot camera tick; for the standing family, sync the ground
  frame, write her pose and replay the body sway after every game writer. It then calls
  `camera/service.gd`'s
  `write_look_target()`, which owns the look point (the missionary gaze, the kissing-mouth blend and
  the authored-Anon fallback) and the pose's kiss and climax weights.
- `runtime._physics_process`: presentation, timers, facing lock, glances,
  auto-cuddle suppression.
- `main._process`: calls `active_runtime.apply_camera_motion()` every rendered frame.
  Keep this single owner.
- Do not merge these timing domains blindly.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | eligibility | `eligibility/service.gd` | adult and consent gate |
| service | settings | `settings/service.gd` | settings declarations and live values |
| shared | act_motion | `shared/act_motion.gd` | lean and travel math |
| shared | hands_reach_plan | `shared/hands_reach_plan.gd` | reach planning math |
| shared | hands_scale | `shared/hands_scale.gd` | palm scale |
| shared | pose_catalog | `shared/pose_catalog.gd` | pose ids and schema |
| shared | pose_specs | `shared/pose_specs.gd` | pose capability table |
| shared | pose_view | `shared/pose_view.gd` | pose read model |

## Lifecycle

- Scope: per runtime, one per pony; the session is not rebuilt for each act
- Constructed by: `runtime._init()`; `bind()` points it at the runtime and its pony
- Begin: `begin(context)` builds the act's pose once, enters `ENTERING`, fills the pose view and
  settles `STEADY`, and returns `false`, before installing anything, when a pose is already live or
  the pony has no body skeleton
- Request: `request_pose()` starts one authored edge without rebuilding the pose, `tick()` advances
  it and `release_pose()` aborts it
- End: `release_pose()` exits through `EXITING`, frees the pose and the standing tail, then clears
  the act identity, the features, the live config, the view and the bed frame
- Idempotent: the teardown phases are safe to repeat; `begin()` is not

### Teardown scope

`runtime._free_pose()` is the one pose teardown ledger. It is the one ledger across two lifetimes:
the pose scope the session owns and the act scope the runtime owns. A pose transition calls none of
the pose-scope steps or the act exit; it retargets through `pose_changed(view)` and leaves the
teardown to `_free_pose()`.

| Step | Scope | Owner |
|---|---|---|
| `leave_pose_start()` | pose: rig-check cache, tail lay, bed/ground frame | the session |
| `clear_presentation()` | act | the runtime |
| `end_lean_action` | act service, pose-local sub-state | the camera |
| `hands.reset()` | act service, pose-local sub-state | the hands |
| `kiss.reset()` | act service, pose-local sub-state | the kiss |
| `integrations.reset()` | act | the integrations |
| `_reset_excitement_hold()` | act | the runtime |
| `release_free_camera_lock` | act | the camera |
| `standing_anon.remove()` | pose: the standing player-body Anon wrapper | the runtime |
| `leave_pose_body()` | pose: extra modifiers | the session |
| `_restore_voice_volume()` | act | the runtime |
| `reactions.end_act()` | act | the reactions |
| `release_pose()` | pose: final clear, act body | the session |

- `leave_pose_start()` — the rig-check cache, `tail_lay`, the bed frame and the ground frame. It
  keeps the pose node, the modifiers, `pose_config` and the view.
- `leave_pose_body()` — the extra modifiers (`body_sway`, `prone_sway`, `ear_twitch`). It keeps
  the pose node, the standing tail, `pose_config` and the view.
- `release_pose()` — the final clear: the act body (after the anatomy handle is cleared), the pose
  node and the standing tail, the act identity, the features, the live config, the rig caches, the
  bed and ground frames and the view. Safe to repeat.

The runtime calls the two leave steps and the final release at their table positions, with the
act-scope resets between them. `release_pose()` is called only from `_free_pose()`. `_end_session()`
(the one act exit), `_build_pose()` (the new-act prep) and `_suspend_for_body_swap()` (the
act-preserving body handover) are the only `_free_pose()` callers. A second `release_pose()` is a
no-op.

`_restore_camera()` also ends the lean action, resets the hands, releases the free-camera lock and
removes the standing player-body Anon wrapper. That is the act's camera restore path, not the pose
teardown; it stays unchanged.

## Tests

- `tests/poses/test_session.gd` — pose build/free, bed frame follow, modifier installs, the
  render-time sway replay, the session API, the effective driver/base paths, the state machine, the
  request/refusal codes, the target snapshot with the presentation, the requested evaluator pair,
  the target adoption, the live/target asset pair and its completion and reload, the tick/switch/
  status path, the real control profiles, the pose-change hook
  and the service-owned act-body release. The oral case pins the turn, the contact switch at 0.9,
  the control lock, the speech/viseme events, the settled delta, the afterglow release and the
  reverse restore.
- `tests/poses/test_oral_turn.gd` — the pose-owned oral turn: the captured root/facing/opening,
  the forward and reverse weight mapping, the opening anchor while turning, the live mouth once
  settled at canon and at a non-canon size, the soft-kiss timer and the one restore.
- `tests/poses/test_modifier_profile.gd` — the synthetic profile reconcile: the shared owner keeps
  its node, the source-only owner is removed, the target-only owners install behind their feature
  gates, the act-exit leave still removes all and the synthetic profile stays out of the shipped
  table.
- `tests/poses/test_pose_blend.gd` — the typed single/blend modes, the single fast path and its
  pose ramp, the base+delta order, the oral delta forcing the blend pair and settling into the
  single delta path, the two-base capture/blend/overlay math and weights, the two-asset pair where
  each side reads its own document, the reused capture buffers, the non-finite guard, the render
  order and the shipped standing driver.
- `tests/poses/test_pose_teardown.gd` — the pose-scope/act-scope split: the leave steps keep the
  pose node, the config and the view, the final release clears them, the transition path keeps the
  pose alive, and no pose-scope or transition function reaches an act exit.
- `tests/poses/test_pose_state.gd` — the pure transition table, the request codes and their order,
  the requirement check, the edge start/validation, the duration and `after` constraints, the
  channel weights and switches, the edge events, completion, the interrupt fields and the reused
  arrays. Plain dictionaries only.
- `tests/poses/test_pose_spec.gd` — the field wrapper, the shared validator, the base/driver rule
  and the pure source.
- `tests/poses/test_pose_registry.gd` — the five shipped specs, the three authored pairs, the
  unchanged public catalog and the table rules.
- `tests/poses/test_pose_offer.gd` — the typed offer's defaults and validity, the blocked hint,
  the cancel/scope/auto fields, and `main.start_pose_offer()`'s history, buck, blocked, transient,
  attempt, failed-start and invalid-handle outcomes.
- `tests/poses/test_start_setup.gd` — the closed start vocabulary and shipped table, the helper
  defaults, the synthetic `auto`/`bed_keep_lying` row and the runtime's setup dispatch for both bed
  adapters and an unknown name.
- `tests/poses/test_pose_edge.gd` — the edge documents, the typed wrapper and validator, the
  registry load and the debug, oral and face-sit forward/reverse run proofs.
- `tests/test_standing_presentation.gd` — the act-owned presentation start, the navigator stepping
  turn and its away settle, a blocked turn aborting without a snap, the fallback rotation and the
  presentation's affectionate face.
- `tests/poses/test_pose_asset.gd` — the missionary asset's v7 version/space/frame, body and Anon
  bone lists, anchor/contact/root and bed reference.
- `tests/poses/test_pose_asset_v7.gd` — the v7 schema and its refusals, `local_rest` bone math, the
  anchor/contact placement at four sizes, variants and the spec `asset` resolution; the v6 fixture
  and the v6 ground refusal.
- `tests/poses/test_pose_bake.gd` — the bake capture/compare math on a synthetic rig, the
  deterministic writer and its fixture-path refusal, the shipped standing asset's freshness, its
  stance guard (rotation-only base, a real hind width, opposite sides), the live base's parity with
  the old procedural pose on every owned bone including `pony_head`, four-size body parity, contact,
  anchor, reference config, and the four-size oral neck/head parity against the reference recipe
  plus the same delta.
- `tests/poses/test_body_sway.gd` — the regular depth sway, the render replay after the pose write,
  the zeroed oral hold and the release.
- `tests/poses/test_prone_sway.gd` — the missionary slide and nod, the render replay after the pose
  write and the active-state gate.
- `tests/poses/test_tail_chain.gd` — the hair/body chain resolver, the body-tail aside/lift, bed lay,
  the custom-root aside/lift and bed turn with its restore, and the post-stop tuck.
- `tests/poses/test_pose_teardown.gd` — the pose-scope/act-scope split, including the body-tail
  install path for fitted exports.
- `tests/poses/test_pose_rig.gd` — bone cache, global write and non-finite rejection.
- `tests/poses/test_pose_scale.gd` — the v6 uniform scale, the v7 anchor/contact placement at four
  sizes and the rest-scale ownership.
- `tests/poses/test_rotation.gd` — body-relative axes and the rotation helpers.
- `tests/poses/test_face_contact.gd` — the bed face-sit contact driver: the begin capture, the
  mouth follow, the depth press, the moving-bed carry, the missing-provider hold and the one
  restore.
- `tests/test_face_sit_action.gd` — the Debug face-sit action and its refusal helper.
- `tests/poses/test_pose_view.gd` — defaults, the filled view, the transition fields, the live
  mirrors and the reused clear.

## Verification / lab

- Missionary on the Golden Oak guest bed: start, pose, a moving bed, the **Reload posed base**
  action (which re-reads the asset and re-evaluates the `pose_rig` gate), the **Show skeleton
  overlay** Anatomy Debug flag, hold-act-key end and the bone restore on the next animation frame.
- Bed face-sit: from Missionary, **Pose: face-sit** and back; the face contact, the source-shot
  hold/cut, the press/rock with depth, the four sizes, a climax mid-edge, the afterglow hold and
  the one act exit. The automated `pose_export --pose bed_facesit --check` and
  `pose_runtime_check --pose bed_facesit` are the non-interactive proof.
- Standing: stance, foreleg spread, ears, tail, wings, afterglow fold and the pose at both Canon
  and Same Height sizes.
- Princess tails: standing aside/lift, the missionary bed lay, the afterglow flick and the
  post-stop tuck. Celestia and Luna use the body chain; a devkit mare keeps the hair chain; Queen
  Chrysalis's `tail_pose_root` spring chain is moved and restored without a body-chain write.
- Four sizes: repeat the missionary and standing lab at Canon, JRHNBR, Same Height and Hoers. The
  body, the Anon, the authored shot and the anatomy contact must stay framed at every size; the
  contact stays on the mattress or the ground and the hips stay at the anchor. The bake/check
  commands are `godot --headless --xr-mode off --path . --script res://mods/unfplap/tools/pose_bake.gd
  -- --check` and the same with `--write`; the exporter round-trip is `pose_export.gd --check`.

## Related docs

- `docs/camera.md` — shots, lean, glance, standing camera, free look.
- `docs/hands.md` — caress paths, palm holders, smack.
- `docs/anatomy.md` — the anatomy part and tail seating.
- `docs/reactions.md` — jiggle, rump blush, climax hearts.
- `docs/afterglow.md` — aftercare and the close window.
