class_name ELFirstTutorial
extends RefCounted
## First game's contextual tutorial (CTutorialScreen): 31 events, each with a
## TUT_<name> body and TUT_<name>_C caption. An event shows once, ever: the
## seen flags are the "tutorial_events" string of the edition's settings (one
## '0'/'1' per event id, the original settings.ini TutorialEvents key), saved
## as soon as an event fires. "show_tutorial" (Options "Обучение") gates the
## automatic events only; H, Clear and the panel's own browsing still work.
## Shown events form a history, browsed per screen: adventure events on the
## map, combat events in battle.

signal shown(category: int)

const ADVENTURE := 1
const COMBAT := 2
## Event id -> [name, category], in the original order.
const EVENTS := [
	["ADVENTURE_SCREEN", ADVENTURE], ["MISSION_2", ADVENTURE], ["MISSION_3", ADVENTURE], ["MISSION_4", ADVENTURE],
	["TERRAIN_CLICK", ADVENTURE], ["HERO_CLICK", ADVENTURE], ["ADVENTURE_PANEL_CLICK", ADVENTURE], ["MONSTER_CLICK", ADVENTURE],
	["USE_ADDITIONAL_BUILDING", ADVENTURE], ["TAKE_MINE", ADVENTURE], ["OPEN_SPELL_SHOP", ADVENTURE], ["OPEN_COMPONENT_SHOP", ADVENTURE],
	["OPEN_BUILDING_SCREEN", ADVENTURE], ["CASTLE_CLICK", ADVENTURE], ["OPEN_GLOBAL_SPELLS_SCREEN", ADVENTURE],
	["OPEN_DIPLOMACY_SCREEN", ADVENTURE], ["TAKE_ARTIFACT", ADVENTURE], ["OPEN_HERO_SCREEN", ADVENTURE],
	["OPEN_EXCHANGE_SCREEN", ADVENTURE], ["HERO_DEATH", ADVENTURE], ["ENEMY_HERO_CLICK", ADVENTURE], ["LEVEL_UP", ADVENTURE],
	["FORT_ATTACK_OR_USE", ADVENTURE], ["COMBAT_SCREEN", COMBAT], ["CAST_CREATURE", COMBAT], ["CAST_ENCHANTMENT", COMBAT],
	["CAST_SORCERY", COMBAT], ["CREATURE_FLAGS", COMBAT], ["ATTACK_OR_BLOCK", COMBAT], ["CREATURE_GONE_TO_GRAVEYARD", COMBAT],
	["CAN_USE_ARTIFACT", COMBAT],
]
## Events the original game never fires (no trigger exists); kept for the
## table only.
const DORMANT := ["MISSION_2", "MISSION_3", "MISSION_4", "TERRAIN_CLICK", "ADVENTURE_PANEL_CLICK", "TAKE_ARTIFACT",
	"CREATURE_FLAGS", "ATTACK_OR_BLOCK", "CREATURE_GONE_TO_GRAVEYARD", "CAN_USE_ARTIFACT"]
## Combat cast events by the card's CombatSpells Class.
const CAST_EVENTS := {"Creature": "CAST_CREATURE", "Sorcery": "CAST_SORCERY", "Enchantment": "CAST_ENCHANTMENT"}
## Played whenever the panel opens.
const SOUND := "Buttons/Tutorial.wav"
## Automatic events run in the game; scripted checks (--script) leave them
## off unless they enable them, as they do the start-up movies.
static var automatic := not OS.get_cmdline_args().has("--script")

var settings: ELSettings
var settings_path := "user://settings.json"
## Writes the settings file when the seen string changes (off in checks that
## only inspect values).
var persist := true
## Event ids in the order they were shown.
var history: Array[int] = []
## The ids of the shown category's history and the one on screen.
var shown_list: Array[int] = []
var index := -1
var category := ADVENTURE

## One tutorial per settings object: the map and the battle share its history.
static func for_settings(source: ELSettings) -> ELFirstTutorial:
	if source.has_meta("first_tutorial"):
		var existing: Variant = source.get_meta("first_tutorial")
		if existing is ELFirstTutorial: return existing
	var tutorial := ELFirstTutorial.new()
	tutorial.settings = source
	tutorial.reload()
	source.set_meta("first_tutorial", tutorial)
	return tutorial

static func id_of(event_name: String) -> int:
	for id in EVENTS.size():
		if EVENTS[id][0] == event_name: return id
	return -1

static func category_of(id: int) -> int:
	return int(EVENTS[id][1]) if id >= 0 and id < EVENTS.size() else 0

## The caption and body of an event from the edition's texts.
static func texts(profile: ELProfile, id: int) -> Dictionary:
	if id < 0 or id >= EVENTS.size() or profile == null: return {"caption": "", "body": ""}
	var key := "TUT_" + str(EVENTS[id][0])
	var caption := profile.text(key + "_C")
	var body := profile.text(key)
	return {"caption": "" if caption == key + "_C" else caption, "body": "" if body == key else body}

## Rebuilds the history from the stored seen string, in id order, as the
## original does when the game starts.
func reload() -> void:
	history.clear()
	var seen := seen_string()
	for id in mini(seen.length(), EVENTS.size()):
		if seen[id] == "1": history.append(id)

func seen_string() -> String:
	if settings == null: return ""
	var value: Variant = settings.values.get("tutorial_events", "")
	return value if value is String else ""

func is_seen(id: int) -> bool:
	var seen := seen_string()
	return id >= 0 and id < seen.length() and seen[id] == "1"

func enabled() -> bool:
	return automatic and settings != null and bool(settings.values.get("show_tutorial", true))

## Fires an event by name. Without `force`, nothing happens when the option is
## off or the event was already shown. Returns true when the panel should show.
func fire(event_name: String, current: int, force := false) -> bool:
	var id := id_of(event_name)
	if id < 0 or settings == null: return false
	if not force and (not enabled() or is_seen(id)): return false
	history.append(id)
	_mark(id)
	return _show(current)

## H: the shown category's history at its last entry, or (empty) both intro
## screens forced.
func open_history(current: int) -> bool:
	if _show(current): return true
	fire("ADVENTURE_SCREEN", current, true)
	return fire("COMBAT_SCREEN", current, true)

## Clear: forget every shown event, then show the intro screens again.
func clear(current: int) -> bool:
	history.clear()
	if settings != null:
		settings.values["tutorial_events"] = ""
		_save()
	fire("ADVENTURE_SCREEN", current, true)
	return fire("COMBAT_SCREEN", current, true)

func can_back() -> bool:
	return index > 0

func can_forward() -> bool:
	return index >= 0 and index < shown_list.size() - 1

func back() -> bool:
	if not can_back(): return false
	index -= 1
	return true

func forward() -> bool:
	if not can_forward(): return false
	index += 1
	return true

## The event on screen (-1 for none).
func current_id() -> int:
	return shown_list[index] if index >= 0 and index < shown_list.size() else -1

func current_name() -> String:
	var id := current_id()
	return str(EVENTS[id][0]) if id >= 0 else ""

func _show(current: int) -> bool:
	category = current
	shown_list.clear()
	for id: int in history:
		if category_of(id) == current: shown_list.append(id)
	index = shown_list.size() - 1
	if index < 0: return false
	shown.emit(current)
	return true

func _mark(id: int) -> void:
	var seen := seen_string()
	while seen.length() <= id: seen += "0"
	seen = seen.substr(0, id) + "1" + seen.substr(id + 1)
	settings.values["tutorial_events"] = seen
	_save()

func _save() -> void:
	if persist and settings != null: settings.save_file(settings_path)
