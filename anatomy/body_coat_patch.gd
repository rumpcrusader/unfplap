extends RefCounted
## Runtime shader patch for the rig coat (MareBody) and its outline hull. The game body uses
## addons/cel-shader/cel-shader-base.gdshader and the hull uses cel-outline-lit or
## outline-tinted; all three already include flank_jiggle.gdshaderinc and call
## `VERTEX += flank_jiggle(VERTEX);`. We duplicate the Shader resource and swap those two
## strings for the mod's extended include and deform call. No game source file is edited and no
## full shader is copied into the mod.
##
## `patched()` caches one Shader per source shader. A game update that changes either hook makes
## it return null, which the caller treats as "leave the original shader alone".

const GAME_INCLUDE := "res://world/characters/hybrid_mare/flank_jiggle.gdshaderinc"
const MOD_INCLUDE := "res://mods/unfplap/anatomy/body_coat_deform.gdshaderinc"
const GAME_CALL := "VERTEX += flank_jiggle(VERTEX);"
const PATCHED_CALL := "VERTEX += body_coat_deform(VERTEX);"

static var _cache: Dictionary = {}

static func patched(source: Shader) -> Shader:
	if source == null:
		return null
	var key := source.get_instance_id()
	if _cache.has(key):
		return _cache[key] as Shader
	var code: String = source.code
	if not code.contains(GAME_INCLUDE) or not code.contains(GAME_CALL):
		_cache[key] = null
		if not source.resource_path.is_empty():
			push_warning("[unfplap] body coat patch skipped: unexpected shader %s"
				% source.resource_path)
		return null
	# Keep the game include and add the mod file after it. Nesting `#include` inside the mod
	# include is not reliable here: Godot's preprocessor tokenised the nested directive.
	var includes := GAME_INCLUDE + "\"\n#include \"" + MOD_INCLUDE
	var patched_code := code.replace(GAME_INCLUDE, includes).replace(GAME_CALL, PATCHED_CALL)
	# The duplicate Shader has no resource_path, so the cel shader's relative includes must
	# become absolute or they resolve against the wrong directory.
	patched_code = patched_code.replace("#include \"includes/",
		"#include \"res://addons/cel-shader/includes/")
	var shader := Shader.new()
	shader.code = patched_code
	_cache[key] = shader
	return shader
