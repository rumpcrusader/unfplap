# Per-mare preferences

This is the contract for the per-mare preference profile: the schema, the two scoring axes, the
touch/talk classification, the character templates and the Characters editor. Readiness and
scoring are `docs/readiness.md`; consent and participation are `docs/eligibility.md`; the settings
framework is `docs/settings.md`.

## Ownership

`shared/preferences.gd` is the pure profile module: defaults, validation, merge, intensity/rhythm and the
talk keyword map. `shared/character_preferences.gd` holds the display names, the selector order and every
spawnable mare's built-in profile. `settings/service.gd` stores the per-mare overrides under
`characters.<id>` and resolves the provider layer. `settings/characters_ui.gd` builds the Characters
form (interim home until a characters service owns it); `settings/ui.gd` owns the declaration rows
for the global settings. `main.gd` supplies the live-mares list and the resolved participation
block through host callbacks.

A known mare's base is her template in `shared/character_preferences.gd`, then any mod provider layer
(`docs/api.md`), then the global `default`. Removing her saved override restores that chain rather
than the global default. The file stores only the player's differences.

## Profile schema

```gdscript
{
    "intensity": "firm",          # soft | firm | rough
    "pattern": "steady",          # steady | teasing | quick
    "touch": ["caress"],          # liked: smack, caress, kiss
    "dislikes": [],               # touch or talk dislike
    "talk": ["reassurance"],      # empty = talk does not score for her
    "warmth": "normal",           # quick | normal | slow
    "tolerance": "normal",        # forgiving | normal | strict
    "notes": "private attitude for the AI"
}
```

- `warmth` scales readiness gain: `quick` ×1.25, `normal` ×1.0, `slow` ×0.8.
- `tolerance` (Neglect tolerance) sets mid-act warnings and the stop threshold; see
  `docs/readiness.md`. The old `timid`/`neutral` values resolve to `forgiving`/`normal`.
- `touch`/`talk` are likes; `dislikes` cannot overlap a like.
- `notes` is the private attitude. The AI prompt receives the mood, the preference summary and the
  last concrete input, never a speed or depth dump.

## The two continuous axes

### Intensity

From the last real inward thrust's travel:

```text
soft   travel < 0.35
firm   0.35 <= travel < 0.65
rough  travel >= 0.65
```

The strength formula in `docs/readiness.md` is the physical impact value (plap, foley, wobble) and
is not the preference axis. The player's depth and tempo are independent, so all nine intensity ×
pattern combinations are reachable.

### Pattern

Classified over the last 3–4 real inward thrusts. Fewer than 3 means “no pattern yet”; only the
intensity axis can match. Pattern is tempo only; depth does not decide the rhythm.

```text
teasing  mean duration > 0.45 s
quick    mean duration < 0.30 s
steady   otherwise
```

## Touch and talk classification

| Action | Event |
|---|---|
| mouse right smack | `smack` |
| held caress | `caress` |
| kiss | `kiss` |

Touch shares one 4 s scoring cooldown across smack, caress and kiss. Talk has an 8 s scoring
cooldown and uses the game's `T`/microphone turn plus the small keyword map in `shared/preferences.gd`;
the AI still writes her reply. The caress action and its five-second touch meter are in
`docs/hands.md`.

The talk classifier is a small keyword map, not an LLM call. Expand it only from real playtest
phrasing, and keep `talk` empty for mares who should not score it.

## Settings editor

The **Characters** tab exposes one name-filtered pony selector, a **Save preset** button and a
**Reset to default** button in one row under the selector, and one form. The selector lists the
103 base-game mares first, then any live adult mare from another mod under **Other mares**; an
off-roster mare uses her registered provider template and placement when one exists
(`docs/api.md`), otherwise the global default profile and placement, until a preset or per-mare
override is saved.

The form holds:

- intensity, pattern, warmth;
- neglect tolerance (forgiving, normal, strict);
- one Dislikes / No preference / Likes pill row per touch action (smack, caress, kiss) and per
  talk action (praise, reassurance, dirty talk, playful);
- public, anal and oral consent (`docs/eligibility.md`);
- private notes;
- the **Takes part in** row (`Acts`, `Anatomy`, `Tail`).

Preset changes are staged in the form and written only by **Save preset**, then applied live during
an act. If the form matches the character's own preference template, Save preset removes the saved
preference override instead of writing a redundant one. **Reset to default** restores the
character's own preference template, including a registered provider layer, and preserves custom
`event_prompts` and pose settings; it does not clear consent overrides. The Reset button is
disabled while the saved preset already matches the character template. Consent defaults are
deterministic from her id, can be supplied by a registered provider layer, and can be overridden
per pony.

`characters.<id>.profile` is a sparse per-mare participation layer. `profile.participation` holds
`acts`, `anatomy` and `tail`; only differences from the resolved default are stored. A provider's
`adult` assertion is top-level and never a player value. The `characters` block is the same per-mare
block as the preference, consent, prompt and pose overrides.

## Character examples

Every spawnable mare in the base game has an explicit profile in `shared/character_preferences.gd`:
103 mares, the original sixteen first in the selector and the rest alphabetical. This table is the
main cast sample; the catalog carries the full roster. `twist` (written as a schoolfilly) and
`fiddly_twang` (written as a stallion) are left out because their identity flags do not match their
character profiles.

| Character | Intensity | Pattern | Touch | Talk | Warmth |
|---|---|---|---|---|---|
| Twilight | firm | steady | kiss | praise | normal |
| Fluttershy | firm | steady | caress | reassurance | slow |
| Rarity | soft | steady | caress | praise | normal |
| Pinkie | firm | quick | smack | playful | quick |
| Applejack | firm | steady | caress, smack | praise, reassurance | normal |
| Rainbow | rough | quick | smack | praise, playful | quick |
| Derpy | rough | quick | smack | playful | quick |
| Lyra | firm | steady | caress, kiss | playful | normal |
| Octavia | soft | steady | caress | praise | slow |
| Vinyl | rough | quick | smack, kiss | playful | quick |
| Berry | rough | quick | smack | playful, dirty | quick |
| Cheerilee | firm | steady | caress | praise, reassurance | normal |
| Maud | soft | steady | caress | none (quiet) | slow |
| Trixie | firm | steady | kiss | praise, playful | quick |
| Zecora | firm | steady | caress | reassurance | slow |
| Spitfire | rough | quick | smack | praise, playful | normal |
| Default | firm | steady | none | none | normal |

Dislikes are shown in the settings editor and stay in the `preferences` block. They are used only
where the character's temperament supports them; the main cast uses `smack` and/or `dirty` for
Rarity, Octavia, Maud and Zecora, and the wider roster follows the same rule.

## Tests

- The Characters form is the only per-mare editor; it writes only on **Save preset**.
- The debug `Show prompt context` action prints the resolved prompt note, relationship line, cycle
  note, history note and recent events.
- `tests/readiness/test_preferences.gd` covers profile merge, likes/dislikes and classification.
- `tests/test_character_preferences.gd` covers the roster, display names and templates.
- `tests/test_settings.gd` covers the per-mare merge and the Characters form contract.

## Related docs

- `docs/readiness.md` — the scoring loop and the auto stroke.
- `docs/eligibility.md` — consent, participation and the per-mare gates.
- `docs/summary.md` — the act summary, tolerance and the history tiers.
- `docs/settings.md` — the settings framework and the Characters tab.
