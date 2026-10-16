class_name ELDuelReport
extends RefCounted
## The duel report (option VisualLog «Создать отчет о дуэли», second game
## OPC_Autosave "Duel log"): a text record of a Duel mode match appended to
## DuelLog.txt. Only Duel mode matches write it; campaign battles never do.
##
## Layout follows both originals: the framed title, version and start time;
## the competitors, connection and conditions; the local side's preset in full
## and the opponent's race, level and life; then per round a centred heading,
## each turn's state of both heroes in two columns (own side at column 6,
## opponent at column 40), the casts, artifact and ability uses and
## specialisation triggers, and the round result; finally the match score.
## Labels are the edition's T_VL_* texts. Lines end in CRLF as in the
## original file; the text is UTF-8 rather than the original ANSI code page.
## The file lives beside the edition's other duel files (the original writes
## it to the game folder) and is never truncated: every match is appended.

const FILE := "DuelLog.txt"
const WIDTH := 80
const FRAME_LEVEL := 20
## Column of the local side's lines and of the opponent's.
const OWN_COLUMN := 6
const ENEMY_COLUMN := 40
## Version suffix: the first game prints a constant 1.07; the second prints
## "2." and the trailing digits of its product version (1.597 → 597).
const VERSIONS := {"el1": "1.07", "el2": "2.597"}
## Race labels by `Duel\heroes.def` race order (ELDuelPresets.RACES).
const RACE_KEYS := {"Red": "T_VL_CHAOTS", "Green": "T_VL_VITALS", "Blue": "T_VL_KINETS", "Black": "T_VL_SYNTHETS"}
const SKILL_SLOTS := 5

var profile: ELProfile
var path := ""
## The side whose preset is printed in full and whose lines use the left column.
var local_side := 0
## Every line written, in order (also kept for checks).
var lines: PackedStringArray = []
## Clock for the timestamps: returns Time.get_datetime_dict_from_system()'s shape.
var clock := Callable(Time, "get_datetime_dict_from_system")
var _duel: WeakRef
var _pending: PackedStringArray = []

static func folder(edition: String) -> String:
	return "user://duel/%s" % edition

## Opens a report for a starting match and writes its header. `names` are the
## two sides' names; `duel` is the first round's battle (for the heroes' life).
func open(match_profile: ELProfile, duel_match: ELDuelMatch, duel: ELDuel, names: Array, side := 0, file_path := "") -> void:
	profile = match_profile
	local_side = side
	path = file_path if not file_path.is_empty() else folder(profile.id).path_join(FILE)
	var title := _text("T_VL_DUEL_TITLE")
	var blank := " ".repeat(mini(title.length(), 255))
	for text: String in ["  ", " " + blank + " ", "  " + title + "  ", " " + blank + " ", "  "]: _framed(text)
	_line("")
	_centred("%s %s" % [_text("T_VL_VERSION"), VERSIONS.get(profile.id, "")])
	_centred("%s: %s" % [_text("T_VL_ROUND_START_AT"), _stamp()])
	_line("")
	_stars()
	_line("")
	_indented(3, _text("T_VL_COMPETITORS"))
	_line("")
	_indented(6, "%s (%s)" % [str(names[side]), _text("T_VL_MY_HERO")])
	_indented(6, "%s (%s)" % [str(names[1 - side]), _text("T_VL_ENEMY_HERO")])
	_line("")
	_indented(3, _text("T_VL_CONNECTION"))
	_line("")
	# The remake plays duels on one machine only.
	_indented(6, _text("T_VL_CONN_LOCAL"))
	_line("")
	_indented(3, _text("T_VL_CONDITIONS"))
	_line("")
	_indented(6, "%s: %d" % [_text("T_VL_RES_LEV"), duel_match.resource_level])
	_indented(6, "%s: %d" % [_text("T_VL_NUM_OF_ROUNDS"), duel_match.rounds])
	_line("")
	_indented(3, _text("T_VL_MY_HERO_INFO"))
	_line("")
	var mine: Dictionary = duel_match.presets[side]
	_indented(6, "%s: %s" % [_text("T_VL_PRESET_NAME"), str(mine.get("name", ""))])
	_line("")
	_hero_lines(mine, duel.heroes[side])
	_line("")
	_indented(6, "%s:" % _text("T_VL_SPELLS_RUNES"))
	var cards: Array = mine.get("cards", [])
	var runes: Array = mine.get("runes", [])
	for index in cards.size():
		var count := int(runes[index]) if index < runes.size() else -1
		if count == -1: _indented(9, "%2d: %s" % [index + 1, _card(cards[index])])
		else: _indented(9, "%2d: %s (%d)" % [index + 1, _card(cards[index]), count])
	_line("")
	var artifacts: Array = mine.get("artifacts", [])
	if not artifacts.is_empty():
		_indented(6, "%s:" % _text("T_VL_ARTEFACTS"))
		for index in artifacts.size(): _indented(9, "%2d: %s" % [index + 1, _card(artifacts[index])])
		_line("")
	var spec := str(mine.get("specialization", "NONE"))
	if not spec.is_empty() and spec != "NONE":
		_indented(6, "%s:" % _text("T_VL_SPECIALIZATION"))
		_indented(9, _spec(spec))
		_line("")
	var skills: Dictionary = mine.get("skills", {})
	if not skills.is_empty():
		_indented(6, "%s:" % _text("T_VL_SKILLS"))
		# Numbered by slot; a preset fills its slots in order.
		var slot := 0
		for code: String in skills:
			slot += 1
			if slot > SKILL_SLOTS: break
			var rank := int(skills[code])
			_indented(9, "%2d: %s (%d)" % [slot, profile.text(str(ELHeroSkills.definition(profile, code, rank).get("Name", code))), rank + 1])
		_line("")
	_indented(3, _text("T_VL_ENEMY_HERO_INFO"))
	_line("")
	_hero_lines(duel_match.presets[1 - side], duel.heroes[1 - side])
	_line("")
	_stars()
	_line("")
	_flush()

func is_open() -> bool:
	return not path.is_empty()

## A round begins (`number` from 1): its heading and the column legend; the
## report then follows that round's battle.
func round_start(number: int, duel: ELDuel) -> void:
	if not is_open(): return
	_centred(" %s " % _format(_text("T_VL_START_ROUND"), [number]))
	_line("")
	_centred("%s: %s" % [_text("T_VL_ROUND_START_AT"), _stamp()])
	_line("")
	_line(_pad(" ".repeat(OWN_COLUMN) + "==> " + _text("T_VL_MY_HERO"), ENEMY_COLUMN) + "<-- " + _text("T_VL_ENEMY_HERO"))
	_line("")
	_flush()
	_untrack()
	# The battle's opening (its first attack phase) already ran in ELDuel.start.
	for data: Dictionary in duel.history.duplicate(): _on_event(data, duel)
	_duel = weakref(duel)
	duel.event.connect(_on_event.bind(duel))

## The round ended: its finish time and winner (-1 for a draw).
func round_end(winner: int) -> void:
	if not is_open(): return
	_untrack()
	_line("")
	_centred("%s: %s" % [_text("T_VL_ROUND_FINISH_AT"), _stamp()])
	_line("")
	if winner < 0: _centred(" %s " % _text("T_VL_ROUND_DRAW"))
	elif winner == local_side: _centred(" %s " % _format(_text("T_VL_ROUND_WIN"), [_text("T_VL_MY_HERO")]))
	# The original writes the opponent's win without the surrounding spaces.
	else: _centred(_format(_text("T_VL_ROUND_WIN"), [_text("T_VL_ENEMY_HERO")]))
	_line("")
	_stars()
	_line("")
	_flush()

## The match is over: the score of the rounds played; the report closes.
func finish(duel_match: ELDuelMatch) -> void:
	if not is_open(): return
	_untrack()
	var own := int(duel_match.wins[local_side])
	var other := int(duel_match.wins[1 - local_side])
	var result := _text("T_VL_MATCH_DRAW")
	if own > other: result = _format(_text("T_VL_MATCH_WIN"), [_text("T_VL_MY_HERO")])
	elif other > own: result = _format(_text("T_VL_MATCH_WIN"), [_text("T_VL_ENEMY_HERO")])
	_centred(_text("T_VL_RESULT_TITLE"))
	_line("")
	_centred("%s %s = %d : %d" % [result, _text("T_VL_SCORE"), own, other])
	_line("")
	_stars()
	_line("")
	_line("")
	_flush()
	path = ""

## Stops following a battle without writing anything (the match was dropped).
func close() -> void:
	_untrack()
	path = ""

func _untrack() -> void:
	var duel: ELDuel = _duel.get_ref() if _duel != null else null
	if duel != null and duel.event.is_connected(_on_event): duel.event.disconnect(_on_event)
	_duel = null

func _on_event(data: Dictionary, duel: ELDuel) -> void:
	if not is_open(): return
	match str(data.get("kind", "")):
		"phase":
			if data.get("phase") == "attack": _turn(duel, int(data.side), int(data.get("round", 1)))
		"cast":
			_detail(int(data.side), _format(_text("T_VL_CASTING"), [duel.card_name(str(data.card))]))
		"artifact":
			_detail(int(data.side), _format(_text("T_VL_USE_ARTEFACT"), [str(data.get("title", duel.card_name(str(data.card))))]))
		"ability":
			# A hero's ability comes from an enchantment on it; a creature's is its own.
			var source := int(data.get("source", data.side))
			if source < 2: _detail(int(data.side), _format(_text("T_VL_USE_ENCHANTMENT"), [str(data.get("name", str(data.get("ability", "")).capitalize()))]))
			else: _detail(int(data.side), _format(_text("T_VL_USE_ABILITY"), [duel.card_name(str(duel.entity(source).get("card", "")))]))
		"spec":
			_detail(int(data.side), _format(_text("T_VL_SPEC_WORKED"), [_spec(str(data.spec))]))
		_: return
	_flush()

## A side's attack phase begins: the turn number in the acting side's column,
## then both heroes' state, side 0 first, each in its own column.
func _turn(duel: ELDuel, acting: int, number: int) -> void:
	var own := acting == local_side
	_indented(OWN_COLUMN if own else ENEMY_COLUMN, ("==> " if own else "<-- ") + _format(_text("T_VL_TURN_NUMBER"), [number]))
	for side in 2:
		var hero: Dictionary = duel.heroes[side]
		_detail(side, "%s: %d" % [_text("T_VL_CURRENT_HEALTH"), int(hero.health)])
		_detail(side, "%s: %d" % [_text("T_VL_MANA_LINKS"), int(hero.channels)])
		_detail(side, "%s: %d" % [_text("T_VL_HAND"), hero.hand.size()])
		# Only the local side's cards are named.
		if side == local_side:
			for card: Variant in hero.hand: _detail(side, "  %s" % duel.card_name(str(card)))
		var army: Array = duel.creatures.values().filter(func(c: Dictionary) -> bool: return int(c.owner) == side)
		_detail(side, "%s: %d" % [_text("T_VL_ARMY"), army.size()])
		for c: Dictionary in army: _detail(side, "  %s %d/%d" % [duel.card_name(str(c.card)), int(c.power), int(c.toughness)])
		_detail(side, "%s: %d" % [_text("T_VL_GRAVEYARD"), hero.grave.size()])

func _hero_lines(preset: Dictionary, hero: Dictionary) -> void:
	_indented(6, "%s: %s" % [_text("T_VL_HERO_RACE"), _text(RACE_KEYS[preset.faction]) if RACE_KEYS.has(preset.get("faction")) else "undefined"])
	_indented(6, "%s: %d" % [_text("T_VL_HERO_LEV"), int(preset.get("level", hero.get("level", 1)))])
	_indented(6, "%s: %d" % [_text("T_VL_HERO_LIFE"), int(hero.get("maximum", hero.get("health", 0)))])

func _detail(side: int, text: String) -> void:
	_indented(OWN_COLUMN if side == local_side else ENEMY_COLUMN, "    " + text)

func _indented(indent: int, text: String) -> void:
	_line(" ".repeat(clampi(indent, 0, WIDTH)) + text)

func _centred(text: String) -> void:
	_line(" ".repeat(maxi((WIDTH - text.length()) / 2, 0)) + text)

## The title box lines: left fill '=' up to '>', right fill '-' after '<'.
func _framed(text: String) -> void:
	var pad := (WIDTH - text.length()) / 2
	if pad <= FRAME_LEVEL + 3:
		_centred(text)
		return
	_line(" ".repeat(FRAME_LEVEL) + "=".repeat(pad - FRAME_LEVEL - 1) + ">" + text + "<" + "-".repeat(maxi(WIDTH - pad - text.length() - FRAME_LEVEL - 1, 0)))

func _stars() -> void:
	_line("*".repeat(WIDTH))

func _line(text: String) -> void:
	lines.append(text)
	_pending.append(text)

static func _pad(text: String, width: int) -> String:
	return text + " ".repeat(maxi(width - text.length(), 0))

func _stamp() -> String:
	var now: Dictionary = clock.call()
	return "%4d/%02d/%02d %2d:%02d:%02d" % [int(now.year), int(now.month), int(now.day), int(now.hour), int(now.minute), int(now.second)]

func _text(key: String) -> String:
	return profile.text(key).strip_edges()

func _card(code: Variant) -> String:
	return profile.text(str(profile.table("CombatSpells").get(str(code), {}).get("Name", str(code))))

func _spec(code: String) -> String:
	return profile.text(str(profile.table("HeroesSpecs").get(code, {}).get("Name", code)))

## Fills %s / %d fields in order (the original printf on a T_VL text).
static func _format(text: String, args: Array) -> String:
	for value: Variant in args:
		var at := text.find("%")
		while at >= 0 and at + 1 < text.length() and not text[at + 1] in ["s", "d", "i"]: at = text.find("%", at + 1)
		if at < 0 or at + 1 >= text.length(): break
		text = text.substr(0, at) + str(value) + text.substr(at + 2)
	return text

## Appends the new lines to the file (the original flushes every line).
func _flush() -> void:
	if _pending.is_empty() or path.is_empty(): return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Duel report: cannot write " + path)
		_pending.clear()
		return
	file.seek_end()
	file.store_string("\r\n".join(_pending) + "\r\n")
	file.close()
	_pending.clear()
