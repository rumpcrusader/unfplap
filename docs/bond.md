# Lover bond (`bond/service.gd`)

The mod-owned lover bond: per-world storage, the stored stage, the grant/clear service and the
world-context event. The eligibility rules that decide when a bond may be granted or ended are in
`docs/eligibility.md`; this doc is the storage and service contract.

## Ownership

`bond/service.gd` stores the bond in `Mods.state("unfplap").sex_bonds`. It is per-world save data and
survives a reload. It never expires. The static functions (`section`, `grant`, `clear`,
`set_stage`, `row`, `bonded`, `save`) are the store the pure tests drive.

The per-pony service is one instance the runtime owns and binds with host callables:

| Method | Contract |
|---|---|
| `bind(host)` | the host: `id`, `state`, `pony`, `bond_facts`, `relationship`, `event`, `log`, and the optional `section` (tests) |
| `grant_bond(source, line)` | re-check the scene gates, store the row, save, record one event |
| `end_bond(source, line)` | clear the row, save, record one event |
| `refresh_bond()` | the stale-bond sweep: keep the stage current, clear after a break-up |

The runtime's `grant_sex_bond()`, `end_sex_bond()` and `refresh_sex_bond()` are thin forwards;
`bond/dialogue_consent.gd` calls them after a spoken agreement or withdrawal, and the Debug actions call
them for the aimed or nearest mare. The runtime supplies `bond_facts` (the eligibility verdict's
bond flag, stage and love level), so the service never reads the policy itself.

`bonds.record_for(id)` is the game's base relationship record; the mod never edits it. The mod bond
is separate.

## Storage

```gdscript
{
  "version": 1,
  "sex_bonds": {
    "<mare id>": {
      "at": 1760000000.0,
      "stage": "dating",          # the base stage when granted
      "love_level": 3,
      "source": "dialogue",       # dialogue | debug | ...
      "line": "the spoken line, left-truncated to 240 chars",
    },
  },
  "sex_bonds_last_clear": {"id": "...", "reason": "...", "at": 0.0},
}
```

The section is created on first write. `grant()` is idempotent: an existing row is left alone, so a
repeat spoken yes cannot replace the original moment or record a second event. `clear()` erases the
row and writes the last-clear note. `save()` is separate from the mutation so pure tests never touch
`user://`.

## Grant and clear rules

- **Grant** requires the eligibility verdict's `bond` mode to pass, which includes the adult and
  Promiscuity gates, the kiss-willingness gate and no active act. It stores the base stage, love
  level, source and spoken line. It records `You and Anon became lovers.` in the world context.
- **End** is a clear spoken withdrawal or the Debug clear. It is allowed whenever a bond exists.
  It records `You and Anon are no longer lovers.`.
- **Stale-bond maintenance** (`refresh_sex_bond`) runs every 2 s while idle. It keeps the stored
  stage current while the base relationship is dating/engaged/married. If the base stage leaves
  those stages and the stored stage was romantic, the bond is cleared. A bond made at Crush or Any
  Adult has no romantic stage to leave and stays.
- There is no break-up call from the mod. The base game's `break_up()` is never called.
- The bond is stored even after a base break-up clears it; the next `refresh_sex_bond` removes it.

## World-context event

`grant` and `end` record one `relationship` event:

```text
You and Anon became lovers.
You and Anon are no longer lovers.
```

The event id is `unfplap:sex_bond:<id>:<ticks>`, so a retry cannot duplicate it. The event is
what the profile and the AI's recent activities read; the private impression is not written by this
module.

## Debug

- **Grant lover bond** (World › Debug › Actions) grants the bond to the aimed or nearest eligible
  mare. It uses the eligibility service, so it fails outside the adult, Promiscuity and
  kiss-willingness gates.
- **Clear lover bond** clears it and always works.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|

## Lifecycle

- Scope: process + per-pony
- Constructed by: `main`/`runtime`
- Begin: `bind()`
- End: `end_bond()`
- Idempotent: yes


## Tests

- `tests/bond/test_sex_bond.gd` — storage shape, idempotent grant, stage update, clear and the
  last-clear note, romantic-stage detection.
- `tests/bond/test_bond_service.gd` — the scene service: grant/end/refresh, the world-context event
  and the stale-bond sweep with a fake relationship runtime.
- `tests/history/test_act_history.gd` — the history tier the gate reads.

## Related docs

- `docs/eligibility.md` — who may be granted a bond and when it blocks or opens an act.
- `docs/history.md` — the act history and the long-term relationship state.
- `docs/settings.md` — the Starting Sex choice and the World debug rows.
