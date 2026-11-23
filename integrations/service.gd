extends "res://mods/unfplap/shared/service.gd"
## Service: integrations
## Scope: world
## Contract: docs/integrations.md
## The optional pack integrations: the two pack modules and the act-start undress hook.

const PANTYHOSE := preload("res://mods/unfplap/integrations/pantyhose.gd")
const CHANGELINGS := preload("res://mods/unfplap/integrations/changelings.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const BODY_CHANGE_SERVICE := preload("res://mods/unfplap/body_change/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")

var _anatomy: ANATOMY = null
var _body_change: BODY_CHANGE_SERVICE = null
var _ponies: PONIES = null
var _eligibility: ELIGIBILITY = null
var _api: Node = null
var _pantyhose: PANTYHOSE = null
var _changelings: CHANGELINGS = null


## Takes the peers the two pack modules read; the composition root is the only caller.
func wire(anatomy: ANATOMY, body_change: BODY_CHANGE_SERVICE, ponies: PONIES,
		eligibility: ELIGIBILITY, api: Node) -> void:
	_anatomy = anatomy
	_body_change = body_change
	_ponies = ponies
	_eligibility = eligibility
	_api = api
	_pantyhose = PANTYHOSE.new()
	_pantyhose.name = "UnfplapPantyhose"
	_pantyhose.wire(_anatomy)
	_changelings = CHANGELINGS.new()
	_changelings.name = "UnfplapChangelings"
	_changelings.wire(_ponies, _eligibility, _body_change, _api)


## A module built in `wire()` attaches here, wired, at the service's own attach.
func _ready() -> void:
	if is_instance_valid(_pantyhose):
		add_child(_pantyhose)
	if is_instance_valid(_changelings):
		add_child(_changelings)
	if is_instance_valid(_body_change) and is_instance_valid(_changelings):
		_body_change.register_source(_changelings)


## The garment module the body-change service binds; null before `wire()`.
func pantyhose() -> PANTYHOSE:
	return _pantyhose


## The body-change provider the service registers; null before `wire()`.
func changelings() -> CHANGELINGS:
	return _changelings


## The runtime's act start, forwarded to the module that acts on it.
func act_started(pony: Node3D) -> void:
	if is_instance_valid(_pantyhose):
		_pantyhose.act_started(pony)


func on_world(host: Node) -> void:
	if is_instance_valid(_pantyhose):
		_pantyhose.on_world(host)
	if is_instance_valid(_changelings):
		_changelings.on_world(host)


func on_world_closed() -> void:
	if is_instance_valid(_pantyhose):
		_pantyhose.on_world_closed()
	if is_instance_valid(_changelings):
		_changelings.on_world_closed()


func on_player(body: Node) -> void:
	if is_instance_valid(_pantyhose):
		_pantyhose.on_player(body)
	if is_instance_valid(_changelings):
		_changelings.on_player(body)


## The entry's teardown: the modules go in the reverse of their attach order.
func shutdown() -> void:
	if is_instance_valid(_changelings):
		_changelings.shutdown()
	if is_instance_valid(_pantyhose):
		_pantyhose.shutdown()
	_anatomy = null
	_body_change = null
	_ponies = null
	_eligibility = null
	_api = null
