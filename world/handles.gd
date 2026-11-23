extends RefCounted
## The World services the Pony scope reads, as one fixed typed record.

const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const ACT_GATE := preload("res://mods/unfplap/act_gate/service.gd")
const BODY_CHANGE_SERVICE := preload("res://mods/unfplap/body_change/service.gd")
const ESTRUS := preload("res://mods/unfplap/estrus/service.gd")
const OFFER := preload("res://mods/unfplap/offer/service.gd")
const STOCK_SMACK := preload("res://mods/unfplap/stock_smack/api.gd")
const INTEGRATIONS := preload("res://mods/unfplap/integrations/service.gd")
const STOOL := preload("res://mods/unfplap/stool/service.gd")
const AUDIO := preload("res://mods/unfplap/audio/api.gd")


var anatomy: ANATOMY = null
var eligibility: ELIGIBILITY = null
var act_gate: ACT_GATE = null
var body_change: BODY_CHANGE_SERVICE = null
var estrus: ESTRUS = null
var offer: OFFER = null
var stock_smack: STOCK_SMACK = null
var integrations: INTEGRATIONS = null
## The cross-mod API node; its facade is an orchestrator, which a service-owned file may not preload.
var api: Node = null
var hud: Node = null
var memory: Node = null
var stool: STOOL = null
var audio: AUDIO = null
