# Body change

The base body-change mechanism: one presented body has one typed body form, a provider source
supplies a borrowed or custom form, and every body-bound system is rebound or refreshed through one
fan-out when the form changes. The provider owns its pack, its offer/reveal policy and its own
observation; the base service never polls.

## Scope

`body_change/service.gd` owns the per-body form store, the default own form, the typed source and
binding registries, the active-change read and the legacy metadata mirror. `body_change/source.gd`
is the provider base and `body_change/wire.gd` writes the legacy keys from the typed form.

The stable pony identity (`pony_id`) is not the presented body: memory, dialogue, preferences,
eligibility, history and summary read the identity; anatomy, tail, camera, pose and appearance read
the form.

## Ownership

The service owns the form for each presented body and the registration order. A source owns its
pack and its forms; a binding owns its own attachment to the body. The service never owns the act
state, the pose, the camera or the act teardown.

## Lifecycle

- Scope: world
- Constructed by: `main._ready()`
- Begin: `setup(host)`
- End: world close
- Idempotent: yes

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| shared | body_change | `shared/body_change.gd` | body change type, state and origin |
| shared | body_change_policy | `shared/body_change_policy.gd` | provider offer/reveal policy base |
| shared | body_binding | `shared/body_binding.gd` | typed body-bound system base |
| shared | body_form | `shared/body_form.gd` | typed body form and the default own form |

## Tests

- `tests/body_change/test_service.gd` — the typed data, the default form, the legacy mirror, the
  form store, the bind/refresh/unbind order, same-node revisions, the source/binding registries and
  the provider-owned notification and request forwarding.

## Related docs

- `docs/README.md` — the service index.
- `docs/anatomy.md`, `docs/runtime.md` — the systems that consume the form.
