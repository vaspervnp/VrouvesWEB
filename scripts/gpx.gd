extends Node
## The GamePix SDK (web/shell.html loads it before the engine): pause and resume, the ads
## between stages, the player's language, and saving to localStorage, which the GamePix
## player keeps for the player (the IndexedDB behind user:// it does not).
## Off the web, or with no SDK on the page, every call does nothing.

var _gp: JavaScriptObject
var _storage: JavaScriptObject
var _keep: Array = []           # the JavaScript callbacks, kept alive for as long as we are
var _started := false
var _why := {}                  # what holds the game paused: "gamepix", "hidden"
var _ad_busy := false

signal _ad_done


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		return
	_storage = JavaScriptBridge.get_interface("localStorage")
	var doc := JavaScriptBridge.get_interface("document")
	doc.addEventListener("visibilitychange", _cb(func(_a): hold("hidden", bool(doc.hidden))))
	if JavaScriptBridge.eval("typeof window.GamePix !== 'undefined'", true):
		_gp = JavaScriptBridge.get_interface("GamePix")
		var on_pause := _cb(func(_a): hold("gamepix", true))
		var on_resume := _cb(func(_a): hold("gamepix", false))
		_gp.events.on("pause", on_pause)
		_gp.events.on("resume", on_resume)
		# the older API the SDK still calls as well; the two are the same pause
		_gp.pause = on_pause
		_gp.resume = on_resume


func _cb(f: Callable) -> JavaScriptObject:
	var c := JavaScriptBridge.create_callback(f)
	_keep.append(c)
	return c


func active() -> bool:
	return _gp != null


## the whole game stops, sound and all, while anything holds it; a call may come twice
func hold(why: String, on: bool) -> void:
	if on:
		_why[why] = true
	else:
		_why.erase(why)
	get_tree().paused = not _why.is_empty()
	AudioServer.set_bus_mute(0, not _why.is_empty())


## the page has finished loading and the title screen is up
func loaded() -> void:
	if _gp:
		_gp.lifecycle.loaded()


## the first time the player starts a game
func game_start() -> void:
	if _gp and not _started:
		_started = true
		_gp.lifecycle.gameStart()


## "en", "el", ... as GamePix knows the player, or "" off GamePix
func lang() -> String:
	return str(_gp.lang()) if _gp else ""


func happy(type: String) -> void:
	if _gp:
		_gp.happyMoment(type)


func sad(type: String) -> void:
	if _gp:
		_gp.sadMoment(type)


func score(s: int) -> void:
	if _gp:
		_gp.updateScore(s)


func level(n: int) -> void:
	if _gp:
		_gp.updateLevel(n)


## an ad between stages: await it; the SDK pauses and resumes the game around it itself
func interstitial() -> void:
	if not _gp or _ad_busy:
		return
	_ad_busy = true
	_gp.ads.interstitial().then(_cb(func(_a): _ad_done.emit()))
	await _ad_done
	_ad_busy = false


## a rewarded ad the player chose to watch: await it; true only if it was watched to the end
func reward() -> bool:
	if not _gp or _ad_busy:
		return false
	_ad_busy = true
	var ok := [false]
	_gp.ads.reward().then(_cb(func(a):
		ok[0] = a.size() > 0 and a[0] != null and bool(a[0].success)
		_ad_done.emit()))
	await _ad_done
	_ad_busy = false
	return ok[0]


# ------------------------------------------------------------------ saving

## a saved value (Dictionary, Array, ...), or null if there is none
func load_json(key: String) -> Variant:
	var t := load_text(key)
	return JSON.parse_string(t) if t != "" else null


## a saved string, or "" if there is none (localStorage on the web, a file in user:// off it)
func load_text(key: String) -> String:
	if _storage:
		var v = _storage.getItem("vrouves_" + key)
		return str(v) if v != null else ""
	var path := "user://%s.json" % key
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func save_text(key: String, text: String) -> void:
	if _storage:
		_storage.setItem("vrouves_" + key, text)
		return
	var f := FileAccess.open("user://%s.json" % key, FileAccess.WRITE)
	if f:
		f.store_string(text)
