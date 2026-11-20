extends RefCounted
## The pose base verdict the start log, the settled line and the debug rows all share.
## Contract: `docs/poses.md`.

const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")

var base := "none"
var reason := ""
var version := 0
var bones := 0
var available := false
var error := ""
## The live pose frame, or null when the pose owns none.
var frame := Transform3D(Basis.IDENTITY, Vector3.INF)
var frame_kind := ""
var shots := false
var asset: AUTHORED = null
var asset_path := ""
var live_path := ""
var target_path := ""
var asset_frame := ""
var variant := ""
