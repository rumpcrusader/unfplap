# World

The world service facade: the one place a service reads the live scene. `world/api.gd` (RefCounted,
static state) is bound by the entry on world and player enter and cleared on world close. It answers
*where* and *what* — the world root, Anon's body, the reads derived from them and the typed views of
the base-game objects around them — and never *whether*: every gate, offer and act rule stays with
its caller.

## Scope

This contract covers:

- the live world root and Anon's body, and the handles resolved from them (the view camera, the
  reach interactor, the desktop interactions node);
- the world-owned reads a rule is built on: the mare list, the place directory's answer for a
  point, the thinkable bed under a point, the real bed behind a mattress hit, the bed a cradle
  looks at, bed occupancy, Anon's seat beside a bed, a house's bed, the shop's item scene, the
  menu/panel gates and the headset test;
- the three scene writes a service cannot do itself: the merged LOD rebuild after a shape change,
  the act chat open past the controls lock and a body's velocity;
- the bound views of a pony's body, navigator, face, wings and flank, Anon's rig, a bed, the
  conversation director and its world context, the inventory and menu surfaces, the mods registry,
  the relationship runtime and its bond store, the scene's kisser and the affection nodes, and the
  handle cache behind them.

It does not cover an offer, a pose, an act start, a gate verdict or any act state. It preloads no
service facade and no runtime.

## Ownership

The facade is also the mod's one "is there a world" read: `ready()` answers it for the bound pair, and
`world_root()` is the world-only half for a caller that needs the scene but not Anon. It replaces
the entry handle every service used to hold for the same answer, so a service never names the entry
to ask whether the scene is live.

`world/api.gd` owns the bound scene handles:

| Read | Why it is a read, not a rule |
|---|---|
| `ready()` | both bound handles are live |
| `world_root()` | the live world root, for a caller that must parent or hand off the scene root |
| `camera()` | which camera the eye looks through, with the one-second lookup cache |
| `interactor()` | the player rig's reach node, resolved once per body |
| `desktop()` | the desktop interactions node in the world |
| `player_body()` | the rig body the game shows for Anon |
| `presentation()` | the game's desktop presentation node |
| `player_rig()` | Anon's rig as the entry bound it |
| `player_is_pony()` | Anon's live form is a pony |
| `game_player()` | the game's own player property, read defensively; null when absent or not a `Node3D` |
| `mares()` | a typed copy of the world's live mare list |
| `shop_item(id)` | the shop's packed item scene |
| `shape_ids()` | a typed copy of the population catalogue's shape ids |
| `shape_scene(id)` | a shape's packed scene from the population catalogue |
| `house_at(at)` | the house interior at a world point |
| `place_at(at)` | the place directory's region id for a world point |
| `house_of(n)` | the house interior that owns a node |
| `bed_under(point, exclude)` | the bed a downward probe finds under a point |
| `real_bed(node)` | the bed behind a mattress or temporary support hit |
| `bed_for_cradle(pony)` | the bed a cradle looks at, under the pony then ahead of the eye |
| `bed_occupied(bed, target)` | another mare already lying on the mattress top |
| `player_beside_bed(bed)` | Anon's seat is the bed or its couch |
| `ensure_bed(house, kind)` | a house's bed through the house's own builder |
| `can_interact()` | the tree is not paused and a desktop cursor is captured or the eye is in a headset |
| `paused()` | the live world's tree is paused |
| `menu_panel_open()` | a tree pause or a known UI panel owns the mouse |
| `menu_open()` | the panel test plus "the cursor is visible" |
| `headset_view()` | the eye is in a headset |
| `interaction_hints()` | the world's own interaction-hints node |
| `bond_level(id)` | her cached love level, with `found` telling the ladder fallback whether the cache held her |
| `refresh_body_lod(pony)` | drop the merged LOD caches and re-arm the near mesh |
| `dock_rump_z(body_name, y)` | the rump surface height of a dock body table entry |
| `set_velocity(body, value)` | a body's velocity |
| `open_chat()` | open the chat box past the act's controls lock |

## Views

A view is a base-game object with its receiver already bound: `pony(n)`, `navigator(n)`, `face(n)`,
`wings(n)`, `flank(n)`, `bed(n)`, `inventory()`, `menu()`, `director()`, `story()`, `anon()`,
`mods()`, `relationship()` and `affection()` answer a handle whose receiver is already chosen.
The factory caches one handle per bound node, and one each for the player, the inventory, the
menu, the relationship runtime, the mods registry and the scene's kisser, so a per-frame read costs
a lookup rather than an allocation, and every bind and `unbind()` drops the cache so a swapped body
can never answer through the old one. A view built on `null` answers the accessors' typed zeroes; a
caller that keeps one across a despawn therefore reads those zeroes rather than crashing.

`Anon` is bound by the facade to its player handle, so its player members take no node. The
presentation and the hand or torso driver it acts on are still passed, because a caller may hold a
different one.

`Bed` binds whichever of the four rest-family nodes holds the row a member reads: the bed itself for
the bedding and the stock rest, the couch/rest that owns it for the seats and the guest entries, one
of its seats for the exit floor, and the seating system for a pony's seating phase. A member takes
the other nodes it needs — the seat it asks about, the pony, the body stepping off — because they are
not the receiver.

| View | Binds | Members |
|---|---|---|
| `Pony` | a pony body, or the act body that answers for her | `identity`, `has_wings`, `skeleton`, `head`, `mouth`, `hair`, `hair_skeleton`, `model`, `body`, `dock`, `dock_anchor`, `dock_fit`, `dock_fitted_mesh`, `dock_reach`, `dock_rump_z`, `claim_body_materials`, `hair_link`, `hair_link_ready`, `hair_link_pelvis`, `set_hair_link_pelvis`, `notify_hair_link`, `far_mesh_shown`, `set_near_mesh`, `forget_far_mesh`, `eye_motion`, `boop`, `body_scale`, `set_body_scale`, `exclude_from_outline`, `head_skeleton`, `set_viseme`, `clear_viseme`, `mouth_point`, `skull_world`, `nose_world`, `muzzle_world`, `eye_transform`, `listen_point`, `look_toward`, `aim_eyes`, `joint_constrain`, `is_held`, `grounded`, `awareness`, `can_hear`, `can_see`, `posture_requested`, `request_posture`, `interruption_reason`, `face_turn_rate`, `set_face_turn_rate`, `stop_speaking`, `speaking`, `set_motion_paused` |
| `Navigator` | a pony body, or the navigator node a caller recorded | `node`, `present`, `owner`, `reserved`, `wander`, `has_target`, `stay`, `set_owner`, `set_reserved`, `set_wander`, `speed_limit`, `pace_target`, `set_speed_limit`, `set_pace_target`, `support`, `walk_to`, `clear_travel`, `set_conversation_target`, `clear_conversation_target`, `set_face_point`, `set_facing`, `clear_facing` |
| `Face` | a pony body | `controller`, `touch`, `release_touch`, `stare`, `fluster`, `fluster_amount`, `dialogue_face`, `set_dialogue`, `finish_dialogue`, `clear_dialogue`, `sustain_blush`, `celebrate`, `set_expression`, `line_faces` |
| `Wings` | her excitement Beat, or the wing node it owns | `node`, `hold`, `release_hold`, `set_open`, `spread`, `flutter`, `opened`, `set_opened`, `set_tuck`, `set_half` |
| `Flank` | her `FlankTouch` node, or the touch body whose hulls need syncing | `sync`, `update_surface`, `surface_contact`, `touch_nearest`, `impact`, `wake_tick`, `start_jiggle`, `process`, `jiggle_amount`, `set_jiggle_amount`, `rump_blush_texture` |
| `Anon` | the player rig, bound by the facade | `seat`, `controls_locked`, `set_controls_locked`, `set_presentation_enabled`, `force_stand_up`, `eye_height`, `set_eye_y`, `set_stand_eye`, `set_eye_height`, `pitch`, `set_pitch`, `form`, `clamp_view`, `form_is_young`, `form_is_pony`, `body`, `exclude_from_outline`, `q_held`, `set_q_held`, `set_space_hold`, `set_rest_held`, `sit_on`, `toggle_couch_sleep`, `set_hold_target`, `clear_hold_target`, `hand_frame`, `apply_torso_pose`, `set_rest_hand_targets`, `clear_rest_hand_targets`, `pose_driver`, `set_pose_driver`, `knockdown`, `start_knockdown` |
| `Bed` | a bed, the couch/rest that owns it, a seat on it or the seating system | `couch_pony_transform`, `couch_seats`, `couch_open`, `couch_invite`, `couch_approach`, `couch_mare_fits`, `couch_cooldown_until`, `couch_partner`, `rest_word`, `rest_bed`, `refresh`, `fits`, `has_guest`, `sleeper`, `front`, `accepts`, `willing`, `eligible`, `seat_free_for`, `seating_phase`, `release_seat`, `finish_guest`, `release_pony`, `surface_top`, `exit_point`, `stock_rest` |
| `Director` | the scene's conversation director, found by the facade, and the world root it belongs to | `speaking`, `interrupt`, `clock`, `subsystem_active`, `lines`, `llm_config`, `new_llm`, `background_allowed`, `prepare_vocal`, `record_event`, `record_situation`, `tts`, `tts_running`, `play_vocal`, `play_kiss`, `world_context`, `impressions`, `impression_mood`, `set_impression_mood`, `commit_impression`, `standing_line`, `voice_facts` |
| `Story` | the world-context node, resolved by the facade from the bound world | `journal`, `store`, `open`, `last_line_id`, `search`, `witnessed`, `line_text`, `events` |
| `Inventory` | the game's inventory node, resolved by the facade from the bound world | `store`, `slots`, `loans`, `writable`, `available`, `take`, `put`, `grant`, `spawn_drop`, `item_scene`, `held_count`, `holding_case`, `hotbar`, `hotbar_visible`, `set_hotbar_visible`, `hotbar_layer`, `set_hotbar_layer_visible`, `place_hotbar`, `hud_hidden`, `set_hud_hidden` |
| `Menu` | the bound world root | `panel`, `show_toast`, `sound` |
| `Relationship` | the scene's relationship runtime | `love_name`, `runtime`, `bonds`, `ladder`, `bonds_of`, `record`, `save_record`, `eligible_for_romance`, `welcomes`, `day`, `mark_met`, `request_space` |
| `ModRegistry` | the game's mods registry autoload | `present`, `state`, `active`, `save`, `list` |
| `Affection` | the scene's stock kisser | `kisser`, `begin_from_pony`, `clear_kisser`, `end`, `cancel_afterglow`, `feed`, `side_known`, `pin_side`, `release_side`, `settle_excitement`, `buck`, `end_cuddle`, `hoof_active`, `carry_ours`, `carry_actions`, `clear_carry`, `carry_released`, `caress`, `end_interaction`, `kiss_settings` |

`Pony` resolves the parts it can reach from the body it holds — her identity, head, mouth, blush
sustainer and gaze controller — so a call names only the extra value it needs. The members that
operate on something else carry that first: a mesh, a dock fit, a body name, a gaze object, a
joint-limit table, or the stock affection while she is held. `Face` resolves her controller and
sustainer the same way, so the pony stays the only handle its caller holds; its `line_faces` is the
base game's expression table, handed out so a pure module can validate a name without an import.

`Navigator` binds the body for the same reason: its members reach her `Navigator` child, so the
leases, the wander switch, the speed and pace overrides, the route and the facing take no node.
It also binds the navigator node itself, so the ledger that recorded the lease at claim time keeps
its reads and writes past a lost pony read; `node()` is that handle and `present()` its presence.
Only the travel lease it clears and the conversation target it keeps are passed. The lease itself
belongs to whichever caller claimed it, and the view only carries that owner's reads and writes.

`Wings` and `Flank` are split by what owns the call: the wing hold and fold members take the wing
node and the stock spread takes her Beat, while the jiggle members take her `FlankTouch` node, the
hull sync takes her touch body and the skinning call takes the owned patch as its argument. The
hull query and the patch's contact query sit on the same view because each is one of those
members' own reads.

`Director` is the one view bound to two nodes. Its director members are bound to the scene's
conversation director, which the facade finds by its group; the world context and the impressions
are the bound world's, so `world_context`, `impressions` and the mood rows resolve them there rather
than through a caller's node. The subsystem, TTS, vocal and boop nodes a member asks about are passed
because they are not the receiver. `voice_facts` is the one composed member: it hands the pure voice
classifier the director's profile, the TTS mode and server, the switch its caller passes and the
game's own routing answer, so no classifier reads a game node. `new_llm` builds a fresh client for a
caller to name, configure and parent, and `background_allowed` answers the game's own policy, so the
classifier and the adapter import no model or policy module. `Story` binds the world-context node itself, so the journal, its
store and the event list take no node either.

`Inventory` binds the inventory node the facade resolved, so the store, the world drop, the
quick-slot bar and its HUD flag take no node; the store a slot row reads and the bar a visibility
member asks about are passed because they are not the receiver. `item_scene` is the shop's one
scene read, and the facade's `shop_item` answers through it instead of keeping a second home.
`Menu` binds the world root for the named panels; the toast sink and the cue's source node are
passed because they are not the receiver. The settings page's own icon, redraw and menu-icon kind
are the settings accessor's, so this view does not carry them.

`Relationship` is bound to the scene's relationship runtime, with `bonds` and `ladder` resolving
through it. `bonds_of` and `love_name` still take a pony because she is not the receiver: they read
the store her own metadata points at. The store-keyed members — the record, its save, the romance
test, the welcome, the day and the mark — take that store for the same reason. `ModRegistry` binds
the game's mods registry autoload, so `present`, `state`, `active`, `save` and `list` answer without
a host argument. `Affection` binds the scene's stock kisser for
`kisser`, `begin_from_pony` and `clear_kisser`; the affection, kiss pose, Beat, cuddle session,
hoof hold, reach, runtime body and touch bridge its other members write are passed because they
are not the kisser. A caller that saves through the registry owns the call: the view only asks it.

A view holds no service and no act state, and it writes nothing on construction. It is a read and
write surface over the accessor module, so a base-game rename stays a change in `world/game.gd`.

## Base-game access

`world/game.gd` is the base-game and presentation accessor module: static functions with explicit
arguments, no bound state and no service preload. `world/api.gd` delegates its raw reads to it, and
the act reads the eye line and the blush sustainer through the views. Every accessor answers with
a typed zero when the member is absent or renamed — `null` for a handle, `false` for a flag, `NAN`
for a measurement, a zero vector for a direction — and a clamp hands back the basis it was given.
An argument that is not a live node is answered the same way, so a caller that
holds a freed handle gets the absent answer instead of a crash.

The private members below are quirks of this game version and its HUD: the accessor mirrors their
behaviour exactly, and a game update that renames one is a change here rather than in a caller.

| Accessor | Member | Returns | Absent answer |
|---|---|---|---|
| `GAME.headset_view(game)` | `headset_view` | `bool` | `false` |
| `GAME.desktop_presentation(game)` | `desktop_presentation` | `Node` | `null` |
| `GAME.game_player(game)` | `player` | `Node3D` | `null` |
| `GAME.mares(game)` | `mares` | `Array[Node3D]`, a copy | empty |
| `GAME.shape_ids(game)` | the population's `available` keys | `Array[String]`, a copy | empty |
| `GAME.shape_scene(game, id)` | the population's `available` path, loaded | `PackedScene` | `null` |
| `GAME.bond_level(game, id)` | the world context's `state.bond_levels` row | `BondLevel` | unfound |
| `GAME.player_camera(player)` | the rig's `camera` | `Camera3D` | `null` |
| `GAME.find_camera(game, player)` | `_find_camera` (private) | `Camera3D` | `null` |
| `GAME.player_avatar(player)` | the rig's `form_driver.avatar` | `Node3D` | `null` |
| `GAME.player_body_node(player)` | the rig's `Body` child | `Node3D` | `null` |
| `GAME.seat_of(player)` | the rig's `seat` | `Node` | `null` |
| `GAME.controls_locked(player)` | the rig's `controls_locked` | `bool` | `false` |
| `GAME.set_controls_locked(player, locked)` | the rig's `controls_locked` | — | no write |
| `GAME.set_presentation_enabled(presentation, on)` | `set_enabled` | — | no call |
| `GAME.force_stand_up(player)` | `force_stand_up` | — | no call |
| `GAME.menu_panel(game, key)` | `save_menu`, `settings_menu`, `pause_menu` | `Node` | `null` |
| `GAME.inventory(game)` | `inventory` | `Node` | `null` |
| `GAME.interaction_hints(game)` | the world's `InteractionHints` child | `Node` | `null` |
| `GAME.inventory_held_count(inventory)` | the inventory's `held` row count | `int` | `0` |
| `GAME.inventory_holding_case(inventory)` | the inventory's `holding_case` | `String` | empty |
| `GAME.case_store(inventory)` | the inventory's `inventory` briefcase store | `Object` | `null` |
| `GAME.case_slots(store)` | the store's `slots`, one row per slot | `Array[Dictionary]`, a copy | empty |
| `GAME.case_loans(store)` | the store's `loans` | `Array[Dictionary]`, a copy | empty |
| `GAME.case_writable(store)` | the store's `writable` | `bool` | `false` |
| `GAME.case_available(store, slot)` | the store's `available` | `int` | `-1` |
| `GAME.case_take(store, slot)` | the store's `take` | `String` | empty |
| `GAME.case_put(store, token, slot)` | the store's `put` | `bool` | `false` |
| `GAME.case_grant(store, id, count)` | the store's `grant` | `int` | `-1` |
| `GAME.shop_item_scene(id)` | `shop_items.scene` | `PackedScene` | `null` |
| `GAME.house_of(node)` | a `house_interior.gd` node | `HOUSE` | `null` |
| `GAME.house_at(tree, at)` | the `house_interiors` group | `Node3D` | `null` |
| `GAME.place_at(point)` | `PonyAwareness.place_at`, the place directory's regions | `String` | empty |
| `GAME.ensure_bed(house, kind)` | `ensure_bed` | `Node3D` | `null` |
| `GAME.spawn_owned_drop(inventory, id, pose)` | the inventory's `spawn_owned_drop` | `Node` | `null` |
| `GAME.map_open(inventory)` | `_map_open` (private) | `bool` | `false` |
| `GAME.case_visible(inventory)` | `case.visible` | `bool` | `false` |
| `GAME.customizer_opened(inventory)` | `customizer.opened` | `bool` | `false` |
| `GAME.inspector_active(inventory)` | `inspector.active` | `bool` | `false` |
| `GAME.chat_box(game)` | the `ChatBox` child | `Node` | `null` |
| `GAME.open_chat(game, player)` | `_open`, `_lock_owned` (private), and the rig's `controls_locked` | `bool` | `false` |
| `GAME.identity_of(pony)` | `identity` | `Resource` | `null` |
| `GAME.boop_of(pony)` | `boop_node` | `Node` | `null` |
| `GAME.sustain_blush(boop, amount)` | `sustain_blush` | — | no call |
| `GAME.celebrate(boop)` | `celebrate` | `bool` | `false` |
| `GAME.head_of(pony)` | `head` | `Node` | `null` |
| `GAME.mouth_of(head)` | the head's `mouth` | `Node` | `null` |
| `GAME.head_skeleton_of(boop)` | the boop's `head_skeleton` | `Skeleton3D` | `null` |
| `GAME.set_viseme(mouth, letter)` | `set_viseme` | — | no call |
| `GAME.clear_viseme(mouth)` | `clear` | — | no call |
| `GAME.expressions_of(pony)` | `expressions` | `Object` | `null` |
| `GAME.touch(expressions, source, smile, lids)` | `touch` | — | no call |
| `GAME.release_touch(expressions, source)` | `release_touch` | — | no call |
| `GAME.stare(expressions, on, lids)` | `stare` | — | no call |
| `GAME.fluster(expressions, seconds, peeks)` | `fluster` | — | no call |
| `GAME.fluster_amount(expressions)` | `fluster_amount` | `float` | `0.0` |
| `GAME.dialogue_face(expressions)` | `dialogue_face` | `String` | empty |
| `GAME.set_dialogue(expressions, face)` | `set_dialogue` | — | no call |
| `GAME.finish_dialogue(expressions, seconds)` | `finish_dialogue` | — | no call |
| `GAME.clear_dialogue(expressions)` | `clear_dialogue` | — | no call |
| `GAME.set_stand_eye(body, y)` | the rig's `_stand_eye` | — | no write |
| `GAME.set_eye_height(body, y)` | the rig's `_eye_height` | — | no write |
| `GAME.eye_height(player)` | `eye_height` | `float` | `NAN` |
| `GAME.set_eye_y(body, y)` | `_set_eye_y` (private) | — | no write |
| `GAME.pitch(body)` | the rig's `_pitch` | `float` | `NAN` |
| `GAME.set_pitch(body, pitch)` | the rig's `_pitch` | — | no write |
| `GAME.form_of(player)` | the rig's `form_driver` | `Node` | `null` |
| `GAME.clamp_view(form)` | `clamp_view` | — | no call |
| `GAME.clear_facing(pony)` | the navigator's `face_point` and `set_conversation_target`, one lookup | — | no write |
| `GAME.look_toward(secondary, angles, weight)` | `look_toward` | `bool` | `false` |
| `GAME.eye_motion_of(pony)` | `eye_motion` | `Node` | `null` |
| `GAME.aim_eyes(eye_motion, target)` | `target_world`, `target_weight` | — | no write |
| `GAME.listen_point(pony)` | `listen_point` | `Vector3` | her root plus `UP` |
| `GAME.eye_transform(body)` | `eye_transform` | `Transform3D` | infinite origin |
| `GAME.skull_world(boop)` | `skull_world` | `Vector3` | `Vector3.INF` |
| `GAME.nose_world(boop)` | `nose_world` | `Vector3` | `Vector3.INF` |
| `GAME.muzzle_world(boop)` | `muzzle_world` | `Vector3` | `Vector3.INF` |
| `GAME.refresh_body_lod(pony)` | the hybrid near and far LOD caches, `set_near_mesh` | — | no rebuild |
| `GAME.far_mesh_shown(pony)` | `_far_mesh_shown` | `bool` | `false` |
| `GAME.set_near_mesh(pony, on)` | `set_near_mesh` | — | no call |
| `GAME.anon_body_of(player)` | the rig's `AnonBody` child | `Node3D` | `null` |
| `GAME.skeleton_of(pony)` | `skeleton` | `Skeleton3D` | `null` |
| `GAME.hair_skeleton_of(pony)` | `hair_skeleton` | `Skeleton3D` | `null` |
| `GAME.hair_of(pony)` | `hair` | `Node3D` | `null` |
| `GAME.model_of(pony)` | `_model` (private) | `Node` | `null` |
| `GAME.body_of(pony)` | the model's `MareBody` child | `MeshInstance3D` | `null` |
| `GAME.dock_of(pony)` | the body's `OpenPonyDock` child | `MeshInstance3D` | `null` |
| `GAME.own_body_materials(pony)` | `FlankTouch._own_body_materials` (private) | — | no call |
| `GAME.hair_link_of(pony)` | `hair_link` | `Node` | `null` |
| `GAME.hair_link_ready(pony)` | the hair link's `pelvis_offset` | `bool` | `false` |
| `GAME.hair_link_pelvis(pony)` | the hair link's `pelvis_offset` | `Transform3D` | `Transform3D.IDENTITY` |
| `GAME.set_hair_link_pelvis(pony, value)` | the hair link's `pelvis_offset` | — | no write |
| `GAME.notify_hair_link(pony)` | the hair link's `_body_updated` (private) | — | no call |
| `GAME.bed_of(collider)` | the mattress `bed_of` lookup | `Node3D` | `null` |
| `GAME.visible_top(bed, points, fallback)` | the mattress `visible_top` lookup | `float` | `fallback` |
| `GAME.stock_bed_rest(bed)` | `SharedBed.for_bed`, installed on first use | `Node3D` | `null` |
| `GAME.navigator_of(pony)` | the `Navigator` child | `Node` | `null` |
| `GAME.navigator_owner(nav)` | the navigator's `command_owner` | `String` | empty |
| `GAME.navigator_reserved(nav)` | the navigator's `reserved_by` | `String` | empty |
| `GAME.navigator_wander(nav)` | the navigator's `wander_enabled` | `bool` | `false` |
| `GAME.navigator_has_target(nav)` | the navigator's `_has_target` (private) | `bool` | `false` |
| `GAME.navigator_stay(nav)` | `stay` | — | no call |
| `GAME.set_navigator_owner(nav, owner)` | the navigator's `command_owner` | — | no write |
| `GAME.set_navigator_reserved(nav, value)` | the navigator's `reserved_by` | — | no write |
| `GAME.set_navigator_wander(nav, enabled)` | the navigator's `wander_enabled` | — | no write |
| `GAME.travel_clear(travel, pony)` | `clear` | — | no call |
| `GAME.set_conversation_target(pony, target, hold)` | `set_conversation_target` | — | no call |
| `GAME.face_turn_rate(pony)` | the body's `face_turn_rate` | `float` | `NAN` |
| `GAME.set_face_turn_rate(pony, value)` | the body's `face_turn_rate` | — | no write |
| `GAME.is_held(pony)` | `is_held` | `bool` | `false` |
| `GAME.grounded(pony)` | `grounded` | `bool` | `false` |
| `GAME.posture_requested(pony)` | `posture_status().requested` | `String` | empty |
| `GAME.posture_settled(pony)` | `posture_status().settled` | `bool` | `false` |
| `GAME.interruption_reason(pony)` | `action_interruption_reason` | `String` | empty |
| `GAME.interrupt_director(director)` | `interrupt` | — | no call |
| `GAME.director_speaking(director)` | the director's `state` | `bool` | `false` |
| `GAME.pony_speaking(pony)` | `is_speaking` | `bool` | `false` |
| `GAME.stop_speaking(pony)` | `stop_speaking` | — | no call |
| `GAME.relationship_runtime(game)` | `relationship_runtime` | `Node` | `null` |
| `GAME.relationship_bonds(runtime)` | the runtime's `bonds` | `Object` | `null` |
| `GAME.relationship_ladder(runtime, id)` | `ladder` | `LADDER`, a typed view | absent view |
| `GAME.relationship_love_name(pony, id)` | the `relationship_runtime` meta's `ladder(id).love.name` | `String` | `?` |
| `GAME.bonds_of(pony)` | the relationship runtime's `bonds` | `Object` | `null` |
| `GAME.bond_record_for(bonds, id)` | `record_for` | `BondRecord`, a typed record | empty record |
| `GAME.bond_record_save(bonds, id, record)` | the store's `_save` (private) | `bool` | `false` |
| `GAME.bond_eligible_for_romance(bonds, id)` | `eligible_for_romance` | `bool` | `false` |
| `GAME.bond_welcomes(bonds, id, kind)` | `welcomes` | `bool` | `false` |
| `GAME.bond_day(bonds)` | `day` | `float` | `NAN` |
| `GAME.bond_mark_met(bonds, id)` | `mark_met` | `bool` | `false` |
| `GAME.request_space(pony, id)` | the bond store's `request_space` | — | no call |
| `GAME.body_scale_of(pony)` | `body_scale` | `float` | `1.0` |
| `GAME.set_body_scale(pony, scale)` | `set_body_scale`, else `body_scale` | — | no write |
| `GAME.world_context(game)` | `world_context` | `Node` | `null` |
| `GAME.story_of(context)` | the world context's `story` | `Object` | `null` |
| `GAME.story_store(story)` | the journal's `store` | `Object` | `null` |
| `GAME.story_open(story)` | `is_open` | `bool` | `false` |
| `GAME.story_last_line_id(store)` | `last_line_id` | `int` | `-1` |
| `GAME.story_search(store, pony, words, before, limit)` | `search` | `Array[StoryRow]`, a copy | empty |
| `GAME.story_witnessed(store, pony, limit, before, kinds)` | `witnessed` | `Array[StoryRow]`, a copy | empty |
| `GAME.story_line_text(story, row, pony, with_day)` | `line_text` | `String` | empty |
| `GAME.world_events(context, id, limit)` | the context's `events_for` | `Array[Dictionary]`, a copy | empty |
| `GAME.world_record(context, kind, text, witnesses, subjects, event_id, place)` | `record` | — | no write |
| `GAME.record_situation(context, text, ids, key)` | the world context's `record` | — | no call |
| `GAME.impressions_of(context)` | the world context's `impressions` | `Node` | `null` |
| `GAME.impression_mood(impressions, id, absent)` | the store's `profile(id).mood` | `String` | `absent`, empty without a profile |
| `GAME.impression_set_mood(impressions, id, mood, key)` | `commit` with the mood row | `bool` | `false` |
| `GAME.impression_commit(impressions, id, mood, romance, thought, event_id)` | `commit` | `bool` | `false` |
| `GAME.impression_standing_line(impressions, id)` | `standing_line` | `String` | empty |
| `GAME.director_now(director)` | the director's `_now` (private) | `float` | `NAN` |
| `GAME.subsystem_active(node)` | an approach or group's `active` | `bool` | `false` |
| `GAME.director_lines(director)` | the director's `begin_player_greeting`, `queue_generated_intent`, `cancel_authored_line` | `DirectorLines` | no call |
| `GAME.llm_config(director)` | the director's `config`, `_llm_section` (private) and `llm.status_path` | `LlmConfig` | `enabled` false |
| `GAME.new_llm()` | the model client module's constructor | `Node` | — |
| `GAME.background_allowed(config)` | `ai_config.background_allowed` | `bool` | `true`, the game's own default |
| `GAME.request_posture(pony, posture)` | `request_posture` | — | no call |
| `GAME.navigator_speed_limit(nav)` | the navigator's `command_speed_limit` | `float` | `NAN` |
| `GAME.navigator_pace_target(nav)` | the navigator's `command_pace_target` | `float` | `NAN` |
| `GAME.set_navigator_speed_limit(nav, value)` | the navigator's `command_speed_limit` | — | no write |
| `GAME.set_navigator_pace_target(nav, value)` | the navigator's `command_pace_target` | — | no write |
| `GAME.navigator_support(nav, point)` | `command_support` | `Vector3` | `Vector3.INF` |
| `GAME.navigator_destination(nav, point, gait)` | `command_destination` | `bool` | `false` |
| `GAME.rest_word(node)` | `rest_word` | `String` | empty |
| `GAME.rest_bed_of(node)` | a couch's `_bed` (private) or `bed_node` | `Node3D` | `null` |
| `GAME.bed_rest_accept(rest, pony)` | `accept` | `bool` | `false` |
| `GAME.bed_rest_willing(rest, pony)` | `_willing` (private) | `bool` | `false` |
| `GAME.bed_rest_eligible(rest, pony)` | `eligible` | `bool` | `false` |
| `GAME.bed_rest_refresh(rest)` | `refresh` | — | no call |
| `GAME.bed_rest_fits(rest)` | `_mare_fits` (private) | `bool` | `false` |
| `GAME.bed_rest_has_guest(rest)` | `_guest` (private) | `bool` | `false` |
| `GAME.bed_rest_sleeper(rest)` | `_sleeper` (private) | `Node3D` | `null` |
| `GAME.bed_rest_front(rest, pony)` | `_front_for` (private) | `Vector3` | `Vector3.INF` |
| `GAME.couch_partner(couch, seat)` | `partner` | `Node` | `null` |
| `GAME.mods_state(mods, id)` | `Mods.state` | `ModState`, the live section | empty rows |
| `GAME.mod_active(mods, id)` | `Mods.is_active` | `bool` | `false` |
| `GAME.mods_save(mods)` | `Mods.save_changed` | — | no save |
| `GAME.mods_list(mods)` | `Mods.list` | `Array[Dictionary]`, the installed rows | empty |
| `GAME.prepare_vocal(director, pony_id)` | the director's `vocal.prepare` | — | no call |
| `GAME.tts_of(director)` | the director's `tts` | `Node` | `null` |
| `GAME.tts_has_server(tts)` | `has_server` | `bool` | `false` |
| `GAME.voice_route(director, id)` | the director's `characters`, its `tts` and the game's own mode/chatter routing | `VoiceRoute` | empty profile, Ponese, no server |
| `GAME.vocal_play(vocal, id, gender, pony, db)` | the vocal node's `play` | `bool` | `false` |
| `GAME.affection_buck(affection, body)` | `Affection.buck` | `bool` | `false` |
| `GAME.kisser_of(game)` | the scene's `kisser` | `Node` | `null` |
| `GAME.begin_from_pony(kisser, pony)` | `pony_kisser.begin_from_pony` | `bool` | `false` |
| `GAME.play_kiss(boop, db, loop)` | `play_kiss` | `bool` | `false` |
| `GAME.clear_kisser(kisser)` | the kisser's `_active`, `_her_kiss`, `_used_hold` (private) | — | no write |
| `GAME.end_affection(affection)` | `Affection.end` | — | no call |
| `GAME.cancel_afterglow(affection)` | `Affection.cancel_afterglow` | — | no call |
| `GAME.feed_affection(affection, target, eye, face)` | the affection's `target`, `eye`, `face` | — | no write |
| `GAME.mouth_point(node)` | `mouth_point` | `Vector3` | `Vector3.INF` |
| `GAME.kiss_side_known(pose)` | the stock kiss pose's `_side` (private) | `bool` | `false` |
| `GAME.kiss_settings()` | the stock kiss settings document | `KissSettings`, the live rows | empty rows |
| `GAME.pin_kiss_side(pose, side, hold_s)` | the pose's `_side`, `_side_now`, `_side_wait` (private) | — | no write |
| `GAME.release_kiss_side(pose)` | the pose's `_side_wait` (private) | — | no write |
| `GAME.settle_excitement(excitement)` | the Beat's `_until` (private) | — | no write |
| `GAME.set_expression(mouth, name, amount)` | the mouth rig's `set_expression` | — | no call |
| `GAME.line_faces()` | the dialogue face table | `LineFaces`, the game's rows | empty rows |
| `GAME.setting_string(settings, key)` | `Settings.get_value` | `String` | empty |
| `GAME.knockdown_of(body)` | the body's `knockdown` | `Object` | `null` |
| `GAME.start_knockdown(node, body, direction)` | `knockdown.start` | `bool` | `false` |
| `GAME.cuddle_end(session)` | the cuddle session's `end(true)` | — | no call |
| `GAME.hoof_active(hoof)` | the hoof hold's `active` | `bool` | `false` |
| `GAME.seat_free_for(seat, pony)` | the seat's `free_for` | `bool` | `false` |
| `GAME.player_sit_on(player, seat)` | the rig's `sit_on` | `bool` | `false` |
| `GAME.player_toggle_couch_sleep(player)` | the rig's `toggle_couch_sleep` | `bool` | `false` |
| `GAME.couch_pony_transform(node, seat)` | a couch's `pony_transform` | `Transform3D` | infinite origin |
| `GAME.couch_seats(node)` | a couch's `seats` | `Array[Node3D]`, a copy | empty |
| `GAME.couch_open(node)` | a couch's `open` | `bool` | `false` |
| `GAME.couch_invite(node, pony, seat)` | a couch's `invite` | `bool` | `false` |
| `GAME.couch_approach(node, seat)` | a couch's `approach` | `Vector3` | `Vector3.INF` |
| `GAME.couch_mare_fits(node)` | a couch's `_mare_fits` (private) | `bool` | `false` |
| `GAME.couch_cooldown_until(node, pony)` | a couch's `_cooldowns` (private) | `int` | `0` |
| `GAME.couch_exit(body, seat, fallback, height, radius)` | the exit-space `find_exit` probe | `Vector3` | `Vector3.INF` |
| `GAME.carry_ours(reach, pony)` | the reach's `held` and `cradled` | `bool` | `false` |
| `GAME.carry_actions(reach)` | the reach's `desktop_actions` | `Node` | `null` |
| `GAME.clear_carry(reach)` | the reach's carry flags | — | no write |
| `GAME.carry_released(actions)` | the desktop actions' `pony_released` | — | no call |
| `GAME.end_interaction(pony)` | `end_interaction` | — | no call |
| `GAME.set_velocity(body, velocity)` | the body's `velocity` | — | no write |
| `GAME.set_motion_paused(pony, paused)` | `motion_paused` | — | no write |
| `GAME.set_q_held(body, held)` | the rig's `_q_held` | — | no write |
| `GAME.seating_phase(seating, id)` | the seating system's phase entry | `String` | empty |
| `GAME.seating_release_entry(seating, id)` | the seating system's `_release` (private) | — | no call |
| `GAME.couch_finish_guest(node)` | a couch's `_finish_guest` (private) | — | no call |
| `GAME.couch_release_pony(node, id)` | a couch's `_release_pony` (private) | — | no call |
| `GAME.touch_sync(body, rig)` | `PonyTouchBody._unprofiled_sync(rig, true)` (private) | — | no call |
| `GAME._touch_nearest(body, point)` | `PonyTouchBody.nearest` | `Dictionary` | empty |
| `GAME.flank_surface_update(surface, skeleton, frame)` | `FlankSurface.update_pose` | — | no call |
| `GAME._flank_surface_contact(surface, point, palm, reach)` | `FlankSurface.contact` | `Dictionary` | empty |
| `GAME.flank_impact(flank, index, at, strength)` | `FlankTouch.impact` | — | no call |
| `GAME.flank_wake_tick(flank)` | `FlankTouch.wake_tick` | — | no call |
| `GAME.flank_start_jiggle(flank, index, strength)` | `FlankTouch._start_jiggle` (private) | `bool` | `false` |
| `GAME.flank_process(flank, delta)` | `FlankTouch._process` (private) | — | no call |
| `GAME.flank_jiggle_amount(flank)` | `FlankTouch._jiggle_amount` (private) | `float` | `NAN` |
| `GAME.set_flank_jiggle_amount(flank, amount)` | `FlankTouch._jiggle_amount` (private) | — | no write |
| `GAME.rump_blush_texture()` | the flank patch's `texture` | `Texture2D` | `null` |
| `GAME.set_hold_target(driver, side, frame, kind)` | the rig's `set_hold_target` | — | no call |
| `GAME.clear_hold_target(driver, side)` | the rig's `clear_hold_target` | — | no call |
| `GAME.hand_frame(driver, side)` | the rig's `hand_frame` | `Transform3D` | infinite origin |
| `GAME.show_toast(instance, text, seconds)` | the HUD's `_show_toast` (private) | — | no call |
| `GAME.interaction_sound(source, kind, at)` | `interaction_sounds.play_at` | — | no call |
| `GAME.inventory_hud_hidden(inventory)` | the inventory's `hud_hidden` | `bool` | `false` |
| `GAME.set_inventory_hud_hidden(inventory, hidden)` | the inventory's `hud_hidden` | — | no write |
| `GAME.hotbar(inventory)` | the inventory's `hotbar` | `Node` | `null` |
| `GAME.hotbar_visible(bar)` | the hotbar's `visible` | `bool` | `false` |
| `GAME.set_hotbar_visible(bar, visible)` | the hotbar's `visible` | — | no write |
| `GAME.hotbar_hud_layer(bar)` | the hotbar's `_hud` (private) | `CanvasLayer` | `null` |
| `GAME.set_hotbar_hud_visible(bar, visible)` | the hotbar's `set_hud_visible` | — | no call |
| `GAME.inventory_place_hotbar(inventory)` | the inventory's `_place_hotbar` (private) | — | no call |
| `GAME.q_held(body)` | the rig's `_q_held` | `bool` | `false` |
| `GAME.set_space_hold(body, seconds)` | the rig's `_space_hold` | — | no write |
| `GAME.set_rest_held(body, held)` | the rig's `_rest_held` | — | no write |
| `GAME.caress(touch)` | the VR touch bridge's `caress` event | — | no call |
| `GAME.set_face_point(nav, point)` | the navigator's `face_point` | — | no write |
| `GAME.clear_conversation_target(nav)` | the navigator's `set_conversation_target` | — | no call |
| `GAME.face_direction(pony, direction)` | the body's `face_direction` | — | no call |
| `GAME.identity_has_wings(identity)` | an identity's `has_wings` | `bool` | `false` |
| `GAME.wings_of(excitement)` | the Beat's `_wings` (private) | `Node` | `null` |
| `GAME.wing_hold_at(wings, owner, value)` | the wing node's `hold_at` | `bool` | `false` |
| `GAME.wing_release_hold(wings, owner)` | the wing node's `release_hold` | — | no call |
| `GAME.wing_set_open(wings, open)` | the wing node's `set_open` | — | no call |
| `GAME.wing_spread(excitement, seconds)` | the Beat's `spread` | — | no call |
| `GAME.wing_flutter(excitement)` | the Beat's `flutter` | — | no call |
| `GAME.wing_opened(wings)` | the wing node's `opened` | `bool` | `false` |
| `GAME.set_wing_opened(wings, open)` | the wing node's `opened` | — | no write |
| `GAME.set_wing_tuck(wings, value)` | the wing node's `tuck` | — | no write |
| `GAME.set_wing_half(wings, value)` | the wing node's `half` | — | no write |
| `GAME.apply_torso_pose(driver, hip, facing)` | the desktop driver's `apply_torso_pose` | — | no call |
| `GAME.set_rest_hand_targets(driver, left, right)` | the desktop driver's `set_rest_hand_targets` | — | no call |
| `GAME.clear_rest_hand_targets(driver, left, right)` | the desktop driver's `clear_rest_hand_targets` | — | no call |
| `GAME.desktop_pose_driver(avatar)` | the Anon body's `desktop_pose_driver` | `Node` | `null` |
| `GAME.set_desktop_pose_driver(avatar, driver)` | the Anon body's `desktop_pose_driver` | — | no write |
| `GAME.awareness_forward(pony)` | the body's `awareness_forward` | `Vector3` | zero vector |
| `GAME.can_hear(observer, partner)` | `PonyAwareness.can_hear` with the stock hearing range | `bool` | `false` |
| `GAME.can_see(observer, target)` | `PonyAwareness.visible` | `bool` | `false` |
| `GAME.joint_constrain(limits, bone, basis)` | the pony's `joint_limits.constrain` | `Basis` | the input basis |
| `GAME.exclude_from_outline(mesh)` | `post_outline_exclusion.apply_to` | — | no call |
| `GAME.player_form_is_young(tree)` | `player_form.active` + `is_young` | `bool` | `false` |
| `GAME.player_form_is_pony(tree)` | `player_form.active` + `is_pony` | `bool` | `false` |
| `GAME.dock_tail_anchor(pony)` | `dock_tail_mount.measure` | `Vector3` | `Vector3.INF` |
| `GAME.dock_fit(pony)` | `hybrid_dock.effective_fit` + `read_fit` | `DOCK_FIT`, the shared document | `null` |
| `GAME.dock_fitted_mesh(fit)` | `hybrid_dock.fitted_mesh` | `ArrayMesh` | `null` |
| `GAME.dock_reach_rump(mesh, pony)` | `hybrid_dock.reach_rump` | `ArrayMesh` | the input |
| `GAME.dock_rump_z(body, y)` | `hybrid_dock.rump_z` | `float` | `NAN` |
| `GAME.forget_far_mesh(pony)` | the far-mesh caches | — | no drop |

Only the accessors that hand back a typed copy or a typed view allocate — the mare, couch-seat,
case, shape-id and mods lists, the ladder, the bond record, the story rows, the world events, the
mod state, the line faces, the kiss settings, the director's line host and the model
config — plus `GAME.refresh_body_lod` and the stock cue, which rebuild through the game's own code,
and the two senses, which build the game's awareness node per call. The per-frame accessors copy
nothing.

`GAME` writes the rig's control hold, its eye line and its look pitch, the chat lock, her navigator's
face point, conversation aim, owner, wander, speed, pace and destination, her own locomotion facing,
her posture request, her face-turn rate, her wing hold, open switch and fold blends, the carry flags,
the seated Q hold, a body's velocity, her gaze and pupils, the stock kiss's
latch and side hold, the affection it feeds, the director's authored-line queue, the world-context
situation record, the mod state section, the briefcase's slot
writes and world drops, the inventory's quick-slot card and its bar, the HUD's toast line, the
seated space and rest holds, and the VR touch bridge's caress event.

## Facade

`WORLD.mares()` answers a typed copy of the game's live list, so a caller may keep it across a
scan but never expects the game's own array. `GAME` is the raw layer behind the facade and the
views: every function takes the scene handle it needs and answers the typed zero, so the mod-owned
accessor module stays a private detail of the world service.

`Bind` runs in this order from the entry: `bind_world()` on world ready (it clears the resolved
handles), `bind_player()` when the player rig arrives, `unbind()` on world close. The two binds and
`unbind()` are the only writers of the private `_game` and `_player` handles; `ready()` and
`player_rig()` are the reads every other file uses. An unbound facade answers `null` and `false`;
that is the "no world yet" answer, not a rule. `game_player()` reads the game's own `player`
property through `GAME`, so a renamed or missing property is null instead of a crash.

The views of a pony's body, navigator, face, wings and flank, of Anon's rig, a bed, the scene's
director and world context, the inventory and menu surfaces, the mods registry, the relationship
runtime and the scene's affection, kiss and carry are answered here. Every consumer outside the
world service reads the game through the facade and one of these views; the suites are the code
that still names `GAME` directly.

## Data ownership

The facade stores no saved data. It holds the two private bound handles, three resolved ones and
the view caches, all cleared on every bind and on unbind. Nothing is written to the settings file or
`Mods.state`.

## Settings

No setting is declared or read here.

## Controls and debug

No control and no debug action. The debug tooling reads the scene through this facade like any
other consumer.

## Host boundary

The entry is the only writer: it calls `bind_world(host)`, `bind_player(body)` and `unbind()`. The
facade never calls back into the entry.
