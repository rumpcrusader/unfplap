extends SceneTree
## The settings change notification: registration order, one place per callable, a released
## listener skipped on the next pass, and an explicit leave at construction, on shutdown, or during
## a pass. `tests/test_settings.gd` holds the API shape; this suite holds the ordering rule.
##
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_settings_change.gd

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")

var failures := 0
var checks := 0
## The order the listeners were called in, shared by every listener of one check.
var order: Array[String] = []


## One subscriber. It records its call and can leave another listener during the same pass.
class Listener extends RefCounted:
	var name := ""
	var leave := Callable()
	var _record: Array[String]

	func _init(record: Array[String], label: String) -> void:
		_record = record
		name = label

	func changed() -> void:
		_record.append(name)
		if leave.is_valid():
			leave.call()


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var base := CHANGE.listener_count()
	_check_order(base)
	_check_repeat(base)
	_check_release(base)
	_check_leave_during_pass(base)
	check(CHANGE.listener_count() == base, "every listener of this suite left the list")
	print("SETTINGS_CHANGE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("SETTINGS_CHANGE_PASS")
	quit(0 if failures == 0 else 1)


## The pass runs in registration order, so the subscribers land in the same order as the service
## list that registered them.
func _check_order(base: int) -> void:
	order.clear()
	var first := Listener.new(order, "first")
	var second := Listener.new(order, "second")
	var third := Listener.new(order, "third")
	for listener: Listener in [first, second, third]:
		CHANGE.on_changed(Callable(listener, "changed"))
	check(CHANGE.listener_count() == base + 3, "three listeners registered")
	SETTINGS.apply_live()
	check(order == ["first", "second", "third"], "apply_live() notifies in registration order")
	# A listener that leaves keeps its place free for the next pass, not for this one.
	order.clear()
	CHANGE.off_changed(Callable(second, "changed"))
	check(CHANGE.listener_count() == base + 2, "leaving drops the place")
	SETTINGS.apply_live()
	check(order == ["first", "third"], "a listener that left is not called")
	for listener: Listener in [first, third]:
		CHANGE.off_changed(Callable(listener, "changed"))


## A service subscribes once at construction even if the entry is rebuilt: the same callable keeps
## one place, and an empty callable is ignored in both directions.
func _check_repeat(base: int) -> void:
	order.clear()
	var listener := Listener.new(order, "once")
	var call := Callable(listener, "changed")
	CHANGE.on_changed(call)
	CHANGE.on_changed(call)
	check(CHANGE.listener_count() == base + 1, "the same callable registers once")
	SETTINGS.apply_live()
	check(order == ["once"], "a twice-registered listener is called once")
	CHANGE.on_changed(Callable())
	CHANGE.off_changed(Callable())
	check(CHANGE.listener_count() == base + 1, "an empty callable is ignored")
	CHANGE.off_changed(call)
	check(CHANGE.listener_count() == base, "off_changed removes the place")


## A service that is freed without leaving is skipped and dropped: the freed node's callable is
## never called.
func _check_release(base: int) -> void:
	order.clear()
	var gone := Listener.new(order, "gone")
	var live := Listener.new(order, "live")
	var gone_call := Callable(gone, "changed")
	CHANGE.on_changed(gone_call)
	CHANGE.on_changed(Callable(live, "changed"))
	gone = null
	check(not gone_call.is_valid(), "the freed listener's callable is no longer valid")
	SETTINGS.apply_live()
	check(order == ["live"], "a released listener is skipped")
	check(CHANGE.listener_count() == base + 1, "a released listener is dropped on the next pass")
	CHANGE.off_changed(Callable(live, "changed"))


## A listener that leaves another one mid-pass is not called in that same pass.
func _check_leave_during_pass(base: int) -> void:
	order.clear()
	var first := Listener.new(order, "first")
	var second := Listener.new(order, "second")
	var late := Listener.new(order, "late")
	var late_call := Callable(late, "changed")
	CHANGE.on_changed(Callable(first, "changed"))
	CHANGE.on_changed(Callable(second, "changed"))
	CHANGE.on_changed(late_call)
	first.leave = func() -> void: CHANGE.off_changed(late_call)
	SETTINGS.apply_live()
	check(order == ["first", "second"], "a listener that leaves during the pass is not called")
	check(CHANGE.listener_count() == base + 2, "the mid-pass leave is kept")
	first.leave = Callable()
	CHANGE.off_changed(Callable(first, "changed"))
	CHANGE.off_changed(Callable(second, "changed"))
