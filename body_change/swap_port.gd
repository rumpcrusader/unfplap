@abstract
extends RefCounted
## The body-change handover's ordered release and resume seams. `act/swap.gd` implements this
## contract directly, so the handover calls one typed object instead of 32 callbacks.


@abstract func attach_to_world() -> void


@abstract func release_carry() -> bool


@abstract func release_contacts() -> void


@abstract func remember_auto() -> void


@abstract func release_act_body() -> void


@abstract func release_scene() -> void


@abstract func release_swap_pose() -> void


@abstract func restore_camera() -> void


@abstract func stop_breath() -> void


@abstract func resume_body() -> void


@abstract func prepare_anatomy_act() -> void


@abstract func apply_resume_settings() -> void


@abstract func rebind_reactions() -> void


@abstract func set_act_pose_config() -> void


@abstract func rebuild_act_pose() -> void


@abstract func sync_start_config() -> void


@abstract func reset_visual_for_form() -> void


@abstract func reset_pelvis() -> void


@abstract func reset_lean() -> void


@abstract func open_camera() -> void


@abstract func reset_wings() -> void


@abstract func claim_nav() -> void


@abstract func pause_face_turn() -> void


@abstract func reset_face() -> void


@abstract func apply_voice_policy() -> void


@abstract func apply_pose_change() -> void


@abstract func apply_anatomy_live() -> void


@abstract func begin_integrations() -> void


@abstract func sync_hud() -> void


@abstract func resume_auto() -> void


@abstract func rebind_body() -> void


@abstract func new_body_is_adult() -> bool
