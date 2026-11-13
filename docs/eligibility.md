# Eligibility and consent

The eligibility system is the one gate for adult intimacy: adulthood, relationship level, kiss
willingness, the lover bond, act history, the estrus cycle and per-mare action consent. This file
is the single technical contract; other docs link here.

The internal API is `eligibility.gd`. The typed surface is `eligible`, `witness_age`, `get_verdict`,
`get_profile` and `set_profile`. Cross-mod exposure stays `docs/api.md`, which is not changed by
this contract.

## Scope

This contract covers:

- the adult identity predicates and the per-target capability answers;
- the Promiscuity level and Starting Sex choice;
- base-game kiss willingness (`bonds.welcomes(id, "kiss")`);
- the stored mod lover bond;
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
| `eligibility.gd` | public API and the only scene adapter: builds the typed facts and verdict, reads the live relationship runtime, settings profile, lover bond, history, cycle and consent |
| `eligibility/policy.gd` | pure truth table: facts dictionary plus mode -> verdict dictionary, capability targets and witness age |
| `eligibility/facts.gd` | pure fact schema; the identity predicates stay private here |
| `scene_gate.gd` | the live scene rows and the refusal executor; contract in `docs/scene_gate.md` |
| `docs/eligibility.md` | this contract |

The purity boundary is deliberate:

- `policy.gd` has no `Node`, `Time`, `SceneTree`, `FileAccess`, `SETTINGS` preload or scene
  preload. It receives plain data and returns plain data.
- `eligibility.gd` is read-only. It never saves settings, history or bonds.
- Only `eligibility.gd` reads `bonds.welcomes`, `bonds.adults`,
  `bonds.eligible_for_romance`, `SETTINGS.promiscuity`, `SETTINGS.sex_start`,
  `SETTINGS.consent` for a gate, `SEX_BOND.bonded`, `ACT_HISTORY.blocks_start/blocks_offers/
  offer_weight` or `CYCLE.allows_sex`.
- `sex_bond.gd`, `act_history.gd`, `cycle.gd` and `consent.gd` remain the authorities for their
  own data. Eligibility only composes their resolved results.
- No file outside `eligibility/` preloads the pure core. Another system calls the facade, which
  answers `eligible(pony, target)` or `witness_age(pony)`; it never inspects age, sex or the
  provider assertion itself.

## Data ownership

Eligibility stores nothing. Facts are a per-call snapshot and are never cached, saved or added to
the per-character profile.

| Data | Stored where | Owner |
|---|---|---|
| Preference profile (intensity, pattern, warmth, tolerance, touch, talk, dislikes, notes) | `settings.json` -> `default.preferences` and `characters.<id>.preferences` (differences only) | `settings.gd`, `character_preferences.gd`, `preferences.gd` |
| Per-mare consent (public, anal, oral) | `settings.json` -> `characters.<id>.consent` (differences only) | `settings.gd` plus the `consent.gd` resolver |
| Per-mare participation (`acts`, `anatomy`, `tail`) | `characters.<id>.profile.participation` (differences only); a provider's `adult` is a provider layer | `settings.gd` plus the `participation.gd` resolver |
| Poses, prompts, `cue_gap`, `aftercare_min`, `smack_zone_radius` | `characters.<id>.*` | settings/profile modules |
| Lover bond | `Mods.state("unfplap").sex_bonds` | `sex_bond.gd` |
| Act history | `Mods.state("unfplap").act_history` | `act_history.gd` |
| Request cooldown | `Mods.state("unfplap").request_times` | `initiation/cooldowns.gd` (contract: `docs/initiation.md`) |
| Relationship stage, love, friendship, willingness | game save (`player_bonds`, impressions) | base game |
| Eligibility facts | nowhere | `eligibility.gd` per call |

Rules:

- No `characters.<id>.eligibility`, no eligibility block in `settings.json`, no eligibility block
  in `Mods.state("unfplap")`.
- `eligibility.gd` never calls `SETTINGS.save_*`, `SEX_BOND.save`, `ACT_HISTORY.commit/save` or
  `Mods.save_changed`.
- `facts.consent` is a snapshot. `get_profile(id).consent` re-resolves live.
- Preferences are not facts. Tolerance stays with `act_tolerance.gd`; eligibility never reads the
  preference profile.
- `api.describe_mare()` keeps its static shape and is not extended with live eligibility.

## Public API

`eligibility.gd` extends `RefCounted`. `main.gd` creates one instance and exposes it as
`main.eligibility`. The types are declared in the facade, so a consumer names them
`ELIGIBILITY.Verdict`, `ELIGIBILITY.Target`, and so on.

```gdscript
enum Target { ACT, ANATOMY, TAIL, CHARACTER }
enum Mode { START, OFFER, BOND, MID_ACT }
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
class Verdict: mode, base, show, attempt, offer, bond, buck_refuse, history_refuse,
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
| `runtime.start_verdict()` | `get_verdict(pony, Mode.START)` | structural rows plus `scene_gate.gd` rows |
| `runtime.offer_verdict()` | `get_verdict(pony, Mode.OFFER)` | offer-safe `scene_gate.gd` rows |
| `runtime.start()` | `start_verdict()` | none |
| `runtime.refuse_available()` / `refuse()` | `buck_refuse` | `scene_gate.gd` refusal executor |
| `runtime.grant_sex_bond()` | `get_verdict(pony, Mode.BOND)` | IDLE, not sleeping |
| `runtime._still_willing()` | `get_verdict(pony, Mode.MID_ACT)` | none |
| `main._refresh_offer()` | `runtime.start_verdict().show` | candidate discovery |
| `main.try_start()` | `runtime.start()` | none |
| `main._try_refusal()` | `runtime.refuse_available()` | none |
| `main.is_adult_mare()` | `eligible(pony, Target.ACT)` | none |
| `main.live_character_ids()` | `eligible(pony, Target.CHARACTER)` | runtime roster, ordering |
| `initiation` | `get_verdict(pony, Mode.OFFER)` | cooldown, approach, bed search, privacy, classifier; see `docs/initiation.md` |
| `dialogue_consent` | `runtime.grant_sex_bond/end_sex_bond` | none |
| `anatomy/act` | `get_profile(id).consent` | feature flags |
| `anatomy` facade | `eligible(pony, Target.ANATOMY)` | rig, assets, dock; forwards to its controllers |
| `tail_seat` | `eligible(pony, Target.TAIL)` through the anatomy facade | hair, dock |
| `memory` | `witness_age(pony)` | perception, sleeping |
| `standing_presentation` | `eligible(pony, Target.ACT)` | pose, state |
| `api.describe_mare()` | `get_profile(id)` | provider metadata, settings shape |

Only `runtime` combines policy rows with scene rows. The rows themselves are built by
`scene_gate.gd` (`docs/scene_gate.md`). The pure policy never sees a bed, a navigator, a pose
asset or the player body.

## Capability targets

A consumer asks about its own target and never inspects identity:

| Target | Veto | Callers |
|---|---|---|
| `Target.ACT` | `participation.acts` | act discovery, the standing invitation, `is_adult_mare` |
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
stored_bond, bond_stage, promiscuity, sex_start, public_feature, player_young, player_pony,
cycle_phase, cycle_allows, heat, history, consent
```

`cycle_phase` comes from `runtime.cycle_phase()`, so the debug heat/diestrus override applies. A
pony that has only just spawned has no relationship runtime yet, so the read is a normal phase
until one exists; the anatomy bridge asks for it during its own bind.
`history` is resolved by `act_history.gd`; `consent` by `SETTINGS.consent(id)`.
`adult` is the provider's tri-state assertion (`null` means the identity decides); `participation`
is the resolved per-mare capability block (`acts`, `anatomy`, `tail`), both by
`SETTINGS.profile_identity(id)`.

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
bond: bool             # a lover-bond dialogue grant is allowed
buck_refuse: bool      # Y triggers refuse()
history_refuse: bool   # Y triggers refuse_from_history()
stop: bool             # mid-act withdrawal
offer_weight: float
facts: Facts
actions: Actions       # public, public_offer, anal, oral
relations: Relations   # id, stage, love_level, willing, stored_bond, bond_stage,
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
`relation`, `sex_bond`, `cycle`, `history`, `history_offers`, `public`.

## Modes and truth table

`base` = valid adult mare + relationship runtime + registered adult + adult player + romance
eligible + Promiscuity level pass.

| Condition | `show` | `attempt` | `buck_refuse` | `history_refuse` | `offer` | `bond` | `stop` |
|---|---|---|---|---|---|---|---|
| not `base` | no | no | no | no | no | no | yes |
| `participation.acts` false | no | no | no | no | no | no | no |
| `!willing`, When Available | no | no | yes | — | no | no | yes |
| `!willing`, Try Your Luck | yes | no | yes | — | no | no | yes |
| `willing`, history withdrawn/stop | yes | no | no | yes | no | yes | no |
| `willing`, history hurt (tier 2) | yes | yes | no | no | no | yes | no |
| no stored bond, When Available | no | no | no | no | no | yes | yes |
| no stored bond, Try Your Luck | yes | yes | no | no | yes | yes | no |
| diestrus | no | no | — | — | no | yes | yes |
| heat or public consent | — | — | — | — | privacy flag | — | — |

Rules:

- `history_refuse` wins over `buck_refuse`; it does not require willingness.
- `buck_refuse` ignores bond, cycle and history.
- `bond` requires base + willing + participation; it does not need a stored bond.
- `stop` requires base + willing + bond + cycle; history does not stop an act.
- `participation.acts` is a block, not a refusal: a player who opts out of acts never gets a
  buck, a history refusal or a mood note. It is a boundary, not a mood beat.
- `show` and `attempt` are separate. Try Your Luck shows the hint while `attempt` is false.

## Adults

- The identity predicates (`adult_pony_identity`, `adult_mare_identity`, `young_identity`) are
  private to `eligibility/facts.gd`. Other systems ask a capability target; they never inspect
  age, sex or the provider assertion.
- `Target.ACT`, `Target.ANATOMY` and `Target.CHARACTER` accept an adult mare: an identified pony
  that is not a filly/colt, not a stallion and not the player's own pony. `Target.TAIL` is the
  same identity plus the tail veto.
- A provider's `adult` assertion is a tri-state override: `true` or `false` overrides the
  identity's age flag; `null` lets the identity decide. It changes age, not sex. It is
  provider-only and never written to the player's settings.
- Adult stallions are not act, anatomy or tail targets. They may still witness an act:
  `witness_age()` returns `Age.ADULT` for them.
- `witness_age()` returns `Age.YOUNG` for a filly/colt the provider has not asserted adult,
  `Age.ADULT` for an adult (or asserted adult), and `Age.NONE` for a pony who can be neither. It is
  the only age-shaped answer a consumer gets, and only for witness wording.
- A young player blocks every act and every lover-bond grant.

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

The selected `relationship.promiscuity` is the lowest love level that can start an act or grant a
lover bond. The ladder is:

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
boundary) and holds the matching face in `mood_face.gd`. `angry` makes `bonds.welcomes()` false, so
she refuses kisses and offers for the note's 300 s freshness.

## Lover bond and Starting Sex

The stored bond is `Mods.state("unfplap").sex_bonds`. It never expires. A bond granted while
dating/engaged/married is cleared when the base stage leaves those stages; a spoken withdrawal
always clears it.

`relationship.sex_start`:

- **When Available** requires the stored bond. A willing mare below that has no hint and no
  proactive offer.
- **Try Your Luck** makes the stored bond optional. It **does not** drop the Promiscuity level and
  it **does not** skip willingness at start. The hint can appear before she welcomes the kiss;
  pressing Y still refuses when she does not.

The old labels that said Try Your Luck drops the stage are corrected to this rule.

## History and cycle

`act_history.gd` owns the point math and tiers (`docs/history.md`). `history.gd` owns the runtime-side
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

1. deterministic per-id defaults from `consent.gd`;
2. a provider layer's `consent` block;
3. the player's differences in `characters.<id>.consent`.

Eligibility reads the resolved result. It never writes it. `public`, `anal` and `oral` are
independent:

- **Public** is an offer privacy override, never an act gate and never a refusal. It only matters
  while `features.act_public_offer` is on.
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
- stored lover bond (When Available) or Starting Sex bypass;
- estrus cycle allows sex.

`runtime._still_willing()` checks this every quarter second. A real tolerance stop is separate:
`act_tolerance.gd` owns disliked-touch distress and its warning/stop thresholds.

## Debug

- `runtime.debug_line()` prints `show`, `attempt`, `offer`, `buck`, `history`, the policy rows and
  the relation facts. It does not re-derive the gate.
- `Verdict.rows_text()` returns the same policy view without scene rows.
- The Debug actions **Grant lover bond**, **Clear lover bond**, **Trigger bed offer** and
  **Trigger standing offer** use the same service.
- The Debug actions **Force heat** and **Force diestrus** feed `cycle_phase`; they do not bypass
  the gate.

## Tests

- `tests/eligibility/test_eligibility.gd`: the pure truth table, identity predicates, capability
  targets, witness age, Promiscuity, willingness, bond, history, cycle, public/anal/oral,
  participation and row effects.
- `tests/eligibility/test_eligibility_api.gd`: the facade's `eligible()`, `witness_age()`, typed
  facts and verdict, capability targets, the profile consent, the provider layer through
  `set_profile()`/`get_profile()` and clear/setup lifecycle.
- `tests/test_participation.gd`: the pure participation layer, defaults, partial merge and clean.
- `tests/bond/test_sex_bond.gd`: bond storage only; `tests/bond/test_bond_service.gd`: the service
  gates, the event and the stale-bond sweep.
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
- `tests/anatomy/test_identity.gd`: the stable-id helpers, the princess body profile and the
  off-roster list.
- `tests/memory/test_memory_api.gd`: the facade's impression and event writes, the refusal mood
  and the stay-close reward.
- `tests/memory/test_text.gd`: the witness wording and the age split.

## Known limits

- The base game changes `bonds.welcomes()` over time; a mid-act mood swing can stop the act through
  the willingness row.
- Stallion partners stored in an older save remain in `sex_bonds`, but they are no longer act
  targets. No migration removes the row.
- Public consent is not a general exhibitionism gate; it is an offer privacy override.
- The internal API is not part of `docs/api.md`; the cross-mod `profile.mare` capability reads
  `get_profile(id)` and writes `set_profile(owner, id, profile)`. A live eligibility verdict is
  not part of the API.
