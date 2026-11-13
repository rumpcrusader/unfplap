# Eligibility and consent

The eligibility system is the one gate for adult intimacy: adulthood, relationship level, kiss
willingness, act history, the estrus cycle and per-mare action consent. This file is the single
technical contract; other docs link here.

The internal API is `eligibility/service.gd`. The typed surface is `eligible`, `witness_age`, `get_verdict`,
`get_profile` and `set_profile`. Cross-mod exposure stays `docs/api.md`, which is not changed by
this contract.

## Scope

This contract covers:

- the one adult predicate and the per-target capability answers;
- the Promiscuity level and Starting Sex choice;
- base-game kiss willingness (`bonds.welcomes(id, "kiss")`);
- history withdrawal and offer blocks;
- the estrus cycle sex gate;
- per-mare public, anal and oral consent;
- the start hint, start attempt, buck refusal and history refusal;
- proactive offer eligibility and offer weight;
- mid-act withdrawal from a relationship change.

It does not cover act readiness, thrust, tolerance, pose or camera rules. The live scene rows
(state, navigator, bed, player, cuddle, affection) and the refusal executor are a separate
contract: `docs/scene_gate.md`.

## Architecture

| File | Role |
|---|---|
| `eligibility/service.gd` | public API and the only scene adapter: builds the typed facts and verdict, reads the live relationship runtime, settings profile, history, cycle and consent |
| `eligibility/policy.gd` | pure truth table: facts dictionary plus mode -> verdict dictionary, capability targets and witness age |
| `eligibility/facts.gd` | pure fact schema; the one adulthood predicate and the pure age category stay private here |
| `scene_gate/service.gd` | the live scene rows and the refusal executor; contract in `docs/scene_gate.md` |
| `docs/eligibility.md` | this contract |

The purity boundary is deliberate:

- `policy.gd` has no `Node`, `Time`, `SceneTree`, `FileAccess`, `SETTINGS` preload or scene
  preload. It receives plain data and returns plain data.
- `eligibility/service.gd` is read-only. It never saves settings, history or consent.
- Only `eligibility/service.gd` reads `bonds.welcomes`, `bonds.adults`,
  `bonds.eligible_for_romance`, `SETTINGS.promiscuity`, `SETTINGS.sex_start`,
  `SETTINGS.consent` for a gate, `ACT_HISTORY.blocks_start/blocks_offers/
  offer_weight` or `CYCLE.allows_sex`.
- `shared/act_history.gd`, `shared/cycle.gd`, `shared/consent.gd` and
  `shared/participation.gd` remain the authorities for their own data. Eligibility only composes
  their resolved results.
- No file outside `eligibility/` preloads the pure core. Another system calls the facade, which
  answers `eligible(pony, target)` or `witness_age(pony)`; it never inspects age, sex or the
  provider assertion itself.

## Data ownership

Eligibility stores nothing. Facts are a per-call snapshot and are never saved or added to the
per-character profile. The runtime's idle hint may reuse a typed `Verdict` in memory (`## Offer
hint snapshot`); that cache is never written, is not part of this service and always keeps the
live scene rows.

| Data | Stored where | Owner |
|---|---|---|
| Preference profile (intensity, pattern, warmth, tolerance, touch, talk, dislikes, notes) | `settings.json` -> `default.preferences` and `characters.<id>.preferences` (differences only) | `settings/service.gd`, `shared/character_preferences.gd`, `shared/preferences.gd` |
| Per-mare consent (public, anal, oral) | `settings.json` -> `characters.<id>.consent` (differences only) | `settings/service.gd` plus the `shared/consent.gd` resolver |
| Per-mare participation (`acts`, `anatomy`, `tail`) | `characters.<id>.profile.participation` (differences only); a provider's `adult` is a provider layer | `settings/service.gd` plus the `shared/participation.gd` resolver || Poses, prompts, `cue_gap`, `aftercare_min`, `smack_zone_radius` | `characters.<id>.*` | settings/profile modules |
| Act history | `Mods.state("unfplap").act_history` | `shared/act_history.gd` |
| Request cooldown | `Mods.state("unfplap").request_times` | `initiation/cooldowns.gd` (contract: `docs/initiation.md`) |
| Relationship stage, love, friendship, willingness | game save (`player_bonds`, impressions) | base game |
| Eligibility facts | nowhere | `eligibility/service.gd` per call |

Rules:

- No `characters.<id>.eligibility`, no eligibility block in `settings.json`, no eligibility block
  in `Mods.state("unfplap")`.
- `eligibility/service.gd` never calls `SETTINGS.save_*`, `ACT_HISTORY.commit/save` or
  `Mods.save_changed`.
- `facts.consent` is a snapshot. `get_profile(id).consent` re-resolves live.
- Preferences are not facts. Tolerance stays with `readiness/tolerance.gd`; eligibility never reads the
  preference profile.
- `shared/participation.gd:KEYS` and `shared/consent.gd:KEYS` are the only capability and consent
  key tables. Validation, the Characters form and the typed snapshots all iterate them.
- `shared/pony_id.gd:from()` is the only stable-id rule: `relationship_id` metadata first, then the
  identity id. Runtime, eligibility, placement, memory and the anatomy internals call it.
- `api.describe_mare()` keeps its static shape and is not extended with live eligibility.

## Public API

`eligibility/service.gd` extends `RefCounted`. `main.gd` creates one instance and exposes it as
`main.eligibility`. The types are declared in the facade, so a consumer names them
`ELIGIBILITY.Verdict`, `ELIGIBILITY.Target`, and so on.

```gdscript
enum Target { ACT, ANATOMY, TAIL, CHARACTER }
enum Mode { START, OFFER, MID_ACT }
enum Effect { NONE, BLOCK, REFUSE, HISTORY_REFUSE, OFFER_BLOCK, FLAG }
enum Age { NONE, YOUNG, ADULT }
enum AdultAssertion { IDENTITY, ADULT, NOT_ADULT }

class Participation: acts, anatomy, tail
class Consent: public, anal, oral
class Profile: adult, participation, consent
               adult_value() -> Variant  # null, true or false; the cross-mod shape
class History: tier, hurt, comfort, blocks_start, blocks_offers, offer_weight
class Facts: id, adult, participation, has_relationship, ... (see `## Facts`)
class Actions: public, public_offer, anal, oral
class Relations: id, stage, love_level, ... (see `## Verdict`)
class Row: key, ok, reason, effect
class Verdict: mode, base, show, attempt, offer, buck_refuse, history_refuse,
               stop, offer_weight, facts, actions, relations, rows
               reasons() -> PackedStringArray
               rows_text() -> String

func setup(main_node: Node) -> void
func clear() -> void

func eligible(pony: Node, target: Target = Target.ACT) -> bool
func witness_age(pony: Node) -> Age

func get_verdict(pony: Node, mode: Mode = Mode.START) -> Verdict

func get_profile(id: String) -> Profile
func set_profile(owner: Node, id: String, profile: Profile) -> Dictionary
```

`eligible()` is the capability answer. `witness_age()` is the only age-shaped answer and only
for witness wording. `get_verdict()` is the typed act gate. `get_profile()` reads the resolved
provider/player profile for one id; `set_profile()` writes the provider layer's adult assertion,
participation and consent. The pair is the cross-mod read/write side. The service stores nothing.

### Callers

| Caller | API | Scene work it keeps |
|---|---|---|
| `runtime.start_verdict()` | `get_verdict(pony, Mode.START)` | structural rows plus `scene_gate/service.gd` rows |
| `runtime.offer_verdict()` | `get_verdict(pony, Mode.OFFER)` | offer-safe `scene_gate/service.gd` rows |
| `runtime.start()` | `start_verdict()` | none |
| `runtime.refuse_available()` / `refuse()` | `buck_refuse` | `scene_gate/service.gd` refusal executor |
| `runtime._still_willing()` | `get_verdict(pony, Mode.MID_ACT)` | none |
| `main._refresh_offer()` | `runtime.hint_start_verdict().show` | candidate discovery; reuses the policy snapshot, runs live scene rows |
| `main.try_start()` | `runtime.start()` | none |
| `main._try_refusal()` | `runtime.refuse_available()` | none |
| `main` candidate scan | `eligible(pony, Target.ACT)` through `_is_act_target()` | candidate discovery |
| `main.live_character_ids()` | `eligible(pony, Target.CHARACTER)` | runtime roster, ordering |
| `initiation` | `get_verdict(pony, Mode.OFFER)` | cooldown, approach, bed search, privacy, classifier; see `docs/initiation.md` |
| `anatomy/act` | `get_profile(id).consent` | feature flags |
| `anatomy` facade | `eligible(pony, Target.ANATOMY)` | rig, assets, dock; forwards to its controllers |
| `tail_seat` | `eligible(pony, Target.TAIL)` through the anatomy facade | hair, dock |
| `memory` | `witness_age(pony)` | perception, sleeping |
| `standing_presentation` | `eligible(pony, Target.ACT)` | pose, state |
| `api.describe_mare()` | `get_profile(id)` | provider metadata, settings shape |

Only `runtime` combines policy rows with scene rows. The rows themselves are built by
`scene_gate/service.gd` (`docs/scene_gate.md`). The pure policy never sees a bed, a navigator, a pose
asset or the player body.

## Capability targets

A consumer asks about its own target and never inspects identity:

| Target | Veto | Callers |
|---|---|---|
| `Target.ACT` | `participation.acts` | act discovery, the standing invitation, the candidate scan |
| `Target.ANATOMY` | `participation.anatomy` | the anatomy controller and runtime attachment |
| `Target.TAIL` | `participation.tail` | tail seating |
| `Target.CHARACTER` | none | the Characters selector, so an opted-out mare stays editable |

`eligible()` is cheap by design: stable id, identity, provider assertion, `profile_identity` and
participation. It never builds the full fact snapshot, because discovery calls it in per-frame
loops. `witness_age()` returns `Age.YOUNG`, `Age.ADULT` or `Age.NONE`; a provider's `adult`
assertion wins over the identity flag in both directions.

## Facts

`Facts` is a typed object on `Verdict.facts`:

```text
id, has_identity, is_player_pony, is_filly, is_stallion, adult, participation,
has_relationship, registered_adult, romance_eligible, stage, love_level, willing,
promiscuity, sex_start, public_feature, player_young, player_pony,
cycle_phase, cycle_allows, heat, history, consent
```

`cycle_phase` comes from `runtime.cycle_phase()`, so the debug heat/diestrus override applies. A
pony that has only just spawned has no relationship runtime yet, so the read is a normal phase
until one exists; the anatomy bridge asks for it during its own bind.
`history` is resolved by `shared/act_history.gd`; `consent` by `SETTINGS.consent(id)`.
`adult` is the provider's tri-state assertion (`null` means the identity decides); `participation`
is the resolved per-mare capability block (`acts`, `anatomy`, `tail`), both by
`SETTINGS.profile_identity(id)`. `registered_adult` follows the same tri-state assertion when one
is set, and otherwise reads the game's `bonds.adults` entry. `willing` and `romance_eligible`
still come from the game's `bonds.welcomes` and `bonds.eligible_for_romance`.

Not in facts: the preference profile, poses, prompts, timing values, prompt names, mood,
first-time state, or request cooldowns.

## Verdict

`Verdict` is the typed gate returned by `get_verdict()`:

```text
mode: Mode
base: bool
show: bool             # the Make love hint appears
attempt: bool          # Y starts the act
offer: bool            # proactive offer allowed
buck_refuse: bool      # Y triggers refuse()
history_refuse: bool   # Y triggers refuse_from_history()
stop: bool             # mid-act withdrawal
offer_weight: float
facts: Facts
actions: Actions       # public, public_offer, anal, oral
relations: Relations   # id, stage, love_level, willing,
                       # promiscuity, sex_start, cycle_phase, heat, base
rows: Array[Row]       # key, ok, reason, effect
```

`reasons()` returns the failed rows' reasons; `rows_text()` renders the rows. `Row.effect` is
the `Effect` enum, not a string.

Rows and effects:

| Effect | Meaning |
|---|---|
| `block` | no hint, no start, no offer |
| `refuse` | hint may show; Y triggers the buck/push refusal |
| `history_refuse` | hint shows; Y speaks the history refusal |
| `offer_block` | start may be allowed; no proactive offer |
| `flag` | public/privacy flag; never a failure |

Reason keys: `adult`, `relationship`, `form`, `romance`, `promiscuity`, `participation`,
`relation`, `cycle`, `history`, `history_offers`, `public`.

## Modes and truth table

`base` = valid adult mare + relationship runtime + registered adult + adult player + romance
eligible + Promiscuity level pass.

| Condition | `show` | `attempt` | `buck_refuse` | `history_refuse` | `offer` | `stop` |
|---|---|---|---|---|---|---|
| not `base` | no | no | no | no | no | yes |
| `participation.acts` false | no | no | no | no | no | no |
| `!willing`, When Available | no | no | yes | — | no | yes |
| `!willing`, Try Your Luck | yes | no | yes | — | no | yes |
| `willing`, history withdrawn/stop | yes | no | no | yes | no | no |
| `willing`, history hurt (tier 2) | yes | yes | no | no | no | no |
| diestrus | no | no | — | — | no | yes |
| heat or public consent | — | — | — | — | privacy flag | — |

Rules:

- `history_refuse` wins over `buck_refuse`; it does not require willingness.
- `buck_refuse` ignores Starting Sex, cycle and history.
- `stop` requires base + willing + cycle; history does not stop an act.
- `participation.acts` is a block, not a refusal: a player who opts out of acts never gets a
  buck, a history refusal or a mood note. It is a boundary, not a mood beat.
- `show` and `attempt` are separate. Try Your Luck shows the hint while `attempt` is false.

## Offer hint snapshot

`main._refresh_offer()` runs at the 0.15 s hint cadence. It calls
`runtime.hint_start_verdict()`, which reuses one cached `Verdict` for `Mode.START` and still runs
every live scene row. Only the hint uses the snapshot: `runtime.start_verdict()`,
`runtime.offer_verdict()`, `runtime.start()`, the refusal path, `debug_line()` and the initiation
service build a fresh verdict.

The runtime stores the snapshot per pony with its last key and a 0.5 s fallback TTL. It rebuilds
when any of these changes:

- settings `generation` or the provider registry `revision`;
- `ACT_HISTORY.revision` (bumped by every stored history write);
- the player form kind or age;
- the cycle phase;
- the pony id, relationship runtime or bonds node;
- a `bonds.changed` or `impressions.changed` signal, where available;
- the TTL expiring, so a missed signal cannot stale the hint forever.

The scene gate receives the snapshot through its `verdict_in` argument, appends its live rows and
evaluates them normally. A cached `show` therefore never bypasses a closed door, a sleep, a cuddle,
a navigator lease or a footstool shortage. `runtime.stool_blocks_verdict()` reuses the same gate's
rows for the blocked hint instead of running the gate a second time.

## Adults

- There is one adulthood predicate: `eligibility/facts.gd:adult_pony()` and `adult_mare()`. It
  takes the identity flags and the provider assertion as values and decides age and sex only. It
  is private to `eligibility/`; `eligibility/policy.gd` delegates to it for a fact snapshot.
- `Target.ACT`, `Target.ANATOMY` and `Target.CHARACTER` accept an adult mare: an identified pony
  that is not a filly/colt, not a stallion and not the player's own pony. `Target.TAIL` is the
  same identity plus the tail veto.
- `eligible()` adds the stable id and the target's participation veto to the identity predicate.
  An adult identity with no stable id is not a target, and the capability never re-derives the
  predicate.
- A provider's `adult` assertion is a tri-state override: `true` or `false` overrides the
  identity's age flag; `null` lets the identity decide. It changes age, not sex. It is
  provider-only and never written to the player's settings.
- The same assertion resolves `registered_adult`: a provider can pass unfplap's relationship row
  for a pony the base game has not registered as an adult. It does not change `willing` or
  `romance_eligible`, which still read the game's `bonds.welcomes` and
  `bonds.eligible_for_romance`.
- Adult stallions are not act, anatomy or tail targets. They may still witness an act:
  `witness_age()` returns `Age.ADULT` for them.
- `witness_age()` returns `Age.YOUNG` for a filly/colt the provider has not asserted adult,
  `Age.ADULT` for an adult (or asserted adult), and `Age.NONE` for a pony who can be neither. It is
  the only age-shaped answer a consumer gets, and only for witness wording. The pure category is
  `eligibility/facts.gd:AgeKind`; the public `Age` enum has the same values.
- A young player blocks every act.

## Participation

`profile.participation` is the per-mare capability block: `acts`, `anatomy` and `tail`. It is
subtractive: `true` means "does not veto", never "grants". A missing key means the default
`true`. The `acts` key is an eligibility row with a `block` effect; it does not set
`buck_refuse` or `history_refuse`, and it does not change `stop`. A player who opts out of acts
is a quiet boundary, not a mood beat. The anatomy and tail keys gate `Target.ANATOMY` and
`Target.TAIL`; their rig checks stay in `docs/anatomy.md`. `Target.CHARACTER` ignores all three
so the Characters selector can always re-enable an opted-out mare.

A provider's `profile` is a layer; the player's `characters.<id>.profile` is a sparse difference
layer. The player's `Reset to default` clears the player's participation and returns to the
provider's default; it does not clear the provider's `adult` assertion.

## Promiscuity

The selected `relationship.promiscuity` is the lowest love level that can start an act. The ladder
is:

```text
Soulmates 4, Head Over Hooves 3, Marefriend/Coltfriend 2, New Couple 1, Crush 0, Any Adult -1
```

An unknown value falls back to Marefriend. `Any Adult` skips only this floor; adulthood,
relationship runtime and romance eligibility still apply.

## Kiss willingness

`bonds.welcomes(id, "kiss")` is the base-game authority. It already accounts for partner stage,
attraction, trust, anger, a boundary cooldown and temporary permissions. Eligibility does not
reimplement it.

`relation` is the willingness row. When it fails, the effect is `refuse`, not a silent block:
`buck_refuse` becomes true even when the hint is hidden.

A refusal is a real mood beat. `runtime.refuse()` tries the buck/push, then `_note_refusal()`
writes the game's impression (`main.memory.commit`, the `REFUSAL` slot): `annoyed` for a
turn-away, `angry` when she
bucked or knocked Anon down. It also calls `bonds.unwanted_contact(id, "kiss")` (trust -2,
boundary) and holds the matching face in `face/mood_face.gd`. `angry` makes `bonds.welcomes()` false, so
she refuses kisses and offers for the note's 300 s freshness.

## Starting Sex

`relationship.sex_start` decides whether the start hint waits for her to welcome a kiss:

- **When Available** requires kiss willingness. A mare who does not welcome a kiss has no hint and
  no proactive offer.
- **Try Your Luck** shows the hint before she welcomes the kiss. It **does not** drop the
  Promiscuity level and it **does not** skip willingness at start. Pressing Y still refuses when
  she does not.

Both modes use the same Promiscuity floor, the same base gate and the same willingness row.

## History and cycle

`shared/act_history.gd` owns the point math and tiers (`docs/summary.md`). `summary/service.gd` owns the runtime-side
summary/tolerance decisions and the refusal gate; the runtime still exposes
`refuse_from_history()`. Eligibility consumes:

- `blocks_start`: withdrawn tier or an active `stop_until`;
- `blocks_offers`: hurt tier or higher, or an active `stop_until`;
- `offer_weight`: the weighted proactive-offer chance.

Tiers: hurt 2–3 keeps normal offers but lowers their weight and may give a rare vague hint
(about one in four acts); hurt 4–5 makes no proactive offers while a player-initiated start is
still allowed; hurt 6+ (withdrawn) makes no offers and keeps the start hint with a spoken refusal
until repaired. An active `stop_until` blocks both the next start and proactive offers.

A withdrawn mare still shows the hint; pressing Y speaks the refusal. A hurt mare still accepts a
player-initiated start but makes no proactive offers.

`cycle.allows_sex()` blocks start and offers in diestrus. Heat does not change the gate; it changes
readiness, offer cooldown and the public-offer override.

## Per-mare action consent

`settings.consent(id)` resolves:

1. deterministic per-id defaults from `shared/consent.gd`;
2. a provider layer's `consent` block;
3. the player's differences in `characters.<id>.consent`.

Eligibility reads the resolved result. It never writes it. `public`, `anal` and `oral` are
independent:

- **Public** is an offer privacy override, never an act gate and never a refusal. It only matters
  while the **Allow public offers** switch is on (off by default).
- **Anal** gates `V`; **oral** gates `N`.
- Feature flags (`features.anatomy_holes`, `features.anatomy_oral`) are capability gates, not
  consent.

## Offers and privacy

A proactive offer uses the same public/heat override for bed, cuddle and standing:

```text
offer_allowed = private or heat or (features.act_public_offer and consent.public)
```

"Private" is a house with no other pony in that house, or outdoors with no other pony within
30 m. The offering mare is excluded from the other-pony checks. A public offer is still an offer;
the act itself does not require privacy.

Offer weight comes from history. A blocked history offer has weight `0`. Heat quarters the
proactive-offer cooldown (`HEAT_COOLDOWN = 0.25`) and adds the heat sentence to the ask prompt.
Cooldown, approach, bed search and the ask/consent classifier remain in the request service; its
contract is `docs/initiation.md`.

## Mid-act withdrawal

`Mode.MID_ACT.stop` is true when any of these changes after the act started:

- adult mare, adult player or romance eligibility;
- Promiscuity level;
- kiss willingness;
- Starting Sex bypass;
- estrus cycle allows sex.

`runtime._still_willing()` checks this every quarter second. A real tolerance stop is separate:
`readiness/tolerance.gd` owns disliked-touch distress and its warning/stop thresholds.

## Debug

- `runtime.debug_line()` prints `show`, `attempt`, `offer`, `buck`, `history`, the policy rows and
  the relation facts. It does not re-derive the gate.
- `Verdict.rows_text()` returns the same policy view without scene rows.
- The Debug actions **Trigger bed offer** and **Trigger standing offer** use the same service.
- The Debug actions **Force/Clear heat** and **Force/Clear diestrus** feed `cycle_phase`; Clear
  sets the session phase to `normal`, and **Resume automatic cycle** clears the override. None of
  them bypasses the gate.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | registry | `registry/service.gd` | provider layers and stable ids |
| service | settings | `settings/service.gd` | settings declarations and live values |
| shared | consent | `shared/consent.gd` | consent keys and defaults |
| shared | cycle | `shared/cycle.gd` | estrus cycle |
| shared | participation | `shared/participation.gd` | participation keys and defaults |
| shared | pony_id | `shared/pony_id.gd` | stable pony id |
| store | act_history | `shared/act_history.gd` | stored history rows |

## Lifecycle

- Scope: world
- Constructed by: `main._ready()`
- Begin: `setup()`
- End: `clear()`
- Idempotent: yes


## Tests

- `tests/eligibility/test_eligibility.gd`: the pure truth table, the one adulthood predicate,
  capability targets, witness age, Promiscuity, willingness, Starting Sex, history, cycle,
  public/anal/oral, participation and row effects.
- `tests/eligibility/test_eligibility_api.gd`: the facade's `eligible()`, `witness_age()`, typed
  facts and verdict, capability targets, the no-stable-id boundary, the profile consent, the
  provider layer through `set_profile()`/`get_profile()` and clear/setup lifecycle.
- `tests/test_pony_id.gd`: the stable-id rule (metadata wins, identity fallback, no identity).
- `tests/test_participation.gd`: the pure participation layer, defaults, partial merge and clean.
- `tests/test_source_hygiene.gd`: purity, the facade-only preload rule, the single-reader rule and
  the docs link.
- `tests/hands/test_actions.gd`: the invalid-pony gate smoke.
- `tests/scene_gate/test_scene_gate.gd`: the live scene rows, the navigator/player/bed
  predicates and the refusal executor; its contract is `docs/scene_gate.md`.
- `tests/initiation/test_policy.gd`, `test_prompts.gd` and `test_initiation_api.gd`: the offer
  rules, wording and facade; `tests/test_consent_classifier.gd` covers the classifier parsing.
  The request service's contract is `docs/initiation.md`.
- `tests/anatomy/test_anatomy.gd`: the anatomy target, participation, the provider's `adult`
  assertion and the rig checks.
- `tests/anatomy/test_identity.gd`: the princess body profile and the off-roster list.
- `tests/memory/test_memory_api.gd`: the facade's impression and event writes, the refusal mood
  and the stay-close reward.
- `tests/memory/test_text.gd`: the witness wording and the age split.

## Known limits

- The base game changes `bonds.welcomes()` over time; a mid-act mood swing can stop the act through
  the willingness row.
- Public consent is not a general exhibitionism gate; it is an offer privacy override.
- The internal API is not part of `docs/api.md`; the cross-mod `profile.mare` capability reads
  `get_profile(id)` and writes `set_profile(owner, id, profile)`. A live eligibility verdict is
  not part of the API.
