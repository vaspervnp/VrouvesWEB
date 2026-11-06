extends Node
## The flow of a game: title -> stages 1..7 -> ending -> high score -> title.
## Lives last the whole game; a stage lost with a life left is played again with the
## score it started with. On GamePix an ad plays between stages and after a game.

const Game := preload("res://scripts/game.gd")
const Title := preload("res://scripts/title.gd")
const Ending := preload("res://scripts/ending.gd")

var screen: Node
var stage_no := 1
var score := 0
var stage_score := 0
var lives := 0
var perf := false
var frames := 0
var slow_frames := 0
var worst := 0.0
var perf_t := 0.0


## --perf: count the frames that took much longer than the screen's refresh
func _process(delta: float) -> void:
	if not perf:
		return
	frames += 1
	perf_t += delta
	worst = maxf(worst, delta)
	if frames > 30 and delta > 1.5 / DisplayServer.screen_get_refresh_rate():
		slow_frames += 1
	if perf_t >= 5.0:
		print("perf: %d frames in %.1f s (%.1f fps), %d slow, worst %.1f ms, refresh %.0f Hz" % [frames, perf_t,
			frames / perf_t, slow_frames, worst * 1000.0, DisplayServer.screen_get_refresh_rate()])
		frames = 0
		slow_frames = 0
		worst = 0.0
		perf_t = 0.0


func _ready() -> void:
	Gpx.loaded()
	var args := OS.get_cmdline_user_args()
	if "--shots" in args:
		# a picture of the screen every few seconds, for testing
		var dir: String = args[args.find("--shots") + 1]
		var n := [0]
		var tm := Timer.new()
		tm.wait_time = 3.0
		tm.timeout.connect(func():
			n[0] += 1
			get_viewport().get_texture().get_image().save_png(dir.path_join("shot_%02d.png" % n[0])))
		add_child(tm)
		tm.start()
	if "--exit" in args:
		get_tree().create_timer(float(args[args.find("--exit") + 1])).timeout.connect(get_tree().quit)
	if "--perf" in args:
		perf = true
	if "--lang" in args:
		# en or gr, for this run only (not saved)
		Data.lang = 1 if args[args.find("--lang") + 1] == "gr" else 0
	if "--music" in args:
		Data.music_on = true            # for this run only, as --lang
	if "--autotest" in args:
		add_child(load("res://tests/autoplay.gd").new())
	elif "--ending" in args:
		# the ending screen with a score, for recording it
		var e: Node = Ending.new()
		e.score = int(args[args.find("--ending") + 1])
		e.done.connect(func(): game_ended(e.score))
		swap(e)
	elif "--stage" in args:
		stage_no = int(args[args.find("--stage") + 1])
		lives = 3
		start_stage()
	else:
		show_title()


func swap(node: Node) -> void:
	if screen:
		screen.queue_free()
	screen = node
	add_child(node)


func show_title(page := "", entry_score := -1) -> void:
	var t: Node = Title.new()
	t.page_on_start = page
	t.entry_score = entry_score
	t.start_game.connect(new_game)
	swap(t)


func new_game() -> void:
	Gpx.game_start()
	stage_no = 1
	score = 0
	stage_score = 0
	lives = Data.DIFFICULTY_LIVES[Data.difficulty]
	start_stage()


func start_stage() -> void:
	Gpx.level(stage_no)
	var g: Node2D = Game.new()
	g.setup(stage_no, stage_score, lives)
	if "--bot" in OS.get_cmdline_user_args():
		g.bot = true
		var a := OS.get_cmdline_user_args()
		g.speed = int(a[a.find("--botspeed") + 1]) if "--botspeed" in a else 3
		if "--funds" in a:
			# a richer start, to fill the map sooner when recording a video
			g.funds = int(a[a.find("--funds") + 1])
	g.finished.connect(_on_stage_finished.bind(g))
	swap(g)


func _on_stage_finished(result: String, s: int, g: Node) -> void:
	print("stage %d %s score %d" % [stage_no, result, s])
	# the life the player won by watching an ad; that ad is the one between stages too
	var rewarded: bool = g.reward == 2
	if rewarded:
		lives += 1
	if result == "won":
		Gpx.happy("level_complete")
	elif result == "lost":
		Gpx.sad("level_failed" if lives > 0 else "game_over")
	if result != "quit" and not rewarded:
		await Gpx.interstitial()
	match result:
		"won":
			score = s
			stage_score = s
			if stage_no >= Data.stages.size():
				var e: Node = Ending.new()
				e.score = score
				e.done.connect(func(): game_ended(score))
				swap(e)
			else:
				stage_no += 1
				start_stage()
		"lost":
			if lives > 0:
				lives -= 1
				start_stage()
			else:
				game_ended(s)
		_:
			game_ended(s)


func game_ended(s: int) -> void:
	Gpx.score(s)
	Sfx.music(false)
	if Data.hiscore_rank(s) >= 0:
		show_title("enter", s)
	else:
		show_title("hiscores")
