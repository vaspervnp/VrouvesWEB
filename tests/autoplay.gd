extends Node
## Headless test: plays every stage with a simple greedy build order and prints how each
## wave goes. Run the game with
##   godot --headless --path . -- --autotest [stage ...]

const Game := preload("res://scripts/game.gd")


func _ready() -> void:
	var which: Array = []
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			which.append(int(a))
	if which.is_empty():
		which = [1, 2, 3, 4, 5, 6, 7]
	var all_ok := true
	for n in which:
		all_ok = play(n) and all_ok
	print("RESULT ", "ALL WON" if all_ok else "SOME LOST")
	get_tree().quit(0 if all_ok else 1)


## buildable cells, best first: how many road or flight cells each would cover
func spots(g, type: int) -> Array:
	var out := []
	var rr: int = Data.TTYPES[type]["range"]
	for r in Data.ROWS:
		for c in Data.COLS:
			if g.build_check(c, r, type) not in ["", "cant_afford"]:
				continue
			var cover := 0
			for r2 in Data.ROWS:
				for c2 in Data.COLS:
					if g.cellt[r2][c2] == 1:
						var dx := (c2 - c) * 12
						var dy := (r2 - r) * 12
						if dx * dx + dy * dy <= rr * rr:
							cover += 1
			out.append([cover, c, r])
	out.sort_custom(func(a, b): return a[0] > b[0])
	return out


func play(n: int) -> bool:
	var g = Game.new()
	g.setup(n, 0, 3)
	add_child(g)
	g.set_process(false)
	var plan := [Data.CRETAN, Data.CRETAN, Data.PSSSST, Data.CRETAN, Data.BRIDE, Data.YIAYIA, Data.BAKER,
		Data.CAULDRON, Data.CRETAN, Data.BRIDE, Data.PSSSST]
	var step := 0
	var ticks := 0
	var last_wave := 0
	while not g.game_over and ticks < 25 * 60 * 40:
		var want: int = plan[step % plan.size()]
		if not want in g.stage["defenders"]:
			step += 1
			continue
		if g.funds >= int(Data.TTYPES[want]["cost"]):
			var s := spots(g, want)
			if not s.is_empty():
				g.selected = want
				g.try_build(s[0][1], s[0][2])
			step += 1
		if not g.wave_active and g.wave_num > 0 and g.cd_sec < 13:
			g.call_wave_now()
		if g.wave_num == 0 and g.cd_sec < 40:
			g.call_wave_now()
		g.game_tick()
		ticks += 1
		if g.wave_num != last_wave:
			last_wave = g.wave_num
			var nt := 0
			for t in g.towers:
				if t:
					nt += 1
			print("  stage %d wave %d  hp %3d funds %4d score %5d towers %d" % [n, g.wave_num, g.hp, g.funds, g.score, nt])
	var won: bool = g.game_over == 1
	print("STAGE %d %s  hp %d score %d after %d s" % [n, "WON" if won else "LOST", g.hp, g.score, ticks / 25])
	g.queue_free()
	return won
