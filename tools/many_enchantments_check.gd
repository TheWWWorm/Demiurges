extends SceneTree
## Headless check of a battle with many enchantments (player report: a hero
## with a dozen copies each of two enchantments made the tooltip fill the
## screen and the frame rate drop). For each game whose files are configured:
## - the hero tooltip (portrait and figure) lists each distinct enchantment
##   once, with its count ("Name ×12: text"), in the order of first copy
##   (first game; the second game's lists none, #230/#274);
## - the creature tooltip shows the printed card, without the enchantments
##   (#202/#230, first game #254);
## - the battle tooltip frame stays inside the viewport however many lines
##   it holds;
## - per-frame work stays bounded: an idle battle with the enchanted hero
##   selected makes no panel or strip rebuilds and adds no nodes frame to
##   frame, a refresh keeps the strip's buttons, the hidden remake readout is
##   not built, and many copies of one effect on one figure in one frame
##   start only the view's SAME_FRAME_EFFECTS effects.
##
##   godot --headless --path game --script ../tools/many_enchantments_check.gd
##
## Needs the original games' files (user://profiles.json, as set up by the
## game); without them a game is skipped. Settings are never written.

const COPIES := 12
## Hero enchantments tried, in order, for the two stacked on the hero.
const HERO_CARDS := ["SACR", "MNTX", "VTLY", "WETX", "WRBN", "LFGR", "ENRG"]

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		await _edition(edition)
	print("MANY ENCHANTMENTS: %d failure(s)" % failures.size())
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
	view._start(edition)
	await _idle(view)
	var duel: ELDuel = view.duel
	var spells: Dictionary = view.profile.table("CombatSpells")
	# Two creatures on side 0 to carry creature enchantments.
	var summons: Array[String] = []
	for row: String in view.profile.table("CombatCreatures"):
		if duel.is_summon(row): summons.append(row)
	for i in 2:
		duel.heroes[0].mana = 99
		duel.cast_free(0, summons[i], [], false)
		await _idle(view)
	var creature := -1
	for id: int in duel.creatures:
		if int(duel.creatures[id].owner) == 0: creature = id
	check(creature >= 2, "%s: a creature stands on the field" % edition)
	# A dozen copies each of two hero enchantments.
	var stacked: Array[String] = []
	for card: String in HERO_CARDS:
		if stacked.size() >= 2 or not spells.has(card): continue
		var placed := 0
		for i in COPIES:
			duel.heroes[0].mana = 99
			if duel.cast_free(0, card, [0], false): placed += 1
		if placed == COPIES: stacked.append(card)
		await _idle(view)
	check(stacked.size() == 2, "%s: %d copies each of two hero enchantments are in play (%s)" % [edition, COPIES, stacked])
	# Creature enchantments: three copies of the first that stacks, then one other.
	var creature_cards: Array[String] = []
	if creature >= 2:
		for card: String in spells:
			if creature_cards.size() >= 2 or str(spells[card].get("Class", "")) != "Enchantment": continue
			if not duel.target_kind(card).contains("creature"): continue
			var placed := 0
			for i in (3 if creature_cards.is_empty() else 1):
				duel.heroes[0].mana = 99
				if not duel.creatures.has(creature): break
				# Only a copy the creature itself holds counts (a water link is the hero's).
				var held := _count(duel.creatures[creature], card)
				duel.cast_free(0, card, [creature], false)
				if duel.creatures.has(creature) and _count(duel.creatures[creature], card) > held: placed += 1
			if not duel.creatures.has(creature): break
			if placed > 0 and (placed == 3 or not creature_cards.is_empty()): creature_cards.append(card)
		await _idle(view)
	check(creature_cards.size() == 2 and duel.creatures.has(creature), "%s: creature enchantments are in play (%s)" % [edition, creature_cards])
	var hero: Dictionary = duel.heroes[0]
	var lines: PackedStringArray = view._enchantment_lines(hero)
	var distinct := _distinct(hero)
	check(lines.size() == distinct.size(), "%s: the hero's %d enchantments give %d lines, one per card (%d)" % [edition, hero.enchantments.size(), lines.size(), distinct.size()])
	for index in mini(lines.size(), distinct.size()):
		var card: String = distinct[index]
		var count := _count(hero, card)
		var head: String = duel.card_name(card) + (" ×%d" % count if count > 1 else "")
		check(lines[index].begins_with(head), "%s: hero line %d names %s with its count (%s)" % [edition, index, card, JSON.stringify(lines[index].left(60))])
	# The portrait tooltip and the figure tooltip of the hero.
	for portrait: bool in [true, false]:
		var tip: Dictionary = view._hero_tip(0, view.portraits[0] if portrait else null)
		var texts := _texts(tip)
		for card: String in stacked:
			var name: String = duel.card_name(card)
			var shown := 0
			for text: String in texts:
				if text.begins_with(name if edition == "el2" else name + " ×%d" % COPIES): shown += 1
			# The second game's hero tooltip lists no enchantments (#230, #274).
			if edition == "el2": check(shown == 0, "el2 #230/#274: the hero %s tooltip lists no enchantments (%s: %d)" % ["portrait" if portrait else "figure", name, shown])
			else: check(shown == 1, "%s: the hero %s tooltip lists %s once with ×%d (%d)" % [edition, "portrait" if portrait else "figure", name, COPIES, shown])
		check(texts.size() <= 16, "%s: the hero %s tooltip has %d lines" % [edition, "portrait" if portrait else "figure", texts.size()])
		await _fits(view, tip, "%s hero %s" % [edition, "portrait" if portrait else "figure"])
	if duel.creatures.has(creature) and creature_cards.size() == 2:
		var text: String = view._creature_tip_text(creature)
		var card := String(duel.creatures[creature].card)
		check(text == ELCombatTooltip.spell_text(duel.profile, card, -1, duel.card_name(card)), "%s #202/#230/#254: the creature tooltip is the original card text" % edition)
		await _fits(view, ELCombatTooltip.text_content(text), edition + " creature")
	# A tooltip far taller than the screen is shrunk to fit it.
	var tall := PackedStringArray()
	for i in 80: tall.append("Line %d of a very long tooltip" % i)
	await _fits(view, ELCombatTooltip.text_content("\n".join(tall)), edition + " 80-line")
	# Per-frame work with the enchanted hero selected.
	view.selected_creature = 0
	view._refresh()
	for i in 10:
		view.ai_clock = -1000.0
		await process_frame
	var refreshes: int = view.refresh_count
	var fills: int = view.strip_fill_count
	var nodes := root.get_tree().get_node_count()
	for i in 120:
		view.ai_clock = -1000.0
		await process_frame
	check(view.refresh_count == refreshes, "%s: an idle battle makes no full refresh (%d in 120 frames)" % [edition, view.refresh_count - refreshes])
	check(view.strip_fill_count == fills, "%s: an idle battle does not rebuild the strip (%d in 120 frames)" % [edition, view.strip_fill_count - fills])
	# A figure's idle sound or cue may come and go; nothing grows per frame.
	check(root.get_tree().get_node_count() <= nodes + 8, "%s: an idle battle adds no nodes frame by frame (%d -> %d in 120 frames)" % [edition, nodes, root.get_tree().get_node_count()])
	var strip: ELCombatStrip = view.rail.strip if view.rail != null else null
	if strip != null:
		var before := strip.buttons.map(func(button: Node) -> int: return button.get_instance_id())
		view._refresh()
		var kept := strip.buttons.map(func(button: Node) -> int: return button.get_instance_id())
		check(before.size() >= hero.enchantments.size() and before == kept, "%s: a refresh keeps the strip's %d buttons" % [edition, before.size()])
	if not view.helper_overlay():
		check(view.inspector_rows.get_child_count() == 0 or view.inspector_rows.get_children().all(func(row: Node) -> bool: return row.is_queued_for_deletion()), "%s: the hidden readout is not built" % edition)
	# Many copies of one effect on one figure in the same frame.
	await process_frame
	var effect_nodes := root.get_tree().get_node_count()
	for i in 3: view._figure_effect("GainMana", 0)
	var three := root.get_tree().get_node_count() - effect_nodes
	for i in 20: view._figure_effect("GainMana", 0)
	var more := root.get_tree().get_node_count() - effect_nodes
	check(more == three, "%s: 23 GainMana effects on the hero in one frame start no more than %d (%d nodes, %d for 3)" % [edition, view.SAME_FRAME_EFFECTS, more, three])
	await process_frame
	var next := root.get_tree().get_node_count()
	view._figure_effect("GainMana", 0)
	check(root.get_tree().get_node_count() > next, "%s: the next frame starts the effect again" % edition)
	view.queue_free()
	await process_frame
	await process_frame

## The cards on `entity`, each once, in the order of its first copy.
func _distinct(entity: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for enchantment: Dictionary in entity.get("enchantments", []):
		if not result.has(String(enchantment.card)): result.append(String(enchantment.card))
	return result

func _count(entity: Dictionary, card: String) -> int:
	var count := 0
	for enchantment: Dictionary in entity.get("enchantments", []):
		if String(enchantment.card) == card: count += 1
	return count

func _texts(content: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for label: Dictionary in content.get("labels", []): result.append(String(label.text))
	return result

## Shows `content` in the battle tooltip at a few pointer places and checks
## that the frame lies inside the viewport.
func _fits(view: Node, content: Dictionary, what: String) -> void:
	var tip: ELCombatTooltip = view.combat_tip
	tip.panel.set_content(-1, content)
	tip.panel.show()
	await process_frame
	var screen := tip.get_global_transform_with_canvas().affine_inverse() * tip.get_viewport_rect()
	var inside := true
	for cursor: Vector2 in [Vector2(20, 20), screen.size * 0.5, screen.size - Vector2(20, 20), Vector2(screen.size.x - 20, 20)]:
		tip._layout_tip(cursor)
		var frame := Rect2(tip.panel.position, tip.panel.size * tip.panel.scale)
		if not screen.grow(0.5).encloses(frame):
			inside = false
			print("  %s at %s: frame %s, screen %s" % [what, cursor, frame, screen])
	check(inside, "%s tooltip (%d lines) stays inside the viewport" % [what, content.get("labels", []).size()])
	tip.hide_tip()

func _idle(view: Node) -> void:
	for i in 600:
		view.ai_clock = -1000.0
		await process_frame
		if not view._cast_busy() and not view._presentation_held() and view._hits_waiting.is_empty() and view._arrivals.is_empty() and view._effect_cast.is_empty(): return
