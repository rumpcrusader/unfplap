# Privacy

The one live privacy provider. It answers one predicate the proactive, negotiation and act stages
share; it does not invent a new rule. Contract owner of the offer and cuddle verdict for a target.

## Scope

This contract covers:

- the live privacy facts for a target: the house, the other mares, Anon, the outdoor radius and
  the target exclusion;
- the offer predicate for a bed or standing offer and the stricter cuddle predicate, chosen by a
  `Kind`;
- the one public answer those facts produce.

It does not cover an offer decision, a pose, a scene row or an act start. Visibility is derived by
the consumer from this answer; there is no public override, no third-pony answer rule and no
negotiation face here. The house lookup is a world read (`docs/world.md`), not a privacy read.

## Ownership

`privacy/api.gd` (a world-list service extending `shared/service.gd`) owns the scene reads for
privacy and the facts they build: Anon's live body, the mares, the house at each point and the
outdoor other-mare radius. The offered mare is excluded from both other-mare counts: she never
counts as another mare.

The rule itself is `shared/privacy_rules.gd`:

```text
offer_private  = house_alone or not others_near
cuddle_private = house_alone if indoors else not others_near
```

"House alone" counts every other mare in the same house; `others_near` counts every other mare
within the radius. The gathered facts are a private value: the provider resolves both predicates
and drops them with the call.

## Facade

`privacy/api.gd` owns the privacy answer.

`is_private()` is the one predicate. The caller names the `Kind`: `OFFER` for a bed or standing
offer, `CUDDLE` for the stricter cuddle rule. A missing world bound, a missing player or a freed
rig fails closed to not-private.

## Data ownership

The provider stores no data. Everything is sampled from the live scene per call.

## Settings

No setting changes privacy. `features.act_public_offer` and `consent.public` no longer override
the reserve; the retired setting is removed from the declaration in the settings retirement
phase.

## Controls and debug

No privacy hotkey and no provider report: the offer and the negotiation log their own privacy-loss
lines.

## Host boundary

The provider calls plain world reads only: Anon's body, the mares and the house at a point. It
never calls a service or a runtime, and with no world bound every answer is public.