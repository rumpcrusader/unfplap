extends RefCounted
## The settings change notification: two static listener lists, because GDScript has no static
## signals. The mod channel re-reads a cache after an edit; the game channel carries the game's own
## setting key. Order is registration order, and a freed listener is dropped on the next notify.
##
## It sits here because shared modules cannot import services, and the log sink subscribes too.

static var _listeners: Array[Callable] = []
static var _game_listeners: Array[Callable] = []


## Join the mod-settings notification; a repeated callable still counts once.
static func on_changed(cb: Callable) -> void:
	if not cb.is_valid() or _listeners.has(cb):
		return
	_listeners.append(cb)


## Leave the mod-settings notification. A callable that is not registered is ignored.
static func off_changed(cb: Callable) -> void:
	_listeners.erase(cb)


## Every live mod listener, in registration order. Leaving mid-pass means not being called; a freed
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


## Join the game-setting notification; a repeated callable still counts once.
static func on_game_changed(cb: Callable) -> void:
	if not cb.is_valid() or _game_listeners.has(cb):
		return
	_game_listeners.append(cb)


## Leave the game-setting notification. A callable that is not registered is ignored.
static func off_game_changed(cb: Callable) -> void:
	_game_listeners.erase(cb)


## Call every live game listener with the key the game changed, in registration order.
static func notify_game(key: String) -> void:
	var live: Array[Callable] = []
	for cb: Callable in _game_listeners:
		if cb.is_valid():
			live.append(cb)
	_game_listeners = live
	for cb: Callable in _game_listeners.duplicate():
		if cb.is_valid() and _game_listeners.has(cb):
			cb.call(key)


## How many listeners the list holds, a released one included until the next notify.
static func listener_count() -> int:
	return _listeners.size()


## How many game listeners the list holds, a released one included until the next notify.
static func game_listener_count() -> int:
	return _game_listeners.size()
