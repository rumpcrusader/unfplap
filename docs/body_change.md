# Body change

The base body-change mechanism: one presented body has one typed body form, a provider supplies a
borrowed or custom form, and every body-bound system is rebound or refreshed through one fan-out
when the form changes. The provider owns its pack, its offer/reveal policy and its own observation;
the base service never polls.

## Scope

`body_change/service.gd` owns the per-body form store, the default own form, the typed source and
binding registries, the per-body active-change read and the legacy metadata mirror.
`body_change/source.gd` is the documented provider base, `body_change/wire.gd` writes the legacy
keys from the typed form, and `integrations/changelings.gd` plus
`integrations/changelings_policy.gd` are the one shipped provider. `body_change/wire()` builds the
five body-bound systems — `anatomy/body_binding.gd` and the service's own `runtime_binding.gd`,
`lod_binding.gd`, `garment_binding.gd` and `smack_binding.gd` — from the facades the entry hands it.

The mechanism covers:

- the lifecycle of a body change and its typed read model;
- the form descriptor that anatomy, tail, camera, pose, appearance, LOD and the world adapters
  measure;
- the typed binding fan-out and the one place a form is applied to a body;
- the provider source contract and the provider-owned observation path;
- the generic provider-policy execution for offers and reveals.

It does not cover the act state machine, the pose session, the camera shot or the act teardown.
Those stay in `docs/runtime.md`, `docs/poses.md` and `docs/camera.md`.

### Business model

| Term | Meaning |
|---|---|
| pony identity | the persistent character; `pony_id` is the relationship id, then the identity id |
| presented body | the scene node the world sees |
| body form | the typed descriptor of one presented body |
| own form | the identity's own body; `form_id` is empty |
| borrowed form | a form the identity wears that is not its own body |
| target form | the form a change requests |
| form fit | the anatomy/tail placement row key, `fit_id` |
| rig | the body scale and rear anchor profile, `RigProfile` |
| body change | a transition between presented bodies |
| body change source | the provider that supplies forms and observes its pack |
| body binding | a system attached to the presented body |
| provider policy | the provider's offer, timing and reveal behavior |

A pony has one identity and one presented body. The identity survives a body change unchanged. The
presented body carries the form.

## Ownership

The service owns the form for each presented body, the applied revision, the registration order,
the live-change indexes and the default-form cache. A source owns its pack, the forms it returns,
its own observation cadence and its optional policy. A binding owns its attachment to the body.

The service never owns the act state, the pose, the camera or the teardown, and it never calls
`force_stop()` or an act exit. The runtime owns suspension, adoption and the one resume; the
service owns
service construction and the idle path, and the service builds its own bindings from the facades
the entry hands it. The identity's social state (memory, dialogue, preferences, eligibility, history
and summary) is owned elsewhere and reads `pony_id`, not the form.

## Types

All types are loaded by path; none uses `class_name`. The read models and binding/policy bases are
`RefCounted`; the source base is a `Node` world extension.

### `BodyForm` — `shared/body_form.gd`

One presented body's descriptor:

| Field | Type | Meaning |
|---|---|---|
| `pony_id` | `String` | stable identity; social systems read this |
| `form_id` | `String` | empty for the own form, otherwise the borrowed/custom form id |
| `form_name` | `String` | presentation name for the caption and dialogue |
| `fit_id` | `String` | anatomy and tail placement row key |
| `rig` | `RigProfile` | body scale and rear anchor |
| `owned_mesh_meta` | `String` | source body's mesh-hide marker; empty for none |
| `tail_root` | `Node3D` | source-owned tail wrapper; null for the normal hair chain |
| `body_scale` | `float` | the body's live scale |
| `revision` | `int` | bumped when a late variant revises the descriptor |

`is_own()` is true when `form_id` is empty. `BodyForm.default_form(pony)` builds the identity's own
form and is the only default builder.

The default own form has `pony_id` from the relationship metadata then the identity, `form_name`
from the identity's display name (else the stable id), `fit_id` from the body-fit metadata then the
identity's `character_id` then its id, `rig` from the identity's `character_id` then its id
(ordinary when the table has no row), no source marker or tail root, the body's live scale and
revision zero.

### `RigProfile` — `shared/body_profile.gd`

The typed rig a form carries: `id`, `rear_y`, `rear_z` and `scale`. `is_ordinary()` is true for the
shared mare body's rig. The module owns the profile table, the ordinary rig, the body-fit key and
the entrance-offset math; `rig_for_identity()`, `rig_for_pony()`, `rig_for_key()` and
`ordinary_rig()` are the typed readers. The array accessors `body_profile()`,
`body_profile_for()` and `body_fit_id()` remain as legacy compatibility for the placement editor
and the tail seat's no-form fallback; new code reads `BodyForm.rig` and `BodyForm.fit_id`.

### `BodyChange` — `shared/body_change.gd`

The read model of one transition, with `State { REQUESTED, PREPARING, ADOPTED, SETTLED, FAILED }`
and `Origin { PLAYER, AI, PROVIDER }`. Fields: `source`, `origin`, `previous_body`, `next_body`,
`target_form_id`, `form`, `state` and `started_s`. `source` is a narrow `Node` handle so the
shared read model does not import the provider base; the service validates it against the source
base before it stores a change.

### `BodyBinding` — `shared/body_binding.gd`

The typed base for one attachment:

```gdscript
func binding_id() -> String
func bind_body(body: Node3D, form: BodyForm) -> void
func refresh_body(body: Node3D, form: BodyForm) -> void
func unbind_body(body: Node3D) -> void
```

The base answers with empty defaults. A service's binding extends it by path, forwards to its own
facade and returns a short `binding_id()` for the service log.

### `BodyChangePolicy` — `shared/body_change_policy.gd`

The typed base for a provider's offer/reveal behavior:

```gdscript
enum ActEvent { ACTIVE, CLIMAX_END, AFTERGLOW, OFFER_ACCEPTED, REVEALED, FORM_SETTLED }

func on_act_event(event: ActEvent, context: BodyChangeActContext) -> void
func should_offer(context: BodyChangeActContext) -> bool
func offer_prompt() -> String
func on_offer_accepted(context: BodyChangeActContext) -> BodyChangeEffects
func on_reveal(context: BodyChangeActContext) -> BodyChangeEffects
```

`BodyChangeEffects` carries `heat`, `peak`, `cue` and `memory_kind`; `0` and `""` mean no effect,
and `is_empty()` tests that. `BodyChangeActContext` carries the stable id, the presented form, the
change, the origin and state, the offer/reveal flags, the climax count and cap and whether the act
is active. The runtime reuses one context value per act and never allocates one per frame. The base
answers no offer and empty effects; the provider decides whether a generic event matters.

### `BodyChangeSource` — `body_change/source.gd`

The typed provider base is a `Node` world extension. Its virtual methods are:

```gdscript
func source_id() -> String
func is_active() -> bool
func refresh() -> void
func handles_pony(pony: Node3D) -> bool
func change_in_progress() -> bool
func active_change() -> BodyChange
func request_form(body: Node3D, form_id: String, origin: BodyChange.Origin) -> bool
func request_own_form(body: Node3D, origin: BodyChange.Origin) -> bool
func prepare_body(body: Node3D, change: BodyChange) -> BodyForm
func claims_body(body: Node3D) -> bool
func target_form_id() -> String
func presented_form_id(body: Node3D) -> String
func asks_form_change(text: String) -> bool
func named_form(text: String) -> String
func named_form_note(text: String) -> String
func policy() -> BodyChangePolicy
func installed_character_ids() -> Array[String]
func has_tail_placement(pony: Node3D) -> bool
func apply_tail_placement(pony: Node3D) -> void
func tail_placement_report() -> String
```

The base answers the neutral default, so a provider overrides only what it supports. The text
hooks, the policy, the installed list and the tail hooks are optional. The provider owns its form
names, its shape lookup and whether a named form is copyable and adult.

## Internal API

`PONIES.body_change` (`body_change/service.gd`):

```gdscript
setup()
wire(anatomy, pantyhose, stock_smack)
register_source(source) -> bool
unregister_source(source)
register_binding(binding) -> bool
unregister_binding(binding)
active_sources() -> Array[BodyChangeSource]
active() -> bool
on_world(host)
installed_character_ids() -> Array[String]
has_tail_placement(body) -> bool
apply_tail_placement(body)
tail_placement_report() -> String
source_for(body) -> BodyChangeSource
policy_for(body) -> BodyChangePolicy
active_change_for(body) -> BodyChange
active_change() -> BodyChange
form_for(body) -> BodyForm
pony_id_for(body) -> String
default_form(body) -> BodyForm
apply_form(body, form)
bind_body(body)
refresh_body(body)
unbind_body(body)
notify_source_changed(source)
notify_body_ready(body)
request_form(body, form_id, origin) -> bool
request_own_form(body, origin) -> bool
```

Registration rejects an object that is not the typed base. Registration order is the binding
fan-out order and the source lookup order. `wire()` is the one call that builds the built-in
binding chain; `register_binding()` stays public for a provider or a test that adds its own
binding, which joins the end of the same fan-out.

### Form store and apply path

`_forms` maps a presented body to its form, including the cached default. `form_for()` returns the
stored form, builds and caches the default when the body has none, and returns null for an invalid
body. `pony_id_for()` reads the form's stable id.

`apply_form(body, form)` is the one apply path:

1. clamp a non-finite or out-of-range body scale to the game's capsule range;
2. store the form and its applied revision;
3. mirror the legacy keys through `body_change/wire.gd`;
4. write one debug line with the body, stable id, form, fit, rig, marker, scale, revision, previous
   form, action and registered binding names;
5. call every binding's `bind_body()` for a new body, `refresh_body()` for the same body with a
   new revision or changed typed values, or neither when the same form is re-applied unchanged.

The first apply to a body connects a one-shot `tree_exiting` unbind, so a body that leaves the tree
releases its bindings once even if its owner does not call `unbind_body()`. `bind_body()` adopts a
body with its stored or default form and is idempotent. `refresh_body()` re-reads the stored form
and refreshes every binding; an unbound body binds instead. `unbind_body()` releases every binding,
drops the stored form and revision and prunes the body's active-change index.

A provider's form may carry a `tail_root` that arrives frames after the first prepare. The
provider's form signature changes, its next `prepare_body()` bumps `revision`, and the service's
refresh path updates the anatomy and tail without a new body.

### Active changes

The service indexes a live change by source and by both presented bodies. A provider runs one
change at a time, so the source key is unique; the body key makes the runtime's old-body and
new-body reads constant-time. `active_change_for(body)` returns the change for one presented body
and falls back to a scan when a provider filled a typed field without a notification.
`active_change()` is the compatibility read of the first live change in source order, for
diagnostics.

A terminal change (`SETTLED` or `FAILED`) clears its source entry. A second provider cannot
overwrite a live change already indexed for the same body, so an idle body's change never replaces
an act's change. A body leaving the tree releases only the change keyed to it; the old body keeps
the change while the new body is alive, and a new body that leaves before it settles clears it.

The provider keeps the terminal change as a read-only record for the act's completion read;
`change_in_progress()` is the in-progress gate.

### Provider notification

`notify_body_ready(body)` asks the claiming provider for the body's form and applies it:

- the claiming source is the first active source whose `claims_body()` accepts the body, else the
  first active source that handles it;
- a `REQUESTED` change becomes `PREPARING`;
- `prepare_body()` returns the form; a null form leaves the default in place;
- when the body belongs to the live change, the service records `next_body`, `form` and
  `ADOPTED` and tracks the change for the runtime;
- a body outside the live change still receives the handling provider's form, but never rewrites
  another change's record.

`notify_source_changed(source)` accepts only a registered source and adopts its current change. A
terminal or null change clears the active entry; an unknown source cannot inject one.

`request_form()` and `request_own_form()` forward to the source that handles the body and adopt the
change when the provider accepts it. A refused request returns false and changes nothing.

### Legacy metadata mirror

`body_change/wire.gd` writes `body_fit_id` (`fit_id`), `anatomy_owned_meta` (`owned_mesh_meta`),
`tail_pose_root` (`tail_root`) and the live body scale. An empty marker or a missing tail root
removes the old key, so a return to the own form cannot leave a borrowed body's marker behind. The
game's `set_body_scale()` updates the capsule and the pose calibration; `GAME.set_body_scale()` uses
it when the body has it and falls back to a plain field write for a test body. The typed form is the
only authority: the mirror is write-only and no system reads a partial form back out of it. The
compatibility status of each key is the owning system's doc; the planned retirement is when every
binding reads `BodyForm`.

## Lifecycle

- Scope: world
- Constructed by: the entry's service list (`_build_services()`)
- Begin: `setup()` and then `wire(anatomy, pantyhose, stock_smack)` in the same list; the providers
  are registered after their own setup
- End: world close; the service node, its forms and its registries are freed with the entry
- Idempotent: yes

A change runs as follows:

1. The runtime (a live act) or the debug block (idle) asks the service for a named or own form.
2. The provider accepts and creates a `BodyChange` in `REQUESTED`; the service adopts it.
3. The provider prepares the next body and returns its `BodyForm`; the state becomes `PREPARING`.
   This happens before anatomy, tail, camera and pose attach.
4. The service applies the form and fans out `bind_body()` on the new body; the state becomes
   `ADOPTED`.
5. The provider settles its pack. If a late variant changed the descriptor, it bumps the revision
   and notifies the body again; the service fans out `refresh_body()` on the same body. It then
   marks the change `SETTLED` or `FAILED` and notifies the service.
6. A live act resumes once through `body_change/act.gd:resume()`, after the watcher returns the
   `RESUME` action; `act/swap.gd:resume()` is its only caller and ends the act through the one exit
   when it fails. The act state, depth, climaxes, history and
   event id survive.
7. A failed change leaves the previous body and form in place (or restores them through the
   provider) and leaves the runtime's offer logic to restore the player's offer.
8. An idle change runs steps 2–5 without an act; the entry's normal `_on_pony` path may attach a
   runtime to the new body.
9. An in-place change (same node, new variant) keeps the presented body and bumps the revision;
   bindings refresh instead of rebind. The runtime's refresh path also recomputes the visual frame:
   it clears the smoothed shot and calls `act/frame.gd:refit()`, which re-solves Anon's placement and
   stance for the revised form without replaying the entrance. A bed act re-reads the live body
   scale in its view.

The service does not own the act's suspension, adoption or resume. A suspended act's runtime
ignores the runtime binding until the one resume; see `docs/runtime.md` (`## Body swap`).

## Bindings

`body_change.wire()` constructs and registers the five body-bound systems from the facades the
entry hands it, in this order: anatomy, runtime, LOD, garments, stock smack. The registration order
is the fan-out order and the order the service's debug line names. A facade the build or the player
did not provide — an absent anatomy or Pantyhose pack — registers no binding and the rest of the
chain still runs. A binding a provider or a test adds with `register_binding()` joins the end of
the same fan-out, and no binding adds a line to the entry.

| Binding | Built from | Reads | Refreshes |
|---|---|---|---|
| `anatomy/body_binding.gd` | the anatomy facade | `fit_id`, `rig`, `owned_mesh_meta`, `tail_root` | anatomy placement and rig, appearance, owned marker and the tail seat row |
| `body_change/runtime_binding.gd` | `PONIES.runtime_for()` | body, form | the live runtime's pose, face, hands, kiss, player frame, view, reactions, wings and audio; a suspended act is left to the one resume |
| `body_change/lod_binding.gd` | `WORLD.refresh_body_lod()` | body | drops the near/far LOD caches and re-arms the near mesh |
| `body_change/garment_binding.gd` | the Pantyhose adapter | body | one worn-garment scan; the adapter has no per-pony rebind |
| `body_change/smack_binding.gd` | the stock smack layer | body | hands the body to the outside-act stock smack layer |

Every binding is scene-free: it reads the facade it was built from and preloads nothing else.

The runtime owns its sub-services behind one binding; they have no separate public binding files.
The runtime binding looks the runtime up through `PONIES.runtime_for(body)` and never runs an act
exit. `bind_body()` and `refresh_body()` both forward to the runtime's idempotent rebind; a body
without a runtime is inert.

The anatomy binding stores the form in the anatomy facade, creates the per-pony controller with
that form and refreshes the tail seat row. A revised form with the same rig and fit re-applies the
live placement; a changed rig or fit rebuilds the placement, appearance and marker and re-seats the
tail. An unbind releases the tail row and detaches the controller, even when the node stays in the
tree.

The player frame has no separate binding: the runtime's rebind clears the smoothed shot and calls
`act/frame.gd:refit(form)`, which re-solves Anon's placement, stance and aim from the presented form
and re-publishes the head clearance, with no entrance replay. The solve derives the stance from the
player's true base, so a late revision cannot compound a previous eye offset. The pose has no
separate binding: the runtime's rebind binds the session and the resume rebuilds the live pose on
the new skeleton. `docs/camera.md` and `docs/poses.md` own those behaviors.

## Provider observation

The base service is push-only and never polls. A provider observes its own pack through its own
timer or signal and calls `body_change.notify_source_changed(self)` when its change state moves and
`notify_body_ready(body)` when a body spawns or a variant settles. The shipped provider observes at
10 Hz.

The act handover `body_change/act.gd` reads `body_change.active_change_for(pony)` on a `0.1 s`
cadence for suspension, adoption, the restore guard and the watchdog, and returns one typed action;
the runtime applies it. Neither polls the provider, and neither scans every frame. The base service
performs no every-frame scan either.

## Provider policy

The provider decides whether and when to offer, the offer prompt and the reveal effects. The base
runtime executes the generic effects and keeps the once-per-act gates:

- `should_offer(context)` is read on each live `ACTIVE` tick until the offer is made or spent. A
  false before the provider's trigger does not spend the offer. A source without a policy, or a
  policy with an empty prompt, never offers.
- `offer_prompt()` becomes the one `FORM_OFFER` reaction of the act.
- A player line that names a form starts a player-origin named change; a line that asks for the
  own form starts a player-origin own-form change.
- A completed player-named change calls `on_offer_accepted(context)`; a completed player-requested
  own-form change calls `on_reveal(context)` once and gives the act its exceptional face beat. A
  player-named change uses the provider's offer-accepted effects; an AI-origin change is neutral.
- The runtime executes `heat` and `cue` only while the act is `ACTIVE`, and turns `memory_kind`
  `form_reveal` into the reveal impression and `peak` into the reveal peak. The summary reads its
  own `form_reveal` input for the extra comfort; the effects carry no comfort value.
- An unanswered offer ends with the act; a player-named change whose handover fails before a new
  body arrives restores the offer. A change her AI starts leaves the player's offer pending.

`on_act_event()` receives the generic act milestones: `ACTIVE` on the first active entry,
`CLIMAX_END` when a pony climax ends, `AFTERGLOW` on the afterglow entry, `OFFER_ACCEPTED` when a
player-named change completes, `REVEALED` when a player-requested own-form change completes and
`FORM_SETTLED` when the act resumes on the presented form. The runtime dispatches them through one
helper with the reused act context; the provider decides whether an event matters. `should_offer()`
stays the per-`ACTIVE`-tick offer check. Bonus climax has no implementation; a later provider may
extend the policy once its behavior is specified.

## Source extension point

`body_change/source.gd` is the documented base-mod extension point for a new form provider,
including a provider added to the base game. A provider extends the file by path (no `class_name`),
is constructed by the entry, and is registered with `PONIES.body_change.register_source()`. The
service
validates the base type before registration, so a source outside the contract cannot enter the
registry.

The extension can rely on the service for the form store, the apply path, the binding fan-out, the
active-change index and the legacy mirror. It must supply its own:

- pack/feature gate (`is_active()`, `refresh()`);
- body handling and claims (`handles_pony()`, `claims_body()`);
- change state (`change_in_progress()`, `active_change()`, `request_*()`);
- the typed form for each body (`prepare_body()`);
- its own observation and its `notify_*` calls;
- optionally its policy, installed ids and tail placement hooks.

The base mod never mentions a provider's characters, pack ids or mesh marker. The static rule is
`scripts/architecture.py --check`.

## Identity and the presented body

`pony_id` is stable across a form change. Memory, dialogue, preferences, eligibility, act history
and summary read it and never the form. The act's id, relationship, history and summary remain the
identity's when the presented body changes.

A physical system reads the presented form: anatomy placement and scale, tail fit and root, camera
entrance, appearance, LOD and the body-bound controllers. The new body must still pass the act's
adult-mare gate; a young or male shape ends the act through the one exit. The act caption and
dialogue presentation name follow the presented form's `form_name`; an empty form name falls back
to the identity's display name. The normal dialogue prompt also carries the live written form state
(“your own body” or “<name>'s shape, not your own body”) from `form_name` and `is_own()`, so the
model reads the body the player can see instead of inferring it from an older shape event. The
stable `pony_id`, act id, memory, dialogue history, preferences, eligibility and relationship never
change with the form.

## Settings

No player-facing setting is added for the mechanism. A provider's own feature gate and timing are
the provider's; the debug logs are the only player-visible diagnostics. The debug body-change line
is written through `LOG.debug()` and obeys **Enable debug**.

## Controls and debug

The Debug block's **Form: true form**, **Form: next named shape** and **Form: bring her out** drive
the shipped provider from `docs/debug.md`. In a live act the two form actions go through
`runtime.act.request_form_change()` and the body handover; outside an act they ask the service, which
forwards to the provider and runs the idle change path. Bring-out is not a change.

The debug log's `body change` line carries the body, stable id, form, fit, rig, marker, scale,
revision, previous form, action and binding names. The runtime's `body swap` lines carry the
suspension, adoption, resume and failure phases.

## Host boundary

| Host call | Purpose |
|---|---|
| `_build_services()` | constructs the service, hands it the anatomy, Pantyhose and stock smack facades in one `wire()` call, and registers the providers |
| `on_world(host)` | re-reads every provider's own installation state, so each one re-reads its pack |
| `PONIES._prepare(pony)` | calls `notify_body_ready()` before the tail seat, the stock smack layer and a runtime |
| `PONIES.runtime_for(pony)` | the runtime binding's public lookup |
| `WORLD.refresh_body_lod(pony)` | the LOD binding's public refresh |
| `pantyhose.scan()` | the garment binding's public scan |
| `stock_smack.pony_ready(pony)` | the stock smack binding's public prepare |
| `PONIES.body_change` | the runtime's, the anatomy editor's and the debug block's service handle |
| `body_change/act.gd` | the act's swap record and form request; it owns `release()`, `resume()`, `rebind()` and the offer/reveal timing, while `act/swap.gd` holds the typed release/resume seams and the one `resume()` caller, and the runtime node keeps only the reparent, `attach_to_body()` and `adopt_body()` |
| `shared/settings_change.gd` | `apply_settings()` re-applies the handling source's tail wrapper for every live body after a settings edit |

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | anatomy | `anatomy/body_binding.gd` | the anatomy body binding this service constructs from the anatomy facade |
| service | dialogue | `dialogue/service.gd` | the reaction line the form offer queues |
| service | memory | `memory/service.gd` | the reveal impression and peak marks, and the form-offer reaction |
| service | ponies | `ponies/service.gd` | the runtime binding's per-pony runtime lookup |
| service | world | `world/service.gd` | the LOD binding's near/far cache refresh |
| service | world | `world/game.gd` | the base-game held and body-scale reads and writes |
| shared | act_state | `shared/act_state.gd` | the act state gate for the offer, reveal and player line |
| shared | body_binding | `shared/body_binding.gd` | typed body-bound system base |
| shared | body_change | `shared/body_change.gd` | body change type, state and origin |
| shared | body_change_policy | `shared/body_change_policy.gd` | provider offer/reveal policy base |
| shared | body_form | `shared/body_form.gd` | typed body form and the default own form |
| shared | log | `shared/log.gd` | log sink |
| shared | settings_change | `shared/settings_change.gd` | the settings change notification |

### Used by

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| host | ponies | `PONIES.body_change` | the runtime's, the anatomy editor's and the debug block's handle |
| host | runtime | `act/build.gd` | act suspension, adoption and provider policy |
| service | integrations | `integrations/changelings.gd` | the shipped provider base and policy |

## Tests

- `tests/body_change/test_service.gd` — the typed data, `RigProfile` mapping, the default form, the
  legacy mirror (fit, marker, tail root, scale through the game setter), the form store, the
  bind/refresh/unbind order, same-node revisions, the source/binding registries, the per-body
  active-change read, provider-owned notification and request forwarding, the `wire()` construction
  order, a missing facade as a quiet no-op, a binding added after the wire, and the runtime binding.
- `tests/integrations/test_changelings.gd` — the shipped provider's forms, markers, per-body fit,
  late revision and policy.
- `tests/handover/test_body_swap.gd` — the act handover, one resume, the stable id, the presented
  form name with the identity fallback, the late-revision eye and standing placement, auto
  settings/state preserved across the swap, the freed vocal-cache prune, and the provider policy's
  six act milestones in order.
- `tests/test_runtime_teardown.gd` — the one exit and the body-change bind/refresh ordering.
- `tests/anatomy/test_attach.gd`, `test_coat.gd`, `test_part.gd`, `test_placement.gd` — the anatomy
  binding, form rig/fit, marker, appearance and tail row.
- `scripts/architecture.py --check` — one body-change fan-out, one resume, one teardown, every
  shipped `.gd` with an owner, no body binding in the entry and no provider vocabulary in the core.

## Verification / lab

- During a standing and a missionary act, use **Form: next named shape** on a regular mare form:
  the anatomy is at ordinary scale and position, the tail and dock at the shape's placement, and
  the act continues at the same depth and climaxes. The debug log names the stable id, the borrowed
  form, its fit, rig and marker.
- Take the same shape while idle: the same anatomy and tail result, with no second runtime.
- Take a princess form: the princess rig and placement, with the source marker kept.
- Return to the own form: the own rig, the source tail root and marker, and no borrowed placement.
- Let a late variant settle several frames after the swap: the anatomy and tail refresh to the
  final form, not the early one.
- Force a failed shape or the watchdog: the old body and form survive, the offer behaves as before
  and no orphan anatomy or tail is left.
- Turn the pack off: its forms and policy vanish and the base mechanism is inert for that body.

## Related docs

- `docs/README.md` — the service index.
- `docs/runtime.md` — the act state, suspension, adoption and one resume.
- `docs/anatomy.md` — anatomy, placement, appearance and tail seat.
- `docs/camera.md`, `docs/poses.md` — the camera and pose refresh on a form.
- `docs/integrations.md` — the shipped provider and its policy.
- `docs/summary.md`, `docs/memory.md` — the reveal's summary and memory effects.
- `docs/debug.md` — the Form debug actions.
