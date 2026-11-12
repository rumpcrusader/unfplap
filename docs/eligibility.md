# Eligibility and consent

The eligibility system is the one gate for adult intimacy: adulthood, relationship level, kiss
willingness, the lover bond, act history, the estrus cycle and per-mare action consent. This file
is the single technical contract; other docs link here.

The internal API is `eligibility.gd`. Cross-mod exposure is a later phase; `docs/api.md` is not
changed by this contract.

## Scope

This contract covers:

- the adult mare and adult player predicates;
- the Promiscuity level and Starting Sex choice;
- base-game kiss willingness (`bonds.welcomes(id, "kiss")`);
- the stored mod lover bond;
- history withdrawal and offer blocks;
- the estrus cycle sex gate;
- per-mare public, anal and oral consent;
- the start hint, start attempt, buck refusal and history refusal;
- proactive offer eligibility and offer weight;
- mid-act withdrawal from a relationship change.

It does not cover act readiness, thrust, tolerance, pose or camera rules.

## Architecture

| File | Role |
|---|---|
| `eligibility.gd` | public API and the only scene adapter: builds facts, reads the live relationship runtime, settings profile, lover bond, history, cycle and consent |
| `eligibility/policy.gd` | pure truth table: facts plus mode -> verdict |
| `eligibility/facts.gd` | pure fact schema and identity predicates |
| `eligibility/verdict.gd` | pure verdict queries and row formatting |
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
| Request cooldown | `Mods.state("unfplap").request_times` | `initiation.gd` |
| Relationship stage, love, friendship, willingness | game save (`player_bonds`, impressions) | base game |
| Eligibility facts | nowhere | `eligibility.gd` per call |

Rules:

- No `characters.<id>.eligibility`, no eligibility block in `settings.json`, no eligibility block
  in `Mods.state("unfplap")`.
- `eligibility.gd` never calls `SETTINGS.save_*`, `SEX_BOND.save`, `ACT_HISTORY.commit/save` or
  `Mods.save_changed`.
- `facts.consent` is a snapshot. `action_consent()` re-resolves live.
- Preferences are not facts. Tolerance stays with `act_tolerance.gd`; eligibility never reads the
  preference profile.
- `api.describe_mare()` keeps its static shape and is not extended with live eligibility.

## Public API

`eligibility.gd` extends `RefCounted`. `main.gd` creates one instance and exposes it as
`main.eligibility`.

```gdscript
const MODE_START := "start"
const MODE_OFFER := "offer"
const MODE_BOND := "bond"
const MODE_MID_ACT := "mid_act"

const ACTION_PUBLIC := "public"
const ACTION_ANAL := "anal"
const ACTION_ORAL := "oral"

func setup(main_node: Node) -> void
func clear() -> void

func facts(pony: Node) -> Dictionary
func evaluate(pony: Node, mode := MODE_START) -> Dictionary
func evaluate_facts(snapshot: Dictionary, mode := MODE_START) -> Dictionary

func adult_pony(pony: Node) -> bool
func adult_mare(pony: Node) -> bool
func adult_player() -> bool
func action_consent(pony: Node, key: String) -> bool

func reasons(verdict: Dictionary) -> PackedStringArray
func rows_text(verdict: Dictionary) -> String
func debug_text(pony: Node, mode := MODE_START) -> String
```

### Callers

| Caller | API | Scene work it keeps |
|---|---|---|
| `runtime.start_verdict()` | `evaluate(pony, MODE_START)` | state, paused, player, navigator, pose asset, bed |
| `runtime.offer_verdict()` | `evaluate(pony, MODE_OFFER)` | offer-safe scene rows |
| `runtime.start()` | `start_verdict()` | none |
| `runtime.refuse_available()` | `buck_refuse` | pose context |
| `runtime.grant_sex_bond()` | `evaluate(pony, MODE_BOND)` | IDLE, not sleeping |
| `runtime._still_willing()` | `evaluate(pony, MODE_MID_ACT)` | none |
| `main._refresh_offer()` | `runtime.start_verdict().show` | candidate discovery |
| `main.try_start()` | `runtime.start()` | none |
| `main._try_refusal()` | `runtime.refuse_available()` | none |
| `initiation` | `runtime.offer_verdict()` | cooldown, approach, bed search, privacy, classifier |
| `dialogue_consent` | `runtime.grant_sex_bond/end_sex_bond` | none |
| `anatomy/act` | `action_consent()` | feature flags |
| `anatomy`, `tail_seat` | `adult_mare()` | rig, hair, dock |
| `memory` | `facts.gd` adult predicates | perception, sleeping |
| `standing_presentation` | `adult_mare()` | pose, state |

Only `runtime` combines policy rows with scene rows. The pure policy never sees a bed, a
navigator, a pose asset or the player body.

## Facts

```gdscript
{
  "id", "has_identity", "is_player_pony", "is_filly", "is_stallion",
  "adult", "participation",
  "has_relationship", "registered_adult", "romance_eligible",
  "stage", "love_level", "willing", "stored_bond", "bond_stage",
  "promiscuity", "sex_start", "public_feature",
  "player_young", "player_pony",
  "cycle_phase", "cycle_allows", "heat",
  "history": {"tier", "hurt", "comfort", "blocks_start", "blocks_offers", "offer_weight"},
  "consent": {"public", "anal", "oral"},
}
```

`cycle_phase` comes from `runtime.cycle_phase()`, so the debug heat/diestrus override applies.
`history` is resolved by `act_history.gd`; `consent` by `SETTINGS.consent(id)`.
`adult` is the provider's tri-state assertion (`null` means the identity decides); `participation`
is the resolved per-mare capability block (`acts`, `anatomy`, `tail`), both by
`SETTINGS.profile_adult(id)` and `SETTINGS.profile_participation(id)`.

Not in facts: the preference profile, poses, prompts, timing values, prompt names, mood,
first-time state, or request cooldowns.

## Verdict

```gdscript
{
  "mode": String,
  "base": bool,
  "show": bool,             # the Make love hint appears
  "attempt": bool,          # Y starts the act
  "offer": bool,            # proactive offer allowed
  "bond": bool,             # a lover-bond dialogue grant is allowed
  "buck_refuse": bool,      # Y triggers refuse()
  "history_refuse": bool,   # Y triggers refuse_from_history()
  "stop": bool,             # mid-act withdrawal
  "offer_weight": float,
  "actions": {"public", "public_offer", "anal", "oral"},
  "relations": {"id", "stage", "love_level", "willing", "stored_bond", "bond_stage",
                "promiscuity", "sex_start", "cycle_phase", "heat", "base"},
  "rows": [{"key", "ok", "reason", "effect"}],
}
```

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

- `adult_pony`: an identified pony that is not a filly/colt and is not the player's own pony.
- `adult_mare`: an adult pony that is not a stallion. This is the act target, the anatomy target
  and the tail-seat target.
- A provider's `adult` assertion is a tri-state override: `true` or `false` overrides the
  identity's age flag; `null` lets the identity decide. It changes age, not sex. It is
  provider-only and never written to the player's settings.
- Adult stallions are not act targets. They may still witness an act; witnesses use
  `adult_pony`.
- A young player blocks every act and every lover-bond grant.

## Participation

`profile.participation` is the per-mare capability block: `acts`, `anatomy` and `tail`. It is
subtractive: `true` means "does not veto", never "grants". A missing key means the default
`true`. The `acts` key is an eligibility row with a `block` effect; it does not set
`buck_refuse` or `history_refuse`, and it does not change `stop`. A player who opts out of acts
is a quiet boundary, not a mood beat. The `anatomy` and `tail` keys are in `docs/anatomy.md`.

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
writes the game's impression (`MEMORY.refusal_event`): `annoyed` for a turn-away, `angry` when she
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

`act_history.gd` owns the point math and tiers (`HISTORY.md`). Eligibility consumes:

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
Cooldown, approach, bed search and the ask/consent classifier remain in `initiation.gd`.

## Mid-act withdrawal

`MODE_MID_ACT.stop` is true when any of these changes after the act started:

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
- `eligibility.debug_text()` returns the same policy view without scene rows.
- The Debug actions **Grant lover bond**, **Clear lover bond**, **Trigger bed offer** and
  **Trigger standing offer** use the same service.
- The Debug actions **Force heat** and **Force diestrus** feed `cycle_phase`; they do not bypass
  the gate.

## Tests

- `tests/eligibility/test_eligibility.gd`: the pure truth table, identity predicates, Promiscuity,
  willingness, bond, history, cycle, public/anal/oral, participation and row effects.
- `tests/test_participation.gd`: the pure participation layer, defaults, partial merge and clean.
- `tests/test_sex_bond.gd`: bond storage only.
- `tests/test_source_hygiene.gd`: purity, the single-reader rule and the docs link.
- `tests/hands/test_actions.gd`: the invalid-pony gate smoke.
- `tests/test_initiation.gd`: offer wording and consent classification.
- `tests/anatomy/test_anatomy.gd`: adult-mare eligibility, participation and the provider's
  `adult` assertion.
- `tests/anatomy/test_identity.gd`: the pure identity predicate and the provider's `adult`
  assertion.
- `tests/test_memory.gd`: witness wording.

## Known limits

- The base game changes `bonds.welcomes()` over time; a mid-act mood swing can stop the act through
  the willingness row.
- Stallion partners stored in an older save remain in `sex_bonds`, but they are no longer act
  targets. No migration removes the row.
- Public consent is not a general exhibitionism gate; it is an offer privacy override.
- The internal API is not part of `docs/api.md`; the cross-mod `profile.mare` capability exposes
  only the resolved `adult` and `participation` block. A live eligibility verdict is not part of
  the API.
