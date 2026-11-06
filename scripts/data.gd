extends Node
## Everything the game knows before it starts: the stages (data/stages.json, from the CPC
## original), the invader and defender tables, the texts in English and Greek, the settings
## and the high scores.

const COLS := 20
const ROWS := 14
const UNITS := 12                       # path steps (and range units) per cell
const TICK := 1.0 / 25.0                # one logic tick, as on the CPC
const NUM_WAVES := 10
const START_FUNDS := 120
const START_HP := 100
const FIRST_COUNTDOWN := 45
const NEXT_COUNTDOWN := 15
const MAX_ENEMIES := 16
const SYN_MAX := 3

enum { DRONE = 1, GUARD = 2, TANK = 3 }
enum { CRETAN = 1, YIAYIA = 2, BRIDE = 3, PSSSST = 4, CAULDRON = 5, BAKER = 6 }

## base hp, hp per wave, speed (1/16 step per tick), armour, reward, base damage (= points)
const ETYPES := {
	DRONE: {"hp": 6, "hpw": 3, "spd": 20, "arm": 0, "reward": 3, "dmg": 4, "name": "drone"},
	GUARD: {"hp": 16, "hpw": 8, "spd": 9, "arm": 2, "reward": 4, "dmg": 8, "name": "guard"},
	TANK: {"hp": 50, "hpw": 19, "spd": 7, "arm": 4, "reward": 10, "dmg": 20, "name": "tank"},
}

## cost, range (units), cooldown (ticks), damage, hits air, projectile, sound, sell value
const TTYPES := {
	CRETAN: {"cost": 35, "range": 30, "cd": 18, "dmg": 6, "air": true, "proj": "bullet", "sfx": "rifle", "sell": 17, "spr": "cretan"},
	YIAYIA: {"cost": 50, "range": 18, "cd": 22, "dmg": 14, "air": false, "proj": "", "sfx": "bash", "sell": 25, "spr": "yiayia"},
	BRIDE: {"cost": 70, "range": 28, "cd": 6, "dmg": 4, "air": true, "proj": "heart", "sfx": "pistol", "sell": 35, "spr": "bride"},
	PSSSST: {"cost": 80, "range": 36, "cd": 10, "dmg": 5, "air": true, "proj": "laser", "sfx": "laser", "sell": 40, "spr": "psssst"},
	CAULDRON: {"cost": 110, "range": 22, "cd": 32, "dmg": 8, "air": false, "proj": "", "sfx": "puff", "sell": 55, "spr": "cauldron"},
	BAKER: {"cost": 60, "range": 34, "cd": 36, "dmg": 16, "air": true, "proj": "dakos", "sfx": "throw", "sell": 30, "spr": "baker"},
}
## the order of the toolbar, as the keys 1-6
const TOWER_ORDER := [CRETAN, YIAYIA, BRIDE, PSSSST, CAULDRON, BAKER]

## neighbour bonus: defender -> [partner, factor in 1/16]
const SYNERGY := {YIAYIA: [BAKER, 19], BRIDE: [CRETAN, 24], PSSSST: [CRETAN, 13], BAKER: [CRETAN, 8]}

## the difficulties in the order D goes through them: lives for the whole game
const DIFFICULTY_LIVES := [3, 2, 0, 4]

var stages: Array = []
var lang := 0                           # 0 English, 1 Greek
var music_on := true
var difficulty := 0
var hiscores: Array = []

var font_title: Font = preload("res://art/fonts/NotoSansDisplay-Black.ttf")
var font_bold: Font = preload("res://art/fonts/NotoSans-Bold.ttf")
var font_text: Font = preload("res://art/fonts/NotoSans-Regular.ttf")

var _tex := {}

const DEFAULT_HISCORES := [["VAS", 6000], ["ZON", 5000], ["KRI", 4000], ["YIA", 3000],
	["NYF", 2500], ["FOU", 2000], ["PAP", 1500], ["KAT", 1000]]


func _ready() -> void:
	var f := FileAccess.open("res://data/stages.json", FileAccess.READ)
	stages = JSON.parse_string(f.get_as_text())["stages"]
	# JSON numbers come back as floats
	for st in stages:
		st["defenders"] = st["defenders"].map(func(v): return int(v))
		st["toughness"] = int(st["toughness"])
	load_settings()
	load_hiscores()
	preload_art()


## load every sprite now: loading one the first time it shows up stalls a frame
func preload_art() -> void:
	for f in DirAccess.get_files_at("res://art/sprites"):
		f = f.trim_suffix(".import").trim_suffix(".remap")
		if f.ends_with(".png"):
			tex(f.get_basename())


func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://art/sprites/%s.png" % name)
	return _tex[name]


func stage_tex(n: int) -> Texture2D:
	var path := "res://art/stages/stage%d.png" % n
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		return ResourceLoader.load_threaded_get(path)
	return load(path)


## start loading a stage's picture in the background, so starting it does not stall
func prefetch_stage(n: int) -> void:
	if n >= 1 and n <= stages.size():
		ResourceLoader.load_threaded_request("res://art/stages/stage%d.png" % n)


# ------------------------------------------------------------------ settings

## saved by Gpx (localStorage on the web); the first time, the language is the one GamePix
## knows the player by
func load_settings() -> void:
	var c = Gpx.load_json("settings")
	if c is Dictionary:
		lang = int(c.get("lang", 0))
		music_on = bool(c.get("music", true))
		difficulty = int(c.get("difficulty", 0))
	else:
		lang = 1 if Gpx.lang() == "el" or (Gpx.lang() == "" and OS.get_locale_language() == "el") else 0


func save_settings() -> void:
	Gpx.save_text("settings", JSON.stringify({"lang": lang, "music": music_on, "difficulty": difficulty}))


func toggle_lang() -> void:
	lang = 1 - lang
	save_settings()


# ------------------------------------------------------------------ high scores

func load_hiscores() -> void:
	hiscores = DEFAULT_HISCORES.duplicate(true)
	var h = Gpx.load_json("hiscores")
	if h is Array and h.size() == 8:
		hiscores = h


func save_hiscores() -> void:
	Gpx.save_text("hiscores", JSON.stringify(hiscores))


func hiscore_rank(score: int) -> int:
	for i in hiscores.size():
		if score > int(hiscores[i][1]):
			return i
	return -1


func add_hiscore(name: String, score: int) -> int:
	var i := hiscore_rank(score)
	if i < 0:
		return -1
	hiscores.insert(i, [name, score])
	hiscores.resize(8)
	save_hiscores()
	return i


# ------------------------------------------------------------------ texts

## id -> [English, Greek]
const TEXT := {
	"title": ["Let's Go For Vrouves", "Πάμε για Βρούβες"],
	"subtitle": ["Defend the bitter greens of Zoniana!", "Σώστε τα πικρά χόρτα των Ζωνιανών!"],
	"start": ["Start", "Έναρξη"],
	"howto": ["How to play", "Οδηγίες"],
	"story_t": ["The story", "Η ιστορία"],
	"defenders_t": ["The defenders", "Οι υπερασπιστές"],
	"invaders_t": ["The invaders of F&M Co.", "Οι εισβολείς της F&M Co."],
	"hiscores_t": ["High scores", "Καλύτερα σκορ"],
	"quit": ["Quit", "Έξοδος"],
	"continue": ["Continue", "Συνέχεια"],
	"to_title": ["Back to the title", "Επιστροφή στον τίτλο"],
	"language": ["Ελληνικά", "English"],
	"music": ["Music: ON", "Μουσική: ΝΑΙ"],
	"music_off": ["Music: OFF", "Μουσική: ΟΧΙ"],
	"dif0": ["Difficulty: Medium - 3 lives", "Δυσκολία: Μέτρια - 3 ζωές"],
	"dif1": ["Difficulty: Hard - 2 lives", "Δυσκολία: Δύσκολη - 2 ζωές"],
	"dif2": ["Difficulty: Hardest - no lives", "Δυσκολία: Πολύ δύσκολη - 0 ζωές"],
	"dif3": ["Difficulty: Easy - 4 lives", "Δυσκολία: Εύκολη - 4 ζωές"],
	"credit": ["REVIVE8BIT - 2026 - VASPER", "REVIVE8BIT - 2026 - VASPER"],
	"back": ["Back", "Πίσω"],
	"story": ["Armed with EU Directive 8647/2026, the corporate Goliaths at Frankenstein & Moreau Co. are deploying bio-drones, hazard squads and heavy machinery to destroy 'vrouves' - the wild, 'copyrighted' mountain greens of Crete.\n\nIn the village of Zoniana, deploy the defenders to protect the kafenio and its precious sacks of bitter greens!\n\nLuckily the rebel corporate drone Psssst has defected, and fights alongside the heavily fortified villagers.",
		"Οπλισμένοι με την Οδηγία ΕΕ 8647/2026, οι κολοσσοί της Frankenstein & Moreau Co. στέλνουν βιο-ντρον, συνεργεία και βαριά μηχανήματα για να ξεριζώσουν τις 'βρούβες' - τα άγρια, 'κατοχυρωμένα' χόρτα των βουνών της Κρήτης.\n\nΣτα Ζωνιανά, στήσε τους υπερασπιστές για να προστατέψεις το καφενείο και τα πολύτιμα σακιά με τα πικρά χόρτα!\n\nΕυτυχώς το επαναστατημένο ντρον Ψσσστ αυτομόλησε και πολεμά δίπλα στους οχυρωμένους χωριανούς."],
	"controls": ["Mouse or touch: choose a defender below, then click or tap a tile to build. Click or tap a defender twice to sell it.\nKeys: arrows / QAOP move, SPACE builds, 1-6 choose, S sells, N calls the next wave, F speeds up, H pauses, L language, M music, ESC menu.",
		"Ποντίκι ή αφή: διάλεξε υπερασπιστή κάτω και πάτα ένα τετράγωνο για να χτίσεις. Πάτα δύο φορές έναν υπερασπιστή για να τον πουλήσεις.\nΠλήκτρα: βελάκια / QAOP κίνηση, SPACE χτίσιμο, 1-6 επιλογή, S πούλημα, N επόμενο κύμα, F γρήγορα, H παύση, L γλώσσα, M μουσική, ESC μενού."],
	"synergy_help": ["Neighbours matter! Bride next to a Cretan +50%, Yiayia next to a Baker +20%, Baker next to a Cretan -50%, Psssst next to a Cretan -20%. At most three bonuses at a time.",
		"Οι γείτονες μετράνε! Νύφη δίπλα σε Κρητικό +50%, Γιαγιά δίπλα σε Φούρναρη +20%, Φούρναρης δίπλα σε Κρητικό -50%, Ψσσστ δίπλα σε Κρητικό -20%. Το πολύ τρία μπόνους μαζί."],
	"name1": ["Cretan", "Κρητικός"],
	"name2": ["Yiayia", "Γιαγιά"],
	"name3": ["Bride", "Νύφη"],
	"name4": ["Psssst", "Ψσσστ"],
	"name5": ["Cauldron", "Καζάνι"],
	"name6": ["Baker", "Φούρναρης"],
	"desc1": ["In midnight black. Hunting rifle, hits drones and walkers.", "Μαυροφόρος με κυνηγετικό τουφέκι. Χτυπά ντρον και πεζούς."],
	"desc2": ["Staff of chastisement and a pot of bitter leaves: slows everyone near her.", "Μαγκούρα και πικρά χόρτα: φρενάρει όλους γύρω της."],
	"desc3": ["Wedding white, rapid pistol. One shot in four is a triple critical.", "Νυφικό και γρήγορο πιστόλι. Μία στις τέσσερις, τριπλή ζημιά."],
	"desc4": ["The defected drone. Laser melts armour. Hovers over walls and trees.", "Το αυτόμολο ντρον. Λέιζερ που λιώνει θώρακες. Πετά πάνω από τοίχους."],
	"desc5": ["Unlicensed lipids & ascorbic acids: toxic area cloud, ignores armour.", "Αδειοδότητα λιπίδια & ασκορβικά: τοξικό σύννεφο, αγνοεί θώρακες."],
	"desc6": ["Hurls dakos (barley rusks) that splash everything around.", "Πετάει ντάκους (κριθαροκούλουρα) που πιτσιλάνε τα πάντα."],
	"ename1": ["Bio-drone", "Βιο-ντρον"],
	"ename2": ["Compliance guard", "Φύλακας συμμόρφωσης"],
	"ename3": ["Weed destroyer", "Καταστροφέας χόρτων"],
	"edesc1": ["Fast and fragile. Flies straight over the walls. Yiayia and the cauldron can't reach it.", "Γρήγορο, εύθραυστο. Πετά πάνω από τους τοίχους. Γιαγιά και καζάνι δεν το φτάνουν."],
	"edesc2": ["Armoured walker with a weed-whacker and herbicide.", "Θωρακισμένος πεζός με χορτοκοπτικό και ζιζανιοκτόνο."],
	"edesc3": ["Treaded tank with lots of health. Dents cauldrons next to the road.", "Ερπυστριοφόρο με πολλή ζωή. Στραβώνει τα καζάνια δίπλα στο δρόμο."],
	"score": ["Score", "Σκορ"],
	"lives": ["Lives", "Ζωές"],
	"wave": ["Wave", "Κύμα"],
	"funds": ["Vrouves", "Βρούβες"],
	"hp": ["Sacks", "Σακιά"],
	"next_in": ["Next in %d", "Επόμενο σε %d"],
	"go": ["GO!", "ΠΑΜΕ!"],
	"next_btn": ["Next wave (N)", "Νέο κύμα (N)"],
	"speed_btn": ["Speed x%d (F)", "Ταχύτητα x%d (F)"],
	"pause_btn": ["Pause (H)", "Παύση (H)"],
	"sell": ["Tap again / S: sell for +%d", "Πάτα ξανά / S: πούλα για +%d"],
	"locked": ["Joins in a later stage", "Έρχεται σε επόμενη πίστα"],
	"cant_afford": ["Not enough vrouves!", "Δεν φτάνουν οι βρούβες!"],
	"cant_build": ["Can't build there", "Δεν χτίζεται εδώ"],
	"only_psssst": ["Only Psssst can hover here", "Μόνο το Ψσσστ πετάει εδώ"],
	"neighbour": ["Neighbour bonus", "Μπόνους γειτονιάς"],
	"bonus_full": ["(bonus places full)", "(γεμάτες οι θέσεις μπόνους)"],
	"call": ["Build, then call the next wave", "Χτίσε και κάλεσε το επόμενο κύμα"],
	"clear": ["Wave cleared! Bonus vrouves!", "Το κύμα αποκρούστηκε! Μπόνους!"],
	"final": ["Final wave! Here come the tanks!", "Τελικό κύμα! Έρχονται τα τανκς!"],
	"newdef": ["A new defender joins the village!", "Νέος αμυντικός στο χωριό!"],
	"press": ["Click, tap or press SPACE", "Κλικ, άγγιγμα ή SPACE"],
	"paused": ["Paused", "Παύση"],
	"paused2": ["H: continue    ESC: back to the title", "H: συνέχεια    ESC: επιστροφή στον τίτλο"],
	"gameover": ["Game over", "Τέλος παιχνιδιού"],
	"reward_btn": ["Watch an ad: +1 life", "Δες διαφήμιση: +1 ζωή"],
	"reward_wait": ["The ad is playing...", "Παίζει η διαφήμιση..."],
	"reward_none": ["No ad right now", "Δεν υπάρχει διαφήμιση τώρα"],
	"life_won": ["+1 life! Try the stage again!", "+1 ζωή! Ξανά από την αρχή!"],
	"life_lost": ["You lose a life. Try the stage again!", "Χάνεις μια ζωή. Ξανά από την αρχή!"],
	"newhs": ["New high score!", "Νέο ρεκόρ!"],
	"entername": ["Type or tap your name (3 letters), then OK", "Γράψε ή πάτα το όνομά σου (3 γράμματα) και OK"],
	"ok": ["OK", "OK"],
	"del": ["Delete", "Σβήσε"],
	"ending": ["The whole village celebrates with a feast in front of the school!", "Όλο το χωριό γιορτάζει με τραπέζι μπροστά στο σχολείο!"],
	"ending2": ["The vrouves of Crete are safe. Kali orexi!", "Οι βρούβες της Κρήτης σώθηκαν. Καλή όρεξη!"],
	"final_score": ["Final score: %d", "Τελικό σκορ: %d"],
}


func t(id: String) -> String:
	if TEXT.has(id):
		return TEXT[id][lang]
	return id


## per stage: name, won, lost
const STAGE_TEXT := [
	[["Stage 1: The Kafenio", "Πίστα 1: Το καφενείο"],
		["Kafenio saved! Now, to the church!", "Το καφενείο σώθηκε! Στην εκκλησία!"],
		["The kafenio has fallen!", "Το καφενείο έπεσε!"]],
	[["Stage 2: The village church", "Πίστα 2: Η εκκλησία του χωριού"],
		["Church saved! Now, to the town hall!", "Η εκκλησία σώθηκε! Στο δημαρχείο!"],
		["The church has fallen!", "Η εκκλησία έπεσε!"]],
	[["Stage 3: The town hall", "Πίστα 3: Το δημαρχείο"],
		["Town hall saved! Now, to the bakery!", "Το δημαρχείο σώθηκε! Στο φούρνο!"],
		["The town hall has fallen!", "Το δημαρχείο έπεσε!"]],
	[["Stage 4: The bakery", "Πίστα 4: Ο φούρνος"],
		["Bakery saved! Now, to the school!", "Ο φούρνος σώθηκε! Στο σχολείο!"],
		["The bakery has fallen!", "Ο φούρνος έπεσε!"]],
	[["Stage 5: The school", "Πίστα 5: Το σχολείο"],
		["School saved! Now, to the pitch!", "Το σχολείο σώθηκε! Στο γήπεδο!"],
		["The school has fallen!", "Το σχολείο έπεσε!"]],
	[["Stage 6: The village pitch", "Πίστα 6: Το γήπεδο του χωριού"],
		["Pitch saved! Now, to the cemetery!", "Το γήπεδο σώθηκε! Στο νεκροταφείο!"],
		["The pitch has fallen!", "Το γήπεδο έπεσε!"]],
	[["Stage 7: The cemetery church", "Πίστα 7: Η εκκλησία του νεκροταφείου"],
		["Victory! The vrouves are safe!", "Νίκη! Οι βρούβες σώθηκαν!"],
		["The cemetery church has fallen!", "Η εκκλησία του νεκροταφείου έπεσε!"]],
]


## what = 0 name, 1 won, 2 lost
func stage_text(stage_no: int, what: int) -> String:
	return STAGE_TEXT[stage_no - 1][what][lang]
