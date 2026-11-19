# Ponies

The one registry of per-pony runtimes. `ponies/service.gd` (RefCounted, world scope, static state)
owns the attach and prepare hooks a new body passes through, the typed pending body swap and its
adoption, the live act pointer, the serial allocator and the prompt note the game reads. Every
runtime is built by the entry's factory, so the service never imports `runtime.gd`.

## Scope

This contract covers:

- the pony-to-runtime registry and the `runtime_for(pony)` lookup;
- the attach and prepare hooks, including the late prepare a mod calls once its node exists;
- the typed pending body swap, the duplicate-runtime guard and the adoption path;
- the live act pointer, the stock smack handoff and the idle offer reset on an act start;
- the serial allocator and the `unfplap.serial` state key;
- the prompt note the game's `pony_prompt_notes` group reads;
- the live and installed character lists the Characters selector shows;
- the per-runtime live-settings pass, the idle perf header counts and the teardown.

It does not cover the act itself (`docs/runtime.md`), the attach-time anatomy and tail work
(`docs/anatomy.md`), the eligibility rule (`docs/eligibility.md`) or the body-change sources
(`docs/body_change.md`).

## Lifecycle

- Scope: world
- Constructed by: static initialization
- Begin: the entry binds its host, factory and services; `attach()` per spawned body
- End: `shutdown()` on process exit, `close_world()` on a world close
- Idempotent: yes

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | anatomy | `anatomy/service.gd` | anatomy and tail seat |
| service | eligibility | `eligibility/service.gd` | adult and consent gate |
| service | settings | `settings/service.gd` | settings declarations and live values |
| service | world | `world/service.gd` | live scene reads |
| shared | body_change | `shared/body_change.gd` | shared data |
| shared | log | `shared/log.gd` | log sink and perf entry |
| shared | pony_id | `shared/pony_id.gd` | shared data |

## Tests

- `tests/ponies/` — the registry, the live act pointer, the serial, the prepare hooks and the
  adoption order.
- `tests/handover/` — suspend, adopt and resume against the real service.
