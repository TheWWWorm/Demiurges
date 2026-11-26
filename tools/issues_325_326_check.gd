extends SceneTree
## Casting gesture checks for two player reports, in both games:
##
## - #325: the sorcery Rage (FURY) plays the hero's sorcery (instant)
##   gesture, not the enchantment one.
## - #326: so do the other sorceries that leave a lasting effect: Fog,
##   Blessing, Mirror, Ether Resonance, Alpha Strike, Ash Storm, Assault,
##   and in the first game Impotence, in the second Ether Vortex and Planar
##   Seal, and the second game's artifact spells Protection, Dust and
##   Reflection. The gesture follows the spell's class in CombatSpells
##   (Creature: summoning, Sorcery: instant, Enchantment: enchantment), so
##   enchantments keep the enchantment gesture (the second game's Quick Fix,
##   a one-off effect, now takes it too) and creatures the summoning one.
##   A live cast of Fog starts the instant clip; with "Hide casting
##   animations" it starts none.
##
##   godot --headless --path game --script ../tools/issues_325_326_check.gd
##
## Needs the original games' files (user://profiles.json); a game without them
## is skipped. Settings are never written.

const SORCERIES := {
	"el1": ["FURY", "FOGG", "BLSS", "FDBK", "ETCH", "ALST", "ASST", "ASLT", "ENFL"],
	"el2": ["FURY", "FOGG", "BLSS", "FDBK", "ETCH", "ALST", "MNVR", "ASST", "ASLT", "PLSL"],
}
## Second-game artifact spells of the sorcery class with lasting effects.
const ARTIFACT_SORCERIES := ["RDDF", "PCDU", "LNRD"]

var failures := 0

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	view.settings.values.hide_cast = false
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		var profile := ELProfile.new()
		if not profile.mount(edition, str(paths[edition])) or not view.profiles.has(edition):
			print("SKIP: %s files could not be mounted" % edition)
			continue
		view._start(edition)
		await _idle(view)
		_gestures(view, edition)
		await _live_cast(view, edition)
	view.settings.values.hide_cast = false
	view.queue_free()
	await process_frame
	print("ISSUES 325/326: %d failure(s)" % failures)
	quit(int(failures > 0))

func _idle(view: Node) -> void:
	for i in 900:
		view.ai_clock = -1000.0
		await process_frame
		if not view._cast_busy() and not view._presentation_held() and view._hits_waiting.is_empty() and view._arrivals.is_empty() \
				and view._effect_cast.is_empty() and not view._shown_held() and not view.figures_turning(): return

func _name(view: Node, card: String) -> String:
	return "%s (%s)" % [ELEncyclopaedia.name(view.profile, card), card]

## The gesture and the hero's clip each card asks for.
func _gestures(view: Node, edition: String) -> void:
	var spells: Dictionary = view.profile.table("CombatSpells")
	var hero: ELModel = view.models[0]
	var cards: Array = SORCERIES[edition].duplicate()
	if edition == "el2": cards.append_array(ARTIFACT_SORCERIES)
	for card: String in cards:
		check(str(spells.get(card, {}).get("Class", "")) == "Sorcery", "%s: %s is a sorcery in the data" % [edition, _name(view, card)])
		check(ELCatalog.rule(view.profile, card).get("effect") == "enchant", "%s: %s leaves a lasting effect" % [edition, _name(view, card)])
		check(view._cast_gesture(card) == "uinstant", "%s: %s asks for the sorcery gesture (%s)" % [edition, _name(view, card), view._cast_gesture(card)])
		if hero.has_clip("uinstant"):
			check(view._cast_clip(0, card) == "uinstant", "%s: the hero plays its instant clip for %s" % [edition, _name(view, card)])
	for card: String in ARTIFACT_SORCERIES if edition == "el2" else []:
		check(view._artifact_clip(0, card) == view._cast_clip(0, card), "%s: an artifact with %s plays that spell's gesture" % [edition, _name(view, card)])
	# A few enchantments (the rule an enchant) and summons, by the data.
	var enchantments: Array[String] = []
	var summons: Array[String] = []
	var keys: Array = spells.keys()
	keys.sort()
	for card: String in keys:
		var rule := ELCatalog.rule(view.profile, card)
		var cls := str(spells[card].get("Class", ""))
		if cls == "Enchantment" and rule.get("effect") == "enchant" and enchantments.size() < 4: enchantments.append(card)
		if cls == "Creature" and rule.get("effect") == "summon" and summons.size() < 4: summons.append(card)
	if edition == "el2": enchantments.append("QKFX")
	check(enchantments.size() >= 4 and summons.size() == 4, "%s: enchantments and creatures to compare" % edition)
	for card: String in enchantments:
		check(view._cast_gesture(card) == "uenchantment", "%s: the enchantment %s asks for the enchantment gesture (%s)" % [edition, _name(view, card), view._cast_gesture(card)])
		if hero.has_clip("uenchantment"):
			check(view._cast_clip(0, card) == "uenchantment", "%s: the hero plays its enchantment clip for %s" % [edition, _name(view, card)])
	for card: String in summons:
		check(view._cast_gesture(card) == "usummon", "%s: the creature %s asks for the summoning gesture (%s)" % [edition, _name(view, card), view._cast_gesture(card)])
	# Every sorcery with a rule asks for the instant gesture.
	var wrong: Array[String] = []
	for card: String in keys:
		if ELCatalog.rule(view.profile, card).is_empty(): continue
		var want: String = {"Creature": "usummon", "Sorcery": "uinstant", "Enchantment": "uenchantment"}.get(str(spells[card].get("Class", "")), "")
		if not want.is_empty() and view._cast_gesture(card) != want: wrong.append(card)
	check(wrong.is_empty(), "%s: every card's gesture follows its class %s" % [edition, str(wrong)])

## A cast of Fog starts the hero's instant clip; hidden casting animations
## start none.
func _live_cast(view: Node, edition: String) -> void:
	var duel: ELDuel = view.duel
	var side: int = duel.attacker
	var hero: ELModel = view.models[side]
	for hidden: bool in [false, true]:
		view.settings.values.hide_cast = hidden
		duel.heroes[side].mana = 40
		var clips: Array[String] = []
		var listen := func(clip: String) -> void: clips.append(clip)
		hero.animation_started.connect(listen)
		var what := "%s: a cast of Fog%s" % [edition, " (casting animations hidden)" if hidden else ""]
		check(duel.cast_free(side, "FOGG", [], true), "%s is accepted (%s)" % [what, duel.error])
		for i in 10: await process_frame
		hero.animation_started.disconnect(listen)
		if hidden: check(not clips.has("uinstant") and not clips.has("uenchantment"), "%s starts no casting gesture %s" % [what, str(clips)])
		else: check(clips.has("uinstant") and not clips.has("uenchantment"), "%s starts the instant clip %s" % [what, str(clips)])
		await _idle(view)
