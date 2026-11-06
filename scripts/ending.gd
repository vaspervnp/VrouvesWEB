extends Node2D
## The ending: the whole village at a feast in front of the school (rendered in Blender
## from the CPC version's ending scene).

signal done

const W := 1280.0
const H := 1024.0

var score := 0
var time := 0.0
var pic: Texture2D


func _ready() -> void:
	pic = load("res://art/ending.png") if ResourceLoader.exists("res://art/ending.png") else Data.stage_tex(5)
	Sfx.play("wave")


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _unhandled_input(ev: InputEvent) -> void:
	if time < 2.0:
		return
	if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventKey and ev.pressed and ev.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]):
		done.emit()


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.35, 0.65, 1.0))
	var s := pic.get_size()
	var sc := W / s.x
	draw_texture_rect(pic, Rect2(0, 120, W, s.y * sc), false)
	var f := Data.font_title
	draw_string_outline(f, Vector2(0, 90), Data.stage_text(7, 1), HORIZONTAL_ALIGNMENT_CENTER, W, 56, 14, Color.BLACK)
	draw_string(f, Vector2(0, 90), Data.stage_text(7, 1), HORIZONTAL_ALIGNMENT_CENTER, W, 56, Color(1, 0.85, 0.2))
	var y := 120 + s.y * sc + 50
	for line in [Data.t("ending"), Data.t("ending2"), Data.t("final_score") % score]:
		draw_string_outline(Data.font_bold, Vector2(0, y), line, HORIZONTAL_ALIGNMENT_CENTER, W, 28, 8, Color.BLACK)
		draw_string(Data.font_bold, Vector2(0, y), line, HORIZONTAL_ALIGNMENT_CENTER, W, 28, Color.WHITE)
		y += 42
	if time > 2.0:
		var a := 0.6 + 0.4 * sin(time * 5.0)
		draw_string(Data.font_bold, Vector2(0, H - 24), Data.t("press"), HORIZONTAL_ALIGNMENT_CENTER, W, 22, Color(1, 1, 1, a))
	# confetti
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 80:
		var x := fposmod(rng.randf() * W + sin(time + i) * 30.0, W)
		var yy := fposmod(rng.randf() * H + time * (60.0 + rng.randf() * 80.0), H)
		var col := Color.from_hsv(rng.randf(), 0.8, 1.0)
		draw_rect(Rect2(x, yy, 8, 12), col)
