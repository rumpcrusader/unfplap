extends RefCounted
## Runtime shader patch for the rig coat and its outline hull: duplicate the game Shader,
## swap the jiggle include and call for the mod's deform, and add the vulva cut. No game file
## is edited and no full shader is copied.
## The cel cutout/occlusion variants have no hook, so the patch injects one; a game update
## that breaks a hook yields null and the caller keeps the original shader.

const LOG := preload("res://mods/unfplap/shared/log.gd")

const GAME_INCLUDE := "res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc"
const GAME_INCLUDE_LINE := "#include \"" + GAME_INCLUDE + "\""
const MOD_INCLUDE := "res://mods/unfplap/anatomy/body_coat_deform.gdshaderinc"
const BASE_INCLUDE_LINE := "#include \"includes/base-cel-shader.gdshaderinc\""
const VERTEX_HOOK := "void vertex() {"
const GAME_CALL := "VERTEX += flank_jiggle(VERTEX);"
const NEAR_CALL := "VERTEX += flank_jiggle(VERTEX) * jiggle_entry[pal];"
const PATCHED_CALL := "body_coat_vertex = (body_coat_anatomy_inverse * vec4(VERTEX, 1.0)).xyz;\n\tVERTEX += body_coat_deform(VERTEX);"
const PATCHED_NEAR_CALL := "vec3 body_coat_posed = VERTEX;\n\tbody_coat_vertex = (body_coat_anatomy_inverse * vec4(body_coat_posed, 1.0)).xyz;\n\tVERTEX += mix(flank_jiggle(body_coat_posed) * jiggle_entry[pal], body_coat_deform(body_coat_posed), body_coat_entry[pal]);"
const FRAGMENT_HOOK := "void fragment() {"
const PATCHED_FRAGMENT := "void fragment() {\n\tif (body_coat_vulva_cut(body_coat_vertex)) { discard; }"
const PATCHED_NEAR_FRAGMENT := "void fragment() {\n\tif (body_coat_entry[pal] > 0.5 && body_coat_vulva_cut(body_coat_vertex)) { discard; }"
const NEAR_ENTRY_UNIFORM := "uniform float body_coat_entry[ENTRIES];"

static var _cache: Dictionary = {}

static func patched(source: Shader) -> Shader:
	if source == null:
		return null
	var key := source.get_instance_id()
	if _cache.has(key):
		return _cache[key] as Shader
	var code: String = source.code
	var game_hook := code.contains(GAME_INCLUDE_LINE)
	if not game_hook:
		# The variants omit the jiggle hook, so inject it before running the same deform/cut patch.
		if not code.contains(BASE_INCLUDE_LINE) or not code.contains(VERTEX_HOOK) \
				or not code.contains(FRAGMENT_HOOK):
			_cache[key] = null
			return null
		var injected := BASE_INCLUDE_LINE + "\n" + GAME_INCLUDE_LINE \
			+ "\n#include \"" + MOD_INCLUDE + "\""
		var injected_code := code.replace(BASE_INCLUDE_LINE, injected)
		injected_code = injected_code.replace(VERTEX_HOOK,
			VERTEX_HOOK + "\n\t" + PATCHED_CALL)
		injected_code = injected_code.replace(FRAGMENT_HOOK, PATCHED_FRAGMENT)
		injected_code = injected_code.replace("#include \"includes/",
			"#include \"res://addons/cel-shader/includes/")
		var injected_shader := Shader.new()
		injected_shader.code = injected_code
		_cache[key] = injected_shader
		return injected_shader
	var near := code.contains(NEAR_CALL)
	if not near and not code.contains(GAME_CALL):
		_cache[key] = null
		if not source.resource_path.is_empty():
			LOG.warning("body coat patch skipped: unexpected shader %s",
				[source.resource_path])
		return null
	if near and not code.contains("const int ENTRIES"):
		_cache[key] = null
		return null
	# The mod include follows the game one: Godot's preprocessor tokenised a nested `#include`
	# directive, so the mod file cannot include it itself.
	var includes := GAME_INCLUDE_LINE + "\n#include \"" + MOD_INCLUDE + "\""
	if near:
		includes += "\n" + NEAR_ENTRY_UNIFORM
	var call := PATCHED_NEAR_CALL if near else PATCHED_CALL
	var patched_code := code.replace(GAME_INCLUDE_LINE, includes)
	patched_code = patched_code.replace(NEAR_CALL if near else GAME_CALL, call)
	if patched_code.contains(FRAGMENT_HOOK):
		patched_code = patched_code.replace(FRAGMENT_HOOK,
			PATCHED_NEAR_FRAGMENT if near else PATCHED_FRAGMENT)
	# A duplicated Shader has no resource_path, so relative includes resolve against the wrong
	# directory and must become absolute.
	patched_code = patched_code.replace("#include \"includes/",
		"#include \"res://addons/cel-shader/includes/")
	var shader := Shader.new()
	shader.code = patched_code
	_cache[key] = shader
	return shader
