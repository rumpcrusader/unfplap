# Act summary and long-term history

This is the contract for the mod-owned post-act summary and the per-mare act history. It is the
only place that decides whether an act was good, neutral or bad, and what that changes later.

## Per-act score

`act_summary.gd` is pure. It scores one act from the action counters the runtime collected:

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

`MEMORY.commit_act` writes this to the game's impressions once. It also records the summary text as
a `relationship` world-context event. The two lines have separate voices: the recorded `text` is the
profile-safe world event, while `thought` is her private first-person impression (`He`/`I`) and is
what the profile shows as **Last impression**. An early end is stated once, not repeated as a
reason. Witness text follows the same rule (`Anon and <name> were seen...`), because it can appear
in the observer's Recent activities too.

An intentional early end and a partner stop each record **one** event: the summary when history is
on and the summary is not skipped, otherwise the basic `cancel`/`stop` event as the fallback. The old
flat `commit_climax` path is gone, so a bad act can no longer give `+2` romance.

`satisfied.gd` starts on a good or non-early neutral act; a bad act gets no satisfied face. The
10 s aftercare hold always runs, but its positive tail-up body language is only used after a good
act. `stay_close_reward` gives its extra romance only on a good or non-early neutral act; after a
bad act, staying close and caressing is a one-point hurt repair instead.

## History points

`act_history.gd` stores per mare in `Mods.state("unfplap").act_history`:

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

| Tier | Trigger | Proactive offers | Player-initiated act |
|---|---|---|---|
| Steady | hurt 0–1 | normal | normal |
| Uneasy | hurt 2–3 | normal, but offer weight drops and she adds a gentle reminder | normal |
| Hurt | hurt 4–5 | no offers | allowed, with a cold reminder |
| Withdrawn | hurt 6+ | none | a gentle spoken refusal until repair |

There is **no break-up path**. The highest tier closes sex, not the relationship. The base
`player_bonds.break_up()` is never called.

## Neglect tolerance and the mid-act stop

`preferences.tolerance` is per mare: `forgiving`, `normal` or `strict`. The Characters sub-tab edits it
as **Neglect tolerance**. The default is normal; Rarity is strict and Fluttershy is forgiving. The
old `timid`/`neutral` values still resolve to `forgiving`/`normal`.

A pure `act_tolerance.gd` meter runs only during `POSING_IN`/`ACTIVE`:

- every actual disliked touch/talk adds `tolerance.dislike_amount` (1);
- every actual liked touch/talk subtracts `tolerance.like_relief` (1);
- a held caress is one action per 5 s of contact (`CAESS_TOUCH_SECONDS`), not one per frame, so
  it can neither erase distress every tick nor stop a caress-disliking mare instantly;
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
- it records `MEMORY.stop_event(..., "withdrew")`;
- it ends through the forced path with no afterglow and no cuddle rejoin;
- Normal: stern spoken line, no buck, no `request_space`, 5-minute sex-only cooldown;
- Strict: stern line, `request_space`, buck/kick from bed, 10-minute sex-only cooldown;
- the history `stop_until` field blocks `blocks_start()`, `blocks_offers()` and offer weight;
- no aftercare or satisfied face. A 20 s tucked-tail effect hinged at the tail base follows her,
  owns no navigator, and is removed if a new act starts.

The debug tunables live under **Neglect tolerance**. Debug actions **Force neglect warning** and
**Force neglect stop** drive the live act for testing.

Offer weight is `clamp(0.70 + comfort * 0.05 - hurt * 0.12, 0, 1)`; a hurt-tier mare has no
weight. The base offer cooldown is `600 s`, reduced by `5%` per comfort point with a `300 s` floor.
`initiation.gd` uses the weight in its candidate pick and the cooldown in its gate.

At the withdrawn tier, the Y hint is still shown. `main.try_start()` checks
`runtime.history_blocks_start()` and calls `runtime.refuse_from_history()` instead of
`runtime.start()`; the refusal is a generated line, not a buck or a silent no. Repair comes from
good acts, time and an apology.

## Mood after a refusal and a buck

A mare's lasting mood in this game is the impression note (`world_context.impressions`), fresh for
300 s. It is what `bonds.anger()` reads (`angry` 70, `annoyed` 40) and therefore what gates
`bonds.welcomes()`, relationship offers, resting closeness, hand feeding and her unprompted
approaches. Her dialogue prompt and the relationship profile also show it.

The mod writes or keeps that note on the moments the base game does not see:

- a refused act attempt (`runtime.refuse()`) commits `annoyed`, or `angry` when the refusal also
  bucked or knocked Anon down (`MEMORY.refusal_event`);
- the refusal calls the game's own `bonds.unwanted_contact(id, "kiss")`, costing a little trust;
- a normal tolerance stop holds `annoyed`; a strict stop holds `angry` (its summary impression).

`upset.gd` displays the mood: it holds `annoyed`/`angry` on her face for the note's 300 s, yields
to any spoken line face, and ends early when her AI commits a different mood. It owns no navigator
and blocks nothing; the gates above do that.

## Feedback

- The afterglow HUD shows the summary. Missionary puts it in the cue line; standing keeps the
  close prompt in the cue and puts the summary on the readiness line. Early end shows no HUD.
- `prompt_note()` carries the private history note while idle, the relationship note during the
  act and afterglow, and her first-person `thought` in afterglow. The afterglow note no longer
  appends the mechanical `last_wants`; hurt/repair and offer prompts filter them through
  `ACT_HISTORY.repair_wants()`, which keeps comfort needs and drops stroke mechanics.
- A pending reminder or complaint is queued as one short line after a 45 s delay, when the player
  is within 5 m and the director is idle. One line per tier rise.
- A sincere apology is detected locally by `preferences.apology_intent()`; only the pony currently
  in conversation with the player repairs.
- The debug log prints one `summary grade=... quality=... checks=... reasons=... tier=... hurt=...
  comfort=...` line per act. Debug → Actions has **Reset act history**.

## Settings

`features.act_history` is the master switch (Settings tab, default on). With it off, no summary is
stored, no history note or refusal is used, and the existing satisfied/aftercare behaviour falls
back to the readiness threshold. It does not disable the per-mare mid-act neglect stop.

The debug thresholds and weights live under `History` in the Debug tab. They are `num` entries, so
stored values are never clamped by the consumer. See `TUNING.md`.

The per-mare neglect-tolerance tier is a preference field, not a global setting: edit it in
**Characters**. The thresholds, like relief, decay and stop cooldowns are the `tolerance.*` debug
tunables.

## Tests

- `tests/test_act_tolerance.gd` — tier thresholds, every-event counting, like relief, 25 s decay,
  warning monotonicity and stop cooldowns.
- `tests/test_act_stop.gd` — neutral/strict stop teardown, history cooldown, no/yes buck and
  request space.
- `tests/test_act_summary.gd` — score bands, silence for talk-seekers only, one-dislike neutrality,
  severe handling, early end, stopped-by-her severe outcome, forced stop, short act, motion and
  touch misses.
- `tests/test_act_history.gd` — points, tiers, offer weight/cooldown, decay, apology, sanitising,
  pending lines, reset.
- `tests/test_act_flow.gd` — runtime snapshot and afterglow HUD summary.
- `tests/test_memory.gd` — grade-aware impression and stay-close rewards.
