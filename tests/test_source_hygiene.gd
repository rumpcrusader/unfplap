extends SceneTree
## Source hygiene for the mod.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_source_hygiene.gd

const ROOT := "res://mods/unfplap"
## Files allowed to create settings widgets. The declaration panel is settings_ui.gd; the
## character preference form in main.gd is the one hand-built exception. The tools are never
## shipped and are not settings UI.
const WIDGET_FILES := ["res://mods/unfplap/settings_ui.gd", "res://mods/unfplap/main.gd"]
const WIDGETS := ["SpinBox.new(", "CheckButton.new(", "OptionButton.new(", "ColorPickerButton.new("]
var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var files: Array[String] = []
	_collect(ROOT, files)
	check(files.size() > 10, "source files found")
	var manifest_text := FileAccess.get_file_as_string(ROOT.path_join("mod.json"))
	var manifest: Variant = JSON.parse_string(manifest_text)
	check(manifest is Dictionary, "mod.json parses")
	if manifest is Dictionary:
		var data := manifest as Dictionary
		var semver := RegEx.new()
		semver.compile("^\\d+\\.\\d+\\.\\d+$")
		var version := str(data.get("version", ""))
		var game_version := str(data.get("game_version", ""))
		check(str(data.get("id", "")) == "unfplap", "mod id")
		check(semver.search(version) != null, "mod version is MAJOR.MINOR.PATCH")
		check(game_version == str(ProjectSettings.get_setting("application/config/version", "")),
			"target game version matches the project")
		check(not data.has("extends"), "entry script only")
		check(str(data.get("entry", "")) == "res://mods/unfplap/main.gd", "entry path")
	for path: String in [
		".opencode/skills/release/SKILL.md",
		".opencode/commands/release.md",
		"scripts/prepare_release.sh",
		"scripts/check_release.sh",
		"scripts/check_release_metadata.py",
		"scripts/build_manifest.py",
		"scripts/asset_pack.py",
		"scripts/pack_assets.sh",
		"scripts/fetch_assets.sh",
		"scripts/asset_pack.json",
		"assets/README.md",
	]:
		check(FileAccess.file_exists(ROOT.path_join(path)), "release file %s" % path)
	for path: String in ["build.sh", "tools/pack.gd", ".github/workflows/build.yml"]:
		check(not FileAccess.get_file_as_string(ROOT.path_join(path)).contains("--no-extends"),
			"no obsolete extension flag in %s" % path)
	_check_preloads(files)
	_check_settings_module(files)
	_check_sync_snapshot()
	_check_teardown()
	_check_hands_isolation()
	_check_hands_docs()
	_check_eligibility_isolation(files)
	_check_eligibility_docs()
	_check_anatomy_isolation(files)
	_check_anatomy_docs()
	_check_stool_isolation(files)
	_check_stool_docs()
	_check_initiation_isolation(files)
	_check_initiation_docs()
	_check_memory_isolation(files)
	_check_memory_docs()
	_check_act_facts()
	_check_act_lines()
	_check_readiness()
	_check_history()
	_check_afterglow()
	_check_face()
	_check_reactions()
	_check_pose_session()
	_check_act_camera()
	_check_scene_gate()
	_check_rest_rejoin()
	_check_act_audio()
	_check_hud_lines()
	_check_bond()
	_check_scene_hold()
	_check_docs_index(files)
	print("SOURCE_HYGIENE_RESULT checks=%d failures=%d files=%d" % [checks, failures, files.size()])
	if failures == 0:
		print("SOURCE_HYGIENE_PASS")
	quit(0 if failures == 0 else 1)


## The settings live in one module with one declaration per setting; settings widgets may only
## live in the declaration panel and the preference form.
func _check_settings_module(files: Array[String]) -> void:
	# The settings live in one module. These checks keep that true as the mod grows.
	var module := FileAccess.get_file_as_string(ROOT.path_join("settings.gd"))
	check(module.contains("static func all_settings() -> Array"), "settings module present")
	var stale: Array = []
	var widget_ok := true
	for path: String in files:
		if not path.ends_with(".gd") or path.begins_with(ROOT.path_join("tests/")):
			continue
		if path.begins_with(ROOT.path_join("tools/")):
			continue
		var text := FileAccess.get_file_as_string(path)
		if text.contains("tunables_schema.gd") or text.contains("unfplap/tunables.gd"):
			stale.append(path)
		if path.begins_with(ROOT.path_join("tests/")):
			continue
		if not WIDGET_FILES.has(path):
			for widget: String in WIDGETS:
				if text.contains(widget):
					widget_ok = false
					print("settings widget %s outside settings_ui.gd: %s" % [widget, path])
	check(stale.is_empty(), "no file imports the removed tunable shims: %s" % str(stale))
	check(widget_ok, "only settings_ui.gd (and the preference form) create settings widgets")


## The sync-settings snapshot must keep the full shipped character templates even though the
## player's settings file stores only differences.
func _check_sync_snapshot() -> void:
	var tool := FileAccess.get_file_as_string(ROOT.path_join("tools/settings_snapshot.gd"))
	check(tool.contains("SETTINGS.CHARACTER_TEMPLATES"),
		"the settings snapshot carries the shipped character templates")


## The hands engine must not know a pose. Pose geometry belongs in the path providers; the
## engine only sees the body surface, a contact path and the palm frame.
func _check_hands_isolation() -> void:
	var engine := FileAccess.get_file_as_string(
		ROOT.path_join("hands/placement.gd"))
	check(engine.contains("func frame("), "hands engine is present")
	for token: String in ["pose_id", "CATALOG", "missionary", "standing",
			"desktop_pose_driver", "missionary_anon"]:
		check(not engine.contains(token), "hands engine has no pose reference: %s" % token)
	var path_base := FileAccess.get_file_as_string(
		ROOT.path_join("hands/path_base.gd"))
	check(path_base.contains("func candidates("), "hands path contract is present")
	var contact := FileAccess.get_file_as_string(ROOT.path_join("hands/contact.gd"))
	check(contact.contains("static func contact("), "hands contact query is present")
	for name: String in ["hands/session.gd", "hands/path_base.gd", "hands/contact.gd",
			"hands/surface.gd", "hands/palm.gd", "hands/reach_plan.gd", "hands/scale.gd",
			"hands/smack.gd"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		for token: String in ["pose_id", "CATALOG", "desktop_pose_driver",
				"missionary_anon"]:
			check(not text.contains(token),
				"%s has no pose reference: %s" % [name, token])


## The hands contract lives in one file; every other doc points to it.
func _check_hands_docs() -> void:
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/hands.md"))
	check(not contract.is_empty(), "docs/hands.md exists")
	check(contract.contains("## Controls") and contract.contains("## Contact engine"),
		"docs/hands.md has the controls and contact contract")
	for name: String in ["AGENTS.md", "docs/README.md", "README.md"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		check(text.contains("docs/hands.md"), "%s links to docs/hands.md" % name)


## One ordered teardown owns act exit. If a new exit path or a copied restore sequence appears,
## this fails before a leak reaches a save.
func _check_teardown() -> void:
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	check(_count(runtime, "func _end_session(") == 1, "one act teardown")
	for name: String in ["_abort_start", "_finish_restore", "_restore_now"]:
		check(_func_body(runtime, name).contains("_end_session("),
			"%s ends through _end_session" % name)
	var force := _func_body(runtime, "force_stop")
	check(force.contains("_end_session(") and force.contains("_restore_now()"),
		"force_stop ends through the same teardown")
	for name: String in ["_abort_start", "_finish_restore", "_restore_now", "force_stop"]:
		var body := _func_body(runtime, name)
		for call: String in ["_restore_camera(", "_restore_look(", "_release_nav(",
				"_free_pose(", "_unlock_player("]:
			check(not body.contains(call), "%s does not call %s directly" % [name, call])
	# `cancel()` queues the early-stop reaction after `_restore_begin()`; the timed finish must
	# not cancel director rows or that line never speaks.
	var finish := _func_body(runtime, "_finish_restore")
	check(not finish.contains("_end_act_lines"), "normal restore keeps the early-stop line")
	check(not finish.contains("main.memory.cancel_act("), "normal restore cancels no director rows")


## The eligibility rules are pure and only the adapter reads the gate sources. The docs contract
## lives in one file; other docs link to it instead of restating the rules.
func _check_eligibility_isolation(files: Array[String]) -> void:
	var pure_files := [
		"eligibility/policy.gd", "eligibility/facts.gd", "eligibility/verdict.gd",
		"participation.gd",
	]
	for name: String in pure_files:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		for token: String in ["extends Node", "get_tree(", "Time.", "FileAccess", "SETTINGS",
				"preload(\"res://world/", "preload(\"res://mods/unfplap/settings.gd\")"]:
			check(not text.contains(token), "%s stays pure: %s" % [name, token])
	var shell := FileAccess.get_file_as_string(ROOT.path_join("eligibility.gd"))
	for token: String in ["save_changed", "save_consent", "save_preferences", "SEX_BOND.save",
			"ACT_HISTORY.commit", "ACT_HISTORY.save", "FileAccess"]:
		check(not shell.contains(token), "eligibility shell is read-only: %s" % token)
	# Only the facade is preloaded outside the system; the pure core stays private.
	for path: String in files:
		if not path.ends_with(".gd") or path.begins_with(ROOT.path_join("tests/")):
			continue
		var relative := path.trim_prefix(ROOT.path_join(""))
		if relative == "eligibility.gd" or relative.begins_with("eligibility/"):
			continue
		var text := FileAccess.get_file_as_string(path)
		check(not text.contains("mods/unfplap/eligibility/"),
			"%s uses the eligibility facade only" % relative)
	# Age, sex and the provider assertion stay private: consumers ask a capability target.
	for path: String in files:
		if not path.ends_with(".gd") or path.begins_with(ROOT.path_join("tests/")):
			continue
		var relative := path.trim_prefix(ROOT.path_join(""))
		var text := FileAccess.get_file_as_string(path)
		for token: String in [".adult_mare(", ".adult_pony(", ".adult_player("]:
			check(not text.contains(token),
				"%s asks for a capability, not identity: %s" % [relative, token])
	var readers := {
		"bonds.welcomes(": ["eligibility.gd"],
		"bonds.eligible_for_romance(": ["eligibility.gd"],
		"bonds.adults": ["eligibility.gd"],
		"SETTINGS.promiscuity": ["eligibility.gd", "settings.gd"],
		"SETTINGS.sex_start": ["eligibility.gd", "settings.gd"],
		"SETTINGS.profile_adult": ["eligibility.gd", "main.gd", "api.gd"],
		"SETTINGS.profile_participation": ["eligibility.gd", "main.gd", "api.gd"],
		"SETTINGS.profile_identity": ["eligibility.gd"],
		"SETTINGS.consent(": ["eligibility.gd", "main.gd", "api.gd"],
		"CYCLE.allows_sex(": ["eligibility.gd", "cycle.gd"],
		"ACT_HISTORY.blocks_start(": ["eligibility.gd", "act_history.gd"],
		"ACT_HISTORY.blocks_offers(": ["eligibility.gd", "act_history.gd"],
		"ACT_HISTORY.offer_weight(": ["eligibility.gd", "act_history.gd"],
	}
	for path: String in files:
		if not path.ends_with(".gd") or path.begins_with(ROOT.path_join("tests/")):
			continue
		var relative := path.trim_prefix(ROOT.path_join(""))
		var text := FileAccess.get_file_as_string(path)
		for token: String in readers.keys():
			if not text.contains(token):
				continue
			var allowed: Array = readers[token]
			check(relative in allowed, "%s does not read %s outside the eligibility API" % [
				relative, token])


## The typed act context and the perf probe stay scene-free. The standing camera reads the
## context and never reaches into the runtime's private fields.
func _check_act_facts() -> void:
	var facts := FileAccess.get_file_as_string(ROOT.path_join("act_facts.gd"))
	check(facts.contains("func neck_midpoint("), "act context is present")
	for token: String in ["extends Node", "get_tree(", "FileAccess", "SETTINGS",
			"preload(\"res://world/", "preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")"]:
		check(not facts.contains(token), "act context has no scene reference: %s" % token)
	var perf := FileAccess.get_file_as_string(ROOT.path_join("perf.gd"))
	check(perf.contains("func note(") and perf.contains("func tick("), "perf probe is present")
	for token: String in ["extends Node", "get_tree(", "FileAccess", "SETTINGS",
			"preload(\"res://world/", "preload(\"res://mods/unfplap/runtime.gd\")"]:
		check(not perf.contains(token), "perf probe has no scene access: %s" % token)
	var camera := FileAccess.get_file_as_string(ROOT.path_join("standing_camera.gd"))
	check(camera.contains("var facts: Variant"), "standing camera reads the act context")
	for token: String in ["runtime.get(\"", "runtime.call(\"", "runtime.set(\""]:
		check(not camera.contains(token), "standing camera has no runtime reach-in: %s" % token)


## The act line facade reads the typed act context and the memory facade only. Its contract is
## `docs/lines.md`, linked from the shared docs.
func _check_act_lines() -> void:
	var facade := FileAccess.get_file_as_string(ROOT.path_join("act_lines.gd"))
	check(facade.contains("func admit_cue("), "act line facade is present")
	for token: String in ["preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")", "runtime.get(\"",
			"runtime.call(\"", "runtime.set(\""]:
		check(not facade.contains(token), "act lines has no host reach-in: %s" % token)
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/lines.md"))
	check(not contract.is_empty(), "docs/lines.md exists")
	for heading: String in ["## Scope", "## Architecture", "## Internal API", "## Admission",
			"## Reactions and bystanders", "## Cancelling", "## Tests"]:
		check(contract.contains(heading), "docs/lines.md has %s" % heading)
	for name: String in ["AGENTS.md", "docs/memory.md"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		check(text.contains("docs/lines.md"), "%s links to docs/lines.md" % name)
	for name: String in ["test_act_lines.gd", "test_utterance.gd", "test_utterance_scheduler.gd",
			"test_prompt_notes.gd"]:
		check(FileAccess.file_exists(ROOT.path_join("tests/act_lines/" + name)),
			"tests/act_lines/%s exists" % name)
	var prompts := FileAccess.get_file_as_string(ROOT.path_join("act_lines/prompts.gd"))
	check(prompts.contains("static func note("), "act_lines/prompts.gd is the pure note module")
	for token: String in ["extends Node", "get_tree(", "FileAccess", "SETTINGS",
			"preload(\"res://world/", "preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")"]:
		check(not prompts.contains(token), "prompt notes have no scene reference: %s" % token)
	check(contract.contains("act_lines/prompts.gd"), "docs/lines.md names the prompt note module")
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	for token: String in ["after making love with Anon", "You are in the middle of sex with Anon",
			"still in the afterglow with Anon", "stay: 120"]:
		check(not runtime.contains(token), "runtime has no prompt wording: %s" % token)


## The scene hold owns the borrowed navigator, player and attention state; the runtime keeps the
## one ledger and thin wrappers with read views.
func _check_scene_hold() -> void:
	var text := FileAccess.get_file_as_string(ROOT.path_join("scene_hold.gd"))
	for token: String in ["func claim_nav(", "func keep_nav(", "func release_nav(",
			"func lock_player(", "func unlock_player(", "func release_carry(",
			"func end_cuddle(", "func keep_attention("]:
		check(text.contains(token), "scene_hold.gd has %s" % token)
	for token: String in ["extends Node", "preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")", "runtime.get(", "runtime.call("]:
		check(not text.contains(token), "scene hold has no runtime reach-in: %s" % token)
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	check(runtime.contains("_hold.claim_nav(_id)") and runtime.contains("_hold.lock_player()"),
		"runtime routes the ownership through the facade")
	check(not runtime.contains("func _claim_nav() -> bool:\n\t_nav ="),
		"runtime has no inline navigator claim")
	check(FileAccess.file_exists(ROOT.path_join("tests/scene_hold/test_scene_hold.gd")),
		"tests/scene_hold/test_scene_hold.gd exists")
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/scene_hold.md"))
	check(contract.contains("## Ownership and boundary"), "docs/scene_hold.md documents the boundary")
	check(contract.contains("`scene_hold.gd`"), "docs/scene_hold.md names the facade")


## The lover bond is a static store plus one per-pony service instance; the runtime only forwards.
func _check_bond() -> void:
	var text := FileAccess.get_file_as_string(ROOT.path_join("sex_bond.gd"))
	check(text.contains("func grant_bond(") and text.contains("func refresh_bond("),
		"sex_bond.gd owns the grant/end/refresh service")
	for token: String in ["extends Node", "preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")", "runtime.get(", "main.get("]:
		check(not text.contains(token), "sex bond has no host reach-in: %s" % token)
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	for token: String in ["SEX_BOND.grant(", "SEX_BOND.clear(", "SEX_BOND.set_stage(",
			"SEX_BOND.bonded(", "SEX_BOND.row(", "sex_bonds_last_clear"]:
		check(not runtime.contains(token), "runtime has no bond store calls: %s" % token)
	for name: String in ["test_sex_bond.gd", "test_bond_service.gd"]:
		check(FileAccess.file_exists(ROOT.path_join("tests/bond/" + name)),
			"tests/bond/%s exists" % name)
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/bond.md"))
	check(contract.contains("## Ownership"), "docs/bond.md documents the owner")
	check(contract.contains("grant_bond"), "docs/bond.md names the service API")


## The readiness facade is scene-free scoring state. Its contract is `docs/readiness.md`, and the
## runtime forwards the public values instead of keeping a second copy.
func _check_readiness() -> void:
	var facade := FileAccess.get_file_as_string(ROOT.path_join("readiness.gd"))
	check(facade.contains("func stroke(") and facade.contains("func tick("),
		"readiness facade is present")
	for token: String in ["extends Node", "get_tree(", "FileAccess", "SETTINGS",
			"preload(\"res://world/", "preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")"]:
		check(not facade.contains(token), "readiness has no scene reference: %s" % token)
	check(facade.contains("func auto_step(") and facade.contains("func auto_panel_tick("),
		"readiness owns the auto generator and the hold-X policy")
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	for token: String in ["AUTO_PANEL", "var _auto_thrust", "var _auto_panel", "_auto_on",
			"_auto_default", "_auto_controller()", "auto_panel_action("]:
		check(not runtime.contains(token), "runtime has no auto internals: %s" % token)
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/readiness.md"))
	check(contract.contains("## Ownership"), "docs/readiness.md documents the readiness owner")
	check(contract.contains("`readiness.gd`"), "docs/readiness.md names readiness.gd")
	for name: String in ["test_readiness.gd", "test_runtime_thrust.gd", "test_preferences.gd",
			"test_auto_thrust.gd", "test_auto_panel.gd", "test_readiness_auto.gd"]:
		check(FileAccess.file_exists(ROOT.path_join("tests/readiness/" + name)),
			"tests/readiness/%s exists" % name)


## The history facade owns the summary/tolerance decisions and reads only its pure modules.
## Its contract is `docs/history.md`, and the runtime keeps the scene stop executor.
func _check_history() -> void:
	var facade := FileAccess.get_file_as_string(ROOT.path_join("history.gd"))
	check(facade.contains("func commit_summary(") and facade.contains("func tick_idle("),
		"history facade is present")
	for token: String in ["extends Node", "get_tree(", "FileAccess", "SETTINGS",
			"preload(\"res://world/", "preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")", "runtime.get("]:
		check(not facade.contains(token), "history has no scene reference: %s" % token)
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/history.md"))
	check(contract.contains("## Ownership"), "docs/history.md documents the history owner")
	check(contract.contains("`history.gd`"), "docs/history.md names history.gd")
	for name: String in ["test_act_flow.gd", "test_act_stop.gd", "test_act_summary.gd",
			"test_act_history.gd", "test_act_tolerance.gd", "test_history.gd"]:
		check(FileAccess.file_exists(ROOT.path_join("tests/history/" + name)),
			"tests/history/%s exists" % name)


## The afterglow facade owns the phase timers and the close-window decision; it reads plain
## host callbacks and never the runtime node. Its contract is `docs/afterglow.md`.
func _check_afterglow() -> void:
	var facade := FileAccess.get_file_as_string(ROOT.path_join("afterglow.gd"))
	check(facade.contains("func self_end_tick(") and facade.contains("func close_tick("),
		"afterglow facade is present")
	for token: String in ["extends Node", "get_tree(", "FileAccess", "SETTINGS",
			"preload(\"res://world/", "preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")", "runtime.get(", "runtime.call(\"",
			"main.get(", "main.call(\""]:
		check(not facade.contains(token), "afterglow has no host reach-in: %s" % token)
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/afterglow.md"))
	check(not contract.is_empty(), "docs/afterglow.md exists")
	for heading: String in ["## Scope", "## Architecture", "## Internal API", "## Self-end",
			"## `[stay]` hold", "## Close window", "## Tests"]:
		check(contract.contains(heading), "docs/afterglow.md has %s" % heading)
	var agents := FileAccess.get_file_as_string(ROOT.path_join("AGENTS.md"))
	check(agents.contains("docs/afterglow.md"), "AGENTS.md links to docs/afterglow.md")
	check(FileAccess.file_exists(ROOT.path_join("tests/afterglow/test_afterglow.gd")),
		"tests/afterglow/test_afterglow.gd exists")


## The face facade owns the act face, the line-face owner and the mood-face lifetime. It reads the
## scene through the pony and the host callbacks and never the runtime node. Its contract is
## `docs/face.md`.
func _check_face() -> void:
	var facade := FileAccess.get_file_as_string(ROOT.path_join("face_session.gd"))
	check(facade.contains("func set_act_face(") and facade.contains("func beat("),
		"face facade is present")
	for token: String in ["extends Node", "get_tree(", "FileAccess", "SETTINGS",
			"preload(\"res://world/", "preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")", "runtime.get(", "runtime.call(\"",
			"main.get(", "main.call(\""]:
		check(not facade.contains(token), "face has no host reach-in: %s" % token)
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/face.md"))
	check(not contract.is_empty(), "docs/face.md exists")
	for heading: String in ["## Scope", "## Architecture", "## Internal API", "## Beat table",
			"## Line-face ownership", "## Post-act mood face", "## Tests"]:
		check(contract.contains(heading), "docs/face.md has %s" % heading)
	var agents := FileAccess.get_file_as_string(ROOT.path_join("AGENTS.md"))
	check(agents.contains("docs/face.md"), "AGENTS.md links to docs/face.md")
	for name: String in ["test_runtime_face.gd", "test_act_face.gd", "test_mood_face.gd"]:
		check(FileAccess.file_exists(ROOT.path_join("tests/face/" + name)),
			"tests/face/%s exists" % name)


## The reaction facade owns the jiggle, smack, rump blush and climax hearts; the runtime only
## binds the scene and dispatches the stroke events. Contract: `docs/reactions.md`.
func _check_reactions() -> void:
	var facade := FileAccess.get_file_as_string(ROOT.path_join("act_reactions.gd"))
	check(facade.contains("func smack(") and facade.contains("func hearts_tick("),
		"reaction facade is present")
	for token: String in ["extends Node", "get_tree(", "FileAccess",
			"preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")", "runtime.get(", "runtime.call(\"",
			"main.get(", "main.call(\""]:
		check(not facade.contains(token), "reactions has no host reach-in: %s" % token)
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/reactions.md"))
	check(not contract.is_empty(), "docs/reactions.md exists")
	for heading: String in ["## Scope", "## Architecture", "## Internal API", "## Jiggle and smack",
			"## Rump blush", "## Climax hearts", "## Tests"]:
		check(contract.contains(heading), "docs/reactions.md has %s" % heading)
	var agents := FileAccess.get_file_as_string(ROOT.path_join("AGENTS.md"))
	check(agents.contains("docs/reactions.md"), "AGENTS.md links to docs/reactions.md")
	check(FileAccess.file_exists(ROOT.path_join("tests/reactions/test_reactions.gd")),
		"tests/reactions/test_reactions.gd exists")
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	check(runtime.contains("_reactions.thrust(") and runtime.contains("_reactions.smack("),
		"runtime dispatches to the reaction facade")
	for token: String in ["_rump_decal", "_attach_body_coat_jiggle_target", "_climax_hearts_tick"]:
		check(not runtime.contains(token), "runtime has no reaction internals: %s" % token)


## The pose session owns the pose and modifier nodes, the bed frame, the bone snapshots and the
## pose diagnostics. Its contract is `docs/poses.md`; the pose suites live under `tests/poses/`.
func _check_pose_session() -> void:
	var facade := FileAccess.get_file_as_string(ROOT.path_join("poses/session.gd"))
	check(facade.contains("func begin(") and facade.contains("func sync_standing_config("),
		"pose session facade is present")
	for token: String in ["extends Node", "FileAccess",
			"preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")", "runtime.get(", "runtime.call(\"",
			"main.get(", "main.call(\""]:
		check(not facade.contains(token), "pose session has no host reach-in: %s" % token)
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/poses.md"))
	check(contract.contains("## Ownership"), "docs/poses.md documents the pose owner")
	check(contract.contains("`poses/session.gd`"), "docs/poses.md names poses/session.gd")
	var agents := FileAccess.get_file_as_string(ROOT.path_join("AGENTS.md"))
	check(agents.contains("`poses/session.gd`"), "AGENTS.md names poses/session.gd")
	for name: String in ["test_session.gd", "test_pose_asset.gd", "test_pose_rig.gd",
			"test_pose_scale.gd", "test_rotation.gd"]:
		check(FileAccess.file_exists(ROOT.path_join("tests/poses/" + name)),
			"tests/poses/%s exists" % name)
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	check(runtime.contains("func _pose_service()"), "runtime reaches the pose through the session")
	for token: String in ["_pony_saved_bones", "_tail_lay", "_pose_rig_checked",
			"_attach_body_coat_jiggle_target"]:
		check(not runtime.contains(token), "runtime has no pose internals: %s" % token)


## The act camera owns the lean, the shot smoothing, the free look, the free-camera lock, the eye
## override and the captured look. Its contract is `docs/camera.md`; its suite is `tests/act_camera/`.
func _check_act_camera() -> void:
	var facade := FileAccess.get_file_as_string(ROOT.path_join("act_camera.gd"))
	check(facade.contains("func tick_lean(") and facade.contains("func tick_shot("),
		"act camera facade is present")
	for token: String in ["extends Node", "FileAccess",
			"preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")", "runtime.get(", "runtime.call(\"",
			"main.get(", "main.call(\""]:
		check(not facade.contains(token), "act camera has no host reach-in: %s" % token)
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/camera.md"))
	check(contract.contains("`act_camera.gd`"), "docs/camera.md names act_camera.gd")
	var agents := FileAccess.get_file_as_string(ROOT.path_join("AGENTS.md"))
	check(agents.contains("`act_camera.gd`"), "AGENTS.md names act_camera.gd")
	check(FileAccess.file_exists(ROOT.path_join("tests/act_camera/test_camera.gd")),
		"tests/act_camera/test_camera.gd exists")
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	check(runtime.contains("func _camera_service()"), "runtime reaches the camera through the facade")
	for token: String in ["_lean_block_logged", "_side_return_armed", "_hold_rock_clock",
			"_free_look_yaw", "_free_look_pitch", "_controls_locked_by_camera", "_look_yaw",
			"_back_target", "_lean_velocity", "_bob_velocity", "_camera_thrust_tick"]:
		check(not runtime.contains(token), "runtime has no camera internals: %s" % token)


## The scene gate owns the live scene rows and the refusal executor. Its contract is
## `docs/scene_gate.md`; its suite is `tests/scene_gate/`.
func _check_scene_gate() -> void:
	var facade := FileAccess.get_file_as_string(ROOT.path_join("scene_gate.gd"))
	check(facade.contains("func rows(") and facade.contains("func refuse_available("),
		"scene gate facade is present")
	for token: String in ["extends Node", "FileAccess",
			"preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")", "runtime.get(", "runtime.call(\"",
			"main.get(", "main.call(\""]:
		check(not facade.contains(token), "scene gate has no host reach-in: %s" % token)
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/scene_gate.md"))
	check(contract.contains("## Ownership"), "docs/scene_gate.md documents the owner")
	check(contract.contains("`scene_gate.gd`"), "docs/scene_gate.md names the facade")
	var eligibility := FileAccess.get_file_as_string(ROOT.path_join("docs/eligibility.md"))
	check(eligibility.contains("`scene_gate.gd`"), "docs/eligibility.md names scene_gate.gd")
	var agents := FileAccess.get_file_as_string(ROOT.path_join("AGENTS.md"))
	check(agents.contains("`scene_gate.gd`"), "AGENTS.md names scene_gate.gd")
	check(FileAccess.file_exists(ROOT.path_join("tests/scene_gate/test_scene_gate.gd")),
		"tests/scene_gate/test_scene_gate.gd exists")
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	check(runtime.contains("func _scene_gate()"), "runtime reaches the scene rows through the gate")
	for token: String in ["_scene_rows", "_sleep_owner_allows_bed", "_refusal_floor",
			"_refuse_trust", "_cuddle_start_override", "_player_beside_bed"]:
		check(not runtime.contains(token), "runtime has no scene gate internals: %s" % token)


## The rest facade owns the bed anchor, placement, cuddle rejoin and restore posture. Its contract
## is `docs/rest.md`; its suite is `tests/rest/`.
func _check_rest_rejoin() -> void:
	var facade := FileAccess.get_file_as_string(ROOT.path_join("rest_rejoin.gd"))
	check(facade.contains("func rejoin_bed_cuddle(") and facade.contains("func bed_anchor("),
		"rest rejoin facade is present")
	for token: String in ["extends Node", "FileAccess",
			"preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")", "runtime.get(", "runtime.call(\"",
			"main.get(", "main.call(\""]:
		check(not facade.contains(token), "rest rejoin has no host reach-in: %s" % token)
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/rest.md"))
	check(contract.contains("## Ownership"), "docs/rest.md documents the owner")
	check(contract.contains("`rest_rejoin.gd`"), "docs/rest.md names the facade")
	var agents := FileAccess.get_file_as_string(ROOT.path_join("AGENTS.md"))
	check(agents.contains("`rest_rejoin.gd`"), "AGENTS.md names rest_rejoin.gd")
	check(FileAccess.file_exists(ROOT.path_join("tests/rest/test_rest.gd")),
		"tests/rest/test_rest.gd exists")
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	check(runtime.contains("func _rest_service()"), "runtime reaches the rest through the facade")
	for token: String in ["_bed_anchor", "_shared_bed_rest", "_bed_rest_for", "_stand_beside_bed",
			"_rejoin_note", "CUDDLE_REJOIN_", "COUCH_EXIT"]:
		check(not runtime.contains(token), "runtime has no rest internals: %s" % token)


## The act audio facade owns the pack layers, the base-game sound child and the Ponese mute
## policy. Its contract is `docs/audio.md`; its suites are `tests/act_audio/`.
func _check_act_audio() -> void:
	var facade := FileAccess.get_file_as_string(ROOT.path_join("act_audio.gd"))
	check(facade.contains("func start(") and facade.contains("func apply_voice_policy("),
		"act audio facade is present")
	for token: String in ["preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")", "runtime.get(", "runtime.call(\"",
			"main.get(", "main.call(\""]:
		check(not facade.contains(token), "act audio has no host reach-in: %s" % token)
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/audio.md"))
	check(contract.contains("## Ownership"), "docs/audio.md documents the owner")
	check(contract.contains("`act_audio.gd`"), "docs/audio.md names the facade")
	var agents := FileAccess.get_file_as_string(ROOT.path_join("AGENTS.md"))
	check(agents.contains("`docs/audio.md`"), "AGENTS.md links to docs/audio.md")
	for name: String in ["test_audio.gd", "test_act_audio.gd"]:
		check(FileAccess.file_exists(ROOT.path_join("tests/act_audio/" + name)),
			"tests/act_audio/%s exists" % name)
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	check(runtime.contains("func _audio_service()"), "runtime reaches the audio through the facade")
	for token: String in ["_voice_player", "_voice_volume_saved", "_text_only_voice",
			"_sounds_controller", "func _find_voice_player("]:
		check(not runtime.contains(token), "runtime has no audio internals: %s" % token)


## The pure HUD text stays scene-free; the runtime gathers the values and the card renders them.
## Its contract is `docs/hud.md`.
func _check_hud_lines() -> void:
	var lines := FileAccess.get_file_as_string(ROOT.path_join("hud_lines.gd"))
	check(lines.contains("static func cue_line(") and lines.contains("static func y_pink("),
		"hud lines module is present")
	for token: String in ["extends Node", "get_tree(", "Time.", "FileAccess", "SETTINGS",
			"preload(\"res://world/", "preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")"]:
		check(not lines.contains(token), "hud lines stays pure: %s" % token)
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/hud.md"))
	check(contract.contains("## Ownership"), "docs/hud.md documents the owner")
	check(contract.contains("`hud_lines.gd`"), "docs/hud.md names hud_lines.gd")
	for name: String in ["test_hud_lines.gd", "test_hud.gd"]:
		check(FileAccess.file_exists(ROOT.path_join("tests/hud/" + name)),
			"tests/hud/%s exists" % name)
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	check(runtime.contains("HUD_LINES.cue_line("), "runtime reaches the HUD text through hud_lines")
	check(not runtime.contains("const Y_END_TINT_MAX"), "runtime has no HUD tint constant")


## The docs are the single source of truth: every doc under docs/ is indexed by docs/README.md, and
## the root holds no service contract. The service doc names its facade and its tests.
func _check_docs_index(files: Array[String]) -> void:
	var index := FileAccess.get_file_as_string(ROOT.path_join("docs/README.md"))
	check(not index.is_empty(), "docs/README.md exists")
	for name: String in ["README.md", "AGENTS.md", "WORKFLOW.md", "assets/README.md",
			"AUDIO_CREDITS.md"]:
		check(FileAccess.file_exists(ROOT.path_join(name)), "root doc %s exists" % name)
	for name: String in ["ROTATION.md", "PREFERENCES.md", "HISTORY.md", "TUNING.md"]:
		check(not FileAccess.file_exists(ROOT.path_join(name)),
			"root service contract is gone: %s" % name)
	for path: String in files:
		if not path.ends_with(".md"):
			continue
		var relative := path.trim_prefix(ROOT.path_join(""))
		if relative.begins_with("docs/"):
			var doc := relative.trim_prefix("docs/")
			if doc != "README.md":
				check(index.contains(doc), "docs/README.md indexes %s" % doc)
		for token: String in ["ROTATION.md", "PREFERENCES.md", "HISTORY.md", "TUNING.md"]:
			check(not FileAccess.get_file_as_string(path).contains("`" + token + "`"),
				"%s does not name a removed root path" % relative)
	var docs := [
		["docs/eligibility.md", "eligibility.gd", "tests/eligibility/"],
		["docs/scene_gate.md", "scene_gate.gd", "tests/scene_gate/"],
		["docs/scene_hold.md", "scene_hold.gd", "tests/scene_hold/"],
		["docs/rest.md", "rest_rejoin.gd", "tests/rest/"],
		["docs/hands.md", "hand_control.gd", "tests/hands/"],
		["docs/anatomy.md", "anatomy.gd", "tests/anatomy/"],
		["docs/vr.md", "vr_act.gd", "tests/test_vr_act.gd"],
		["docs/initiation.md", "initiation.gd", "tests/initiation/"],
		["docs/memory.md", "memory.gd", "tests/memory/"],
		["docs/lines.md", "act_lines.gd", "tests/act_lines/"],
		["docs/readiness.md", "readiness.gd", "tests/readiness/"],
		["docs/preferences.md", "preferences.gd", "tests/readiness/"],
		["docs/poses.md", "poses/session.gd", "tests/poses/"],
		["docs/camera.md", "act_camera.gd", "tests/act_camera/"],
		["docs/kiss.md", "kiss_control.gd", "tests/act_camera/"],
		["docs/history.md", "history.gd", "tests/history/"],
		["docs/afterglow.md", "afterglow.gd", "tests/afterglow/"],
		["docs/face.md", "face_session.gd", "tests/face/"],
		["docs/reactions.md", "act_reactions.gd", "tests/reactions/"],
		["docs/stool.md", "stool.gd", "tests/stool/"],
		["docs/audio.md", "act_audio.gd", "tests/act_audio/"],
		["docs/hud.md", "hud.gd", "tests/hud/"],
		["docs/settings.md", "settings.gd", "tests/test_settings.gd"],
		["docs/bond.md", "sex_bond.gd", "tests/bond/"],
		["docs/act_facts.md", "act_facts.gd", "tests/act_facts/"],
		["docs/perf.md", "perf.gd", "tests/perf/"],
		["docs/debug.md", "debug_actions.gd", "tests/"],
	]
	for row: Array in docs:
		var doc := str(row[0])
		var facade := str(row[1])
		var tests := str(row[2])
		var text := FileAccess.get_file_as_string(ROOT.path_join(doc))
		check(not text.is_empty(), "%s exists" % doc)
		check(text.contains(facade), "%s names %s" % [doc, facade])
		check(text.contains(tests), "%s names %s" % [doc, tests])
		check(text.contains("## Ownership") or text.contains("## Scope"),
			"%s has an ownership section" % doc)
		check(text.contains("## Tests"), "%s has a tests section" % doc)


func _check_eligibility_docs() -> void:
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/eligibility.md"))
	check(not contract.is_empty(), "docs/eligibility.md exists")
	for heading: String in ["## Data ownership", "## Public API", "## Modes and truth table",
			"## Tests"]:
		check(contract.contains(heading), "docs/eligibility.md has %s" % heading)
	for name: String in ["AGENTS.md", "docs/README.md", "README.md"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		check(text.contains("docs/eligibility.md"), "%s links to docs/eligibility.md" % name)


## The pure anatomy core is scene-free, and the system internals never preload the two hosts.
## The facade is the only file another system should call.
func _check_anatomy_isolation(files: Array[String]) -> void:
	var pure_files := [
		"anatomy/identity.gd", "anatomy/geometry.gd", "anatomy/act/state.gd",
		"anatomy/facts.gd",
	]
	for name: String in pure_files:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		for token: String in ["extends Node", "get_tree(", "Time.", "FileAccess", "SETTINGS",
				"preload(\"res://world/", "preload(\"res://mods/unfplap/runtime.gd\")",
				"preload(\"res://mods/unfplap/main.gd\")"]:
			check(not text.contains(token), "%s stays pure: %s" % [name, token])
	var act := FileAccess.get_file_as_string(ROOT.path_join("anatomy/act.gd"))
	check(not act.contains("runtime.get("), "the anatomy act does not read runtime fields")
	check(not act.contains("runtime.call(\"_"), "the anatomy act does not call runtime private helpers")
	var bridge := FileAccess.get_file_as_string(ROOT.path_join("anatomy/act_bridge.gd"))
	check(bridge.contains("func bind(host_in: Dictionary)") and bridge.contains("func context("),
		"the anatomy bridge takes a host dictionary and owns the typed context")
	for token: String in ["extends Node", "FileAccess",
			"preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")"]:
		check(not bridge.contains(token), "the anatomy bridge has no host reach-in: %s" % token)
	var runtime_text := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	for token: String in ["anatomy/controller.gd", "anatomy/act.gd", "anatomy/player.gd",
			"anatomy/act_bridge.gd"]:
		check(not runtime_text.contains(token), "runtime does not preload anatomy internals: %s" % token)
	check(not runtime_text.contains("_anatomy.call(\"_"),
		"runtime does not call anatomy private helpers")
	var main_text := FileAccess.get_file_as_string(ROOT.path_join("main.gd"))
	for token: String in ["var anon_part", "var tail_seat"]:
		check(not main_text.contains(token), "main does not hold the anatomy node: %s" % token)
	check(not main_text.contains("anatomy.call(\"_"),
		"main does not call anatomy private helpers")
	for path: String in files:
		if not path.ends_with(".gd") or path.begins_with(ROOT.path_join("tests/")):
			continue
		var relative := path.trim_prefix(ROOT.path_join(""))
		if not relative.begins_with("anatomy/") or relative == "anatomy.gd":
			continue
		var text := FileAccess.get_file_as_string(path)
		for token: String in ["preload(\"res://mods/unfplap/runtime.gd\")",
				"preload(\"res://mods/unfplap/main.gd\")",
				"runtime.get(", "runtime.call(\"", "main.get(", "main.call(\""]:
			check(not text.contains(token), "%s does not read the host: %s" % [relative, token])


## The anatomy contract owns the anatomy and tail-seating rules. It is one file; AGENTS and the
## settings/pose docs link to it instead of restating them.
func _check_anatomy_docs() -> void:
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/anatomy.md"))
	check(not contract.is_empty(), "docs/anatomy.md exists")
	for heading: String in ["## Scope", "## Architecture", "## Controls", "## Act anatomy",
			"## Act bridge", "## Tail seating", "## Tests", "## Migration target"]:
		check(contract.contains(heading), "docs/anatomy.md has %s" % heading)
	for name: String in ["AGENTS.md", "README.md", "docs/README.md"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		check(text.contains("docs/anatomy.md"), "%s links to docs/anatomy.md" % name)
	check(FileAccess.file_exists(ROOT.path_join("tests/anatomy/test_act_bridge.gd")),
		"tests/anatomy/test_act_bridge.gd exists")


## The stool system is self-contained: only its facade may be preloaded outside `stool/`, and the
## pure measurement/item files stay scene-free.
func _check_stool_isolation(files: Array[String]) -> void:
	for name: String in ["stool/measure.gd", "stool/item.gd"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		for token: String in ["extends Node", "get_tree(", "Time.", "FileAccess", "SETTINGS",
				"preload(\"res://world/", "preload(\"res://mods/unfplap/runtime.gd\")",
				"preload(\"res://mods/unfplap/main.gd\")"]:
			check(not text.contains(token), "%s stays pure: %s" % [name, token])
	for path: String in files:
		if not path.ends_with(".gd") or path.begins_with(ROOT.path_join("tests/")):
			continue
		var relative := path.trim_prefix(ROOT.path_join(""))
		if relative == "stool.gd" or relative.begins_with("stool/"):
			continue
		var text := FileAccess.get_file_as_string(path)
		check(not text.contains("mods/unfplap/stool/"),
			"%s uses the stool facade only" % relative)


func _check_stool_docs() -> void:
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/stool.md"))
	check(not contract.is_empty(), "docs/stool.md exists")
	for heading: String in ["## Scope", "## Architecture", "## Internal API", "## Rule",
			"## Gate and hint", "## Act flow", "## Supply", "## Settings and debug",
			"## Tests and limits"]:
		check(contract.contains(heading), "docs/stool.md has %s" % heading)
	for name: String in ["AGENTS.md", "README.md", "docs/README.md"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		check(text.contains("docs/stool.md"), "%s links to docs/stool.md" % name)
	var act := FileAccess.get_file_as_string(ROOT.path_join("stool/act.gd"))
	check(act.contains("func take_items(") and act.contains("func place("),
		"the per-act footstool handle is present")
	var facade := FileAccess.get_file_as_string(ROOT.path_join("stool.gd"))
	check(facade.contains("func new_act()"), "the stool facade creates the per-act handle")
	check(FileAccess.file_exists(ROOT.path_join("tests/stool/test_act.gd")),
		"tests/stool/test_act.gd exists")
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	for token: String in ["_stool_active", "_stool_tokens", "_stool_slots", "_stool_node",
			"_stool_height_m", "_stool_floor_y", "_stool_lifted", "_inventory_store"]:
		check(not runtime.contains(token), "runtime has no footstool internals: %s" % token)


## The request rules and wording are pure, and the director, classifier, navigator and bed-rest
## internals live only in the two scene adapters.
func _check_initiation_isolation(files: Array[String]) -> void:
	var pure_files := [
		"initiation/consent.gd", "initiation/facts.gd", "initiation/policy.gd",
		"initiation/prompts.gd",
	]
	for name: String in pure_files:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		for token: String in ["extends Node", "get_tree(", "Time.", "FileAccess", "SETTINGS",
				"preload(\"res://world/", "preload(\"res://mods/unfplap/settings.gd\")"]:
			check(not text.contains(token), "%s stays pure: %s" % [name, token])
	# No outside file reaches into the service; the service never reaches into a host's private
	# members (the game privates live only in the two adapters).
	for path: String in files:
		if not path.ends_with(".gd") or path.begins_with(ROOT.path_join("tests/")):
			continue
		var relative := path.trim_prefix(ROOT.path_join(""))
		var text := FileAccess.get_file_as_string(path)
		if relative == "initiation.gd" or relative.begins_with("initiation/"):
			for token: String in ["runtime.call(\"_", "main.call(\"_", "main.get(\"_",
					"_cuddle_active"]:
				check(not text.contains(token), "%s keeps host privates out: %s" % [relative, token])
		else:
			for token: String in ["initiation.call(\"_", "initiation._", "initiation.get(\"_"]:
				check(not text.contains(token),
					"%s does not touch the request internals: %s" % [relative, token])
	var facade := FileAccess.get_file_as_string(ROOT.path_join("initiation.gd"))
	for token: String in [".get(\"_player_text\")", ".get(\"_held_text\")",
			".get(\"_has_target\")", "\"_front_for\"", ".get(\"_mare_fits\")",
			".get(\"_guest\")", ".get(\"_sleeper\")", "get_first_node_in_group",
			"main.get(\"classifier\")"]:
		check(not facade.contains(token), "the initiation facade keeps %s behind an adapter" % token)
	for name: String in ["initiation/conversation.gd", "initiation/venue.gd"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		for token: String in ["preload(\"res://mods/unfplap/runtime.gd\")",
				"preload(\"res://mods/unfplap/main.gd\")"]:
			check(not text.contains(token), "%s does not preload the hosts: %s" % [name, token])
	for path: String in files:
		if not path.ends_with(".gd") or path.begins_with(ROOT.path_join("tests/")):
			continue
		var relative := path.trim_prefix(ROOT.path_join(""))
		if relative == "initiation.gd" or relative.begins_with("initiation/"):
			continue
		var text := FileAccess.get_file_as_string(path)
		check(not text.contains("mods/unfplap/initiation/"),
			"%s uses the initiation facade only" % relative)


func _check_initiation_docs() -> void:
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/initiation.md"))
	check(not contract.is_empty(), "docs/initiation.md exists")
	for heading: String in ["## Scope", "## Architecture", "## Internal API", "## Data ownership",
			"## Episode", "## Admission", "## Candidates", "## Privacy", "## Ask", "## Consent",
			"## Presentation and invite", "## Cancellation", "## Prompts", "## Debug and lab",
			"## Tests", "## Known limits"]:
		check(contract.contains(heading), "docs/initiation.md has %s" % heading)
	for name: String in ["AGENTS.md", "docs/eligibility.md"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		check(text.contains("docs/initiation.md"), "%s links to docs/initiation.md" % name)


## The memory wording and facts are pure, the adapters own every stock read, and the facade keeps
## the director, store and world details behind them. The docs contract lives in one file.
func _check_memory_isolation(files: Array[String]) -> void:
	for name: String in ["memory/text.gd", "memory/facts.gd"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		for token: String in ["extends Node", "get_tree(", "Time.", "FileAccess", "SETTINGS",
				"preload(\"res://world/", "preload(\"res://mods/unfplap/settings.gd\")"]:
			check(not text.contains(token), "%s stays pure: %s" % [name, token])
	for path: String in files:
		if not path.ends_with(".gd") or path.begins_with(ROOT.path_join("tests/")):
			continue
		var relative := path.trim_prefix(ROOT.path_join(""))
		if relative == "memory.gd" or relative.begins_with("memory/"):
			continue
		var text := FileAccess.get_file_as_string(path)
		check(not text.contains("mods/unfplap/memory/"),
			"%s uses the memory facade only" % relative)
	var facade := FileAccess.get_file_as_string(ROOT.path_join("memory.gd"))
	for token: String in ["_authored_lines", "_authored_active", "peak_memories", "save_changed"]:
		check(not facade.contains(token),
			"the memory facade keeps %s behind an adapter" % token)
	var runtime := FileAccess.get_file_as_string(ROOT.path_join("runtime.gd"))
	check(not runtime.contains("witness.gd"), "runtime does not preload the witness wrapper")
	for token: String in ["commit_act", "refusal_event", "stay_close_reward", "cancel_event",
			"climax_event", "stop_event", "history_apology", "reaction_for", "utterance_for",
			"bystander_line", "perceived_adults", "mod_key", "keep_active_line",
			"cancel_act_lines", "peak_memory", "record_peak_memory", "witness_kind",
			"witness_text", "witness_scene_prefix", "witness_thought", "witness_impression"]:
		check(not runtime.contains("MEMORY." + token),
			"runtime uses the memory facade, not MEMORY.%s" % token)


func _check_memory_docs() -> void:
	var contract := FileAccess.get_file_as_string(ROOT.path_join("docs/memory.md"))
	check(not contract.is_empty(), "docs/memory.md exists")
	for heading: String in ["## Scope", "## Architecture", "## Internal API", "## Data ownership",
			"## Impressions and events", "## Witness pass", "## Line channel",
			"## Cue facts and shared memory", "## Tests", "## Known limits"]:
		check(contract.contains(heading), "docs/memory.md has %s" % heading)
	for name: String in ["AGENTS.md", "docs/history.md", "docs/initiation.md"]:
		var text := FileAccess.get_file_as_string(ROOT.path_join(name))
		check(text.contains("docs/memory.md"), "%s links to docs/memory.md" % name)


func _func_body(text: String, name: String) -> String:
	var needle := "func " + name + "("
	var start := text.find(needle)
	if start < 0:
		return ""
	var next := text.find("\nfunc ", start + needle.length())
	if next < 0:
		next = text.length()
	return text.substr(start, next - start)


func _count(text: String, needle: String) -> int:
	var total := 0
	var at := text.find(needle)
	while at >= 0:
		total += 1
		at = text.find(needle, at + needle.length())
	return total


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file: String in dir.get_files():
		if file.ends_with(".gd") or file.ends_with(".md") or file.ends_with(".json"):
			out.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)


func _check_preloads(files: Array[String]) -> void:
	var seen := {}
	for path: String in files:
		if not path.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string(path)
		var regex := RegEx.new()
		regex.compile("res://mods/unfplap/[A-Za-z0-9_./-]+\\.(gdshaderinc|gdshader|gd|json|md)")
		for match: RegExMatch in regex.search_all(text):
			var target := match.get_string()
			if seen.has(target):
				continue
			seen[target] = true
			check(FileAccess.file_exists(target), "resolved preload %s" % target)
