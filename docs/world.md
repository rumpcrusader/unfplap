# World

The one place a service reads the live scene. `world/service.gd` (RefCounted, static state) is
bound by the entry on world and player enter and cleared on world close. It answers *where* and
*what* — the world root, Anon's body and the reads derived from them — and never *whether*: every
gate, offer and act rule stays with its caller.

## Scope

This contract covers:

- the live world root and Anon's body, and the handles resolved from them (the view camera, the
  reach interactor, the desktop interactions node);
- the world-owned reads a rule is built on: the mare list, the thinkable bed under a point, the
  real bed behind a mattress hit, the bed a cradle looks at, bed occupancy, Anon's seat beside a
  bed, the menu/panel gates and the headset test;
- the two scene writes a service cannot do itself: the merged LOD rebuild after a shape change and
  the act chat open past the controls lock.

It does not cover an offer, a pose, an act start, a gate verdict or any act state. It preloads no
service facade and no runtime.

## Ownership

The facade is also the mod's one "is there a world" read: a pure guard is
`is_instance_valid(WORLD.game)`. It replaces the entry handle every service used to hold for the
same answer, so a service never names the entry to ask whether the scene is live.


`world/service.gd` owns the bound scene handles:

| Read | Why it is a read, not a rule |
|---|---|
| `game` | the live world root; the caller decides what to do with it |
| `player` | Anon's body; the caller decides whether he may act |
| `camera()` | which camera the eye looks through, with the one-second lookup cache |
| `interactor()` | the player rig's reach node, resolved once per body |
| `desktop()` | the desktop interactions node in the world |
| `player_body()` | the rig body the game shows for Anon |
| `player_is_pony()` | Anon's live form is a pony |
| `game_player()` | the game's own player property, read defensively; null when absent or not a `Node3D` |
| `mares()` | a typed copy of the world's live mare list |
| `bed_under(point, exclude)` | the bed a downward probe finds under a point |
| `real_bed(node)` | the bed behind a mattress or temporary support hit |
| `bed_for_cradle(pony)` | the bed a cradle looks at, under the pony then ahead of the eye |
| `bed_occupied(bed, target)` | another mare already lying on the mattress top |
| `player_beside_bed(bed)` | Anon's seat is the bed or its couch |
| `scan_allowed()` | the tree is not paused and a desktop cursor is captured or the eye is in a headset |
| `menu_panel_open()` | a tree pause or a known UI panel owns the mouse |
| `menu_open()` | the panel test plus "the cursor is visible" |
| `headset_view()` | the eye is in a headset |
| `refresh_body_lod(pony)` | drop the merged LOD caches and re-arm the near mesh |
| `open_act_chat()` | open the chat box past the act's controls lock |

## Base-game access

`world/game.gd` is the base-game and presentation accessor module: static functions with explicit
arguments, no bound state and no service preload. `world/service.gd` delegates its raw reads to it,
and the act calls it directly for the eye line and the blush sustainer. Every accessor answers with
a typed zero when the member is absent or renamed — `null` for a handle, `false` for a flag, `NAN`
for a measurement, a zero vector for a direction — and a clamp hands back the basis it was given.
An argument that is not a live node is answered the same way, so a caller that
holds a freed handle gets the absent answer instead of a crash.

The private members below are quirks of this game version and its HUD: the accessor mirrors their
behaviour exactly, and a game update that renames one is a change here rather than in a caller.

| Accessor | Member | Returns | Absent answer |
|---|---|---|---|
| `GAME.headset_view(game)` | `headset_view` | `bool` | `false` |
| `GAME.game_player(game)` | `player` | `Node3D` | `null` |
| `GAME.mares(game)` | `mares` | `Array[Node3D]`, a copy | empty |
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
| `GAME._settings_page_button(page, parent, text, callback)` | the page's `_button` (private) | `Button` | `null` |
| `GAME.settings_page_icon(page, kind)` | the page's `_icon_texture` (private) | `Texture2D` | `null` |
| `GAME.settings_page_redraw(page)` | the page's `_redraw` (private) | — | no call |
| `GAME.set_menu_icon_kind(icon, kind)` | a menu icon's `kind` | — | no write |
| `GAME.inventory(game)` | `inventory` | `Node` | `null` |
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
| `GAME.bond_record_for(bonds, id)` | `record_for` | `BondRecord`, a typed view | absent view |
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
| `GAME.mods_data_folder(mods, id)` | `Mods.data_folder` | `String` | empty |
| `GAME.mods_list(mods)` | `Mods.list` | `Array[Dictionary]`, the installed rows | empty |
| `GAME.prepare_vocal(director, pony_id)` | the director's `vocal.prepare` | — | no call |
| `GAME.tts_of(director)` | the director's `tts` | `Node` | `null` |
| `GAME.tts_has_server(tts)` | `has_server` | `bool` | `false` |
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
| `GAME.pin_kiss_side(pose, side, hold_s)` | the pose's `_side`, `_side_now`, `_side_wait` (private) | — | no write |
| `GAME.release_kiss_side(pose)` | the pose's `_side_wait` (private) | — | no write |
| `GAME.settle_excitement(excitement)` | the Beat's `_until` (private) | — | no write |
| `GAME.set_expression(mouth, name, amount)` | the mouth rig's `set_expression` | — | no call |
| `GAME.setting_string(settings, key)` | `Settings.get_value` | `String` | empty |
| `GAME.anon_height(settings)` | `Settings.anon_height_scale` | `float` | `NAN` |
| `GAME.tts_enabled(settings)` | `Settings.tts_enabled` | `bool` | `false` |
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
| `GAME.set_hold_target(driver, side, frame, kind)` | the rig's `set_hold_target` | — | no call |
| `GAME.clear_hold_target(driver, side)` | the rig's `clear_hold_target` | — | no call |
| `GAME.hand_frame(driver, side)` | the rig's `hand_frame` | `Transform3D` | infinite origin |
| `GAME.show_toast(instance, text, seconds)` | the HUD's `_show_toast` (private) | — | no call |
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
| `GAME.oral_ready(bridge)` | the anatomy bridge's `oral_ready` | `bool` | `false` |
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
| `GAME.joint_constrain(limits, bone, basis)` | the pony's `joint_limits.constrain` | `Basis` | the input basis |

Only the accessors that hand back a typed copy or a typed view allocate — the mare, couch-seat,
case and mods lists, the ladder, the bond record, the story rows, the world events, the mod state,
the director's line host and the model config — plus `GAME.refresh_body_lod` and the settings page's
tab button and icon, which rebuild through the game's own code. The per-frame accessors copy
nothing.

`GAME` writes the rig's control hold, its eye line and its look pitch, the chat lock, her navigator's
face point, conversation aim, owner, wander, speed, pace and destination, her own locomotion facing,
her posture request, her face-turn rate, her wing hold, open switch and fold blends, the carry flags,
the seated Q hold, a body's velocity, her gaze and pupils, the stock kiss's
latch and side hold, the affection it feeds, the director's authored-line queue, the world-context
situation record, the mod state section, the settings page's tab icon kind, the briefcase's slot
writes and world drops, the inventory's quick-slot card and its bar, the HUD's toast line, the
seated space and rest holds, and the VR touch bridge's caress event.

## Internal API

```gdscript
const WORLD := preload("res://mods/unfplap/world/service.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")

static var game: Node
static var player: Node3D

static func bind_world(host: Node) -> void
static func bind_player(body: Node3D) -> void
static func unbind() -> void
static func camera() -> Camera3D
static func interactor() -> Node
static func desktop() -> Node
static func player_body() -> Node3D
static func player_is_pony() -> bool
static func game_player() -> Node3D
static func mares() -> Array[Node3D]
static func bed_under(point: Vector3, exclude: RID = RID()) -> Node3D
static func real_bed(node: Node) -> Node3D
static func bed_for_cradle(pony: Node3D) -> Node3D
static func bed_occupied(bed: Node3D, target: Node) -> bool
static func player_beside_bed(bed: Node3D) -> bool
static func scan_allowed() -> bool
static func menu_panel_open() -> bool
static func menu_open() -> bool
static func headset_view() -> bool
static func refresh_body_lod(pony: Node) -> void
static func open_act_chat() -> bool
```

`WORLD.mares()` answers a typed copy of the game's live list, so a caller may keep it across a
scan but never expects the game's own array. `GAME` is the raw layer: every function takes the
scene handle it needs and answers the typed zero, so a consumer that already holds `game` or
`player` calls it directly instead of reaching through the facade.

`Bind` runs in this order from the entry: `bind_world()` on world ready (it clears the resolved
handles), `bind_player()` when the player rig arrives, `unbind()` on world close. An unbound
facade answers `null` and `false`; that is the "no world yet" answer, not a rule. `game_player()`
reads the game's own `player` property through `GAME`, so a renamed or missing property is null
instead of a crash.

## Data ownership

The facade stores no saved data. It holds the two bound handles and three resolved ones, all
cleared on every bind and on unbind. Nothing is written to the settings file or `Mods.state`.

## Lifecycle

- Scope: world
- Constructed by: static initialization
- Begin: `bind_world()`/`bind_player()`
- End: `unbind()`/world close
- Idempotent: yes

## Settings

No setting is declared or read here.

## Controls and debug

No control and no debug action. The debug tooling reads the scene through this facade like any
other consumer.

## Host boundary

The entry is the only writer: it calls `bind_world(host)`, `bind_player(body)` and `unbind()`. The
facade never calls back into the entry.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|

## Tests

- `tests/world/test_world.gd`: the camera cache and its fallback, the bed resolution and the
  real-bed walk, bed occupancy and Anon's seat, the menu/paused/headset gates, the player body and
  mare reads, the LOD rebuild and the act chat, the unbound and freed-handle answers, and every
  `GAME` accessor's live and absent answer, including the chat hold's save and restore.
- `tests/test_settings.gd`: the settings page's tab button, icon texture and redraw and the mods
  data folder, live and absent, and the size preset through the setting accessor.

## Related docs

- `ARCHITECTURE.md` — the layer rules and the host boundary.
- `docs/scene_gate.md` — the live scene rows a gate evaluates through this facade.
- `docs/poses.md` — the bed pose that seats a pony on it.
