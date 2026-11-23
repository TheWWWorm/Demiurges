extends SceneTree
## Headless check that a direct-damage spell's damage and deaths show when its
## effect hits, not when the rules settle the cast:
## - a creature killed by Chain Lightning (CLIG) keeps its numbers and does not start its
##   death until the spell's hit time (the caster's release frame plus the
##   effect's MonstersHit cue, if it has one);
## - a hero (or monster opponent) killed by Zap (ZAPP) keeps its shown health
##   and does not fall, nor does the duel's ending begin, before that time;
## - a spell with an authored hit cue (Comet) waits for that cue too;
## - all of it is shown once the hit time has passed;
## - a creature killed by another's ability (the Aviak Archer's Wing Flap)
##   does not fall before the archer's shot reaches its impact frame.
## Runs for each game whose files are configured.
##
##   godot --headless --path game --script ../tools/spell_hit_timing_check.gd
##
## Needs the original games' files (user://profiles.json, as set up by the
## game); without them a game is skipped. Settings are never written.

const DuelView := preload("res://src/duel/view.gd")
const Fixtures := preload("res://../tools/duel_fixtures.gd")

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		await _edition(edition)
		await _wing_flap(edition)
	print("SPELL HIT TIMING: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _edition(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has(edition):
		print("SKIP: %s files could not be mounted" % edition)
		view.queue_free()
		await process_frame
		return
	view.settings.values.hide_cast = false
	view._start(edition)
	await _idle(view)
	# A creature of the opponent's, with as much toughness left as Chain
	# Lightning deals (its RedLightning effect has no hit cue: it hits at the
	# caster's release frame).
	var duel: ELDuel = view.duel
	var caster := duel.active_side()
	var victim := await _summoned(view, 1 - caster)
	check(victim >= 2, "%s: a creature stands on the opposing side" % edition)
	if victim >= 2:
		duel.creatures[victim].damage = maxi(0, int(duel.creatures[victim].toughness) - 3)
		await _idle(view)
		await _lethal_cast(view, caster, "CLIG", victim, "%s Chain Lightning on a creature" % edition)
	await _idle(view)
	# A spell with an authored hit cue.
	victim = await _summoned(view, 1 - caster)
	if victim >= 2:
		duel.creatures[victim].damage = maxi(0, int(duel.creatures[victim].toughness) - 1)
		duel.heroes[caster].mana = maxi(int(duel.heroes[caster].mana), 20)
		await _idle(view)
		await _lethal_cast(view, caster, "COMT", victim, "%s Comet on a creature" % edition, [1])
	await _idle(view)
	# The deciding spell on the opposing hero ends the duel at its hit.
	duel.heroes[1 - caster].health = 1
	await _idle(view)
	await _lethal_cast(view, caster, "ZAPP", 1 - caster, "%s Zap on the opposing hero" % edition)
	view.queue_free()
	await process_frame
	await process_frame

## Waits until nothing of the previous action is on screen.
func _idle(view: Node) -> void:
	for i in 600:
		view.ai_clock = -1000.0
		await process_frame
		if not view._cast_busy() and not view._presentation_held() and view._hits_waiting.is_empty() and view._arrivals.is_empty() and view._effect_cast.is_empty(): return

## A new creature on `side` (a free script summon of its first creature card).
func _summoned(view: Node, side: int) -> int:
	var duel: ELDuel = view.duel
	var before: Array = duel.creatures.keys()
	var card := ""
	for row: String in view.profile.table("CombatCreatures"):
		if duel.is_summon(row):
			card = row
			break
	duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 30)
	duel.cast_free(side, card, [], false)
	await _idle(view)
	for id: int in duel.creatures:
		if not before.has(id): return id
	return -1

## Whether the figure's numbers row is drawn.
func _has_numbers(view: Node, id: int) -> bool:
	if not is_instance_valid(view.symbols): return true
	for figure: Dictionary in view.symbols.figures:
		if int(figure.id) == id: return true
	return false

## Casts `card` from `caster` at `target` (lethal by the setup) and watches
## the screen until well after its hit time.
func _lethal_cast(view: Node, caster: int, card: String, target: int, what: String, extra: Array = []) -> void:
	var duel: ELDuel = view.duel
	var hero := target < 2
	var health_before: int = view.shown_health(target) if hero else 0
	var wound_before: int = view.shown_damage(target) if not hero else 0
	var model: ELModel = view.models.get(target)
	check(_has_numbers(view, target), "%s: the target's numbers are drawn before the cast" % what)
	# The battle clock the effect cues run on; the wall clock can fall a
	# frame behind on long frames.
	var start: float = view.elapsed
	var args: Array = [target]
	args.append_array(extra)
	if not duel.cast_free(caster, card, args, true):
		check(false, "%s: the cast is legal (%s)" % [what, duel.error])
		return
	var hit := float(view._effect_cast.get("hit", 0.0))
	check(hit > 0.1, "%s: the effect hits after the cast (%.2f s)" % [what, hit])
	var settled := duel.phase == ELDuel.Phase.FINISHED if hero else not duel.creatures.has(target)
	check(settled, "%s: the rules settle the kill at once" % what)
	var early := PackedStringArray()
	var shown_at := -1.0
	for i in 2000:
		view.ai_clock = -1000.0
		await process_frame
		var seconds: float = view.elapsed - start
		var shown := false
		if hero:
			shown = view.shown_health(target) != health_before or not view.ending.is_empty() or (is_instance_valid(model) and model.clip == "udeath")
		else:
			shown = not is_instance_valid(model) or bool(model.get_meta("dying", false)) or model.clip == "udeath" or view.shown_damage(target) != wound_before or not _has_numbers(view, target)
		if shown and shown_at < 0.0:
			shown_at = seconds
			# One frame's slack: the cue timer fires between frames.
			if seconds < hit - 0.02: early.append("%.3f s" % seconds)
		if seconds > hit + 0.5: break
	check(early.is_empty() and shown_at >= 0.0, "%s: damage and death show at the hit (%.2f s), not before (shown at %.3f s)" % [what, hit, shown_at])
	if hero:
		check(not view.ending.is_empty() and view.shown_health(target) == int(duel.heroes[target].health), "%s: the hero has fallen and its health is shown after the hit" % what)
	else:
		check(not is_instance_valid(model) or bool(model.get_meta("dying", false)), "%s: the creature dies after the hit" % what)

## The Aviak Archer rests to shoot an attacker: the attacker's death waits for
## the archer's action clip to reach its impact frame.
func _wing_flap(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has(edition):
		view.queue_free()
		await process_frame
		return
	var what := "%s Wing Flap on an attacker" % edition
	var position := Fixtures.build(view.profiles[edition], {"attacker": 1, "phase": "defence", "fixed": true,
		"heroes": [{"health": 15, "mana": 0, "hand": []}, {"health": 15, "mana": 0, "hand": []}],
		"creatures": [{"card": "AVMK", "owner": 0}, {"card": "STRT", "owner": 1}]})
	position.attacks = [3]
	view.demo = false
	view._start(edition, {}, position)
	await _idle(view)
	var archer: ELModel = view.models.get(2)
	var model: ELModel = view.models.get(3)
	if archer == null or model == null:
		check(false, "%s: both figures stand" % what)
	else:
		var start: float = view.elapsed
		check(view.duel.use_ability(2, "shoot", 3), "%s: the ability is legal (%s)" % [what, view.duel.error])
		var impact: float = view._action_key(archer)
		check(impact > 0.1, "%s: the archer's shot strikes after the click (%.2f s)" % [what, impact])
		var shown_at := -1.0
		for i in 2000:
			view.ai_clock = -1000.0
			await process_frame
			var seconds: float = view.elapsed - start
			if shown_at < 0.0 and (not is_instance_valid(model) or bool(model.get_meta("dying", false)) or model.clip == "udeath"): shown_at = seconds
			if seconds > impact + 0.5: break
		check(shown_at >= impact - 0.02, "%s: the attacker falls at the shot's impact (%.2f s), not before (fell at %.3f s)" % [what, impact, shown_at])
	view.queue_free()
	await process_frame
	await process_frame
