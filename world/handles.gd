extends RefCounted
## The World services the Pony scope reads, as one fixed typed record.

const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/api.gd")
const ACT_GATE := preload("res://mods/unfplap/act_gate/api.gd")
const BODY_CHANGE_SERVICE := preload("res://mods/unfplap/body_change/api.gd")
const ESTRUS := preload("res://mods/unfplap/estrus/api.gd")
const OFFER := preload("res://mods/unfplap/offer/api.gd")
const STOCK_SMACK := preload("res://mods/unfplap/stock_smack/api.gd")
const STOOL := preload("res://mods/unfplap/stool/api.gd")
const AUDIO := preload("res://mods/unfplap/audio/api.gd")
const ACT_OWNER := preload("res://mods/unfplap/act_owner/api.gd")
const HUD := preload("res://mods/unfplap/hud/api.gd")
const MEMORY := preload("res://mods/unfplap/memory/api.gd")
const PONIES := preload("res://mods/unfplap/ponies/api.gd")


var anatomy: ANATOMY = null
var eligibility: ELIGIBILITY = null
var act_gate: ACT_GATE = null
var body_change: BODY_CHANGE_SERVICE = null
var estrus: ESTRUS = null
var offer: OFFER = null
var stock_smack: STOCK_SMACK = null
var hud: HUD = null
var memory: MEMORY = null
var stool: STOOL = null
var audio: AUDIO = null
## The act frame every act module reads; a bare record leaves it null.
var act_owner: ACT_OWNER = null
var ponies: PONIES = null
