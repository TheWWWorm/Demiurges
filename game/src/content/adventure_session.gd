class_name ELAdventureSession
extends RefCounted
## Mutable scenario state and explicit script-to-engine calls. The presentation
## consumes queued commands; unsupported bindings produce a visible error.
signal event(data: Dictionary)
var map: ELAdventureMap
var vm: ELLuaVM
var objects: Dictionary = {}
var players: Dictionary = {}
var commands: Array[Dictionary] = []
var messages: Array[Dictionary] = []
var error := ""
var main_hero := -1
var current_player := 1
var day := 1
var income_day := 0
var difficulty := 0
var script_name := ""
var seed_value := 212
var camera_zoom := 40.0
var camera_rotation := 0.0
var camera_locked := false
## Mission music fades (in, out), read and written by scripts; second game:
## initialised from settings.ini MusicThemeFadeIn/Out.
var theme_fade := Vector2(1.0, 1.0)
## Second game: the background theme, terrain effects and looping sounds the
## script post-step started (ELSecondAmbience). Saved.
var ambience: Dictionary = ELSecondAmbience.blank()
var exclusive := false
var outcome := ""
## First-game castles, campaign mode and chapter flags (ELFirstScenario).
var scenario: Dictionary = {}
var colorless_level := 0
var explored := PackedByteArray()
## Guard zones, set by the director (second-game ExCheckIntercepts).
var interception: ELInterception
## The director's map grid, for placements made outside a move. Assigning it
## also rebuilds fog visibility (ELFog), including after a load.
var grid: ELAdventureGrid:
	set(value):
		grid = value
		if value != null and ELFog.applies(self):
			if not value.actor_moved.is_connected(_fog_moved): value.actor_moved.connect(_fog_moved)
			ELFog.refresh(self)
## ELFog's rebuilt visible masks and revision; never saved.
var fog: Dictionary = {}
## EL2 script observations by id: [x, y, radius]; every player sees each disc
## until it is finished (ExStartObservation / ExFinishObservation). Saved.
var observations: Dictionary = {}
var variables: ELLuaVM.Table
## Keys of `variables` set with the persistence flag; they carry to the next
## chapter of the campaign.
var persistent: ELLuaVM.Table
var _next_effect := 1
var _next_object := 1
var _mob_ids: Array[int] = []
var _loot_message: Array[Dictionary] = []
## Second-game Notebook entries (ELSecondNotebook) and the next entry id.
var notebook: Array = []
var notebook_next := 0
## Map cell the view's camera looks at (notebook entry points); (-1, -1) headless.
var view_point := Vector2(-1, -1)
## Second game: the adventure tutorial (Single game -> Tutorial -> Adventure;
## mission). It is never saved.
var tutorial := false
## Second game: highlighted interface elements (ExBlinkElement name -> true).
var blinks: Dictionary = {}
## Second game: the scenario script replaces the library Hook_OnPostStep (its
## weather and music segments, ELSecondAmbience), as the tutorial does.
var scenario_post_step := false
## Whether a modal window (message box, inventory, shop, notebook, Esc menu) is
## open, for ExIsDesktopModalChild; the director and the view install it.
var desktop_modal: Callable
## ExBlinkElement names (dispatcher): 0-5 InventoryScreen frames,
## 6 the bag button, 7-8 the level and life digits, 9 the experience bar.
const BLINK_ELEMENTS := ["E_INV_HERO_INFO", "E_INV_SPEC", "E_INV_SKILLS", "E_INV_ARTIFACTS", "E_INV_DECK", "E_INV_BAG",
	"E_ADV_INVENTORY_BTN", "E_ADV_LEVEL", "E_ADV_LIFE", "E_ADV_EXPERIENCE"]

func _init() -> void:
	event.connect(_fog_event)

func _fog_event(data: Dictionary) -> void:
	ELFog.on_event(self, data)

func _fog_moved(actor: Dictionary) -> void:
	ELFog.moved(self, actor)

func start(source: ELAdventureMap, level := 0, seed_number := 212, scenario_script := "", human := 1, campaign := false) -> bool:
	close()
	map = source
	difficulty = clampi(level, 0, 4)
	seed_value = seed_number
	script_name = scenario_script if not scenario_script.is_empty() else "Maps/" + map.id
	error = ""
	day = 0 if map.profile.id == "el2" else 1
	income_day = 0
	current_player = 1
	main_hero = -1
	outcome = ""
	colorless_level = 0
	explored.resize(map.width * map.height)
	explored.fill(0)
	fog = {}
	observations = {}
	_next_object = int(ELXml.child(map.document, "support").get("attrs", {}).get("last_permanent_id", 0))
	for player: Dictionary in map.players:
		var resources := ELResources.read_node(map.profile.id, ELXml.child(player, "start_resources"))
		var relations := {}
		for relation: Dictionary in ELXml.children(ELXml.child(player, "diplomacy"), "opponent"):
			relations[int(relation.attrs.get("id", 0))] = int(relation.attrs.get("relations", 0))
		players[int(player.attrs.id)] = {"color": ELXml.value(player, "color"), "resources": resources, "relations": relations}
	scenario = {}
	# The campaign entry chooses which authored player the human controls.
	if map.profile.id == "el1" and players.has(human): current_player = human
	for index in map.objects.size():
		var placed: Dictionary = map.objects[index]
		# XML writes runtime permanent IDs plus one; scripts use the runtime value.
		var id := int(placed.permanent_id) - 1 if placed.permanent_id > 0 else index + 1000000
		var object: Dictionary = placed.duplicate()
		object.merge({"uid": id, "source_index": index, "alive": true, "visible": ELXml.child(placed.node, "hidden").is_empty(), "enabled": true,
			"type": "object", "shape": "", "level": 1, "health": 10, "base_ap": 0, "ap": 0, "experience": 0, "cards": [], "spell_stock": {}, "stock_separate": true, "skills": {}, "inventory": [], "orders": []}, true)
		if placed.group in ["heroes", "np_heroes"]:
			object.ship = map.profile.id == "el2" and _water_cell(object.x, object.y)
			object.type = "hero" if ELXml.child(placed.node, "monster").is_empty() else "monster"
			if map.mobs.has(placed.name):
				var variants: Dictionary = map.mobs[placed.name]
				var mob: Dictionary = variants.get(difficulty, variants.get(0, variants.values()[0]))
				object.shape = mob.attrs.get("shape", "")
				object.type = "hero" if mob.attrs.get("IsHero", "0") == "1" else "monster"
				object.level = int(mob.attrs.get("Lvl", 1))
				object.health = int(mob.attrs.get("Hp", 10))
				object.base_ap = int(mob.attrs.get("AP", 0))
				object.ap = object.base_ap
				object.title = map.profile.text(mob.attrs.get("ElkName", placed.name))
				object.specialization = mob.attrs.get("Spec", "NONE")
				object.battle_script = mob.attrs.get("Script", "")
				var runes: Array[int] = []
				for spell: Dictionary in ELXml.children(ELXml.child(mob, "deck"), "spell"):
					var card: String = spell.attrs.get("code", "")
					object.cards.append(card)
					runes.append(int(spell.attrs.get("components", 0)))
				if map.profile.id == "el1": ELRunes.initialize(map.profile, object, runes)
				for skill: Dictionary in ELXml.children(ELXml.child(mob, "skills"), "skill"):
					object.skills[str(skill.attrs.get("type", ""))] = int(skill.attrs.get("level", 0))
				ELHeroProgression.initialize(map.profile, object)
			elif object.type == "monster" and map.profile.id == "el1":
				if not ELFirstMonsters.initialize(map.profile, object, difficulty): return _fail("Missing neutral creature: " + placed.name)
			elif object.type == "hero":
				var template: Dictionary = map.profile.table("HeroTemplates").get(placed.name, {})
				object.level = int(template.get("Level", 1))
				var growth := int(template.get("HealthIncrease", 3))
				object.health = int(template.get("BaseHealth", 7)) + object.level * growth
				object.title = map.profile.text(str(template.get("ELKName", placed.name)))
				object.specialization = template.get("Specialization", "NONE")
				object.cards = ELCatalog.deck(map.profile, str(template.get("StartDeck", "")))
				object.skills = ELHeroSkills.from_template(map.profile, template)
				ELHeroProgression.initialize(map.profile, object, growth)
				if map.profile.id == "el1": ELRunes.initialize(map.profile, object)
			if map.profile.id == "el1" and not object.has("rune_uses"): ELRunes.initialize(map.profile, object)
			if map.profile.id == "el1": ELStrategy.initialize(map.profile, object)
			if map.profile.id == "el2": ELAdventureClock.initialize(object)
			if placed.owner == current_player and main_hero < 0: main_hero = id
			_mob_ids.append(id)
		elif placed.group == "additional_buildings":
			object.type = String(placed.name).to_lower()
			if map.profile.id == "el1": ELAdditionalBuildings.initialize(map.profile, object)
			else: ELSecondGates.initialize(object)
		elif placed.group == "laboratories" and map.profile.id == "el2":
			object.type = "spell_shop"
			object.shop_stock = ELSpellShop.authored_stock(map.profile, placed.node)
		elif placed.group in ["factories", "laboratories"] and map.profile.id == "el1":
			ELBuildings.initialize(map.profile, object)
		elif ELResourceSites.TYPES.has(placed.group):
			ELResourceSites.initialize(map.profile, object)
		elif placed.group == "forts":
			ELForts.initialize(map.profile, object)
		objects[id] = object
		_next_object = maxi(_next_object, id + 1)
	if map.profile.id == "el1":
		ELFirstScenario.initialize(self, current_player, campaign)
		# The first day-start runs at mission start and counts as a weekly reset.
		ELAdditionalBuildings.new_day(self, 0)
	if map.profile.id == "el2":
		# Heroes and creatures authored on a fort's tile garrison it.
		ELForts.occupy_placed(self)
		theme_fade = ELSecondAmbience.theme_fades(map.profile)
		vm = ELLuaVM.new()
		variables = vm.table()
		vm.globals["__engine_variables"] = variables
		persistent = vm.table()
		vm.globals["__engine_persistent"] = persistent
		for name: String in _bindings(): vm.bind(name, _native.bind(name))
		var library_post_step: Variant = null
		for name: String in ["Maps/adventure_lib.scp.sobj", script_name + ".scp.sobj"]:
			if not vm.load_script(map.profile.read("scripts", name), name): return _fail(vm.error)
			if library_post_step == null: library_post_step = vm.globals.get("Hook_OnPostStep")
		scenario_post_step = vm.has_function("Hook_OnPostStep") and vm.globals.get("Hook_OnPostStep") != library_post_step
		if not hook("Hook_Init"): return false
		if not hook("Hook_GameStarted"): return false
	return true

func close() -> void:
	if vm != null: vm.clear()
	vm = null
	variables = null
	persistent = null
	objects.clear()
	_mob_ids.clear()
	players.clear()
	commands.clear()
	messages.clear()
	_loot_message.clear()
	blinks.clear()

func hook(name: String, arguments: Array = []) -> bool:
	if vm == null or not vm.has_function(name): return true
	vm.invoke(name, arguments)
	return _fail(vm.error) if not vm.error.is_empty() else true

## One script tick. Second game: Hook_Wake(current player) only while that
## player's heroes are idle (`wake`).
func step(wake := true) -> bool:
	if map.profile.id == "el2":
		# Wake first: chapter set-up (e.g. chapter 13's hero ids) runs in the
		# first wake before any step check reads it.
		if wake and not hook("Hook_Wake", [float(current_player)]): return false
		if not hook("Hook_OnStep"): return false
		# Mission update runs Hook_OnPostStep right after Hook_OnStep:
		# the library's weather and music segments, or the scenario's own hook.
		ELSecondAmbience.step(self)
		return hook("Hook_OnPostStep")
	if not hook("Hook_Wake", [50.0]): return false
	return hook("Hook_OnStep")

func object(id: Variant) -> Dictionary:
	if typeof(id) not in [TYPE_INT, TYPE_FLOAT]: return {}
	return objects.get(int(id), {})

func _mobs() -> Array[int]:
	return _mob_ids

func create_hero(owner: int, template: String, x: int, y: int) -> int:
	if not map.mobs.has(template):
		vm._fail("Missing adventure hero template: " + template)
		return -1
	var variants: Dictionary = map.mobs[template]
	var mob: Dictionary = variants.get(difficulty, variants.get(0, variants.values()[0]))
	var id := _next_object
	_next_object += 1
	var item := {"uid": id, "permanent_id": id, "source_index": -1, "id": id, "name": template, "owner": owner, "group": "heroes" if owner else "np_heroes", "x": x, "y": y, "rotation": 0,
		"type": "hero" if mob.attrs.get("IsHero", "0") == "1" else "monster", "alive": true, "visible": true, "enabled": true, "shape": mob.attrs.get("shape", ""),
		"level": int(mob.attrs.get("Lvl", 1)), "health": int(mob.attrs.get("Hp", 10)), "base_ap": int(mob.attrs.get("AP", 0)), "ap": int(mob.attrs.get("AP", 0)), "experience": 0,
		"cards": [], "spell_stock": {}, "stock_separate": true, "skills": {}, "inventory": [], "orders": [], "node": {}, "title": map.profile.text(mob.attrs.get("ElkName", template)), "specialization": mob.attrs.get("Spec", "NONE"), "battle_script": mob.attrs.get("Script", "")}
	item.ship = _water_cell(x, y)
	var runes: Array[int] = []
	for spell: Dictionary in ELXml.children(ELXml.child(mob, "deck"), "spell"):
		var card: String = spell.attrs.get("code", "")
		item.cards.append(card)
		runes.append(int(spell.attrs.get("components", 0)))
	if map.profile.id == "el1": ELRunes.initialize(map.profile, item, runes)
	for skill: Dictionary in ELXml.children(ELXml.child(mob, "skills"), "skill"):
		item.skills[str(skill.attrs.get("type", ""))] = int(skill.attrs.get("level", 0))
	ELHeroProgression.initialize(map.profile, item)
	if map.profile.id == "el2": ELAdventureClock.initialize(item)
	objects[id] = item
	_mob_ids.append(id)
	event.emit({"kind": "object_created", "id": id})
	return id

func _water_cell(x: int, y: int) -> bool:
	return [map.tile(x, y), map.tile(x + 1, y), map.tile(x + 1, y + 1), map.tile(x, y + 1)].count(16) > 2

func hostile(first: Dictionary, second: Dictionary) -> bool:
	if first.is_empty() or second.is_empty() or first.owner == second.owner: return false
	if map.profile.id == "el1":
		var a := maxi(0, int(first.owner))
		var b := maxi(0, int(second.owner))
		if a == b: return false
		var lower: Dictionary = players.get(mini(a, b), {}).get("relations", {})
		var upper: Dictionary = players.get(maxi(a, b), {}).get("relations", {})
		return (int(lower.get(maxi(a, b), upper.get(mini(a, b), 0))) & 4) == 0
	var relations: Dictionary = players.get(first.owner, {}).get("relations", {})
	# Interception filter: hostile while relation bit value 4 is clear.
	# Authored 170/239/255 agree with bit 1; the tutorial's 174 is peaceful.
	return (int(relations.get(second.owner, 0)) & 4) == 0

func change_resources(player_id: int, amounts: Dictionary) -> bool:
	error = ""
	if not players.has(player_id) or not ELResources.change(map.profile.id, players[player_id].resources, amounts): return _fail("Invalid resource reward.")
	event.emit({"kind": "resources_changed", "player": player_id})
	return true

func add_experience(hero_id: int, amount: int) -> int:
	error = ""
	var hero := object(hero_id)
	if hero.is_empty() or amount < 0:
		_fail("Invalid experience reward.")
		return -1
	var previous := int(hero.level)
	var granted := ELHeroProgression.award(map.profile, hero, amount)
	if granted > 0:
		event.emit({"kind": "experience_gained", "id": hero_id, "amount": granted, "levels": int(hero.level) - previous})
	return granted

func move_spell(hero_id: int, card: String, index := -1, reserve_index := 0) -> bool:
	error = ""
	var hero := object(hero_id)
	if hero.is_empty() or not hero.alive or hero.owner != current_player or hero.type != "hero": return _fail("This hero's spellbook is unavailable.")
	var problem := ELSpellInventory.unequip(map.profile, hero, index) if index >= 0 else ELSpellInventory.equip(map.profile, hero, card, reserve_index)
	if not problem.is_empty(): return _fail(problem)
	if not hook("Hook_OnInventorySpellMoved"): return false
	event.emit({"kind": "inventory_changed", "id": hero_id})
	return true

func choose_skill(hero_id: int, code: String) -> bool:
	error = ""
	var hero := object(hero_id)
	if hero.is_empty() or not hero.alive or hero.owner != current_player or hero.type != "hero": return _fail("This hero's skills are unavailable.")
	var problem := ELHeroSkills.choose(map.profile, hero, code)
	if not problem.is_empty(): return _fail(problem)
	event.emit({"kind": "skill_learned", "id": hero_id, "code": code, "rank": hero.skills[code]})
	return true

func collect_resources(hero_id: int, resource_id: int) -> bool:
	error = ""
	var actor := object(hero_id)
	var item := object(resource_id)
	if actor.is_empty() or actor.type not in ["hero", "monster"] or not actor.alive or not players.has(actor.owner): return _fail("The collecting hero is unavailable.")
	if item.is_empty() or item.group != "resource_cuts" or not item.alive or not item.visible or not item.enabled: return _fail("These resources are no longer available.")
	var amounts := ELResources.read_node(map.profile.id, ELXml.child(item.node, "resources"))
	if not change_resources(actor.owner, amounts): return false
	item.alive = false
	item.visible = false
	item.enabled = false
	event.emit({"kind": "object_killed", "id": resource_id})
	event.emit({"kind": "resources_collected", "player": actor.owner, "amounts": amounts})
	return true

func _bindings() -> Array[String]:
	return ["date", "ExSetVariable", "ExGetVariable", "ExClearVariables", "ExGetMainHeroID", "ExGetCurrentPlayer", "ExGetDay", "ExSetDay", "ExGetPos", "ExGetTilePoint", "ExGetObjectPoint", "ExGetMapSize", "ExGetObjectType", "ExIsAlive", "ExIsHostile", "ExGetMobCount", "ExGetMobByIndex", "ExGetResources", "ExAddResources",
		"ExCreateHero", "ExCreateHeroForPlayer", "ExKillHero", "ExHideHero", "ExCreateCorpse", "ExGetCorpseHero", "ExSetHeroShape", "ExSetHeroName", "ExSetHostility", "ExWinLoseMission",
		"ExIsShip", "ExHideExploration", "ExSetHeroColorlessnessTolerance", "ExGetClrlessLevel", "ExSetClrlessLevel", "ExIsSpecializationAvailable", "ExHaveSpecialization", "ExGiveNewSpecialization",
		"ExClearHand", "ExAddSpellToHand", "ExAllowCardColor", "ExIsCardColorAllowed", "ExTakeObject", "ExPlaceObject", "ExGetUsability",
		"ExAddSpell", "ExRemoveSpell", "ExHasSpell", "ExIsHeroFortified", "ExStartLootMessage", "ExAddLootMessageSpell", "ExSendLootMessage", "ExSendNoLootMessage",
		"ExRunToPosCmd", "ExRunAndUseObjectCmd", "ExExecuteCmd",
		"ExGetHeroLevel", "ExGetHeroBaseAP", "ExSetHeroBaseAP", "ExGetHeroProperAP", "ExSetHeroProperAP", "ExUseHeroProperAP", "ExEndOfTurn", "ExGetExp", "ExAddExp", "ExGetBattleExp", "ExGetCommandQueueSize", "ExHasCmd", "ExSoftAbortCmd", "ExAbortAllCommand", "ExCheckIntercepts", "ExSetExclusiveFlag", "ExGetTextByID", "ExSetUsability", "ExGetRotateMirror", "ExSetRotateMirror", "ExJumpToPos",
		"ExCameraGetZoom", "ExCameraGetRotate", "ExCameraLock", "ExCameraUnlock", "ExCameraRotate", "ExCameraScrollToObject", "ExCameraScrollToPos", "ExGetThemeFadeIn", "ExGetThemeFadeOut", "ExStartBackgroundTheme", "ExStopBackgroundTheme", "ExStartEmphasisTheme", "ExStopEmphasisTheme", "ExStartEffect", "ExFinishEffect", "ExSoundBeginFX", "ExSoundCancelFX", "ExOrientEffect", "ExOrientEffectByObject",
		"ExAddCommandWait", "ExAddCommandText", "ExAddCommandQuestion", "ExAddCommandMoving", "ExAddCommandMoveAndUseObject", "ExAddCommandCameraToObject", "ExAddCommandCameraToPos", "ExAddCommandCameraRotate", "ExAddCommandCameraRotateToObject", "ExAddCommandCameraRotateToPos", "ExAddCommandCameraAttach", "ExAddCommandJumpToPos", "ExAddCommandStartEffect", "ExAddCommandStartSound", "ExAddCommandFinishEffect", "ExAddCommandFinishSound", "ExAddCommandKillHero", "ExAddCommandLose", "ExAddCommandWin", "ExAddCommandMobOrient", "ExAddCommandMobOrientToObject", "ExAddCommandMobOrientToPoint", "ExAddCommandStartObservation", "ExAddCommandFinishObservation", "ExAddCommandExecuteScriptFunction", "ExAddCommandOrientEffectByObject", "ExAddCommandTakeObject", "ExAddCommandStartAffect", "ExAddCommandEndOfTurn", "ExStartObservation", "ExFinishObservation"] + UNPORTED + ["ExTrace", "ExError", "ExGetTickCount", "ExGetTickCountDelta", "ExGetHeroName", "ExGetExclusiveFlag",
		"ExCameraInstantScrollToObject", "ExCameraInstantScrollToPos", "ExCameraZoom", "ExCameraPitch", "ExCanRunToPos", "ExCanRunToObject", "ExIsAccesibleGoalPos", "ExIsAccesibleGoalObject", "ExIsNear", "ExOrientMobToPoint",
		"ExAddCommandPlaceObject", "ExAddCommandFinishAffect", "ExAddCommandAddSpell", "ExAddCommandAddArtefact",
		"ExHasArtefact", "ExAddArtefact", "ExRemoveArtefact", "ExGetArtefactBlankCount", "ExSetArtefactBlankCount", "ExAddLootMessageArtefact",
		"ExCreateArtifact", "ExMessageBoxArtefactCreated", "ExRechargeArtefacts", "ExShowInventory",
		"ExGiveKey", "ExOpenGate", "ExCloseGate",
		"ExMessageToScreen", "ExMessageBoxStandard", "ExMessageBoxStandardAction", "ExMessageBoxDialog", "ExMessageBoxDialogHero", "ExMessageBoxOkCancel", "ExMessageBoxHeroOkCancel",
		"ExBlinkElement", "ExIsDesktopModalChild",
		"ExPassability", "ExRemoteUseObjectCmd", "ExRunToObjectCmd", "ExWaitCmd", "ExCanRunAndUseObject", "ExGetBuildingMob", "ExSetThemeFadeIn", "ExSetThemeFadeOut",
		"ExGetAffectCount", "ExGetAffectByIndex", "ExStartAffect", "ExFinishAffect"]

## Original adventure natives the remake does not implement yet: bound so a
## script that calls one stops with its name instead of a nil call.
const UNPORTED := ["ExPlayHeroAnimation", "ExSetRepeatControlFlag",
	"ExStartLight", "ExFinishLight",
	"ExCameraGetPitch", "ExCameraGetScroll", "ExCameraScroll", "ExCommandGroup",
	"ExGetCommandAtQueue", "ExIsCommandExist", "ExGetCommandInfo", "ExAbortCommand", "ExAddCommandStartLight",
	"ExAddCommandFinishLight"]

## Second-game heroes keep every specialisation they own; one is active.
func specializations(hero: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for code: Variant in hero.get("specializations", []): result.append(str(code))
	var active := str(hero.get("specialization", "NONE"))
	if active != "NONE" and not result.has(active): result.push_front(active)
	return result

## A specialisation is available to heroes of a colour its row lists.
func specialization_available(hero: Dictionary, code: String) -> bool:
	if hero.is_empty() or not map.profile.table("HeroesSpecs").has(code): return false
	var colors: Variant = map.profile.table("HeroesSpecs")[code].get("MagicColor", [])
	var color := hero_color(hero)
	return colors.has(color) if colors is Array else str(colors) == color

func hero_color(hero: Dictionary) -> String:
	var row: Dictionary = map.profile.table("Shapes").get(hero.get("shape", ""), {}) if not str(hero.get("shape", "")).is_empty() else map.profile.table("HeroTemplates").get(hero.get("name", ""), {})
	return str(row.get("Color", ""))

func learn_specialization(id: int, code: String) -> bool:
	var hero := object(id)
	if hero.is_empty() or not ELSpecs.valid(map.profile, code) or code == "NONE": return false
	var owned := specializations(hero)
	if owned.has(code): return false
	owned.append(code)
	hero.specializations = owned
	if str(hero.get("specialization", "NONE")) == "NONE": hero.specialization = code
	var name := map.profile.text(str(map.profile.table("HeroesSpecs")[code].get("Name", code)))
	event.emit({"kind": "specialization_learned", "id": id, "code": code, "text": map.profile.text("T_MB_RECEIVE_NEW_SPEC").replace("%s", name)})
	return true

func choose_specialization(id: int, code: String) -> bool:
	var hero := object(id)
	if hero.is_empty() or not specializations(hero).has(code): return _fail("This hero does not know that specialization.")
	hero.specialization = code
	event.emit({"kind": "object_changed", "id": id})
	return true

## Script variables; a nil value removes the entry as in the original.
## Numbers are truncated toward zero (ftol) and `keep` marks the entry for
## the next chapter.
func set_variable(key: Variant, value: Variant, keep := false) -> void:
	if variables == null: return
	if value is float: value = float(int(value))
	if vm != null: vm._table_set(variables, key, value)
	elif value == null: variables.values.erase(key)
	else: variables.values[key] = value
	if persistent == null: return
	if keep and value != null: persistent.values[key] = 1.0
	else: persistent.values.erase(key)

## A numeric flag counts when non-zero; any other non-nil value counts.
static func _truthy_flag(value: Variant) -> bool:
	if value is float or value is int: return value != 0
	if value is bool: return value
	return value != null

## The variables that carry to the next chapter.
func persistent_variables() -> Dictionary:
	var result := {}
	if persistent == null or variables == null: return result
	for key: Variant in persistent.values:
		if variables.values.has(key): result[key] = variables.values[key]
	return result

func _native(args: Array, name: String) -> Array:
	if name.begins_with("ExAddCommand"):
		commands.append({"kind": name.trim_prefix("ExAddCommand"), "arguments": args.duplicate()})
		return []
	var first: Variant = args[0] if not args.is_empty() else null
	var item := object(first)
	match name:
		"date": return [str(seed_value)]
		"ExSetVariable":
			if args.size() >= 2: set_variable(first, args[1], args.size() >= 3 and _truthy_flag(args[2]))
		"ExGetVariable": return [variables.values.get(first)]
		"ExClearVariables":
			variables.values.clear()
			if persistent != null: persistent.values.clear()
		"ExGetMainHeroID": return [float(main_hero)]
		"ExGetCurrentPlayer": return [float(current_player)]
		"ExGetDay": return [float(day)]
		"ExSetDay":
			day = maxi(0, int(first))
			if map.profile.id == "el2" and not object(main_hero).is_empty(): object(main_hero).travel_day = day
		"ExGetPos": return [float(item.get("x", -1)), float(item.get("y", -1))]
		"ExGetTilePoint": return [(float(args[0]) + 0.5) * 2.0, (float(args[1]) + 0.5) * 2.0, 0.0] if args.size() > 1 else []
		"ExGetObjectPoint": return [(float(item.get("x", -1)) + 0.5) * 2.0, (float(item.get("y", -1)) + 0.5) * 2.0, 0.0]
		"ExGetMapSize": return [float(map.width), float(map.height)]
		"ExGetObjectType": return ["other" if ELResourceSites.TYPES.has(item.get("group", "")) else item.get("type", "")]
		"ExIsShip": return [1.0 if item.get("ship", false) else null]
		"ExIsHeroFortified": return [1.0 if ELGlobalSpells.held_in_fort(item) else null]
		"ExHideExploration":
			# Clears explored and visible for every player; no refresh follows.
			ELFog.hide_exploration(self)
			event.emit({"kind": "exploration_changed"})
		"ExStartObservation":
			if args.size() < 4: return []
			var key := str(first) if first != null else ""
			if key.is_empty():
				vm._fail("Empty string.")
				return []
			for value: Variant in args.slice(1, 4):
				if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
					vm._fail("Invalid observation position.")
					return []
			# A repeated id finishes the earlier observation first.
			observations[key] = [int(args[1]), int(args[2]), maxi(0, int(args[3]))]
			ELFog.refresh(self)
			event.emit({"kind": "exploration_changed"})
		"ExFinishObservation":
			if observations.erase(str(first) if first != null else ""):
				ELFog.refresh(self)
				event.emit({"kind": "exploration_changed"})
		"ExSetHeroColorlessnessTolerance":
			if not item.is_empty() and args.size() > 1: item.colorless_tolerant = args[1] != null and args[1] != 0
		"ExGetClrlessLevel": return [float(colorless_level)]
		"ExIsSpecializationAvailable": return [1.0 if args.size() > 1 and specialization_available(item, str(args[1])) else null]
		"ExHaveSpecialization": return [1.0 if args.size() > 1 and specializations(item).has(str(args[1])) else null]
		"ExGiveNewSpecialization":
			if args.size() > 1: learn_specialization(int(first), str(args[1]))
		"ExSetClrlessLevel":
			colorless_level = int(first)
			event.emit({"kind": "colorless_changed", "level": colorless_level})
		"ExIsAlive": return [1.0 if item.get("alive", false) else null]
		"ExIsHostile": return [1.0 if args.size() > 1 and hostile(item, object(args[1])) else null]
		"ExGetMobCount": return [float(_mobs().size())]
		"ExGetMobByIndex":
			var mobs := _mobs()
			return [float(mobs[int(first)])] if int(first) >= 0 and int(first) < mobs.size() else [-1.0]
		"ExCreateHeroForPlayer": return [float(create_hero(int(first), str(args[1]), int(args[2]), int(args[3])))] if args.size() >= 4 else []
		"ExCreateHero": return [float(create_hero(0, str(first), int(args[1]), int(args[2])))] if args.size() >= 3 else []
		"ExKillHero":
			if not item.is_empty():
				item.alive = false
				_mob_ids.erase(int(item.uid))
				item.orders.clear()
				event.emit({"kind": "object_killed", "id": item.uid})
		"ExHideHero":
			if not item.is_empty():
				item.visible = false
				event.emit({"kind": "object_changed", "id": item.uid})
		"ExCreateCorpse":
			if not item.is_empty():
				var id := _next_object
				_next_object += 1
				var corpse: Dictionary = item.duplicate(true)
				corpse.merge({"uid": id, "source_index": -1, "type": "corpse", "appearance_type": item.type, "hero": item.uid, "alive": false, "enabled": false}, true)
				item.visible = false
				event.emit({"kind": "object_changed", "id": item.uid})
				objects[id] = corpse
				event.emit({"kind": "object_created", "id": id})
				return [float(id)]
			return [-1.0]
		"ExGetCorpseHero":
			if item.is_empty() or item.type != "corpse": return [-1.0]
			if not item.has("hero"):
				var id := _next_object
				_next_object += 1
				var hero: Dictionary = item.duplicate(true)
				hero.merge({"uid": id, "name": ELXml.value(item.node, "params"), "type": "monster", "alive": false, "visible": false}, true)
				if map.profile.id == "el2": ELAdventureClock.initialize(hero)
				objects[id] = hero
				item.hero = id
			return [float(item.hero)]
		"ExSetHeroShape":
			if not item.is_empty() and args.size() > 1:
				item.shape = str(args[1])
				event.emit({"kind": "shape_changed", "id": item.uid})
		"ExSetHeroName":
			if not item.is_empty() and args.size() > 1: item.title = map.profile.text(str(args[1]))
		"ExSetHostility":
			if args.size() >= 3:
				for pair: Array in [[int(first), int(args[1])], [int(args[1]), int(first)]]:
					if players.has(pair[0]): players[pair[0]].relations[pair[1]] = 170 if args[2] != null and args[2] != 0 else 239
		"ExWinLoseMission":
			outcome = "win" if first != null and first != 0 else "lose"
			event.emit({"kind": "mission_finished", "outcome": outcome})
		"ExGetHeroLevel": return [float(item.get("level", 1))]
		"ExGetHeroBaseAP": return [float(item.get("base_ap", 0))]
		"ExSetHeroBaseAP":
			if not item.is_empty() and args.size() > 1 and int(args[1]) >= 0: item.base_ap = int(args[1])
		"ExGetHeroProperAP": return [float(item.get("ap", 0))]
		"ExSetHeroProperAP":
			if not item.is_empty() and args.size() > 1 and int(args[1]) >= 0: item.ap = int(args[1])
		"ExUseHeroProperAP":
			if not item.is_empty() and args.size() > 1: ELAdventureClock.use_points(self, item, int(args[1]))
		"ExEndOfTurn": commands.append({"kind": "EndOfTurn", "arguments": [current_player if first == null or int(first) == -1 else int(first)]})
		"ExGetExp": return [float(ELHeroProgression.effective(item)) if item.get("type") == "hero" else 0.0]
		"ExGetBattleExp": return [float(ELHeroProgression.battle_reward(map.profile, int(item.get("level", 1)))) if not item.is_empty() else 0.0]
		"ExGetResources":
			var wallet: Dictionary = players.get(int(first), {}).get("resources", {})
			return [float(wallet.get("Herbs", 0)), float(wallet.get("Gems", 0)), float(wallet.get("Flames", 0))]
		"ExAddResources":
			if args.size() >= 4: change_resources(int(first), {"Herbs": int(args[1]), "Gems": int(args[2]), "Flames": int(args[3])})
		"ExAddExp":
			if not item.is_empty() and args.size() > 1: add_experience(int(first), int(args[1]))
		"ExGetCommandQueueSize": return [float(commands.size())]
		"ExHasCmd": return [1.0 if not item.get("orders", []).is_empty() else null]
		"ExRunToPosCmd", "ExRunAndUseObjectCmd", "ExRunToObjectCmd", "ExRemoteUseObjectCmd":
			# Orders replace the hero's plan; nothing moves until ExExecuteCmd.
			if not item.is_empty():
				var kind: String = {"ExRunToPosCmd": "Moving", "ExRunToObjectCmd": "MoveToObject"}.get(name, "MoveAndUseObject")
				item.orders.assign([{"kind": kind, "arguments": args.duplicate()}])
		"ExCanRunAndUseObject":
			var goal := object(args[1]) if args.size() > 1 else {}
			if item.is_empty() or goal.is_empty() or goal.get("uid") == item.get("uid") or grid == null: return [null]
			return [1.0 if not grid.approach(Vector2i(item.x, item.y), goal, item.get("ship", false)).is_empty() else null]
		# Static passability for the hero's travel mode: 1 or -1, actors ignored.
		"ExPassability":
			if item.is_empty() or grid == null or args.size() < 3: return [-1.0]
			var cell := Vector2i(int(args[1]), int(args[2]))
			return [1.0 if grid.contains(cell) and grid.passability(cell, item.get("ship", false)) > 0.0 else -1.0]
		"ExGetBuildingMob":
			if item.is_empty():
				vm._fail("Object not found")
				return []
			return [float(item.get("monster", item.get("guard", -1)))]
		# Message boxes are modal but the script runs on; the answer reaches
		# Hook_OnCloseMessageBox, except for the action box and screen lines.
		"ExMessageToScreen": event.emit({"kind": "script_notice", "text": str(first)})
		"ExMessageBoxStandard", "ExMessageBoxStandardAction", "ExMessageBoxDialog", "ExMessageBoxOkCancel":
			# Notebook: a standard box with a
			# hero is journaled with that speaker; OkCancel when its
			# third argument is set; Dialog never (drops its flag).
			if name == "ExMessageBoxStandard" and args.size() > 1 and not ELSecondNotebook._hero(self, args[1]).is_empty(): ELSecondNotebook.add_phrase(self, first, args[1], true)
			elif name == "ExMessageBoxOkCancel" and args.size() > 2 and ELSecondNotebook.lua_flag(args[2]): ELSecondNotebook.add_phrase(self, first, null, false)
			# Standard boxes use the MessageBox panel; Dialog and OkCancel
			# the TextDialog without a speaker.
			var box := {"kind": "message_box", "speaker": -1, "text": map.profile.text(str(first)), "question": name == "ExMessageBoxOkCancel", "hook": name != "ExMessageBoxStandardAction",
				"box": "message" if name in ["ExMessageBoxStandard", "ExMessageBoxStandardAction"] else "text", "speaker_box": false}
			# ExMessageBoxStandard(text, hero, dx, dy): centred on the topmost
			# modal window, moved by (dx, dy) design pixels.
			if name == "ExMessageBoxStandard" and args.size() > 3: box.offset = [float(args[2]) if args[2] != null else 0.0, float(args[3]) if args[3] != null else 0.0]
			event.emit(box)
		"ExBlinkElement":
			# an empty name is only logged and an unknown one ignored.
			var element := str(first) if first != null else ""
			if element.is_empty(): push_warning("ExBlinkElement: Empty element")
			elif BLINK_ELEMENTS.has(element):
				var on := args.size() > 1 and _truthy_flag(args[1])
				if on: blinks[element] = true
				else: blinks.erase(element)
				event.emit({"kind": "blink", "element": element, "on": on})
		"ExIsDesktopModalChild": return [1.0 if desktop_modal.is_valid() and bool(desktop_modal.call()) else null]
		"ExMessageBoxDialogHero", "ExMessageBoxHeroOkCancel":
			if args.size() > 3 and ELSecondNotebook.lua_flag(args[3]): ELSecondNotebook.add_phrase(self, args[1] if args.size() > 1 else null, first, true)
			# A speaker TextDialog; an id that is not a hero shows the unknown speaker.
			event.emit({"kind": "message_box", "speaker": int(first) if first is float or first is int else -1, "text": map.profile.text(str(args[1]) if args.size() > 1 else ""), "question": name == "ExMessageBoxHeroOkCancel", "hook": true,
				"box": "text", "speaker_box": true})
		"ExWaitCmd": event.emit({"kind": "script_wait", "ticks": maxf(0.0, float(first) if first != null else 0.0)})
		# Script affects: hero status entries {name, id} from the AffectsList.
		"ExStartAffect", "ExFinishAffect", "ExGetAffectCount", "ExGetAffectByIndex":
			if item.get("type") != "hero":
				vm._fail("Hero not found: %d" % int(first if first is float or first is int else -1))
				return []
			if not item.has("affects"): item.affects = []
			match name:
				"ExStartAffect":
					item.affects.append({"name": str(args[2]) if args.size() > 2 and args[2] != null else "", "id": str(args[1]) if args.size() > 1 and args[1] != null else ""})
					event.emit({"kind": "affects_changed", "id": item.uid})
				"ExFinishAffect":
					var wanted := str(args[1]) if args.size() > 1 and args[1] != null else ""
					item.affects = item.affects.filter(func(entry: Dictionary) -> bool: return str(entry.id) != wanted)
					event.emit({"kind": "affects_changed", "id": item.uid})
				"ExGetAffectCount": return [float(item.affects.size())]
				_:
					var index := int(args[1]) if args.size() > 1 and args[1] != null else -1
					if index < 0 or index >= item.affects.size(): return [null, null]
					return [item.affects[index].name, item.affects[index].id]
		"ExSetThemeFadeIn": theme_fade.x = float(first)
		"ExSetThemeFadeOut": theme_fade.y = float(first)
		"ExExecuteCmd":
			if not item.is_empty() and not item.orders.is_empty() and item.orders[0] is Dictionary:
				commands.append(item.orders[0].duplicate(true))
		"ExSoftAbortCmd":
			if not item.is_empty(): item.orders.clear()
		"ExAbortAllCommand": commands.clear()
		"ExCheckIntercepts":
			# Second game: the hero's cell in the guard zones, with the veto hook.
			if map.profile.id == "el2" and interception != null:
				return [float(interception.intercept(self, item, Vector2i(item.x, item.y))) if not item.is_empty() else -1.0]
			if not item.is_empty():
				for other_id: int in _mob_ids:
					var other: Dictionary = objects[other_id]
					if other.alive and other.enabled and other.type == "monster" and hostile(item, other) and maxi(absi(item.x - other.x), absi(item.y - other.y)) <= 1: return [float(other.uid)]
			return [-1.0]
		"ExSetExclusiveFlag": exclusive = first != null and first != 0
		"ExGetTextByID": return [map.profile.text(str(first))]
		"ExSetUsability":
			if not item.is_empty() and args.size() > 1: item.enabled = args[1] != null and args[1] != 0
		"ExGetUsability": return [1.0 if item.get("enabled", false) else null]
		"ExClearHand":
			if not item.is_empty():
				item.cards.clear()
				if item.has("rune_uses"): item.rune_uses.clear()
		"ExAddSpellToHand":
			if not item.is_empty() and args.size() > 1 and item.cards.size() < ELSpellInventory.book_size(map.profile) and ELSpellInventory.is_spell(map.profile, str(args[1])):
				if map.profile.id == "el1":
					if not ELRunes.restore(map.profile, item):
						_fail("Invalid rune inventory.")
						return []
					item.rune_uses.append(-1 if ELRunes.unlimited(map.profile, item, str(args[1])) else 0)
				item.cards.append(str(args[1]))
		"ExAddSpell", "ExRemoveSpell":
			if not item.is_empty() and args.size() > 1:
				var card := str(args[1])
				if name == "ExAddSpell": ELSpellInventory.add(map.profile, item, card)
				else: ELSpellInventory.remove(item, card)
		"ExHasSpell": return [1.0 if not item.is_empty() and args.size() > 1 and int(item.spell_stock.get(str(args[1]), 0)) > 0 else null]
		"ExStartLootMessage": _loot_message.clear()
		"ExAddLootMessageSpell": _loot_message.append({"kind": "spell", "card": str(first)})
		# Second-game artifacts: case-sensitive Artefacts names, a new copy at full
		# charges per add, no message (the library's AddArtefact adds the loot line).
		"ExAddLootMessageArtefact":
			if _artefact_valid(str(first)): _loot_message.append({"kind": "artifact", "name": str(first)})
		"ExAddArtefact", "ExRemoveArtefact", "ExHasArtefact":
			if item.get("type") != "hero":
				vm._fail("Hero not found: %d" % int(first if first is float or first is int else -1))
				return []
			var artefact := str(args[1]) if args.size() > 1 and args[1] != null else ""
			if not _artefact_valid(artefact): return []
			if not item.has("artifacts"): item.artifacts = []
			var index := -1
			for i in item.artifacts.size():
				if str(item.artifacts[i].get("name", "")) == artefact:
					index = i
					break
			if name == "ExHasArtefact": return [1.0 if index >= 0 else null]
			if name == "ExAddArtefact": item.artifacts.append(ELSecondArtifacts.entry(self, artefact))
			elif index >= 0: item.artifacts.remove_at(index)
		# The artifact constructor: a new
		# CustomN template and a full-charge copy for the main hero.
		"ExCreateArtifact":
			var code := str(args[1]) if args.size() > 1 and args[1] != null else ""
			if not map.profile.table("CombatSpells").has(code):
				vm._fail("Spell not found: " + code)
				return []
			var hero := object(main_hero)
			if hero.get("type") != "hero":
				vm._fail("Main hero not found")
				return []
			var values: Array[int] = []
			for index in [2, 3, 4, 5]:
				var value: Variant = args[index] if args.size() > index else null
				values.append(int(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else (-1 if index == 5 else 0))
			return [ELSecondArtifacts.create(self, hero, str(first), code, values[0], values[1], values[2], values[3])]
		# The created-artifact box follows the battle's processing; it raises no close hook.
		"ExMessageBoxArtefactCreated":
			var definition := ELSecondArtifacts.template(self, str(first))
			if definition.is_empty(): return []
			var made := {"name": str(first), "custom": definition}
			event.emit({"kind": "message_box", "speaker": -1, "text": map.profile.text("T_MB_ARTEFACT_CREATED") + "\n" + ELSecondArtifacts.title(map.profile, made),
				"question": false, "hook": false, "artifact": str(first), "card": str(definition.spell), "box": "message", "speaker_box": false})
		"ExRechargeArtefacts":
			if item.get("type") != "hero":
				vm._fail("Hero not found: %d" % int(first if first is float or first is int else -1))
				return []
			ELSecondArtifacts.recharge(map.profile, item)
			event.emit({"kind": "inventory_changed", "id": int(item.uid)})
		# Opens the main hero's inventory; the view shows it until the player closes it.
		"ExShowInventory":
			if object(main_hero).get("type") == "hero": event.emit({"kind": "show_inventory", "id": main_hero})
		# Second-game barriers: scripts open and close them silently, without keys.
		"ExOpenGate", "ExCloseGate":
			if not ELSecondGates.is_gate(item):
				vm._fail("Gate not found: %d" % int(first if first is float or first is int else -1))
				return []
			ELSecondGates.set_open(self, item, name == "ExOpenGate")
		"ExGiveKey":
			if item.get("type") != "hero":
				vm._fail("Hero not found: %d" % int(first if first is float or first is int else -1))
				return []
			ELSecondGates.give_key(item, str(args[1]) if args.size() > 1 and args[1] != null else "")
		"ExGetArtefactBlankCount", "ExSetArtefactBlankCount":
			if item.get("type") != "hero":
				vm._fail("Hero not found: %d" % int(first if first is float or first is int else -1))
				return []
			if not item.has("artifacts"): item.artifacts = []
			var blanks: Array[int] = []
			for i in item.artifacts.size():
				if _artefact_blank(str(item.artifacts[i].get("name", ""))): blanks.append(i)
			if name == "ExGetArtefactBlankCount": return [float(blanks.size())]
			var wanted := maxi(0, int(args[1]) if args.size() > 1 and args[1] != null else 0)
			for i in range(blanks.size() - 1, wanted - 1, -1): item.artifacts.remove_at(blanks[i])
			for i in range(blanks.size(), wanted): item.artifacts.append(_artefact_entry("Blank"))
		"ExSendLootMessage", "ExSendNoLootMessage":
			var message := {"kind": "loot", "items": _loot_message.duplicate(true) if name == "ExSendLootMessage" else []}
			messages.append(message)
			event.emit(message)
			_loot_message.clear()
		"ExAllowCardColor":
			if not item.is_empty() and args.size() > 2 and str(args[1]) in ELSpellInventory.MAGIC_COLORS:
				if not item.has("allowed_colors"): item.allowed_colors = {}
				item.allowed_colors[str(args[1])] = args[2] != null and args[2] != 0
		"ExIsCardColorAllowed":
			if not item.is_empty() and args.size() > 1: return [1.0 if ELSpellInventory.color_enabled(item, str(args[1])) else null]
			return [null]
		"ExTakeObject":
			if not item.is_empty():
				item.visible = false
				item.placed = false
				event.emit({"kind": "object_changed", "id": item.uid})
		"ExPlaceObject":
			if not item.is_empty() and args.size() > 2:
				item.visible = true
				item.placed = true
				item.x = int(args[1])
				item.y = int(args[2])
				# EL2 actors travel by ship wherever they are set down on water.
				if map.profile.id == "el2" and item.get("type") in ["hero", "monster"]: item.ship = _water_cell(item.x, item.y)
				event.emit({"kind": "object_changed", "id": item.uid})
		"ExGetRotateMirror": return [float(item.get("rotation", 0))]
		"ExSetRotateMirror":
			if not item.is_empty() and args.size() > 1:
				item.rotation = int(args[1])
				event.emit({"kind": "object_changed", "id": item.uid})
		"ExJumpToPos":
			if not item.is_empty() and args.size() > 2:
				item.x = int(args[1])
				item.y = int(args[2])
				# EL2 actors travel by ship wherever they are set down on water.
				if map.profile.id == "el2" and item.get("type") in ["hero", "monster"]: item.ship = _water_cell(item.x, item.y)
				event.emit({"kind": "object_changed", "id": item.uid})
		"ExCameraGetZoom": return [camera_zoom]
		"ExCameraGetRotate": return [camera_rotation]
		"ExCameraLock":
			camera_locked = true
			event.emit({"kind": "camera_lock", "locked": true})
		"ExCameraUnlock":
			camera_locked = false
			event.emit({"kind": "camera_lock", "locked": false})
		"ExCameraRotate":
			camera_rotation = float(first)
			event.emit({"kind": name, "arguments": args.duplicate()})
		# Zoom and pitch take a value and an optional duration (-1 = default).
		"ExCameraZoom":
			camera_zoom = float(first)
			event.emit({"kind": name, "arguments": args.duplicate()})
		"ExCameraPitch":
			event.emit({"kind": name, "arguments": args.duplicate()})
		"ExCameraInstantScrollToObject", "ExCameraInstantScrollToPos":
			event.emit({"kind": name.replace("Instant", ""), "arguments": args.duplicate(), "instant": true})
		"ExTrace": pass
		"ExError": vm._fail("Scenario error: " + str(first))
		"ExGetTickCount": return [float(Time.get_ticks_msec())]
		"ExGetTickCountDelta": return [float(Time.get_ticks_msec()) - float(first if first != null else 0.0)]
		"ExGetHeroName": return [str(item.get("title", item.get("name", "")))]
		"ExGetExclusiveFlag": return [1.0 if exclusive else null]
		"ExCanRunToPos", "ExIsAccesibleGoalPos":
			if item.is_empty() or grid == null or args.size() < 3: return [null]
			return [1.0 if not grid.path(Vector2i(item.x, item.y), Vector2i(int(args[1]), int(args[2])), item.get("ship", false)).is_empty() else null]
		"ExCanRunToObject", "ExIsAccesibleGoalObject":
			var goal := object(args[1]) if args.size() > 1 else {}
			if item.is_empty() or goal.is_empty() or grid == null: return [null]
			return [1.0 if not grid.approach(Vector2i(item.x, item.y), goal, item.get("ship", false)).is_empty() else null]
		"ExIsNear":
			var other := object(args[1]) if args.size() > 1 else {}
			if item.is_empty() or other.is_empty(): return [null]
			return [1.0 if maxi(absi(int(item.x) - int(other.x)), absi(int(item.y) - int(other.y))) <= 1 else null]
		"ExOrientMobToPoint":
			if not item.is_empty() and args.size() > 2: event.emit({"kind": "orient_to_point", "id": item.uid, "x": float(args[1]), "y": float(args[2])})
		"ExCameraScrollToObject", "ExCameraScrollToPos", "ExStartEmphasisTheme", "ExStopEmphasisTheme":
			event.emit({"kind": name, "arguments": args.duplicate()})
		"ExStartBackgroundTheme": ELSecondAmbience.start_theme(self, args)
		"ExStopBackgroundTheme": ELSecondAmbience.stop_theme(self)
		"ExFinishEffect": ELSecondAmbience.finish_effect(self, first)
		"ExSoundCancelFX": ELSecondAmbience.cancel_sound(self, first)
		"ExGetThemeFadeIn": return [theme_fade.x]
		"ExGetThemeFadeOut": return [theme_fade.y]
		# Both return nothing.
		"ExStartEffect": ELSecondAmbience.start_effect(self, args)
		"ExSoundBeginFX": ELSecondAmbience.start_sound(self, args)
		"ExOrientEffectByObject": ELSecondAmbience.orient_effect(self, first, args[1] if args.size() > 1 else null)
		# The shipped ExOrientEffect(name) finishes the named effect (
		# calls the ExFinishEffect routine); no script uses it.
		"ExOrientEffect": ELSecondAmbience.finish_effect(self, first)
		_:
			vm._fail("Adventure binding is not implemented: " + name)
	return []

func _artefact_valid(artefact: String) -> bool:
	if artefact.is_empty():
		vm._fail("Empty string.")
		return false
	# Generated (CustomN) templates count once any hero carries one.
	if not ELSecondArtifacts.known(self, artefact):
		vm._fail("Artefact not found: " + artefact)
		return false
	return true

func _artefact_entry(artefact: String) -> Dictionary:
	return {"name": artefact, "charges": int(map.profile.table("Artefacts").get(artefact, {}).get("MaxCharges", 0))}

## Blank artifacts are those whose spell type is BLNK ("Blank" in shipped data).
func _artefact_blank(artefact: String) -> bool:
	return str(map.profile.table("Artefacts").get(artefact, {}).get("SpellType", "")) == "BLNK"

func _fail(message: String) -> bool:
	error = message
	return false
