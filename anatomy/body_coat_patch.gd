extends RefCounted
## Runtime shader patch for the rig coat (MareBody) and its outline hull. The game body uses
## addons/cel-shader/cel-shader-base.gdshader and the hull uses cel-outline-lit or
## outline-tinted; all three already include flank_jiggle.gdshaderinc and call
## `VERTEX += flank_jiggle(VERTEX);`. The cel cutout and occlusion variants use the base include
## without that hook, so the patch injects the include and call into their duplicate. We duplicate
## the Shader resource and swap those strings for the mod's extended include and deform call, then
## add the vulva coat cut to the fragment. No game source file is edited and no full shader is
## copied into the mod.
##
## The merged near pony uses near_pony, near_pony_occlusion and near_pony_outline. Their
## jiggle call is multiplied by `jiggle_entry[pal]`; the patch keeps the rig body entries and
## leaves every other palette entry on the stock path. `patched()` caches one Shader per source
## shader. A game update that changes a required hook makes it return null, which the caller
## treats as "leave the original shader alone". A missing `void fragment()` keeps the deform and
## only drops the cut.

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
		# The cel cutout and occlusion variants use the same base include but omit the game's
		# flank_jiggle hook. Add the hook in the duplicate, then run the same deform/cut patch.
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
			push_warning("[unfplap] body coat patch skipped: unexpected shader %s"
				% source.resource_path)
		return null
	if near and not code.contains("const int ENTRIES"):
		_cache[key] = null
		return null
	# Keep the game include and add the mod file after it. Nesting `#include` inside the mod
	# include is not reliable here: Godot's preprocessor tokenised the nested directive.
	var includes := GAME_INCLUDE_LINE + "\n#include \"" + MOD_INCLUDE + "\""
	if near:
		includes += "\n" + NEAR_ENTRY_UNIFORM
	var call := PATCHED_NEAR_CALL if near else PATCHED_CALL
	var patched_code := code.replace(GAME_INCLUDE_LINE, includes)
	patched_code = patched_code.replace(NEAR_CALL if near else GAME_CALL, call)
	if patched_code.contains(FRAGMENT_HOOK):
		patched_code = patched_code.replace(FRAGMENT_HOOK,
			PATCHED_NEAR_FRAGMENT if near else PATCHED_FRAGMENT)
	# The duplicate Shader has no resource_path, so the cel shader's relative includes must
	# become absolute or they resolve against the wrong directory.
	patched_code = patched_code.replace("#include \"includes/",
		"#include \"res://addons/cel-shader/includes/")
	var shader := Shader.new()
	shader.code = patched_code
	_cache[key] = shader
	return shader
