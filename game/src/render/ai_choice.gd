class_name ELAIChoice
## The computer players' strength as dropdowns: "duel_ai" (the battle
## opponent, both games) and "world_ai" (computer players on the first
## game's map), ELSettings.DUEL_AI_LEVELS and WORLD_AI_LEVELS. Options and
## the screens where a campaign's difficulty is chosen use the same lists;
## each item's tooltip says what it does.
##
## Each campaign or single scenario keeps its own levels
## (ELAdventureSession.duel_ai and world_ai, saved with it and carried to the
## next chapter). A new game takes them from its difficulty (`defaults`):
## the original opponents on the lowest difficulty, otherwise the choices in
## Options. The screens with a difficulty choice show them and reset them
## when the difficulty changes; Options in a running game changes that game's.
## Standalone duels, puzzles and network games use the Options choices.

## The keys a game keeps.
const KEYS := ["duel_ai", "world_ai"]
const FIGHT_MONSTERS := "fight_neutral_monsters"
const LIVING_WORLD := 2
const MONSTER_LABEL := "AI fights neutral monsters"
const MONSTER_HELP := "Recommended for the easiest difficulty. On higher difficulties, leave this off: strong guards can defeat computer heroes and block their route to resources.\n\nBy default, computer heroes automatically win off-screen battles against ordinary neutral monsters. Enable this option to have them forecast and play those duels. Map turns may take longer.\n\nThis option requires Living world. Field monsters have less health, and guards near mines and mana nodes fight at a lower level. On the easiest difficulty, those near starting castles guard only their own tile."
const MONSTER_LOCK := "Living world is required while AI fights neutral monsters is enabled."

## The levels of `key`: [[caption, description], ...].
static func levels(key: String) -> Array:
	return ELSettings.DUEL_AI_LEVELS if key == "duel_ai" else ELSettings.WORLD_AI_LEVELS

## Whether `key` matters in `edition`: the map's computer players are the
## first game's only.
static func applies(key: String, edition: String) -> bool:
	return key == "duel_ai" or edition == "el1"

## The heading shown beside a picker.
static func caption(key: String) -> String:
	return "Duel AI" if key == "duel_ai" else "World AI"

## A level's caption: its own "AI level: …" translation where there is one
## (a Russian adjective agrees with "ИИ"), else the plain word's.
static func level_name(caption: String, profile: ELProfile) -> String:
	var own := ELRemakeText.t("AI level: " + caption, profile)
	return ELRemakeText.t(caption, profile) if own.begins_with("AI level: ") else own

## The Options choice of `key` (the default without preferences).
static func preferred(settings: ELSettings, key: String) -> int:
	var value: Variant = settings.values.get(key, ELSettings.SHARED[key]) if settings != null else ELSettings.SHARED[key]
	return clampi(int(value), 0, levels(key).size() - 1)

## The levels a new game at `difficulty` starts with: on the lowest (0) the
## original duel opponent and the original map players; on the others the
## Options choices (by default the smarter ones). A save made before games
## kept their own levels gets them the same way when it is loaded.
static func defaults(difficulty: int, settings: ELSettings) -> Dictionary:
	if difficulty <= 0: return {"duel_ai": 1, "world_ai": 0}
	return {"duel_ai": preferred(settings, "duel_ai"), "world_ai": preferred(settings, "world_ai")}

## Whether `value` is a level of `key`.
static func valid_level(key: String, value: Variant) -> bool:
	return ELLuaSave._integer(value, 0, levels(key).size() - 1)

## Whether `value` is a game's levels: {"duel_ai": n, "world_ai": n}.
static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != KEYS.size() + int(value.has(FIGHT_MONSTERS)): return false
	if not value.get(FIGHT_MONSTERS, false) is bool: return false
	for key: String in KEYS:
		if not valid_level(key, value.get(key)): return false
	return true

## `value` with integer levels (JSON reads numbers as floats).
static func normalized(value: Dictionary) -> Dictionary:
	var result := {"duel_ai": int(value.duel_ai), "world_ai": selected_world(value)}
	if value.get(FIGHT_MONSTERS, false): result[FIGHT_MONSTERS] = true
	return result

static func selected_world(value: Dictionary) -> int:
	return LIVING_WORLD if value.get(FIGHT_MONSTERS, false) else int(value.world_ai)

## The levels a chapter row brings ("ai", or the second game's campaign
## progress' "ai"); empty when it brings none.
static func from_scenario(scenario: Dictionary) -> Dictionary:
	if valid(scenario.get("ai")): return normalized(scenario.ai)
	var progress: Variant = scenario.get(ELSecondCampaign.KEY)
	if progress is Dictionary and valid(progress.get("ai")): return normalized(progress.ai)
	return {}

## The session's own levels; empty before they are set.
static func of(state: ELAdventureSession) -> Dictionary:
	if state == null or state.duel_ai < 0 or state.world_ai < 0: return {}
	var result := {"duel_ai": state.duel_ai, "world_ai": state.world_ai}
	if state.fight_neutral_monsters: result[FIGHT_MONSTERS] = true
	return result

## Gives the session the levels `value` (when valid).
static func store(state: ELAdventureSession, value: Dictionary) -> void:
	if state == null or not valid(value): return
	state.duel_ai = int(value.duel_ai)
	state.fight_neutral_monsters = bool(value.get(FIGHT_MONSTERS, false))
	state.world_ai = selected_world(value)

## A map being opened: a session without levels (a new map, or a save from
## before games kept them) takes the chapter row's, else its difficulty's.
static func adopt(state: ELAdventureSession, scenario: Dictionary, settings: ELSettings) -> void:
	if state == null or not of(state).is_empty(): return
	var carried := from_scenario(scenario)
	store(state, carried if not carried.is_empty() else defaults(state.difficulty, settings))

## The next chapter rows of a finished first-game chapter (`rows`, one or
## the two of a branch choice), copied with the game's levels ("ai").
static func carry_rows(state: ELAdventureSession, rows: Array) -> Array:
	var levels := of(state)
	var result: Array = []
	for row: Variant in rows:
		var copy: Variant = Dictionary(row).duplicate() if row is Dictionary else row
		if copy is Dictionary and not levels.is_empty(): copy.ai = levels.duplicate()
		result.append(copy)
	return result

## Second game: the campaign progress at a chapter's end takes the game's
## levels ("ai"), for the next chapter and the between-chapter autosave.
static func carry_progress(state: ELAdventureSession, progress: Dictionary) -> void:
	var levels := of(state)
	if not levels.is_empty(): progress.ai = levels

## The duel opponent's level in a battle of `state`'s game (the Options
## choice without one).
static func duel_level(state: ELAdventureSession, settings: ELSettings) -> int:
	return state.duel_ai if state != null and state.duel_ai >= 0 else preferred(settings, "duel_ai")

## The map players' level of `state`'s game (the Options choice without one).
static func world_level(state: ELAdventureSession, settings: ELSettings) -> int:
	return state.world_ai if state != null and state.world_ai >= 0 else preferred(settings, "world_ai")

## The director's computer-player switches from the game's world level
## (`shared`: a network game, which uses the Options choice).
static func apply_world(director: ELAdventureDirector, settings: ELSettings, shared := false) -> void:
	var level := world_level(null if shared else director.state, settings)
	director.smart_ai = level >= 1
	director.living_world = level >= LIVING_WORLD
	director.fight_neutral_monsters = not shared and director.state.fight_neutral_monsters

## A dropdown of `key`'s levels showing the current value; choosing one
## stores it in `settings` (written to `path` when given).
static func picker(settings: ELSettings, key: String, profile: ELProfile, path := "") -> OptionButton:
	return values_picker(settings.values, key, profile, func(_index: int):
		if not path.is_empty(): settings.save_file(path))

## A dropdown of `key`'s levels showing `values[key]`; choosing one stores it
## there and calls `changed` with it. `display(pick, level)` shows another value.
static func values_picker(values: Dictionary, key: String, profile: ELProfile, changed := Callable()) -> OptionButton:
	var pick := OptionButton.new()
	pick.name = "DuelAi" if key == "duel_ai" else "WorldAi"
	pick.focus_mode = Control.FOCUS_NONE
	var list := levels(key)
	for i in list.size():
		pick.add_item(level_name(String(list[i][0]), profile))
		pick.set_item_tooltip(i, ELRemakeText.t(String(list[i][1]), profile))
	if profile != null: pick.set_meta("ai_profile", profile)
	pick.set_meta("ai_key", key)
	display(pick, int(values.get(key, ELSettings.SHARED[key])))
	pick.item_selected.connect(func(index: int):
		values[key] = index
		pick.tooltip_text = ELRemakeText.t(String(list[index][1]), profile)
		if changed.is_valid(): changed.call(index))
	return pick

## The campaign setup checkbox and the corresponding World AI picker state.
static func monster_checkbox(values: Dictionary, pick: OptionButton) -> CheckBox:
	var box := CheckBox.new()
	box.name = "FightNeutralMonsters"
	for state: String in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		box.add_theme_color_override(state, ELGameChoice.INK)
	box.add_theme_color_override("font_disabled_color", ELGameChoice.INK.darkened(0.30))
	box.toggled.connect(func(enabled: bool):
		if enabled: values[FIGHT_MONSTERS] = true
		else: values.erase(FIGHT_MONSTERS)
		display_monsters(box, pick, values))
	return box

static func display_monsters(box: CheckBox, pick: OptionButton, values: Dictionary) -> void:
	var enabled := bool(values.get(FIGHT_MONSTERS, false))
	box.set_pressed_no_signal(enabled)
	display(pick, selected_world(values))
	pick.disabled = enabled
	if enabled:
		var profile: ELProfile = pick.get_meta("ai_profile") if pick.has_meta("ai_profile") else null
		pick.tooltip_text = ELRemakeText.t(MONSTER_LOCK, profile)

## Shows `level` on a dropdown `values_picker` made, without choosing it.
static func display(pick: OptionButton, level: int) -> void:
	var key := str(pick.get_meta("ai_key", "duel_ai"))
	var list := levels(key)
	pick.select(clampi(level, 0, list.size() - 1))
	pick.tooltip_text = ELRemakeText.t(String(list[pick.selected][1]), pick.get_meta("ai_profile") if pick.has_meta("ai_profile") else null)
