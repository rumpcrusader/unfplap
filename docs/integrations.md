# Mod integrations

Optional bridges to other installed mods. The service presents another mod's reactions through the
act without changing that mod, and lists every supported integration in its own settings tab
whether or not the other mod is installed.

## Scope

- `integrations/service.gd` is the per-act facade and the only per-act scene adapter.
- `integrations/pantyhose.gd` is the world-side adapter for the Pantyhose & Panties 0.1.1 pack:
  it lifts a worn piece over the anatomy, carries the coat's rump wobble into the worn cloth and
  takes the lower garment off at an act start. The pack is never edited; the compatibility shaders
  are a pinned copy under `integrations/shaders/`.
- `integrations/garment_jiggle.gd` is the adapter's scene-side cloth-jiggle helper: it reads the
  coat's live wobble off a `FlankTouch` target material and carries it into one worn node's own
  model space through per-node instance uniforms; it preloads nothing and allocates nothing per
  frame.
- `shared/integrations.gd` is the provider catalog: mod identity, verified version, feature names
  and binding paths.
- `integrations/provider.gd`, `context.gd`, `action.gd` and `kissing.gd` are pure service
  internals.
- `integrations/changelings.gd` is a world-side body-change provider for the Queen Chrysalis
  0.2.12 pack (`changelings`): it extends `body_change/source.gd`, lists her as an installed
  provider mare, returns the typed body form for each body the pack brings, owns the placement
  wrapper above her spring tail and supplies her own form names, shape lookup and player words.
  It is not a catalog entry, has no settings, adds no Integrations tab section and needs no pack
  rebuild.
- `integrations/changelings_policy.gd` is the provider's offer/reveal policy: the offer timing and
  prompt, the reveal effects and the `form_reveal` memory mark. The base runtime executes the
  generic effects; the base service owns the mechanism (`docs/body_change.md`).
- Two integrations are supported by the per-act service: the Kissing 1.2.9 reaction layer and the
  Pantyhose & Panties 0.1.1 world garment adapter. Kissing's own kiss driver, guard, rear, reach,
  approach, step-back and memory recorder stay out of this service.
- The Integrations settings tab always lists a supported mod, even when that mod is absent. The
  version is the one this adapter was verified with, not a semver compatibility promise; a later
  release may still work, and the tab does not report the installed version or a mismatch.

## Ownership

The facade owns the per-act provider state, the binding resolution, the save/restore table and the
lifecycle. A per-act catalog provider owns only policy: whether it applies, and which properties it
wants set. A provider never reads a node, a tree, the clock, the filesystem, the settings file or
the runtime's private fields.

The world adapter owns its every-frame hull update, its cloth-jiggle pass and its fixed-fallback
node discovery, the per-node material overrides, its cached feature/debug values and the act-start
undress. The undress is the game's own `take_off` action when her executor exists, with the direct
wardrobe calls as its fallback. It reads the anatomy through `PONIES.anatomy` and the game
through the root the entry hands it on `on_world`; it never preloads either host and never edits
the pack.

The changelings adapter owns its provider layer registration, the installed-mare list, the typed
body form it returns for each of the pack's bodies, the `UnfplapTailPlacement` wrapper above her
spring chain and the pack's own change state. It reads the API through `PONIES.api`, and the
pack's
own public nodes and fields; it never edits the pack and never preloads a host. Its policy object
owns the offer timing, prompt and reveal effects; the adapter's text hooks own the player's reveal
and named-form words. Neither owns the form store or the binding fan-out.

The body-change service owns the source list, the form store, the apply path and the optional
forwards. The entry registers the providers and the service answers which source handles a pony;
the runtime and the debug block see the typed source and policy surfaces, never the pack.

The builder constructs one service per pony (`act/build.gd`) and passes its typed
`shared/act_facts.gd` view. The act modules call `begin()`, `tick()`, `afterglow()`,
`apply_live_settings()` and `reset()` at the ordered lifecycle points; `act/exit.gd:run()` remains
the only act teardown.

## Catalog

`shared/integrations.gd` is the single source for the tab and the adapter. A provider entry has
`mod_id`, `mod_name`, `author`, `verified_version`, `features` and `bindings`.

A binding is a path from the act pony: each step is `{"property": "..."}` or `{"child": "..."}`.
A step marked `"optional": true` makes the whole binding optional. The facade resolves every
binding at act start, re-checks required bindings each tick, and keeps optional bindings pending
until their node appears. The catalog order is the tab order.

Kissing 1.2.9 binds:

| Binding | Path | Required |
|---|---|---|
| `feelings` | pony child `KissingFeelings` | yes |
| `excitement` | pony property `excitement` | yes |
| `beat` | `excitement` child `Beat` | yes |
| `skeleton` | pony property `skeleton` | yes |
| `fidgets` | `skeleton` child `KissingFidgets` | no |

Pantyhose & Panties 0.1.1 is a world integration: its `bindings` dictionary is empty, so the
per-act facade never creates a provider for it. Its two features drive the world adapter below.

## Provider contract

`integrations/provider.gd` is the pure base. A provider implements:

```gdscript
func available(context: RefCounted) -> bool
func holds_excitement() -> bool
func start_actions(context: RefCounted, out: Array) -> void
func tick_actions(context: RefCounted, delta: float, out: Array) -> void
func afterglow_actions(context: RefCounted, out: Array) -> void
```

`holds_excitement()` asks the facade to acquire the runtime's shared excitement Beat hold while the
provider runs. The runtime refcounts named owners, so the kiss service and a provider can hold the
Beat at the same time; only the last release restores the original pause state. A provider never
writes `Beat.paused` itself.

`integrations/context.gd` carries the state, pose family, satisfaction, mood, seconds since the last
real stroke, act seconds, afterglow flag, Affection kind, the provider's reaction cap, whether the
provider's external mod is active this launch, the runtime feature snapshot and binding presence.
The external-mod flag comes from the runtime's `shared/act_facts.gd` `mod_active(id)` callback; a
provider that does not need it ignores the field. `integrations/action.gd` carries a `set` (required binding),
`bind` (optional binding) or `restore` action with one property and value. The facade saves each
original value before its first write and restores the saved values in reverse order on stop,
feature-off, missing required binding, failed start, act end or `reset()`. A `restore` puts one
saved original back without dropping the record, so a later write keeps the act-start value for the
final reset.

Providers must stay scene-free and must not preload a service, `runtime.gd` or `main.gd`;
`scripts/architecture.py --check` rejects that import edge.

## Body-change provider

`integrations/changelings.gd` extends `body_change/source.gd`, the typed provider base
(`docs/body_change.md`, `## Source extension point`). A provider implements the base's virtual
methods by path; it has no `class_name` and is registered by the entry's service list. The base
answers the neutral default, so a provider overrides only what it supports.

A provider owns its own pack read and its own forms:

- `is_active()`, `refresh()` and `handles_pony()` gate its pack and the bodies it may change;
- `change_in_progress()`, `active_change()` and the request methods own its one live change;
- `prepare_body(body, change)` returns the typed `BodyForm` for that presented body. It may be
  called again when a late variant settles and bumps the form revision;
- `claims_body()` and `presented_form_id()` let the entry adopt the spawned body and let the
  runtime read the shape the body actually wears;
- `target_form_id()` is the requested form, empty for the own form;
- the optional text hooks (`asks_form_change()`, `named_form()`, `named_form_note()`), installed
  list, tail hooks and `policy()` are the provider's presentation and business policy.

The provider observes its own pack. The shipped provider reads it at 10 Hz and calls
`body_change.notify_source_changed(self)` and `notify_body_ready(body)`; the base service never
polls and never scans every frame. The act handover reads the service's active change only for
suspension, late adoption, the restore guard and the watchdog (`docs/body_change.md`,
`docs/runtime.md`).

The provider-policy execution is `docs/body_change.md`'s; the shipped policy's contents are
`## Queen Chrysalis` below. Bonus climax has no implementation.

A future regular-changelings pack gets its own provider under `integrations/`, constructed and
registered the same way; it reads that pack's own public fields and leaves the runtime core and
the base service unchanged. No second real provider is registered now, and no future pack id is
added to unfplap.

## Kissing provider

`integrations/kissing.gd` runs when `features.kissing_reactions` is on and the required bindings
exist. It exists to keep Kissing's build-up, which is driven by `Feelings.level`, under act control
while suppressing the game's own burst excitement. The act owns the level instead of giving Kissing
a permanent cause:

- Start: clear `excitement._until`, take the shared excitement Beat hold, and suppress the optional
  `KissingFidgets` weight shift and hoof taps (`_root = -1`, `_tap_next = 1e9`).
- Tick: below the close band (`mood != "close"`) the target level is 0. Once she is close and a
  real stroke landed within `ACTIVE_GRACE_S = 1.2 s`, the target ramps from 0 to her bond cap with
  readiness (`CLOSE_AT = 65` to 100), and the provider eases `feelings.level` toward it. The cap is
  read from Kissing's `Feelings._peak()` at provider start and carried as `context.reaction_cap`, so
  the ramp never exceeds the stage's ambient ceiling. When the player stops stroking, the target
  falls to 0 and the level fades.
- The cause (`excitement._until = 0.5`) stays set only while the level is above the resting
  threshold, which keeps Kissing's hold topped up; afterglow clears it and lets Kissing's own 1.5 s
  hold + 4 s fade run.
- Climax: `state == CLIMAX` pins the target to `reaction_cap` at the climax rate, so the reaction is
  fully active for her bond even if the player keeps thrusting through it.
- An Affection kiss keeps its own cause and build-up; the provider resumes act control after it.
- Optional `KissingFidgets`: the weight-shift root and the hoof-tap clock stay suppressed through
  the act, because they move the skeleton root or lift a planted hoof. Her climax restores them for
  its duration, then suppresses them again when the climax ends or afterglow starts.

Kissing's horn aura/hum, wing shiver and earth-pony tail/ear fidgets are the three reaction families
in scope. The act's own wing controller creates the open-wing node the shiver needs.

## Pantyhose & Panties

`integrations/pantyhose.gd` is the world adapter the entry creates. It is
world-side rather than per-act: every frame it updates the hull transform and instance uniforms for
each worn piece, so the cloth follows the anatomy with no scan lag. It re-discovers the
`Wear_panties-*` and `Wear_pantyhose-*` nodes on a fixed fallback (0.5 s), and while the anatomy
mesh is shown and the bulge flag is on, gives every surface of the shared piece an override of the
copied compatibility shader. The original material stays on the shared mesh; the override is per
node, and every instance value is per node, so two mares never share a transform. The compatibility
material is cached per source material and variant, so each fabric keeps its own look parameters
while every mare shares it. With the cloth-jiggle flag on, a worn piece keeps that override even
with the anatomy hidden or the lift off, and its `hull_on` instance value is then off: the copied
shader is what carries the wobble. The previous override is saved and restored when neither the
lift nor the jiggle needs the copy (hidden anatomy, or a lift off with the jiggle off), on
feature-off, pack-off, node replacement and world close.

The lift samples `anatomy/garment_hull.gd`'s rest-surface outer depth field, built from the refined
anatomy mesh and shared by every mare. The field is the **rest appearance**: the base mesh with
`closed` at 1 and `ponut_scale` at the rest `anal_scale - 1`; `wink`, the anal keys and `stretch`
are at 0. The field takes the maximum Z per cell over every rest triangle, so the inner canal and
body-facing surfaces never win the max; the curved ponut-top/vulva-bottom silhouette is included.
The garment is removed at act start, so the field does not need the opened/stretched act shapes.
The shader maps the garment vertex into anatomy-local space with the per-mare transform, reads the
field, and pushes the cloth out along the anatomy's +Z by the surface difference plus the margin.
The margin is stored in anatomy-local units and converted back by the basis' Z scale, so the
slider stays in world millimetres. The field has a larger Y domain margin and the shader fades the
lift over only the outer 3%, so the ponut top and vulva bottom keep their full lift without
raising the margin over the vulva. The debug controls choose the field width, height, smoothing
and margin; the hull rows are unbounded debug values, and a high width/height or many smoothing
passes costs a one-time rebuild. The adapter updates the hull transform every frame; a precision
edit clears the cache and rebuilds after 0.3 s, and the Rebuild action rebuilds immediately. Both
are off the frame path. **Show hull** draws the heatmap as a continuous corner-grid surface from a
top-level world mesh that copies the anatomy mesh's transform, so the field can be inspected even
when the anatomy is hidden (far mesh or `act` mode outside an act); the overlay state and the
reason it is hidden are logged once per change with debug logs on.

On `runtime.act_started` (connected by the entry) the adapter reads `wanted()` under the
wardrobe's own `_season()` and
collects the kinds she wears from this pack (`panties-*`, `pantyhose-*`). It sends one `take_off`
action per kind through the game's action coordinator (`conversation_director.actions.commit`)
with the director's current turn — the same path as one of her own `[take_off]` replies. The
executor calls the pack's `set_worn()` and `dress()` synchronously inside that commit, so the
nodes are gone before the first rendered act frame, and the game records the action outcome for
her dialogue prompt. When the director, her executor or an accepted commit is unavailable, the
adapter falls back to the same two wardrobe calls itself: `set_worn(kind, false)` for every worn
kind, then `dress(pony, id, season)`. The id is the pony's `identity.id` and the season the
wardrobe's own `_season()` (falling back to `spring`), the same key and season every other
wardrobe call uses. `set_worn` writes the game's own `pony_off` state; the adapter does not
restore anything at act end, so she stays undressed until she is asked or given a new piece. A
missing wardrobe, pony id or worn piece is a quiet no-op.

The compatibility shaders are `integrations/shaders/pantyhose_common.gdshaderinc`,
`pantyhose_cut.gdshader`, `pantyhose_sheer.gdshader` and the cloth-jiggle
`pantyhose_jiggle.gdshaderinc`: a self-contained copy of 0.1.1's look with the hull lift and the
wobble added. The catalog's `verified_version` pins the copy. A renamed or changed pack shader is
left alone and logged once; the adapter never edits the pack.

**Jiggle the cloth** (`features.pantyhose_jiggle`) makes the cloth follow the game's own rump wobble
instead of running a second one. `FlankTouch` is the only simulator: every rendered frame it writes
`jiggle_amount`, `jiggle_time`, `jiggle_center` and `jiggle_normal` into the materials of its
`_jiggle_targets` pairs, in each mesh's own space, and `_end_jiggle()` returns them to null when the
wobble ends. `integrations/garment_jiggle.gd` reads those live values — not the redness decal and
not the raw age and amount — once per pony per garment pass.

The reference pair is the first one that carries a live field and whose mesh is visible, otherwise
the game body (`_body`), otherwise the first pair with a live field. That keeps the cloth on the coat
the player sees; a visible source-body mesh that never enters `_jiggle_targets` is not followed. A
missing `FlankTouch`, a missing or renamed field, a mesh outside the tree, or a null, zero or
negative amount is not a wobble: the cloth stays rigid, keeps its lift and logs nothing.

The coat's field is in its target mesh's local space, so the helper maps it into the worn node's own
space through the two live transforms: the centre through `garment⁻¹ × target`, the outward normal
and the body's up through their bases. The amount and the radius are multiplied by the target mesh's
mean axis scale over the garment node's, so a trimmed, rotated or differently scaled piece moves by
the coat's world amplitude and spread. The radius is the live `jiggle_radius` on that same coat
material while an act's reactions widen it, the stock `flank_jiggle.gdshaderinc` spread otherwise.
The world adapter runs its garment pass at process priority 100, after `FlankTouch`'s default 0, so
it reads the values the rendered coat uses in that same frame; a game change that moves `FlankTouch`
later has to move that constant with it. Every worn node of a pony carries six per-node instance
uniforms (`garment_jiggle_amount`, `_time`, `_center`, `_normal`, `_radius` and `_up`), so two mares
never share a wobble.

The copied shaders run the coat's own damped spring, ripple and vertical bob on the cloth, evaluated
at the rest cloth vertex and added after the hull lift, so the lift keeps sampling its rest UVs and
there is no normal tilt. The bob runs along the body's up as the coat's does, not along a trimmed
piece's own axis. Because one smack outside an act and a thrust or a smack during one all start the
game's own wobble, the cloth follows all three; the adapter wires no smack event of its own and the
follower works with the anatomy shown or hidden and with the lift on or off. A finished wobble clears
only the six uniforms, so the lift stays, and every restore path clears them while the compatibility
material is still the override, because the pack's shader does not know the names. The six jiggle
uniforms plus the ten hull ones are exactly Godot's sixteen instance uniforms per shader, so a new
per-node value has to be packed into an existing one or replace it.

## Queen Chrysalis

`integrations/changelings.gd` is active only while `Mods.is_active("changelings")` is true. It
registers one provider layer through `api.register_mare` with the adapter as the owner, so the
layer leaves with unfplap and is never written to `settings.json`:

- `id` `chrysalis`, source `changelings`, name `Queen Chrysalis`;
- the approved profile (`intensity firm`, `pattern teasing`, `touch caress, kiss`,
  `dislikes smack`, `talk praise, playful`, `warmth slow`, `tolerance normal`) and her
  second-person notes;
- the placement for her own body (`offset_y`, `offset_z`, `pitch_deg`, `scale`) over the global
  default, applied through her Celestia body profile;
- no `eligible` assertion: her identity decides age, so a young disguised shape still fails the
  act gate.

`installed_character_ids()` returns `["chrysalis"]` only while the pack is active and the layer is
registered. `body_change.installed_character_ids()` merges that with the live off-roster mares for
the Characters selector, so she is listed under **Other mares** even while she is away in the
Badlands. The base roster stays 103, and removing the pack removes the entry.

`PONIES.attach(pony)` calls `body_change.notify_body_ready(pony)` before the tail seat and the
anatomy bind. The service asks the provider's `prepare_body()` for the body's typed form and
mirrors it. Her own body (the pack's own meshes or its spring tail) gets:

- `pony_id chrysalis`, `form_id` empty, `form_name Queen Chrysalis`;
- `fit_id chrysalis` and the Celestia rig, because the cell body is the princess profile;
- `owned_mesh_meta chrysalis_own`, the pack marker her hide pass reads;
- the chain under the game rig's `Hair_tail` attachment as `tail_root`.

`ChrysalisHair` is the pack's hair controller; the attachment and its `Chain` are built on
`pony.skeleton` (`Hair_` + part), not under the controller. The adapter owns one
`UnfplapTailPlacement` node between `Hair_tail` and `Chain`; the resolved `tail_y`, `tail_z` and
`tail_tilt_deg` move and tilt that wrapper from the pack's modelled tail, the same absolute-offset
rule the seat uses from its reference dock. Her provider placement bakes her own tail reference,
so the global tail default stays a game-dock value and does not move her spring tail; a reset
keeps her look. The act modifiers keep saving, rotating and restoring `Chain` itself. The dock
keys do not apply. The chain is not a tail-seat row and has no dock.

A disguise (`geometry_variant` `changeling=<pony id>` in 0.2.12) gets `pony_id chrysalis`,
`form_id` and `fit_id` from the copied pony, that pony's rig from the shared profile table (the
ordinary rig for a regular mare), the same `owned_mesh_meta chrysalis_own` marker and no
`tail_root`, so it uses the copied pony's placement and the normal hair chain.

The pack builds `Hair_tail/Chain` during her body's ready, and the first prepare can still run
before the chain is readable or before the body has an identity. The adapter owns the late check:
six tries at 50 ms, scheduled from her own-body path and from an identity-less early body. It
finds the chain under `pony.skeleton` and, when that rig is not exposed, by searching for the
`Hair_tail` attachment. When the chain appears it re-prepares the body (the form's `tail_root`
changes its signature, so the revision bumps) and calls `PONIES.prepare_late(pony)` once for the
late anatomy/tail pass. The check does not depend on the anatomy seat, the tail row or a dock.

Her own body's hide pass runs every half second and hides every mesh under her model that lacks
the pack's `chrysalis_own` marker. The form carries that marker as `owned_mesh_meta`, the service
mirrors it to `anatomy_owned_meta` and the anatomy attachment copies it onto its parts, which ride
the same skeleton. A disguise keeps the marker too. Without it her body hides the anatomy once and
the visibility cache never re-shows it, because the state did not change.

A missing node or field is a quiet no-op, so a pack update can change the shape without a crash.
The integration does not depend on a new signal or a rebuilt pack. The typed `BodyForm` is the
internal contract between the provider and the base service; the mirrored `body_fit_id`,
`tail_pose_root` and `anatomy_owned_meta` metadata are the legacy readers' fallback and are not a
`docs/api.md` convention. The `UnfplapTailPlacement` node is adapter-owned state as well, not a
public convention.

The adapter is also the pack's body-change provider. It watches the pack's public `busy`, `actor`
and `disguised_as` at its own 10 Hz observation tick: `request_form()` captures the current actor
and calls `disguise(id)`; `request_own_form()` calls `reveal()`; a rising `busy` with the act pony
as `actor` is a change her own AI started, with no request call. The adapter records the typed
`BodyChange` with its origin and old body, and lets the service publish it to the runtime. If the
pack has already moved `actor` to the new body, the adapter still records the act pony as the old
body, so the watcher can suspend on it while the flame still holds it. A `busy` on another body
never reaches the act.

`prepare_body()` builds the form from the body it is given, never from one global fit flag. During
a named change it returns the target shape's form for the change's new body before the pack writes
the `changeling=<id>` variant: `form_id` and `fit_id` are the target, the rig is the target's
profile, the marker is kept and there is no own `tail_root` or wrapper. The old body and unrelated
ponies keep their own forms. When observation sees the new body's variant or `disguised_as` report
the target, the adapter calls `prepare_body()` again; if the descriptor changed, its per-body
signature bumps the revision, the service refreshes the bound body, and the adapter runs
`PONIES.prepare_late()` and `WORLD.refresh_body_lod()`. The per-body revision and signature
reset when the change ends.

The new body is claimed by its stable identity before the shape is known, and observation fills
`target_form_id` from the new body's `changeling=<id>` variant or `disguised_as`. `claims_body()`
accepts her own body for a true form and the `changeling=<id>` variant for a named shape.
`target_form_id()` stays readable for the act watcher after the change ends;
`presented_form_id()` reports the shape the body actually wears. `request_appear()` calls
`bring_out()` for the idle debug action. A `busy` from a visit end or another action that removes
her follows the old-body/watchdog path in `docs/runtime.md`; a young or male shape ends the act
cleanly instead of resuming it. Her own change never spends the player's post-climax offer: the
offer stays pending and only a shape the player names clears it.

The player's own words are the adapter's: `asks_form_change(text)` matches its reveal phrase set
(“true form”, “real you”, “real her”, “drop the disguise”, “unmask” and similar). `named_form(text)`
matches an adult mare's display name or id against the base roster and the entry's live
off-roster/provider list; it excludes the shape she already wears and herself, refuses an ambiguous
name (a tie or two whole names), and returns a shape only when the game's population has a scene the
pack can copy. A line is a choice only when it is a whole name or carries an imperative request
(“wear”, “become”, “turn into”, “change into”, “name yourself” or a leading “name”); a name mentioned
inside a sentence without one is ordinary talk, and a negated or descriptive line (“I don't want
Rarity”, “your name is Rarity”) never selects a shape. Names are matched as whole words, so an id
word does not match inside another word. `named_form_note()`
returns a short status when the line names a shape she already wears, herself, a body the
eligibility facade says is not an adult mare, or an uncopyable pony, and returns nothing for
ordinary talk. A population body outside the adult candidate list asks the facade's id-only
`eligible_id()`; there is no young/male name table in the adapter. The live candidate list
still gates every real choice. The reveal uses the existing talk turn and offer line; it adds no
dedicated reaction line. The pack needs no rebuild and no new signal.

The provider policy (`integrations/changelings_policy.gd`) offers after at least one pony climax,
in her own form and in `ACTIVE`, while no offer is pending and the reveal is unused. The prompt is
one short line in her voice. A named shape is a neutral continuation; the player-requested
own-form reveal supplies the heat, peak, cue and `form_reveal` memory mark. The runtime executes the
generic heat/cue/memory/peak effects and dispatches the six generic act milestones to
`on_act_event()`; this policy leaves that hook as the base no-op because `should_offer()` owns its
timing. The summary reads its own `form_reveal` flag for the extra comfort (`docs/body_change.md`,
`## Provider policy`). A second offer or reveal in one act does nothing. Bonus climax is deferred.

## Settings

One declaration per supported integration in `settings/service.gd`, each with its `##` description.

Each supported mod gets its own collapsible section, named `$mod_name by $author` and open by
default, under one blue **Experimental** notice at the top of the tab. The section body carries the hint `Verified with version: $verified_version`, then that
provider's player-facing declarations; its open state is stored under `integrations/Mods/<mod id>`.
The tab's one Debug block (behind **Enable debug**) carries the Pantyhose hull rows and the
**Pantyhose: rebuild hull** action; Kissing has no debug rows.
There is no installed/mismatch status and no other buttons. A flag edit during an act starts or
stops the Kissing provider live through `apply_live_settings()`; the Pantyhose flags are cached by
the world adapter on the same settings edit. Its cached flags, hull width/height, smoothing and
margins are fields with no code default: `apply_live_settings()` fills them before the hull or an
overlay reads them.

## Host boundary

| Host call | Purpose |
|---|---|
| `runtime.act.context.integrations` | the per-pony act facade, built once by `act/build.gd` |
| `begin()` | resolve bindings and start available providers after the act reaches `POSING_IN` |
| `tick(delta)` | update context, watch optional bindings and apply provider tick actions |
| `afterglow()` | apply the one afterglow action before Kissing's hold/fade |
| `apply_live_settings()` | restart or stop providers after a settings edit; refresh the world adapter's cached flags |
| `reset()` | restore every saved value after the base kiss reset in `act/exit.gd:free_pose()` |
| `shared/act_facts.gd` | typed read model passed to the constructor; no per-frame settings read |
| `hold_beat(owner)` / `release_beat(owner)` | acquire or release the runtime's shared excitement Beat hold |
| `PONIES.anatomy` | `garment(pony)` and its `hull()`, `transform()`, `parent()` and `visible()`, plus `rebuild_garment()` |
| `_game.mares` | the loaded mares the world adapter scans |
| `pony_wardrobe` group | the wardrobe's `wanted()`, `_season()`, `set_worn()` and `dress()` for the act undress |
| `conversation_director.actions` | the action coordinator's `commit()` and `executors`, so the undress is a `take_off` action when her executor exists |
| `shared/settings_change.gd` | calls the world adapter's `apply_live_settings()` after a settings edit, and the body-change service's per-body tail pass |
| `PONIES.api` | the changelings adapter's `register_mare()` / `unregister_mare()` |
| `PONIES._prepare(pony)` | calls `body_change.notify_body_ready()` before the tail seat and anatomy bind, then adopts a pending act instead of creating a runtime |
| `PONIES.prepare_late(pony)` | re-runs the body-change prepare and the anatomy `present`/`reseat_tail` pass after a mod adds a node the first pass needed; late form/ownership only, no runtime and no tail wrapper |
| `SETTINGS.apply_live()` | one settings pass after the settled form: the live anatomy controllers, the player part and the tail seats re-read, the body's LOD rebuilds |
| `WORLD.refresh_body_lod(pony)` | drops the new body's near/far LOD caches and re-arms its near mesh after a form or an adoption |
| `PONIES.body_change` `has_tail_placement()` / `apply_tail_placement()` / `tail_placement_report()` | the anatomy editor's read of the provider that owns a body's tail placement |
| `PONIES.adopt_pending_body(pony)` | the runtime's late-body path: prepare and adopt a body the spawn hook did not claim in time |
| `PONIES.live_character_ids()` | merges the body-change service's `installed_character_ids()` |
| `runtime.act.request_form_change()` | the act-side start of a body change; the watcher owns the suspension and the player flag marks the player's change, with only a true form exceptional |
| `runtime.adopt_body()` / `attach_to_body()` | moves the suspended act under the claimed body |
| `Mods.is_active("changelings")` | the adapter's installation gate |

## Verification / lab

- Start a standing act with Kissing 1.2.9 installed: no horn/wing/fidget reaction before the close
  band, a bond-capped ramp through it, the reactions fading when thrusting stops, and the full cap
  through the five-second climax.
- Start a missionary act: the same readiness-driven level drives the reactions.
- Toggle `Use Kissing reactions` off and on during an act, including during a base kiss: the
  provider stops and restores (including `level`), then starts again, and the Beat hold follows the
  last owner.
- At her climax the root sway and hoof taps return, and are suppressed again when it ends or
  afterglow begins.
- End the act and force-stop one: `_until`, `level`, the fidget fields and the shared Beat hold are
  restored.
- Remove Kissing: the tab still shows `Kissing by modChad` and `Verified with version: 1.2.9`; the
  flag has no effect.
- With the pantyhose pack as `0_pantyhose.pck`, give all eight kinds and check the bulge in
  `always` and `act` anatomy modes; start an act and confirm the immediate removal; check she stays
  undressed; turn each flag off; remove the pack; check the original materials come back and two
  mares keep independent transforms. Use **Show hull** and **Rebuild** to inspect the field; the
  overlay is desktop-only and is skipped headless.
- Smack a mare outside an act in each of the eight kinds and check the cloth and the coat move
  together: no gap opens between them at the peaks and troughs and the anatomy never shows through
  the cloth. Do it on cut and sheer, with the anatomy shown, with it hidden and with the lift off,
  and check the cloth's bob runs up and down with the rump's rather than along a trimmed piece's own
  axis. Smack two mares side by side and check the wobbles stay independent. At 60 and at 90 fps,
  start an act with the undress off and check thrusts and act smacks wobble the cloth in step with
  the coat, and that the borrowed act radius spreads both the same way. Turn **Jiggle the cloth**
  off: the cloth is rigid, the pack materials return with the lift off, and `last-run.log` holds no
  shader or uniform warning.
- With Queen Chrysalis 0.2.12 installed, open Settings → Characters: **Queen Chrysalis** is under
  **Other mares** with the approved profile, before she visits. Turn the pack off: the entry and
  the provider layer are gone and the base roster still reads 103.
- Visit her anatomy in `always` and `act` on her own body; check the scale and position and that
  the spring tail lifts asides in standing and lays in missionary. Take a disguise shape and check
  it uses the copied pony's fit and the normal hair tail.
- Point at her own body in the Anatomy Debug block: **Placement tail** moves the
  `UnfplapTailPlacement` wrapper, **Placement tail tilt** turns it, and a dock action answers
  `no dock on this tail.` `Show placement` includes the `chrysalis custom tail offset=...` line.
  Nudge her tail during a standing and a missionary act and confirm the act's tail modifiers do
  not undo the wrapper. Check a body swap, the pack switched off, a regular mare and
  Celestia/Luna are unchanged.
- In the World Debug block, **Form: bring her out** brings her out while idle; **Form: true form**
  and **Form: next named shape** drive the body-change service outside an act. During a standing
  and a missionary act the same two actions exercise the body handover: the flame plays, the act
  re-poses on the new body and continues, and a second change is refused until the first finishes.
- Disguised during a standing or missionary act, say the reveal ask in the game's talk turn
  (`T`/microphone): the flame plays, the act re-poses on her own body and continues, the readiness
  spike and the reveal impression/peak/comfort appear once, and a second ask does nothing. Her own
  AI reveal must get the handover but not the exceptional event.
- Let her own AI take the shape off or put one on during an act (`[take_off: disguise]` /
  `[put_on: …]` or the pack's own controls): the same handover runs with no exceptional event. A
  change while she is not the act pony leaves the act alone; a visit end that removes her ends the
  act cleanly.
- After one climax in her own form, wait for the offer line; no HUD row may name the reveal or the
  gift. Name a base adult mare and check the act re-poses on that disguise with no comfort or peak
  boost. Name a young or male body and check the short status and the unchanged act. Say a name
  without an imperative (“you are a rarity”, “your name is Rarity”, “I don't want Rarity”) and
  check it is ordinary talk.
- Let her own AI change shape while the offer waits: the act re-poses neutrally and the offer stays
  pending; naming a shape afterwards still works.
- Leave the offer unanswered through an act end: no change, and the next act may offer again. A
  named change that fails before a new body arrives puts the offer back.
- Let her AI start a change during the restore window: the act finishes its teardown through the
  one exit instead of leaving the body to be freed under the runtime.
- With **Enable debug** on, check the run log's `form hint suppressed` line clears at the climax,
  afterglow and restore while the HUD row stays empty, and that a held body refuses the request.
