# Act summary and long-term history

This is the contract for the mod-owned post-act summary and the per-mare act history. It is the
only place that decides whether an act was good, neutral or bad, and what that changes later. The
event and impression the summary writes are owned by the memory system; see `docs/memory.md`.
Readiness is `docs/readiness.md`; the afterglow phase is `docs/afterglow.md`; the face is
`docs/face.md`.

## Ownership

`history/service.gd` is the system facade. It owns the summary trigger and commit, the summary input and
context shape the pure scorer reads (`summary_inputs()`, `summary_context()`), the peak-memory
record, the idle apology/reminder decisions and the pure
`history/tolerance.gd` meter. The stored ledger is read from `shared/act_history.gd` directly, by
this facade and by every other consumer. The runtime keeps the act state machine, gathers the action counters and
the scene values into one dictionary, runs the scene stop executor (`_stop_with_her`: bed release,
session end, space, buck, tail tuck) and owns the face and line presentation. `history/summary.gd` and
`shared/act_history.gd` remain the pure scoring and stored-row modules behind the facade.

## Per-act score

`history/summary.gd` is pure. It scores one act from the action counters the runtime collected:

| Component | Weight | Passes when | Applies |
|---|---:|---|---|
| Climax | `0.30` | she reached at least one climax | always |
| Talk | `0.20` | at least one liked talk category and no disliked talk | only if `preferences.talk` is non-empty |
| Touch | `0.20` | at least one liked touch and no disliked touch | only if she has touch likes or dislikes |
| Motion | `0.15` | a majority of scored real thrusts match both her intensity and pattern | only after the pattern window has at least three strokes |
| Not early | `0.15` | not an intentional 0-climax early end | always |

Penalties:

- `0.10` per disliked touch or talk, capped at `0.20` for the act.
- `0.15` extra when the same disliked touch kind happened twice, or there were three or more
  disliked events.
- `0.15` when she seeks talk and the player never spoke during the act.
- `0.10` when a touch preference was never met, or motion did not match. This is a miss, not a
  bad act on its own, but it keeps the act out of the good band.

`quality = clamp((passed weight - penalties) / applicable weight, 0, 1)`.

- **Good:** `quality >= 0.80`
- **Neutral:** `0.20 < quality < 0.80`
- **Bad:** `quality <= 0.20` (or severe handling plus another miss, which the penalties push below
  the band)
- **Great:** a good act with two or more climaxes, no dislikes, no silence and no early end.

A talk-seeker who is otherwise perfect but silent lands around `0.65`: neutral, not bad. A single
disliked touch lands around `0.70`: neutral, not bad. Repeated disliked handling plus silence lands
at or below `0.20`: bad. A clean act with a motion mismatch stays out of the good band.

Minimum evidence: an act shorter than `history.early_grace_s` (20 s) **and** with fewer than
`history.min_thrusts` (2) real thrusts is skipped. Forced stops never commit a summary. Only the
intentional early-end path commits an early summary, and only after the grace period or the first
real thrust. A neutral early end adds `history.mild_hurt` (1) instead of a full bad-act penalty.

`talk-seeker` means a non-empty `preferences.talk` list. Touch applies when she has a touch like or a
touch dislike. A mare with an empty talk list is never punished for a quiet act.

## Rewards

The summary carries the once-per-act impression:

| Grade | Romance | Mood |
|---|---:|---|
| Great / Good | `+2` | `happy` |
| Neutral | `+1` | `relaxed` |
| Bad | `-1` | `sad`, or `annoyed` when severe |
| Early end, neutral | `0` | `relaxed` |
| Early end, bad | `-1` | `sad` |

An event line starts with the pair, `You and Anon `, so the profile can replace that prefix with
`You and <name>`; after that prefix it uses no second-person pronouns for the pony, so the
**Recent activities** line stays correct. The event text is what the AI reads as context; the
reason sentences in each voice keep that same rule.

`main.memory.commit` writes this to the game's impressions once. It also records the summary text as
a `relationship` world-context event. The two lines have separate voices: the recorded `text` is the
profile-safe world event, while `thought` is her private first-person impression (`He`/`I`) and is
what the profile shows as **Last impression**. An early end is stated once, not repeated as a
reason. Witness text follows the same rule (`Anon and <name> were seen...`), because it can appear
in the observer's Recent activities too.

An intentional early end and a partner stop each record **one** event: the summary when history is
on and the summary is not skipped, otherwise the basic `cancel`/`stop` event as the fallback. The old
flat `commit_climax` path is gone, so a bad act can no longer give `+2` romance.

A completed act starts `face/mood_face.gd`: a good or non-early neutral act holds a relaxed face with
the warm prompt note, and a bad act holds `sad`/`annoyed` instead. The 10 s aftercare hold always
runs, but its positive tail-up body language is only used after a good act. `stay_close_reward`
gives its extra romance only on a good or non-early neutral act; after a bad act, staying close and
caressing is a one-point hurt repair instead. The caress reward threshold is in `docs/hands.md`.

### Memory and rewards

- **First pony climax:** one world-context event; every climax gets a generated reaction.
- **Once at afterglow:** `_commit_summary()` scores the act, `main.memory.commit()` writes the
  grade-aware romance and mood, and `main.memory.witnesses()` follows.
- **Standing close reward:** `main.memory.commit()` (the `STAY_CLOSE` slot) records a private
  impression. On a good or non-early neutral act, staying and caressing adds a happy mood, a
  private thought and a small `romance` gain. After a bad act, staying and caressing repairs one
  point of history hurt instead. The caress time threshold is in `docs/hands.md`.
- **Peak act:** one strongest memory per mare is kept in
  `Mods.state("unfplap").peak_memories`. It requires a positive summary, no disliked touch/talk and
  either peak readiness >= 90 or six both-axis thrust matches. A later higher-scoring act replaces
  it. The text is the last player exchange, or a generic warm beat if he did not speak.
- **Zero-climax Y:** the early-stop/cancel path commits an early summary but no romance. The summary
  can add hurt through this file; the early-stop reaction includes what she wanted.
- Act lines that have not started speaking are cancelled at every climax/afterglow boundary and at
  every act end. A line already speaking may finish. The intentional early-stop line is queued
  after the act-line cancel.

## History points

`shared/act_history.gd` stores per mare in `Mods.state("unfplap").act_history`:

```gdscript
{
  "version": 1,
  "acts": 7, "good": 4, "bad": 2, "neutral": 1,
  "hurt": 0, "comfort": 2,
  "streak_good": 1, "streak_bad": 0,
  "last_grade": "good", "last_quality": 0.92,
  "last_reasons": ["silent_talk"],
  "last_text": "You and Anon made love...",
  "last_wants": "talk to me while we move",
  "last_at": 0.0, "last_day": 0.0,
  "last_apology_day": -1.0,
  "stop_until": 0.0, "last_stop_kind": "", "last_stop_at": 0.0,
  "reminder_pending": false, "complaint_pending": false,
  "announced_tier": 2,
  "recent": [],
}
```

Only good and bad acts move the points. Neutral acts change no history.

| Event | Effect |
|---|---|
| Good act | `comfort +1`, `hurt -1` |
| Great act | `comfort +2`, `hurt -2` |
| Bad act | `hurt +1`, `comfort -1` |
| Severe bad act | `hurt +2`, `comfort -1` |
| Neutral early end | `hurt +1` |
| Time | `hurt -1` per 2 in-game days |
| Sincere apology | `hurt -1`, at most once per in-game day |
| Stay close and caress after a bad act | `hurt -1` |

`hurt` and `comfort` are capped at `8`.

## Tiers

| Tier | Trigger |
|---|---|
| Steady | hurt 0–1 |
| Uneasy | hurt 2–3 |
| Hurt | hurt 4–5 |
| Withdrawn | hurt 6+ |

The tier names are presentation. Their effect on the start hint, proactive offers and spoken
refusal is in `docs/eligibility.md`.

There is **no break-up path**. The highest tier's act gate is in `docs/eligibility.md`; it never
calls `player_bonds.break_up()`.

## Neglect tolerance and the mid-act stop

`preferences.tolerance` is per mare: `forgiving`, `normal` or `strict`. The Characters sub-tab edits
it as **Neglect tolerance**. The default is normal; Rarity is strict and Fluttershy is forgiving.
The old `timid`/`neutral` values still resolve to `forgiving`/`normal`.

A pure `history/tolerance.gd` meter runs only during `POSING_IN`/`ACTIVE`:

- every actual disliked touch/talk adds `tolerance.dislike_amount` (1);
- every actual liked touch/talk subtracts `tolerance.like_relief` (1);
- a held caress is a discrete action; its five-second meter is in `docs/hands.md`;
- passive decay subtracts 1 every 25 s;
- warning stages are one-shot per act; compensation can lower distress and avoid a stop but does
  not replay a warning.

| Tier | Warnings | Stop |
|---|---|---|
| Forgiving | one at 4 | never |
| Normal | at 1, then 4 | 10 |
| Strict | at 1 | 3 |

A warning sets a HUD cue and queues one short spoken warning. Warnings and the stop line speak
even when `features.act_lines` is off.

A stop is a dedicated path, not `cancel()`:

- it forces a severe bad summary (`stopped_by_her`, no romance, mood annoyed/angry) and `+2` hurt;
- it records `main.memory.note(MEMORY.NoteKind.STOPPED, ..., MEMORY.StopReason.WITHDREW)`;
- it ends through the forced path with no afterglow and no cuddle rejoin;
- Normal: stern spoken line, no buck, no `request_space`, 5-minute sex-only cooldown;
- Strict: stern line, `request_space`, buck/kick from bed, 10-minute sex-only cooldown;
- `stop_until`'s act gate is in `docs/eligibility.md`;
- no aftercare; the `angry`/`annoyed` mood face follows when a summary was written. A 20 s
  tucked-tail effect hinged at the tail base follows her, owns no navigator, and is removed if a
  new act starts.

The neglect settings live under **Neglect tolerance** in World's Debug block. The **Force neglect
warning** and **Force neglect stop** debug actions drive the live act for testing.

Offer weight is `clamp(0.70 + comfort * 0.05 - hurt * 0.12, 0, 1)`; a hurt-tier mare has no
weight. The base offer cooldown is `600 s`, reduced by `5%` per comfort point with a `300 s` floor.
How the weight, cooldown and refusal reach the act gate is in `docs/eligibility.md`.

## Mood after a refusal and a buck

A mare's lasting mood in this game is the impression note (`world_context.impressions`), fresh for
300 s. It is what `bonds.anger()` reads (`angry` 70, `annoyed` 40). Its eligibility gate effect is
in `docs/eligibility.md`; it also gates resting closeness, hand feeding and her unprompted
approaches. Her dialogue prompt and the relationship profile also show it.

The mod writes or keeps that note on the moments the base game does not see:

- a refused act attempt (`runtime.refuse()`) commits `annoyed`, or `angry` when the refusal also
  bucked or knocked Anon down (`main.memory.commit`, the `REFUSAL` slot);
- the refusal calls the game's own `bonds.unwanted_contact(id, "kiss")`, costing a little trust;
- a normal tolerance stop holds `annoyed`; a strict stop holds `angry` (its summary impression).

`face/mood_face.gd` displays the mood: it holds `annoyed`/`angry` on her face for the note's 300 s,
yields to any spoken line face, and ends early when her AI commits a different mood. It owns no
navigator and blocks nothing; the gates above do that.

## Feedback

- The afterglow HUD shows the summary. Missionary puts it in the cue line; standing keeps the
  close prompt in the cue and puts the summary on the readiness line. Early end shows no HUD.
- `prompt_note()` carries the private history note while a hurt history is active, the 300 s
  warm note after a good or non-early neutral act (`_warm_note`), the relationship note during the
  act and afterglow, and one short random afterglow beat (or none). It does not recite the summary or her
  first-person `thought`; the HUD and the impression keep those. Hurt/repair and offer prompts
  filter `last_wants` through `ACT_HISTORY.repair_wants()` and pass `last_text` through
  `ACT_HISTORY.private_text()`, which keeps the reason and drops the repeated act opening.
- An intentional early end gives one short reaction 50% of the time and marks its pending history
  line announced, so the same act does not speak twice.
- A pending complaint (tier 2/3) is queued as one short line after a 45 s delay, when the player is
  within 5 m and the director is idle. Tier 1 uses a deterministic rare hint (about one act in
  four) and a vague line with no wants list. One line per tier rise.
- A sincere apology is detected locally by `preferences.apology_intent()`; only the pony currently
  in conversation with the player repairs.
- The debug log prints one `summary grade=... quality=... checks=... reasons=... tier=... hurt=...
  comfort=...` line per act. The **Reset act history** debug action clears the row.

## Lifecycle

- Scope: per-act
- Constructed by: `runtime._init()`
- Begin: `reset_act()`
- End: act teardown
- Idempotent: yes


## Settings

`features.act_history` is the master switch (General › Controls, default on). With it off, no summary is
stored, no history note or refusal is used, and the warm note and aftercare fall back to the
readiness threshold. It does not disable the per-mare mid-act neglect stop.

The thresholds and weights live under `History` in World's Debug block. They are debug numbers,
so stored values are never clamped. See `docs/settings.md`.

The per-mare neglect-tolerance tier is a preference field, not a global setting: edit it in
**Characters**. The thresholds, like relief, decay and stop cooldowns, are the `tolerance.*` debug
settings.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | memory | `memory/service.gd` | act memory and witness pass |
| service | settings | `settings/service.gd` | settings declarations and live values |
| shared | preferences | `shared/preferences.gd` | profile math and defaults |
| shared | relationship_cue | `shared/relationship_cue.gd` | relationship prompt note |
| store | act_history | `shared/act_history.gd` | stored history rows |

## Tests

- `tests/history/test_act_tolerance.gd` — tier thresholds, every-event counting, like relief, 25 s
  decay, warning monotonicity and stop cooldowns.
- `tests/history/test_act_stop.gd` — neutral/strict stop teardown, history cooldown, no/yes buck and
  request space.
- `tests/history/test_act_summary.gd` — score bands, silence for talk-seekers only, one-dislike
  neutrality, severe handling, early end, stopped-by-her severe outcome, forced stop, short act,
  motion and touch misses.
- `tests/history/test_act_history.gd` — points, tiers, offer weight/cooldown, decay, apology,
  sanitising, pending lines, reset.
- `tests/history/test_act_flow.gd` — runtime snapshot and afterglow HUD summary.
- `tests/history/test_history.gd` — facade: summary commit, peak memory, tolerance decisions,
  refusal gate and the idle apology/reminder scan.
- `tests/memory/test_memory_api.gd` — grade-aware impression and stay-close rewards.
- `tests/memory/test_text.gd` — the event, refusal and witness wording and the id suffixes.

## Verification / lab

- One act per grade: summary log once, history row and tier, peak memory, mood face.
- Early end (hold Y at 0 climaxes) and a forced stop (Debug → Force neglect stop).
- Apology and time decay in the lab.

## Related docs

- `docs/readiness.md` — scoring inputs and the climax count.
- `docs/memory.md` — the event, impression and witness channel.
- `docs/eligibility.md` — the history gate and the stop cooldown.
- `docs/face.md` — the post-act mood face.
- `docs/afterglow.md` — the close window and its reward.
