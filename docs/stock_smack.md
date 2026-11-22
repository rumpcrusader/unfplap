# Outside-act smack

The flank smack outside an act: the native `FlankTouch` sound player's pack layer, its restore,
and the handoff of that player to the act and back.

## Ownership and boundary

`stock_smack/api.gd` is one world-scope service the entry's service list constructs. It owns the
per-pony bookkeeping of the players it changed and the one `AudioStreamRandomizer` over the pack
hand-smack variants; `hands/api.gd` owns the act's own per-impact swap on the same player. The
service reads only the pony nodes the registry hands it and the setting through the settings
service, and it does no per-frame work.

## Decisions

- The replacement is a stream swap on the game's own player, not a second player: the decal,
  blush, jiggle and reaction stay on the stock impact, and the native player's own play call
  drives the pack variants.
- The randomizer runs in no-repeat mode at its own level and a neutral native pitch, so its own
  pitch variation applies; the act's hand-smack level stays separate.
- Each changed player's stream, volume and pitch are saved before the swap and restored exactly
  when the switch goes off, when the pony starts an act, or when the world closes.
- The service remembers a pony seen while the switch is off, so turning it on reaches every pony
  already loaded.
- An act pony is skipped: `act_start()` gives her stock player back so the hands' per-impact swap
  owns it, and `act_end()` re-installs the pack layer after the hands restore.

## Invariants

- Only the stock player is touched; a pony without `FlankTouch` is ignored.
- A restored player gets the values it had, not the shipped defaults.
- A world enter or close puts every stock player back and forgets its ponies; the loaded pack
  streams stay for the next world.
- The setting is live: the service subscribes to the settings change notification itself, so the
  entry installs no settings path.

## Extension points

A second outside-act cue family joins the same saved-and-restored player record rather than a
second listener; a new pack variant is a row in `shared/smack_cues.gd`.
