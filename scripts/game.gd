extends Node2D
## One stage of LET'S GO FOR VROUVES: the logic runs at 25 ticks a second exactly as on the
## CPC (docs/cpc_mechanics.md); positions are in path steps, 12 to a map cell.

signal finished(result: String, score: int)     # "won", "lost" or "quit"

const CELL := 64.0
const TOP := 48.0
const PF_W := 1280.0
const PF_H := 896.0
const BOT_Y := TOP + PF_H
const K := CELL / 12.0                  # pixels per step
const SPR := 0.5                        # sprite pictures are 128 px per cell

const C_BAR := Color(0.13, 0.11, 0.2, 0.92)
const C_GOLD := Color(1.0, 0.85, 0.2)
const C_OK := Color(0.45, 1.0, 0.4)
const C_BAD := Color(1.0, 0.35, 0.3)

class Enemy:
	var type: int
	var x: int
	var y: int
	var px: float
	var py: float
	var path: Dictionary
	var seg := 0
	var rem := 0
	var acc := 0
	var prog := 0
	var slow := 0
	var anim := 0
	var hp := 0
	var max_hp := 0
	var arm := 0
	var gen := 0
	var flash := 0.0
	var alive := true

class Tower:
	var type: int
	var c: int
	var r: int
	var cx: int
	var cy: int
	var cd := 8
	var dis := 0
	var syn := 0
	var face := 1
	var kick := 0.0
	var on_blocked := false

class Proj:
	var kind: String
	var x: float
	var y: float
	var px: float
	var py: float
	var tx: float
	var ty: float
	var target: Enemy
	var gen: int
	var dmg: int
	var crit := false
	var lost := false
	var speed: float
	var src: Vector2

class Fx:
	var kind: String
	var x: float
	var y: float
	var life: float
	var total: float
	var text := ""
	var col := Color.WHITE

var stage_no := 1
var stage: Dictionary
var grid: Array = []
var cellt: Array = []                   # 0 buildable, 1 road, 2 blocked (Psssst only), 3 base
var tower_at: Array = []
var paths := {}

var funds := Data.START_FUNDS
var hp := Data.START_HP
var score := 0
var lives := 0
var wave_num := 0
var wave_active := false
var cd_sec := Data.FIRST_COUNTDOWN
var cd_sub := 25
var groups: Array = []
var sp_timer := 0
var sp_left := 0
var gen_ctr := 0

var enemies: Array[Enemy] = []
var towers: Array = []                  # 32 slots, null when free
var projs: Array[Proj] = []
var fxs: Array[Fx] = []
var sacks_full := [true, true, true, true, true]

var selected := Data.CRETAN
var cursor := Vector2i(7, 3)
var mouse_in_field := false
var paused := false
var speed := 1
var game_over := 0                      # 1 won, 2 lost
var end_wait := 0.0
var msg := ""
var msg_timer := 0
var banner: Array = []                  # lines of the big banner
var ban_timer := 0
var shake := 0.0
var tick_acc := 0.0
var alpha := 0.0
var time := 0.0
var rng := RandomNumberGenerator.new()
var hover_btn := ""
var sell_cell := Vector2i(-1, -1)       # a defender clicked once: a second click sells it
var sell_t := 0.0
var has_left := false
var buttons := {}                       # name -> Rect2, the clickable parts of the HUD
var bot := false                        # plays by itself (--bot, the tests, the title demo)
var bot_step := 0
const BOT_PLAN := [Data.CRETAN, Data.CRETAN, Data.PSSSST, Data.CRETAN, Data.BRIDE, Data.YIAYIA,
	Data.BAKER, Data.CAULDRON, Data.CRETAN, Data.BRIDE, Data.PSSSST, Data.YIAYIA]


func setup(n: int, start_score: int, lives_left: int) -> void:
	stage_no = n
	stage = Data.stages[n - 1]
	score = start_score
	lives = lives_left
	grid = stage["grid"]
	cellt.clear()
	tower_at.clear()
	for r in Data.ROWS:
		var row := []
		var trow := []
		for c in Data.COLS:
			var ch: String = grid[r][c]
			row.append(0 if ch in ".F" else (1 if ch == "#" else (3 if ch in "KP" else 2)))
			trow.append(null)
		cellt.append(row)
		tower_at.append(trow)
	towers.resize(32)
	towers.fill(null)
	paths["ground"] = make_path(stage["ground"])
	paths["air"] = make_path(stage["air"])
	rng.seed = 0xA5F3 ^ Time.get_ticks_msec()
	selected = stage["defenders"][0]
	msg = Data.t("call")
	msg_timer = -1
	var newdef := {2: Data.YIAYIA, 3: Data.BRIDE, 4: Data.BAKER, 5: Data.CAULDRON}
	if stage_no == 1:
		banner = [Data.stage_text(1, 0), "[1] %s - %s" % [Data.t("name1"), Data.t("desc1")],
			"[4] %s - %s" % [Data.t("name4"), Data.t("desc4")]]
		ban_timer = 250
	elif newdef.has(stage_no):
		var d: int = newdef[stage_no]
		banner = [Data.stage_text(stage_no, 0), Data.t("newdef"),
			"[%d] %s - %s" % [Data.TOWER_ORDER.find(d) + 1, Data.t("name%d" % d), Data.t("desc%d" % d)]]
		selected = d
		ban_timer = 250
	else:
		banner = [Data.stage_text(stage_no, 0)]
		ban_timer = 125


var bg: Sprite2D
var warmed := false


func _ready() -> void:
	# the background has no mipmaps, so it is drawn by its own node with plain linear filtering
	bg = Sprite2D.new()
	bg.texture = Data.stage_tex(stage_no)
	bg.centered = false
	bg.scale = Vector2(PF_W, PF_H) / bg.texture.get_size()
	bg.offset = Vector2(0, TOP) / bg.scale
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.show_behind_parent = true
	add_child(bg)
	Data.prefetch_stage(stage_no + 1)
	Sfx.music(true)


# ====================================================================== paths

## waypoints (col,row) -> start position in steps and segments (dx, dy, n)
func make_path(wps: Array) -> Dictionary:
	var segs := []
	for i in wps.size() - 1:
		var a: Array = wps[i]
		var b: Array = wps[i + 1]
		var dc := signi(int(b[0]) - int(a[0]))
		var dr := signi(int(b[1]) - int(a[1]))
		var n := 12 * maxi(absi(int(b[0]) - int(a[0])), absi(int(b[1]) - int(a[1])))
		segs.append([dc, dr, n])
	var p := {"x0": int(wps[0][0]) * 12, "y0": int(wps[0][1]) * 12, "segs": segs, "seg0": 0, "rem0": segs[0][2]}
	# start low enough to be on the map, as the CPC does
	var x: int = p["x0"]
	var y: int = p["y0"]
	var seg := 0
	var rem: int = segs[0][2]
	while y < 2:
		x += segs[seg][0]
		y += segs[seg][1]
		rem -= 1
		if rem == 0:
			seg += 1
			rem = segs[seg][2]
	p["x0"] = x
	p["y0"] = y
	p["seg0"] = seg
	p["rem0"] = rem
	return p


# ====================================================================== main loop

func _process(delta: float) -> void:
	time += delta
	shake = maxf(0.0, shake - delta * 3.0)
	if game_over:
		end_wait += delta
		if bot and end_wait > 3.0:
			leave()
			bot = false
	elif not paused:
		tick_acc += delta * speed
		var n := 0
		while tick_acc >= Data.TICK and n < 10:
			tick_acc -= Data.TICK
			game_tick()
			n += 1
			if game_over:
				break
	alpha = clampf(tick_acc / Data.TICK, 0.0, 1.0) if not paused and not game_over else 1.0
	for e in enemies:
		e.flash = maxf(0.0, e.flash - delta * 6.0)
	for tw in towers:
		if tw:
			tw.kick = maxf(0.0, tw.kick - delta * 5.0)
	queue_redraw()


func game_tick() -> void:
	if bot:
		bot_tick()
	wave_update()
	if game_over:
		return
	update_enemies()
	update_towers()
	update_projs()
	update_fx()
	if ban_timer > 0:
		ban_timer -= 1
		if ban_timer == 0:
			banner = []
	if msg_timer > 0:
		msg_timer -= 1
		if msg_timer == 0:
			msg = ""


# ====================================================================== waves

func wave_update() -> void:
	if hp <= 0:
		end_stage(2)
		return
	if not wave_active:
		if cd_sub > 0:
			cd_sub -= 1
		elif cd_sec == 0:
			start_wave()
		else:
			cd_sec -= 1
			cd_sub = 24
		return
	if sp_left == 0 and enemies.is_empty():
		funds += 15 + 3 * wave_num
		Sfx.play("sell")
		if wave_num >= Data.NUM_WAVES:
			score += funds
			end_stage(1)
			return
		wave_active = false
		cd_sec = Data.NEXT_COUNTDOWN
		cd_sub = 25
		msg = Data.t("clear")
		msg_timer = 150
		float_text(PF_W / 2, TOP + 60, "+%d" % (15 + 3 * wave_num), C_GOLD)
		return
	spawn_tick()


func start_wave() -> void:
	if wave_num >= Data.NUM_WAVES:
		return
	banner = []
	ban_timer = 0
	wave_num += 1
	wave_active = true
	groups = stage["waves"][wave_num - 1].duplicate(true)
	sp_left = 0
	for g in groups:
		sp_left += int(g[1])
	sp_timer = 10
	if bot:
		print("stage %d wave %d hp %d funds %d score %d" % [stage_no, wave_num, hp, funds, score])
	if wave_num == Data.NUM_WAVES:
		msg = Data.t("final")
		msg_timer = 100
	else:
		msg = ""
	Sfx.play("wave")


func call_wave_now() -> void:
	if wave_active or game_over:
		return
	funds += cd_sec >> 1
	score += cd_sec
	if cd_sec > 1:
		float_text(PF_W - 170, TOP + 40, "+%d" % (cd_sec >> 1), C_GOLD)
	start_wave()


func spawn_tick() -> void:
	if groups.is_empty():
		return
	sp_timer -= 1
	if sp_timer > 0:
		return
	if enemies.size() >= Data.MAX_ENEMIES:
		sp_timer = 1
		return
	var g: Array = groups[0]
	spawn_enemy(int(g[0]))
	sp_left -= 1
	g[1] = int(g[1]) - 1
	sp_timer = int(g[2])
	if int(g[1]) <= 0:
		groups.pop_front()
		if not groups.is_empty():
			sp_timer = int(groups[0][2])


func spawn_enemy(type: int) -> void:
	var et: Dictionary = Data.ETYPES[type]
	var e := Enemy.new()
	e.type = type
	e.path = paths["air"] if type == Data.DRONE else paths["ground"]
	e.x = e.path["x0"]
	e.y = e.path["y0"]
	e.px = e.x
	e.py = e.y
	e.seg = e.path["seg0"]
	e.rem = e.path["rem0"]
	e.hp = mini(255, int(et["hp"]) + int(et["hpw"]) * (wave_num + int(stage["toughness"])))
	e.max_hp = e.hp
	e.arm = et["arm"]
	e.anim = rng.randi() & 255
	gen_ctr += 1
	e.gen = gen_ctr
	enemies.append(e)


# ====================================================================== enemies

func update_enemies() -> void:
	for e: Enemy in enemies.duplicate():
		if not e.alive:
			continue
		e.px = e.x
		e.py = e.y
		var c: int = Data.ETYPES[e.type]["spd"]
		if e.slow > 0:
			e.slow -= 1
			c >>= 1
		var t := e.acc + c
		e.acc = t & 15
		for i in t >> 4:
			if enemy_step(e):
				arrive(e)
				break
		if not e.alive:
			continue
		e.anim += 1
		if e.type == Data.TANK and (e.anim & 7) == 0:
			tank_crush(e)


## one path step; true when the enemy has reached the base
func enemy_step(e: Enemy) -> bool:
	var segs: Array = e.path["segs"]
	var s: Array = segs[e.seg]
	e.x += int(s[0])
	e.y += int(s[1])
	e.prog += 1
	e.rem -= 1
	if e.rem <= 0:
		e.seg += 1
		if e.seg >= segs.size():
			return true
		e.rem = segs[e.seg][2]
	return false


func arrive(e: Enemy) -> void:
	remove_enemy(e)
	hp = maxi(0, hp - int(Data.ETYPES[e.type]["dmg"]))
	for k in 5:
		if hp <= 80 - 20 * k and sacks_full[k]:
			sacks_full[k] = false
			var sc: Array = stage["sacks"][k]
			add_fx("poof_b", sc[0] * 12 + 6, sc[1] * 12 + 6, 0.5)
	shake = 1.0
	Sfx.play("hurt")
	float_text((e.x + 6) * K, TOP + (e.y + 6) * K - 30, "-%d" % Data.ETYPES[e.type]["dmg"], C_BAD)


func remove_enemy(e: Enemy) -> void:
	e.alive = false
	enemies.erase(e)


func damage_enemy(e: Enemy, d: int, ignore_armour := false) -> void:
	if not e.alive:
		return
	if not ignore_armour:
		d = maxi(1, d - e.arm)
	e.hp -= d
	e.flash = 1.0
	if e.hp <= 0:
		kill_enemy(e)


func kill_enemy(e: Enemy) -> void:
	var et: Dictionary = Data.ETYPES[e.type]
	funds += int(et["reward"])
	score = mini(65535, score + int(et["dmg"]))
	remove_enemy(e)
	add_fx("boom" if e.type == Data.TANK else "poof", e.x + 6, e.y + 6, 0.5 if e.type == Data.TANK else 0.4)
	float_text((e.x + 6) * K, TOP + (e.y + 2) * K - 20, "+%d" % int(et["reward"]), C_GOLD)
	Sfx.play("die")


func tank_crush(e: Enemy) -> void:
	var c := (e.x + 6) / 12
	var r := (e.y + 6) / 12
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var cc: int = c + d.x
		var rr: int = r + d.y
		if cc < 0 or rr < 0 or cc >= Data.COLS or rr >= Data.ROWS:
			continue
		var tw = tower_at[rr][cc]
		if tw and tw.type == Data.CAULDRON and tw.dis == 0:
			tw.dis = 125
			Sfx.play("crush")
			add_fx("bash", tw.cx, tw.cy - 6, 0.3)


# ====================================================================== towers

func update_towers() -> void:
	var budget := 4
	for tw in towers:
		if tw == null:
			continue
		if tw.dis > 0:
			tw.dis -= 1
			continue
		if tw.cd > 0:
			tw.cd -= 1
			continue
		if budget == 0:
			continue
		budget -= 1
		var tg := find_target(tw)
		if tg == null:
			tw.cd = 4
			continue
		tw.cd = Data.TTYPES[tw.type]["cd"]
		fire(tw, tg)


func in_range(tw: Tower, e: Enemy, rng_units: int) -> bool:
	var dx := e.x + 6 - tw.cx
	var dy := e.y + 6 - tw.cy
	return dx * dx + dy * dy <= rng_units * rng_units


func find_target(tw: Tower) -> Enemy:
	var tt: Dictionary = Data.TTYPES[tw.type]
	var best: Enemy = null
	for e in enemies:
		if e.type == Data.DRONE and not tt["air"]:
			continue
		if in_range(tw, e, tt["range"]) and (best == null or e.prog > best.prog):
			best = e
	return best


func tower_damage(tw: Tower) -> int:
	var base: int = Data.TTYPES[tw.type]["dmg"]
	if tw.syn == 0:
		return base
	return (base * tw.syn + 8) / 16


func fire(tw: Tower, tg: Enemy) -> void:
	var tt: Dictionary = Data.TTYPES[tw.type]
	tw.face = -1 if tg.x + 6 < tw.cx else 1
	tw.kick = 1.0
	Sfx.play(tt["sfx"])
	match tw.type:
		Data.YIAYIA:
			for e in enemies:
				if e.type != Data.DRONE and in_range(tw, e, tt["range"]):
					e.slow = 40
			add_fx("bash", tg.x + 6, tg.y + 2, 0.3)
			damage_enemy(tg, tower_damage(tw))
		Data.CAULDRON:
			var clouds := 0
			for e: Enemy in enemies.duplicate():
				if e.type != Data.DRONE and in_range(tw, e, tt["range"]):
					e.slow = 30
					if clouds < 2:
						add_fx("puff", e.x + 6, e.y + 4, 0.5)
						clouds += 1
					damage_enemy(e, 8, true)
		_:
			var p := Proj.new()
			p.kind = tt["proj"]
			p.x = tw.cx
			p.y = tw.cy - 6
			if tw.type == Data.PSSSST:
				p.y = tw.cy - 14
			p.px = p.x
			p.py = p.y
			p.src = Vector2(p.x, p.y)
			p.target = tg
			p.gen = tg.gen
			p.tx = tg.x + 6
			p.ty = tg.y + 6
			p.dmg = tower_damage(tw)
			p.speed = {"bullet": 10.0, "heart": 11.0, "laser": 17.0, "dakos": 5.5}[p.kind]
			if tw.type == Data.BRIDE and rng.randi_range(0, 255) < 64:
				p.dmg *= 3
				p.crit = true
			if projs.size() < 20:
				projs.append(p)


func update_projs() -> void:
	for p: Proj in projs.duplicate():
		p.px = p.x
		p.py = p.y
		if not p.lost:
			if p.target.alive and p.target.gen == p.gen:
				p.tx = p.target.x + 6
				p.ty = p.target.y + 6
			else:
				p.lost = true
		var d := Vector2(p.tx - p.x, p.ty - p.y)
		if d.length() > p.speed:
			d = d.normalized() * p.speed
			p.x += d.x
			p.y += d.y
			continue
		p.x = p.tx
		p.y = p.ty
		projs.erase(p)
		if p.kind == "dakos":
			add_fx("bash", p.x, p.y - 4, 0.35)
			for e: Enemy in enemies.duplicate():
				if absi(e.x + 6 - int(p.x)) <= 12 and absi(e.y + 6 - int(p.y)) <= 12:
					damage_enemy(e, p.dmg)
			continue
		if p.lost:
			continue
		if p.kind == "laser":
			if p.target.arm > 0:
				p.target.arm -= 1
			add_fx("zap", p.x, p.y, 0.25)
		else:
			add_fx("spark", p.x, p.y, 0.25)
		damage_enemy(p.target, p.dmg)
		if p.crit:
			float_text(p.x * K, TOP + p.y * K - 30, "x3!", Color(1, 0.4, 0.7))


# ====================================================================== effects

func add_fx(kind: String, x: float, y: float, life: float) -> void:
	if fxs.size() >= 40:
		return
	var f := Fx.new()
	f.kind = kind
	f.x = x
	f.y = y
	f.life = life
	f.total = life
	fxs.append(f)


func float_text(px: float, py: float, s: String, col: Color) -> void:
	var f := Fx.new()
	f.kind = "text"
	f.x = px
	f.y = py
	f.life = 1.0
	f.total = 1.0
	f.text = s
	f.col = col
	fxs.append(f)


func update_fx() -> void:
	for f: Fx in fxs.duplicate():
		f.life -= Data.TICK
		if f.life <= 0:
			fxs.erase(f)


# ====================================================================== build and sell

## 0 ok, or the text id of why not
func build_check(c: int, r: int, type: int) -> String:
	if not type in stage["defenders"]:
		return "locked"
	if tower_at[r][c] != null:
		return "cant_build"
	var ct: int = cellt[r][c]
	if ct == 2 and type != Data.PSSSST:
		return "only_psssst"
	if ct != 0 and not (ct == 2 and type == Data.PSSSST):
		return "cant_build"
	if funds < int(Data.TTYPES[type]["cost"]):
		return "cant_afford"
	if towers.find(null) < 0:
		return "cant_build"
	return ""


func try_build(c: int, r: int) -> void:
	if game_over:
		return
	if tower_at[r][c] != null:
		return
	var why := build_check(c, r, selected)
	if why != "":
		Sfx.play("error")
		msg = Data.t(why)
		msg_timer = 50
		return
	var tt: Dictionary = Data.TTYPES[selected]
	funds -= int(tt["cost"])
	score = mini(65535, score + int(tt["dmg"]))
	var tw := Tower.new()
	tw.type = selected
	tw.c = c
	tw.r = r
	tw.cx = c * 12 + 6
	tw.cy = r * 12 + 6
	tw.on_blocked = cellt[r][c] == 2
	towers[towers.find(null)] = tw
	tower_at[r][c] = tw
	syn_update()
	add_fx("poof", tw.cx, tw.cy, 0.35)
	Sfx.play("build")
	if ban_timer > 0:
		ban_timer = 1


func try_sell(c: int, r: int) -> void:
	var tw = tower_at[r][c]
	if tw == null or game_over:
		return
	var tt: Dictionary = Data.TTYPES[tw.type]
	funds += int(tt["sell"])
	score = maxi(0, score - int(tt["dmg"]))
	towers[towers.find(tw)] = null
	tower_at[r][c] = null
	syn_update()
	add_fx("poof", tw.cx, tw.cy, 0.35)
	float_text(tw.cx * K, TOP + tw.cy * K - 40, "+%d" % int(tt["sell"]), C_GOLD)
	Sfx.play("sell")


# ====================================================================== neighbours

func syn_factor_at(c: int, r: int, type: int) -> int:
	if not Data.SYNERGY.has(type):
		return 0
	var partner: int = Data.SYNERGY[type][0]
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var cc: int = c + d.x
		var rr: int = r + d.y
		if cc < 0 or rr < 0 or cc >= Data.COLS or rr >= Data.ROWS:
			continue
		var tw = tower_at[rr][cc]
		if tw and tw.type == partner:
			return Data.SYNERGY[type][1]
	return 0


func syn_count() -> int:
	var n := 0
	for tw in towers:
		if tw and tw.syn > 16:
			n += 1
	return n


func syn_update() -> void:
	var cnt := 0
	var done := {}
	for pass_no in 2:
		for tw in towers:
			if tw == null or done.has(tw):
				continue
			if pass_no == 0 and tw.syn < 17:
				continue
			done[tw] = true
			var f := syn_factor_at(tw.c, tw.r, tw.type)
			if f == 0:
				tw.syn = 0
			elif f < 16:
				tw.syn = f
			elif cnt < Data.SYN_MAX:
				cnt += 1
				tw.syn = f
			else:
				tw.syn = 0


# ====================================================================== end

func end_stage(how: int) -> void:
	game_over = how
	end_wait = 0.0
	projs.clear()
	var lines := [Data.stage_text(stage_no, 1 if how == 1 else 2)]
	if how == 2:
		lines.append(Data.t("life_lost") if lives > 0 else Data.t("gameover"))
	lines.append(Data.t("press"))
	banner = lines
	ban_timer = -1
	Sfx.play("wave" if how == 1 else "crush")


func leave() -> void:
	if has_left:
		return
	has_left = true
	if game_over == 1:
		finished.emit("won", score)
	elif game_over == 2:
		finished.emit("lost", score)
	else:
		finished.emit("quit", score)


# ====================================================================== input

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var p: Vector2 = get_local_mouse_position()
		mouse_in_field = p.y >= TOP and p.y < BOT_Y
		if mouse_in_field:
			cursor = Vector2i(clampi(int(p.x / CELL), 0, Data.COLS - 1), clampi(int((p.y - TOP) / CELL), 0, Data.ROWS - 1))
		hover_btn = ""
		for b in buttons:
			if buttons[b].has_point(p):
				hover_btn = b
		return
	if ev is InputEventMouseButton and ev.pressed:
		var p: Vector2 = get_local_mouse_position()
		if game_over:
			if end_wait > 1.2:
				leave()
			return
		for b in buttons:
			if buttons[b].has_point(p):
				press_button(b)
				return
		if paused:
			return
		if p.y >= TOP and p.y < BOT_Y:
			var c := clampi(int(p.x / CELL), 0, Data.COLS - 1)
			var r := clampi(int((p.y - TOP) / CELL), 0, Data.ROWS - 1)
			cursor = Vector2i(c, r)
			if ev.button_index == MOUSE_BUTTON_LEFT and tower_at[r][c] != null:
				# no right button on a touch screen: one tap says what it sells for, a second sells
				if sell_cell == cursor and time - sell_t < 3.0:
					sell_cell = Vector2i(-1, -1)
					try_sell(c, r)
				else:
					sell_cell = cursor
					sell_t = time
					msg = Data.t("sell") % int(Data.TTYPES[tower_at[r][c].type]["sell"])
					msg_timer = 75
					Sfx.play("move")
			elif ev.button_index == MOUSE_BUTTON_LEFT:
				try_build(c, r)
			elif ev.button_index == MOUSE_BUTTON_RIGHT:
				try_sell(c, r)
		return
	if not (ev is InputEventKey and ev.pressed):
		return
	var k: int = ev.keycode
	if game_over:
		if end_wait > 1.2 and k in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			leave()
		return
	match k:
		KEY_L:
			Data.toggle_lang()
			return
		KEY_M:
			Sfx.toggle_music()
			return
		KEY_H:
			paused = not paused
			return
		KEY_ESCAPE:
			if paused:
				leave()
			else:
				paused = true
			return
	if paused:
		return
	match k:
		KEY_LEFT, KEY_O:
			move_cursor(-1, 0)
		KEY_RIGHT, KEY_P:
			move_cursor(1, 0)
		KEY_UP, KEY_Q:
			move_cursor(0, -1)
		KEY_DOWN, KEY_A:
			move_cursor(0, 1)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			try_build(cursor.x, cursor.y)
		KEY_S, KEY_DELETE, KEY_BACKSPACE:
			try_sell(cursor.x, cursor.y)
		KEY_N:
			call_wave_now()
		KEY_F:
			speed = 1 + speed % 3
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			select(Data.TOWER_ORDER[k - KEY_1])


func move_cursor(dc: int, dr: int) -> void:
	cursor = Vector2i(clampi(cursor.x + dc, 0, Data.COLS - 1), clampi(cursor.y + dr, 0, Data.ROWS - 1))
	mouse_in_field = true
	Sfx.play("move")


func select(type: int) -> void:
	if type in stage["defenders"]:
		selected = type
		Sfx.play("move")
	else:
		Sfx.play("error")
		msg = Data.t("locked")
		msg_timer = 50


func press_button(b: String) -> void:
	if b.begins_with("def"):
		select(int(b.substr(3)))
	elif b == "next":
		call_wave_now()
	elif b == "speed":
		speed = 1 + speed % 3
	elif b == "pause" or b == "continue":
		paused = not paused
	elif b == "quit":
		leave()


# ====================================================================== drawing

func cell_px(c: int, r: int) -> Vector2:
	return Vector2(c * CELL, TOP + r * CELL)


func unit_px(x: float, y: float) -> Vector2:
	return Vector2(x * K, TOP + y * K)


## a sprite picture with its ground point (ax, ay) at pos
func draw_sprite(name: String, pos: Vector2, scale := 1.0, flip := false, mod := Color.WHITE, anchor := Vector2(-1, -1)) -> void:
	var tx := Data.tex(name)
	if tx == null:
		return
	var sz := tx.get_size()
	var a := anchor
	if a.x < 0:
		a = Vector2(sz.x / 2.0, sz.y * 200.0 / 256.0) if sz.y > 128 else Vector2(sz.x / 2.0, sz.y * 0.75)
	var s := SPR * scale
	draw_set_transform(pos, 0.0, Vector2(-s if flip else s, s))
	draw_texture(tx, -a, mod)
	draw_set_transform(Vector2.ZERO)


func draw_shadow(pos: Vector2, w: float, alpha_ := 0.28) -> void:
	draw_set_transform(pos, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, w, Color(0, 0, 0, alpha_))
	draw_set_transform(Vector2.ZERO)


func text(pos: Vector2, s: String, size := 20, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font: Font = null, outline := 0) -> void:
	var f: Font = font if font else Data.font_bold
	if outline > 0:
		draw_string_outline(f, pos, s, align, width, size, outline, Color(0, 0, 0, 0.85))
	draw_string(f, pos, s, align, width, size, col)


func _draw() -> void:
	var off := Vector2.ZERO
	if shake > 0:
		off = Vector2(sin(time * 60.0), cos(time * 47.0)) * shake * 6.0
	bg.position = off
	if not warmed:
		# have the fonts draw every glyph the floating texts use, before they are needed
		warmed = true
		for sz in [18, 22, 24, 40]:
			text(Vector2(-2000, -2000), "0123456789+-x!%BOOMBONK", sz, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, Data.font_title, 6)
	draw_cursor()
	draw_world()
	draw_top_bar()
	draw_bottom_bar()
	draw_banner()


func draw_cursor() -> void:
	if not mouse_in_field or game_over:
		return
	var c := cursor.x
	var r := cursor.y
	var p := cell_px(c, r)
	var tw = tower_at[r][c]
	var ok := tw != null or build_check(c, r, selected) == ""
	var col := C_OK if ok else C_BAD
	var blink := 0.55 + 0.25 * sin(time * 8.0)
	draw_rect(Rect2(p + Vector2(2, 2), Vector2(CELL - 4, CELL - 4)), Color(col, 0.18 * blink))
	draw_rect(Rect2(p + Vector2(2, 2), Vector2(CELL - 4, CELL - 4)), Color(col, blink + 0.2), false, 3.0)
	var rr: int
	var center := p + Vector2(CELL / 2, CELL / 2)
	if tw != null:
		rr = Data.TTYPES[tw.type]["range"]
	elif build_check(c, r, selected) in ["", "cant_afford"]:
		rr = Data.TTYPES[selected]["range"]
	else:
		return
	draw_circle(center, rr * K, Color(1, 1, 1, 0.1))
	draw_arc(center, rr * K, 0, TAU, 64, Color(1, 1, 1, 0.55), 2.0, true)


func draw_world() -> void:
	var items := []     # [sort y, kind, object]
	for k in 5:
		var sc: Array = stage["sacks"][k]
		items.append([sc[1] * CELL + CELL * 0.5, "sack", k])
	for tw in towers:
		if tw:
			items.append([tw.r * CELL + CELL * 0.5, "tower", tw])
	for e in enemies:
		var y := enemy_pos(e).y
		items.append([y * K + (40.0 if e.type == Data.DRONE else 0.0), "enemy", e])
	for p in projs:
		if p.kind != "laser":
			items.append([lerpf(p.py, p.y, alpha) * K + 30.0, "proj", p])
	for f in fxs:
		if f.kind != "text":
			items.append([f.y * K + 20.0, "fx", f])
	items.sort_custom(func(a, b): return a[0] < b[0])
	# shadows first, all on the ground
	for it in items:
		if it[1] == "enemy":
			var e: Enemy = it[2]
			var ep := enemy_pos(e)
			var pos := unit_px(ep.x, ep.y)
			draw_shadow(pos + Vector2(0, 4), 16.0 if e.type == Data.DRONE else (26.0 if e.type == Data.TANK else 18.0), 0.22)
		elif it[1] == "tower":
			var tw: Tower = it[2]
			draw_shadow(cell_px(tw.c, tw.r) + Vector2(CELL / 2, CELL / 2 + 6), 20.0, 0.25)
	for it in items:
		match it[1]:
			"sack":
				var sc: Array = stage["sacks"][it[2]]
				var pos := cell_px(sc[0], sc[1]) + Vector2(CELL / 2, CELL / 2 + 8)
				var wob := sin(time * 2.0 + it[2]) * 0.03 if sacks_full[it[2]] else 0.0
				draw_sprite("sack_full" if sacks_full[it[2]] else "sack_empty", pos, 1.0 + wob)
			"tower":
				draw_tower(it[2])
			"enemy":
				draw_enemy(it[2])
			"proj":
				var p: Proj = it[2]
				var pos := unit_px(lerpf(p.px, p.x, alpha), lerpf(p.py, p.y, alpha))
				if p.kind == "bullet":
					draw_circle(pos, 4.0, Color(0.15, 0.12, 0.1))
					draw_circle(pos - Vector2(1, 1), 1.6, Color(1, 0.9, 0.5))
				elif p.kind == "heart":
					draw_sprite("heart_crit" if p.crit else "heart", pos + Vector2(0, 26), 1.0)
				elif p.kind == "dakos":
					var hop := sin(clampf(Vector2(p.x - p.src.x, p.y - p.src.y).length() / 40.0, 0, 1) * PI) * 30.0
					draw_set_transform(pos - Vector2(0, hop), time * 9.0, Vector2(0.55, 0.55))
					draw_texture(Data.tex("dakos"), -Vector2(64, 74))
					draw_set_transform(Vector2.ZERO)
			"fx":
				draw_effect(it[2])
	# lasers on top
	for p in projs:
		if p.kind == "laser":
			var a := unit_px(lerpf(p.px, p.x, alpha), lerpf(p.py, p.y, alpha))
			var b := a - Vector2(p.tx - p.x, p.ty - p.y).normalized() * 26.0
			draw_line(b, a, Color(1, 0.2, 0.4, 0.6), 7.0, true)
			draw_line(b, a, Color(1, 0.85, 0.95), 3.0, true)
	for f in fxs:
		if f.kind == "text":
			var t := 1.0 - f.life / f.total
			var col := Color(f.col, clampf(f.life * 2.5, 0, 1))
			text(Vector2(f.x - 40, f.y - t * 34.0), f.text, 24, col, HORIZONTAL_ALIGNMENT_CENTER, 80, Data.font_title, 6)


func draw_tower(tw: Tower) -> void:
	var tt: Dictionary = Data.TTYPES[tw.type]
	var pos := cell_px(tw.c, tw.r) + Vector2(CELL / 2, CELL / 2 + 6)
	var name: String = tt["spr"]
	var sc := 1.0
	var mod := Color.WHITE
	if tw.type == Data.CAULDRON:
		if tw.dis > 0:
			name = "cauldron_dented"
		elif int(time * 4.0) % 2:
			name = "cauldron_b"
	if tw.type == Data.PSSSST:
		pos.y += sin(time * 3.0 + tw.c) * 4.0
	else:
		pos.y -= tw.kick * 5.0
	# a little squash when it strikes, a gentle breath otherwise
	var sq := 1.0 + 0.02 * sin(time * 2.5 + tw.c * 1.7) + tw.kick * 0.06
	var tx := Data.tex(name)
	var a := Vector2(128, 200)
	draw_set_transform(pos, 0.0, Vector2(SPR * tw.face * (2.0 - sq), SPR * sq))
	draw_texture(tx, -a, mod)
	draw_set_transform(Vector2.ZERO)
	if tw.syn > 0:
		var good := tw.syn > 16
		var p := pos + Vector2(20, -64)
		draw_circle(p, 11, Color(0, 0, 0, 0.6))
		draw_circle(p, 9, C_OK if good else C_BAD)
		text(p + Vector2(-8, 6), "+" if good else "-", 18, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER, 16)
	if tw.dis > 0:
		var p := pos + Vector2(-26, -50)
		draw_arc(p, 9, -PI / 2, -PI / 2 + TAU * tw.dis / 125.0, 20, Color(1, 1, 1, 0.8), 3.0)


## where to draw an enemy's centre, in steps: the logic moves it whole steps 25 times a
## second, so between ticks it is drawn on its way through the next step by the fraction
## of a step its speed has built up, which keeps its motion even
func enemy_pos(e: Enemy) -> Vector2:
	var segs: Array = e.path["segs"]
	if e.seg >= segs.size():
		return Vector2(e.x + 6, e.y + 6)
	var s: Array = segs[e.seg]
	var c: int = Data.ETYPES[e.type]["spd"]
	if e.slow > 0:
		c >>= 1
	var frac := clampf((e.acc + c * alpha) / 16.0, 0.0, 1.0)
	return Vector2(e.x + 6 + int(s[0]) * frac, e.y + 6 + int(s[1]) * frac)


func draw_enemy(e: Enemy) -> void:
	var et: Dictionary = Data.ETYPES[e.type]
	var ep := enemy_pos(e)
	var x := ep.x
	var y := ep.y
	var pos := unit_px(x, y)
	var segs: Array = e.path["segs"]
	var s: Array = segs[mini(e.seg, segs.size() - 1)]
	var dir := "down"
	if s[0] > 0:
		dir = "right"
	elif s[0] < 0:
		dir = "left"
	elif s[1] < 0:
		dir = "up"
	var frame := (e.anim >> 2) & 1
	if e.type == Data.DRONE:
		frame = (e.anim >> 1) & 1
		pos.y += sin(time * 5.0 + e.gen) * 4.0
	else:
		pos.y -= absf(sin(e.anim * PI / 8.0)) * 3.0
	var mod := Color.WHITE
	if e.flash > 0:
		mod = Color(1, 1 - e.flash * 0.6, 1 - e.flash * 0.6)
	if e.slow > 0:
		mod = mod * Color(0.75, 1.0, 0.75)
	draw_sprite("%s_%s_%d" % [et["name"], dir, frame], pos, 1.0, false, mod)
	if e.hp < e.max_hp:
		var w := 34.0
		var top := pos + Vector2(-w / 2, -76 if e.type != Data.TANK else -84)
		draw_rect(Rect2(top, Vector2(w, 6)), Color(0, 0, 0, 0.7))
		var f := clampf(float(e.hp) / e.max_hp, 0, 1)
		draw_rect(Rect2(top + Vector2(1, 1), Vector2((w - 2) * f, 4)), C_OK.lerp(C_BAD, 1.0 - f))
	if e.slow > 0 and e.type != Data.DRONE:
		draw_circle(pos + Vector2(14, -60), 4, Color(0.6, 1, 0.3, 0.8))


func draw_effect(f: Fx) -> void:
	var pos := unit_px(f.x, f.y)
	var t := 1.0 - f.life / f.total
	var a := clampf(f.life / f.total * 2.0, 0, 1)
	match f.kind:
		"spark", "zap":
			var col := Color(1, 0.9, 0.2, a) if f.kind == "spark" else Color(0.5, 1, 1, a)
			for i in 6:
				var ang := i * TAU / 6 + t
				draw_line(pos + Vector2.from_angle(ang) * 4, pos + Vector2.from_angle(ang) * (8 + t * 14), col, 3.0, true)
		"bash", "boom":
			var sc := (0.6 + t * 0.6) * (1.0 if f.kind == "bash" else 1.2)
			draw_set_transform(pos + Vector2(0, 30), t * 2.0, Vector2(sc, sc) * SPR)
			draw_texture(Data.tex("fx_" + f.kind), -Vector2(128, 200), Color(1, 1, 1, a))
			draw_set_transform(Vector2.ZERO)
			if f.kind == "boom" or t < 0.5:
				text(pos + Vector2(-50, -10), "BOOM!" if f.kind == "boom" else "BONK!", 22 if f.kind == "boom" else 18,
					Color(1, 1, 0.6, a), HORIZONTAL_ALIGNMENT_CENTER, 100, Data.font_title, 5)
		"puff", "poof", "poof_b":
			var nm := "fx_puff" if f.kind == "puff" else ("fx_poof" if f.kind == "poof" else "fx_poof_b")
			var sc := 0.5 + t * 0.7
			draw_set_transform(pos + Vector2(0, 30), 0.0, Vector2(sc, sc) * SPR)
			draw_texture(Data.tex(nm), -Vector2(128, 200), Color(1, 1, 1, a))
			draw_set_transform(Vector2.ZERO)


func draw_top_bar() -> void:
	draw_rect(Rect2(0, 0, PF_W, TOP), C_BAR)
	draw_rect(Rect2(0, TOP - 3, PF_W, 3), C_GOLD)
	# left to right: stage, wave, countdown, speed; each placed after the one before
	var x := 14.0
	x = bar_text(x, Data.stage_text(stage_no, 0), 20, C_GOLD, Data.font_title) + 24
	x = bar_text(x, "%s %d/%d" % [Data.t("wave"), wave_num, Data.NUM_WAVES], 22, Color.WHITE) + 16
	var cd := Data.t("go") if wave_active else Data.t("next_in") % cd_sec
	x = bar_text(x, cd, 20, C_OK if wave_active else Color(0.6, 0.85, 1.0)) + 14
	if speed > 1:
		x = bar_text(x, "x%d" % speed, 20, C_GOLD)
	# right to left: the sacks bar, funds, lives, score
	var rx := PF_W - 180.0
	var hpcol := C_BAD if hp < 30 else Color.WHITE
	draw_rect(Rect2(rx, 14, 160, 20), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(rx + 2, 16, 156 * hp / 100.0, 16), C_OK.lerp(C_BAD, 1.0 - hp / 100.0))
	text(Vector2(rx, 31), "%s %d" % [Data.t("hp"), hp], 16, hpcol, HORIZONTAL_ALIGNMENT_CENTER, 160)
	rx -= 22
	rx = bar_text_right(rx, "%d" % funds, 24, C_GOLD) - 26
	draw_sprite("sack_full", Vector2(rx + 12, 44), 0.42)
	rx -= 22
	rx = bar_text_right(rx, "%s %d" % [Data.t("lives"), lives], 22, Color(1, 0.6, 0.8)) - 22
	bar_text_right(rx, "%s %05d" % [Data.t("score"), score], 22, Color.WHITE)
	if msg != "":
		var w := Data.font_bold.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 40
		var r := Rect2(PF_W / 2 - w / 2, TOP + 10, w, 40)
		draw_rect(r, Color(0.1, 0.25, 0.75, 0.9))
		draw_rect(r, C_GOLD, false, 2.0)
		text(Vector2(r.position.x, r.position.y + 28), msg, 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)


func draw_bottom_bar() -> void:
	buttons.clear()
	draw_rect(Rect2(0, BOT_Y, PF_W, 1024 - BOT_Y), C_BAR)
	draw_rect(Rect2(0, BOT_Y, PF_W, 3), C_GOLD)
	for i in 6:
		var type: int = Data.TOWER_ORDER[i]
		var tt: Dictionary = Data.TTYPES[type]
		var r := Rect2(8 + i * 108, BOT_Y + 8, 102, 66)
		var key := "def%d" % type
		buttons[key] = r
		var unlocked: bool = type in stage["defenders"]
		var afford := funds >= int(tt["cost"])
		var bg := Color(0.25, 0.22, 0.35)
		if type == selected:
			bg = Color(0.15, 0.45, 0.25)
		elif hover_btn == key:
			bg = Color(0.32, 0.3, 0.45)
		draw_rect(r, bg)
		draw_rect(r, C_GOLD if type == selected else Color(1, 1, 1, 0.25), false, 2.0)
		if unlocked:
			draw_sprite(tt["spr"], r.position + Vector2(30, 60), 0.62, false, Color.WHITE if afford else Color(1, 1, 1, 0.45))
			text(r.position + Vector2(54, 24), "%d" % int(tt["cost"]), 20, C_GOLD if afford else C_BAD)
			text(r.position + Vector2(4, 18), "%d" % (i + 1), 16, Color(1, 1, 1, 0.7))
			var nm := Data.t("name%d" % type)
			var fs := 13
			while fs > 8 and Data.font_bold.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > 50:
				fs -= 1
			text(r.position + Vector2(50, 54), nm, fs, Color.WHITE)
		else:
			draw_sprite(tt["spr"], r.position + Vector2(50, 62), 0.62, false, Color(0, 0, 0, 0.5))
			text(r.position + Vector2(0, 40), "?", 30, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	# the info line: what is under the cursor or selected
	var ix := 664.0
	var info := ""
	var info2 := ""
	var info_col := Color.WHITE
	var tw = tower_at[cursor.y][cursor.x] if mouse_in_field else null
	if tw:
		info = "%s  -  %s" % [Data.t("name%d" % tw.type), Data.t("sell") % int(Data.TTYPES[tw.type]["sell"])]
		if tw.syn:
			info2 = syn_label(tw.syn)
			info_col = C_OK if tw.syn > 16 else C_BAD
	else:
		info = "%s %d: %s" % [Data.t("name%d" % selected), int(Data.TTYPES[selected]["cost"]), Data.t("desc%d" % selected)]
		if mouse_in_field and build_check(cursor.x, cursor.y, selected) in ["", "cant_afford"]:
			var f := syn_factor_at(cursor.x, cursor.y, selected)
			if f and f < 16:
				info2 = syn_label(f)
				info_col = C_BAD
			elif f > 16:
				info2 = syn_label(f) + ("" if syn_count() < Data.SYN_MAX else " " + Data.t("bonus_full"))
				info_col = C_OK if syn_count() < Data.SYN_MAX else Color(0.7, 0.7, 0.7)
	draw_info(Vector2(ix, BOT_Y + 26), info, 15, Color.WHITE, 360)
	if info2 != "":
		text(Vector2(ix, BOT_Y + 70), info2, 15, info_col)
	# buttons
	var bx := PF_W - 250.0
	var labels := [["next", Data.t("next_btn")], ["speed", Data.t("speed_btn") % speed], ["pause", Data.t("pause_btn")]]
	for i in labels.size():
		var r := Rect2(bx, BOT_Y + 6 + i * 24, 240, 22)
		buttons[labels[i][0]] = r
		var dim: bool = labels[i][0] == "next" and wave_active
		draw_rect(r, Color(0.35, 0.3, 0.5) if hover_btn == labels[i][0] else Color(0.22, 0.2, 0.3))
		text(r.position + Vector2(0, 17), labels[i][1], 15, Color(1, 1, 1, 0.35) if dim else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## text on the top bar starting at x; returns where it ends
func bar_text(x: float, s: String, size: int, col: Color, font: Font = null) -> float:
	var f: Font = font if font else Data.font_bold
	text(Vector2(x, 32), s, size, col, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	return x + f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## text on the top bar ending at x; returns where it starts
func bar_text_right(x: float, s: String, size: int, col: Color) -> float:
	var w := Data.font_bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(Vector2(x - w, 32), s, size, col)
	return x - w


func syn_label(f: int) -> String:
	var pct := {19: "+20%", 24: "+50%", 13: "-20%", 8: "-50%"}
	return "%s %s" % [Data.t("neighbour"), pct.get(f, "")]


func draw_info(pos: Vector2, s: String, size: int, col: Color, width: float) -> void:
	draw_multiline_string(Data.font_bold, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, 3, col)


func draw_banner() -> void:
	if paused and not game_over:
		draw_rect(Rect2(0, TOP, PF_W, PF_H), Color(0, 0, 0, 0.45))
		box([Data.t("paused"), Data.t("paused2")])
		var labels := [["continue", Data.t("continue")], ["quit", Data.t("to_title")]]
		for i in 2:
			var r := Rect2(PF_W / 2 - 310 + i * 320, TOP + PF_H / 2 + 60, 300, 64)
			buttons[labels[i][0]] = r
			draw_rect(Rect2(r.position + Vector2(6, 6), r.size), Color(0, 0, 0, 0.35))
			draw_rect(r, Color(0.85, 0.2, 0.15) if i == 1 else Color(0.15, 0.45, 0.25))
			draw_rect(r, C_GOLD if hover_btn == labels[i][0] else Color(1, 1, 1, 0.4), false, 3.0)
			text(r.position + Vector2(0, 42), labels[i][1], 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return
	if banner.is_empty():
		return
	box(banner)


func box(lines: Array) -> void:
	var w := 0.0
	for i in lines.size():
		var sz := 40 if i == 0 else 22
		w = maxf(w, Data.font_bold.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x)
	w = minf(w + 80, PF_W - 40)
	var h := 40.0 + 54 + (lines.size() - 1) * 34
	var r := Rect2(PF_W / 2 - w / 2, TOP + PF_H / 2 - h / 2 - 40, w, h)
	draw_rect(Rect2(r.position + Vector2(8, 8), r.size), Color(0, 0, 0, 0.35))
	draw_rect(r, Color(0.08, 0.2, 0.62, 0.95))
	draw_rect(r, C_GOLD, false, 4.0)
	var y := r.position.y + 58
	for i in lines.size():
		if i == 0:
			text(Vector2(r.position.x, y), lines[i], 40, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER, w, Data.font_title, 8)
			y += 46
		else:
			var blink: bool = game_over and i == lines.size() - 1 and end_wait > 1.2
			var col := Color.WHITE if not blink else Color(1, 1, 1, 0.6 + 0.4 * sin(time * 6.0))
			text(Vector2(r.position.x + 20, y), lines[i], 22, col, HORIZONTAL_ALIGNMENT_CENTER, w - 40)
			y += 34


# ====================================================================== the bot

func bot_tick() -> void:
	if game_over:
		return
	var want: int = BOT_PLAN[bot_step % BOT_PLAN.size()]
	if not want in stage["defenders"]:
		bot_step += 1
	elif funds >= int(Data.TTYPES[want]["cost"]):
		var best := Vector3i(-1, 0, 0)
		var rr: int = Data.TTYPES[want]["range"]
		for r in Data.ROWS:
			for c in Data.COLS:
				if build_check(c, r, want) != "":
					continue
				var cover := 0
				for r2 in range(maxi(0, r - 4), mini(Data.ROWS, r + 5)):
					for c2 in range(maxi(0, c - 4), mini(Data.COLS, c + 5)):
						if cellt[r2][c2] == 1:
							var dx := (c2 - c) * 12
							var dy := (r2 - r) * 12
							if dx * dx + dy * dy <= rr * rr:
								cover += 1
				if cover > best.x:
					best = Vector3i(cover, c, r)
		if best.x > 0:
			var keep := selected
			selected = want
			try_build(best.y, best.z)
			selected = keep
		bot_step += 1
	if not wave_active and cd_sec < (40 if wave_num == 0 else 12):
		call_wave_now()
