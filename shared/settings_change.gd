extends RefCounted
## The settings change notification: one static listener list, because GDScript has no static
## signals. The settings module notifies it after an edit and every subscriber re-reads what it
## caches. Order is registration order, and a freed listener is dropped on the next notify.
##
## It sits here because shared modules cannot import services, and the log sink subscribes too.

static var _listeners: Array[Callable] = []


## Join the notification; a repeated callable still counts once.
static func on_changed(cb: Callable) -> void:
	if not cb.is_valid() or _listeners.has(cb):
		return
	_listeners.append(cb)


## Leave the notification. A callable that is not registered is ignored.
static func off_changed(cb: Callable) -> void:
	_listeners.erase(cb)


## Every live listener, in registration order. Leaving mid-pass means not being called; a freed
## object's callable is dropped.
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
