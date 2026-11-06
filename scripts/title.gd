extends Node2D
## The title screen: the menu, the pages (story, defenders, invaders, controls, high
## scores) and the name entry for a new high score.

signal start_game

const W := 1280.0
const H := 1024.0
const C_GOLD := Color(1.0, 0.85, 0.2)
const C_RED := Color(1.0, 0.3, 0.25)
const PAGES := ["story", "defenders", "invaders", "howto"]

var page := "menu"
var page_on_start := ""
var entry_score := -1
var entry_name := ""
var entry_rank := -1
var sel := 0
var hover := -1
var items: Array = []           # [id, rect]
var time := 0.0
var bg: Texture2D
var has_art := false


func _ready() -> void:
	has_art = ResourceLoader.exists("res://art/title.png")
	bg = load("res://art/title.png") if has_art else Data.stage_tex(1)
	Data.prefetch_stage(1)
	if page_on_start != "":
		page = page_on_start
	Sfx.music(true)


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func menu_items() -> Array:
	return [
		["start", Data.t("start")],
		["howto", Data.t("howto")],
		["hiscores", Data.t("hiscores_t")],
		["dif", Data.t("dif%d" % Data.difficulty)],
		["lang", Data.t("language")],
		["music", Data.t("music") if Data.music_on else Data.t("music_off")],
	]


func activate(id: String) -> void:
	Sfx.play("move")
	match id:
		"start":
			Sfx.play("wave")
			start_game.emit()
		"howto":
			page = "story"
		"hiscores":
			page = "hiscores"
		"dif":
			Data.difficulty = (Data.difficulty + 1) % 4
			Data.save_settings()
		"lang":
			Data.toggle_lang()
		"music":
			Sfx.toggle_music()
			Sfx.music(true)
		"ok":
			entry_done()
		"del":
			entry_name = entry_name.substr(0, maxi(0, entry_name.length() - 1))
		"back":
			page = "menu"
		_ when id.begins_with("key"):
			if entry_name.length() < 3:
				entry_name += id.substr(3)
		"next":
			var i := PAGES.find(page)
			page = PAGES[(i + 1) % PAGES.size()] if i >= 0 else "menu"


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		hover = -1
		for i in items.size():
			if items[i][1].has_point(get_local_mouse_position()):
				hover = i
				if page == "menu":
					sel = i
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		for it in items:
			if it[1].has_point(get_local_mouse_position()):
				activate(it[0])
				return
		if page != "menu" and page != "enter":
			activate("next" if page in PAGES else "back")
		return
	if not (ev is InputEventKey and ev.pressed):
		return
	if page == "enter":
		entry_key(ev)
		return
	match ev.keycode:
		KEY_L:
			Data.toggle_lang()
		KEY_M:
			Sfx.toggle_music()
			Sfx.music(true)
		KEY_D:
			activate("dif")
	if page == "menu":
		var n := menu_items().size()
		match ev.keycode:
			KEY_UP, KEY_Q:
				sel = (sel + n - 1) % n
				Sfx.play("move")
			KEY_DOWN, KEY_A:
				sel = (sel + 1) % n
				Sfx.play("move")
			KEY_ENTER, KEY_KP_ENTER:
				activate(menu_items()[sel][0])
			KEY_SPACE:
				activate("start")
			KEY_RIGHT, KEY_P:
				page = "story"
			KEY_ESCAPE:
				pass
	else:
		match ev.keycode:
			KEY_ESCAPE, KEY_BACKSPACE:
				activate("back")
			KEY_RIGHT, KEY_P, KEY_ENTER, KEY_KP_ENTER:
				activate("next" if page in PAGES else "back")
			KEY_LEFT, KEY_O:
				var i := PAGES.find(page)
				page = PAGES[(i + PAGES.size() - 1) % PAGES.size()] if i >= 0 else "menu"
			KEY_SPACE:
				activate("start")


func entry_key(ev: InputEventKey) -> void:
	if ev.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		entry_done()
		return
	if ev.keycode == KEY_BACKSPACE:
		entry_name = entry_name.substr(0, maxi(0, entry_name.length() - 1))
		return
	if ev.unicode > 32 and entry_name.length() < 3:
		var ch := String.chr(ev.unicode).to_upper()
		if ch.to_upper() != ch.to_lower() or ch.is_valid_int():
			entry_name += ch
			Sfx.play("move")


func entry_done() -> void:
	var nm := entry_name.strip_edges()
	if nm == "":
		nm = "???"
	entry_rank = Data.add_hiscore(nm.to_upper(), entry_score)
	page = "hiscores"
	Sfx.play("build")


# ====================================================================== drawing

func txt(pos: Vector2, s: String, size: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font: Font = null, outline := 0) -> void:
	var f: Font = font if font else Data.font_bold
	if outline:
		draw_string_outline(f, pos, s, align, width, size, outline, Color(0, 0, 0, 0.9))
	draw_string(f, pos, s, align, width, size, col)


func spr(name: String, pos: Vector2, sc: float, flip := false) -> void:
	var tx := Data.tex(name)
	var sz := tx.get_size()
	draw_set_transform(pos, 0.0, Vector2(-sc if flip else sc, sc))
	draw_texture(tx, -Vector2(sz.x / 2, sz.y * 200.0 / 256.0))
	draw_set_transform(Vector2.ZERO)


func panel(r: Rect2, alpha := 0.82) -> void:
	draw_rect(Rect2(r.position + Vector2(8, 8), r.size), Color(0, 0, 0, 0.3))
	draw_rect(r, Color(0.1, 0.12, 0.3, alpha))
	draw_rect(r, C_GOLD, false, 3.0)


func _draw() -> void:
	items.clear()
	var bs := bg.get_size()
	var sc := maxf(W / bs.x, H / bs.y)
	draw_texture_rect(bg, Rect2((W - bs.x * sc) / 2, (H - bs.y * sc) / 2, bs.x * sc, bs.y * sc), false)
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.15 if page == "menu" else 0.45))
	# the title, bouncing a little
	var bob := sin(time * 2.0) * 4.0
	txt(Vector2(0, 100 + bob), Data.TEXT["title"][0], 78, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER, W, Data.font_title, 16)
	txt(Vector2(0, 168 - bob), Data.TEXT["title"][1], 54, C_RED, HORIZONTAL_ALIGNMENT_CENTER, W, Data.font_title, 14)
	match page:
		"menu":
			draw_menu()
		"story":
			draw_story()
		"defenders":
			draw_defenders()
		"invaders":
			draw_invaders()
		"howto":
			draw_howto()
		"hiscores":
			draw_hiscores()
		"enter":
			draw_entry()
	txt(Vector2(0, H - 14), Data.t("credit"), 16, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, W, null, 4)


func draw_menu() -> void:
	txt(Vector2(0, 214), Data.t("subtitle"), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, W, null, 6)
	var mi := menu_items()
	var y := 300.0
	for i in mi.size():
		var big: bool = i == 0
		var r := Rect2(W / 2 - 230, y, 460, 62 if big else 46)
		items.append([mi[i][0], r])
		var on := i == sel
		draw_rect(Rect2(r.position + Vector2(6, 6), r.size), Color(0, 0, 0, 0.3))
		draw_rect(r, Color(0.85, 0.2, 0.15, 0.95) if big else (Color(0.12, 0.35, 0.8, 0.95) if on else Color(0.1, 0.12, 0.3, 0.85)))
		draw_rect(r, C_GOLD if on else Color(1, 1, 1, 0.3), false, 3.0 if on else 1.5)
		txt(Vector2(r.position.x, r.position.y + (43 if big else 32)), mi[i][1], 34 if big else 22,
			Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, Data.font_title if big else null, 4 if big else 0)
		y += r.size.y + 12
	if has_art:
		return
	# the defenders cheering on the left, the invaders sulking on the right
	var defs := ["cretan", "yiayia", "bride", "baker", "psssst"]
	for i in defs.size():
		var x := 120.0 + (i % 2) * 110
		var yy := 420.0 + i * 120
		spr(defs[i], Vector2(x, yy + absf(sin(time * 3.0 + i)) * -10.0), 0.9)
	spr("guard_left_%d" % (int(time * 3) % 2), Vector2(W - 140, 560), 0.9)
	spr("tank_left_%d" % (int(time * 3) % 2), Vector2(W - 200, 760), 0.9)
	spr("drone_left_%d" % (int(time * 6) % 2), Vector2(W - 120, 420 + sin(time * 2.0) * 10.0), 0.9)
	spr("sack_full", Vector2(260, 960), 0.8)
	spr("sack_full", Vector2(330, 975), 0.8)
	txt(Vector2(0, H - 44), "UP / DOWN  ·  ENTER  ·  SPACE  ·  L  ·  M  ·  D", 16, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, W, null, 4)


func page_frame(title: String) -> Rect2:
	var r := Rect2(90, 220, W - 180, H - 300)
	panel(r)
	txt(Vector2(r.position.x, r.position.y + 52), title, 36, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, Data.font_title, 6)
	var i := PAGES.find(page)
	var nav := "<  %d/%d  >   ESC: %s" % [i + 1, PAGES.size(), Data.t("back")] if i >= 0 else "ESC: " + Data.t("back")
	txt(Vector2(r.position.x, r.end.y - 18), nav, 18, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var b := Rect2(r.end.x - 150, r.position.y + 14, 130, 40)
	items.append(["back", b])
	draw_rect(b, Color(0.85, 0.2, 0.15))
	txt(Vector2(b.position.x, b.position.y + 28), Data.t("back"), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, b.size.x)
	return r


func draw_story() -> void:
	var r := page_frame(Data.t("story_t"))
	draw_multiline_string(Data.font_bold, r.position + Vector2(60, 130), Data.t("story"), HORIZONTAL_ALIGNMENT_LEFT,
		r.size.x - 360, 25, -1, Color.WHITE)
	spr("psssst", Vector2(r.end.x - 150, r.position.y + 340 + sin(time * 3.0) * 8.0), 1.3)
	spr("sack_full", Vector2(r.end.x - 150, r.end.y - 80), 1.4)


func draw_defenders() -> void:
	var r := page_frame(Data.t("defenders_t"))
	for i in 6:
		var type: int = Data.TOWER_ORDER[i]
		var tt: Dictionary = Data.TTYPES[type]
		var y := r.position.y + 130 + i * 86
		spr(tt["spr"], Vector2(r.position.x + 90, y + 50), 0.62)
		txt(Vector2(r.position.x + 160, y + 10), "%d. %s - %d" % [i + 1, Data.t("name%d" % type), int(tt["cost"])], 26, C_GOLD)
		txt(Vector2(r.position.x + 160, y + 42), Data.t("desc%d" % type), 20, Color.WHITE)
	draw_multiline_string(Data.font_bold, Vector2(r.position.x + 60, r.end.y - 70), Data.t("synergy_help"),
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 120, 17, -1, Color(0.7, 1, 0.6))


func draw_invaders() -> void:
	var r := page_frame(Data.t("invaders_t"))
	var names := ["drone", "guard", "tank"]
	for i in 3:
		var y := r.position.y + 150 + i * 170
		spr("%s_down_%d" % [names[i], int(time * 3) % 2], Vector2(r.position.x + 120, y + 90), 1.0)
		txt(Vector2(r.position.x + 230, y + 40), Data.t("ename%d" % (i + 1)), 30, C_RED, HORIZONTAL_ALIGNMENT_LEFT, -1, Data.font_title, 4)
		draw_multiline_string(Data.font_bold, Vector2(r.position.x + 230, y + 80), Data.t("edesc%d" % (i + 1)),
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 300, 22, -1, Color.WHITE)


func draw_howto() -> void:
	var r := page_frame(Data.t("howto"))
	draw_multiline_string(Data.font_bold, r.position + Vector2(60, 140), Data.t("controls"), HORIZONTAL_ALIGNMENT_LEFT,
		r.size.x - 120, 24, -1, Color.WHITE)
	draw_multiline_string(Data.font_bold, r.position + Vector2(60, 420), Data.t("synergy_help"), HORIZONTAL_ALIGNMENT_LEFT,
		r.size.x - 120, 22, -1, Color(0.7, 1, 0.6))
	for i in 4:
		spr(["cretan", "bride", "yiayia", "baker"][i], Vector2(r.position.x + 260 + i * 150, r.end.y - 70), 0.75, i % 2 == 1)


func draw_hiscores() -> void:
	var r := page_frame(Data.t("hiscores_t"))
	for i in Data.hiscores.size():
		var y := r.position.y + 150 + i * 62
		var col := C_GOLD if i == entry_rank else Color.WHITE
		if i == entry_rank:
			draw_rect(Rect2(r.position.x + 200, y - 40, r.size.x - 400, 54), Color(1, 1, 1, 0.12 + 0.08 * sin(time * 6.0)))
		txt(Vector2(r.position.x + 260, y), "%d." % (i + 1), 34, col)
		txt(Vector2(r.position.x + 360, y), str(Data.hiscores[i][0]), 34, col, HORIZONTAL_ALIGNMENT_LEFT, -1, Data.font_title)
		txt(Vector2(r.position.x + 540, y), "%05d" % int(Data.hiscores[i][1]), 34, col, HORIZONTAL_ALIGNMENT_RIGHT, 300)


const KEYS := ["ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "0123456789"]


func draw_entry() -> void:
	var r := Rect2(140, 240, W - 280, 700)
	panel(r)
	txt(Vector2(r.position.x, r.position.y + 70), Data.t("newhs"), 48, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, Data.font_title, 8)
	txt(Vector2(r.position.x, r.position.y + 130), Data.t("final_score") % entry_score, 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	txt(Vector2(r.position.x, r.position.y + 190), Data.t("entername"), 22, Color(0.8, 0.9, 1), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	for i in 3:
		var b := Rect2(W / 2 - 150 + i * 105, r.position.y + 220, 90, 110)
		draw_rect(b, Color(0, 0, 0, 0.4))
		var on := i == entry_name.length() and int(time * 3) % 2 == 0
		draw_rect(b, C_GOLD if on else Color(1, 1, 1, 0.5), false, 3.0)
		if i < entry_name.length():
			txt(Vector2(b.position.x, b.position.y + 86), entry_name[i], 72, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, b.size.x, Data.font_title)
	# the letters, for a screen with no keyboard
	var y := r.position.y + 370
	for row: String in KEYS:
		var x := W / 2 - row.length() * 36.0
		for ch in row:
			key_button("key" + ch, Rect2(x + 3, y, 66, 62), ch, Color(0.12, 0.35, 0.8, 0.95))
			x += 72
		y += 70
	key_button("del", Rect2(W / 2 - 290, y + 10, 270, 62), Data.t("del"), Color(0.4, 0.4, 0.5, 0.95))
	key_button("ok", Rect2(W / 2 + 20, y + 10, 270, 62), Data.t("ok"), Color(0.85, 0.2, 0.15, 0.95))


func key_button(id: String, b: Rect2, label: String, col: Color) -> void:
	items.append([id, b])
	var on: bool = hover >= 0 and hover < items.size() and items[hover][0] == id
	draw_rect(b, col.lightened(0.2) if on else col)
	draw_rect(b, C_GOLD if on else Color(1, 1, 1, 0.3), false, 2.0)
	txt(Vector2(b.position.x, b.position.y + 44), label, 32, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, b.size.x, Data.font_title)
