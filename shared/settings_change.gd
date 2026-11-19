extends RefCounted
## The settings change notification: one static listener list, because GDScript has no static
## signals. `settings/service.gd` notifies it through `apply_live()` after an edit; every
## subscriber re-reads what it caches. Order is registration order, and a listener whose object
## has been freed is dropped on the next notify instead of being called.
##
##   const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
##   CHANGE.on_changed(Callable(self, "apply_settings"))    # construction
##   CHANGE.off_changed(Callable(self, "apply_settings"))   # shutdown
##
## The list lives here rather than on `settings/service.gd` because a shared module may not
## import a service and the log sink joins the same list. See docs/settings.md.

static var _listeners: Array[Callable] = []


## Join the notification. The same callable registered twice keeps one place.
static func on_changed(cb: Callable) -> void:
	if not cb.is_valid() or _listeners.has(cb):
		return
	_listeners.append(cb)


## Leave the notification. A callable that is not registered is ignored.
static func off_changed(cb: Callable) -> void:
	_listeners.erase(cb)


## Every live listener once, in registration order. A listener that leaves during the pass is not
## called, and a freed object's callable is dropped from the list.
static func notify() -> void:
	var live: Array[Callable] = []
	for cb: Callable in _listeners:
		if cb.is_valid():
			live.append(cb)
	_listeners = live
	for cb: Callable in _listeners.duplicate():
		if cb.is_valid() and _listeners.has(cb):
			cb.call()


## How many listeners the list holds, a released one included until the next notify.
static func listener_count() -> int:
	return _listeners.size()
