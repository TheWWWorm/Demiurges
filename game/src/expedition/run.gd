class_name ELExpeditionRun
extends RefCounted
## Standalone Etherlords II expedition. The route and offered cards come from
## seeds. A battle checkpoint also carries the duel's last settled state.

const SAVE_PATH := "user://expedition-el2.json"
const SAVE_FORMAT := "etherlords-el2-expedition"
const SAVE_VERSION := 15
const MAX_SAVE_BYTES := 2 * 1024 * 1024
const ACTS := 3
const FLOORS := 6
const MIN_DECK := 8
const MAX_DECK := 24
const STARTING_LIFE := 24
const LIFE_PER_ACT := 4
const MAX_LIFE_BONUS := 12
const REWARD_RECOVERY := 0.2
const MIRROR_EXCHANGE_COST := 3
const KEEPSAKE_COST := 5
const TRAINING_LIMIT := 2
const STARTING_GOLD := 40
const MAX_GOLD := 9999
const COURIER_COST := 20
const COURIER_REWARD := 55
const TRIAL_EVENT := 9
const REROLL_COST := 12
const BROKER_COST := 12
const BOUNTY_COST := 10
const SWIFT_ROUND_LIMIT := 8
const REFOCUS_COST := 18
const ELITE_VARIANT_GOLD := 10
const RESERVE_LIMIT := 2
const RESERVE_SWAP_COST := 18
const ANVIL_EVENT := 15
const LIBRARY_EVENT := 16
const SCHOLAR_EVENT := 17
const OPENING_COST := 24
const CONSTRUCTOR_EVENT := 18
const FIELD_RECHARGE_COST := 20
const PROJECT_FINISH_COST := 28
const ANVIL_COST := 12
const ELITE_VARIANTS := ["standard", "overcharged", "fortified"]
const DIFFICULTIES := ["standard", "veteran"]
const EXPANDED_ROOM_ROWS := [
	["fight", "fight", "fight"],
	["event", "fight", "event"],
	["fight", "elite", "event"],
	["shop", "rest", "event"],
	# Test the evolving book before the last preparation rooms. Every route
	# contains at least opening combat, a mid-act fight, and its guardian.
	["fight", "fight", "elite"],
	["event", "shop", "rest"],
	["elite", "rest", "treasure"],
	["boss"],
]
const TRAINABLE_SKILLS := ["PRVD", "SUPR"]
# Mounted faction spells that can remove an enemy ward. Green trades a creature.
const CAMP_STUDY := {"Blue": "CLNP", "Black": "PRFY", "Green": "ETTD", "Red": "FLIC"}
const EXPEDITION_ARTIFACTS := ["RingOfHealing", "RodOfLightning"]
const ROOM_ROWS := [
	["fight", "fight", "fight"],
	["event", "fight", "fight"],
	["fight", "elite", "event"],
	["rest", "event", "fight"],
	["elite", "rest"],
	["boss"],
]
const ROOM_TITLES := {
	"fight": "Battle", "elite": "Elite battle", "event": "Encounter",
	"rest": "Rest site", "boss": "Act boss", "shop": "Merchant", "treasure": "Treasure",
}
const COMBAT_ROOMS := ["fight", "elite", "boss"]
const RELIQUARY_EVENT := 3
const WARDEN_EVENT := 4
const EVENTS := [
	["Wayside Spring", "A wayfarer rests by a clear spring. They offer to teach you a spell or lend an artifact."],
	["Spellwright's Mirror", "A copper mirror reflects the pages of your spellbook. It can erase, copy, or transform a spell."],
	["Totem of the Wilds", "The old totem promises to strengthen your life in exchange for a blood oath."],
	["The Silent Reliquary", "A ward keeps two artifacts charged. Offer life to carry one, or take a draught from the workbench."],
	["The Bridge Warden", "A warden challenges you to a duel. Win to earn an elite reward. Defeat ends the expedition."],
]

var profile: ELProfile
var preset: Dictionary = {}
var seed_value := 0
var act := 1
var health := 0
var max_health := 0
var life_bonus := 0
var deck: Array[String] = []
var current := ""
var phase := "map"
var error := ""
var visited: Array[String] = []
var pending_card := ""
var borrowed_artifact := ""
var keepsake_artifact := ""
var _route: Array[Array] = []
var _nodes: Dictionary = {}
var _battle_checkpoint: Dictionary = {}
var _final_battle := {}
var _version := SAVE_VERSION
var _opponents := {}
var _previous_paths := {}
var _training := {}
var gold := 0
var relics: Array[String] = []
var _shop_stock: Array[String] = []
var _shop_relic := ""
var _shop_bought: Array[String] = []
var _removals := 0
var _contract_remaining := 0
var _prepared := false
var _last_reward := {}
var difficulty := "standard"
var pending_relic := ""
var _reroll_used_acts: Array[int] = []
var _reward_roll := 0
var _bounty := {}
var study_path := ""
var keystones: Array[String] = []
var inactive_powers: Array[String] = []
var _keystone_claimed: Array[int] = []
var _detours_used: Array[int] = []
var elite_variant := ""
var reserve: Array[String] = []
var pending_reserve := -1
var pending_craft := ""
var _last_outcome := {}
var opening_spell := ""
var opening_selecting := false
var opening_suppressed := false
var field_artifact := ""
var field_charges := 0
var artifact_project := ""

func implements_enabled() -> bool:
	return _version >= 15

func field_artifact_details() -> Dictionary:
	if not implements_enabled() or field_artifact.is_empty(): return {}
	var detail := ELExpeditionArtifacts.find(profile, field_artifact)
	if not detail.is_empty(): detail.charges = field_charges
	return detail

func artifact_project_details() -> Dictionary:
	if not implements_enabled() or artifact_project.is_empty(): return {}
	var detail := ELExpeditionArtifacts.find(profile, artifact_project)
	if not detail.is_empty(): detail.completion = _project_completion_text()
	return detail

func artifact_use_limit() -> int:
	var skills := _starting_skills()
	skills.merge(trained_skills(), true)
	return [2, 4, 8][clampi(int(skills["ARTF"]), 0, 2)] if skills.has("ARTF") else 1

func _artifact_slots(include_field := true, include_borrowed := true) -> int:
	return preset.get("artifacts", []).size() + int(not keepsake_artifact.is_empty()) + int(include_borrowed and not borrowed_artifact.is_empty()) + int(include_field and implements_enabled() and not field_artifact.is_empty())

func _field_recipe_offers(count: int, salt: int) -> Array[String]:
	var pool := ELExpeditionArtifacts.available(profile)
	pool.erase(field_artifact)
	pool.erase(artifact_project)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_nodes.get(current, {}).get("seed", seed_value)) ^ salt
	for index in range(pool.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var id := pool[index]
		pool[index] = pool[other]
		pool[other] = id
	return pool.slice(0, count)

## Only the current act needs a search: any earlier act still has at least
## two guardians ahead. Include optional duels and one legal Compass detour.
## The cap is two because a field artifact cannot store more charges.
func _remaining_artifact_duels() -> int:
	if finished(): return 0
	if act < ACTS: return 2
	if phase in ["haven", "battle"] and _nodes.get(current, {}).get("kind") == "boss": return 1
	var best := 0
	var queue: Array[Dictionary] = [{"id": current, "wins": 0, "detour": act in _detours_used}]
	var seen := {}
	while not queue.is_empty():
		var state: Dictionary = queue.pop_back()
		var signature := "%s:%d:%s" % [state.id, state.wins, state.detour]
		if seen.has(signature): continue
		seen[signature] = true
		var room: Dictionary = _nodes.get(state.id, {})
		if room.get("kind") == "boss": continue
		var next_ids: Array[String] = []
		if room.is_empty():
			for next: Dictionary in _route[0]: next_ids.append(next.id)
		else: next_ids.assign(room.next)
		var natural := next_ids.duplicate()
		if _has_keystone("wayfarer_compass") and not bool(state.detour) and not room.is_empty() and int(room.floor) < _route.size():
			for next: Dictionary in _route[int(room.floor)]:
				if next.id not in next_ids: next_ids.append(next.id)
		for id: String in next_ids:
			var next: Dictionary = _nodes[id]
			var combat: bool = next.kind in COMBAT_ROOMS or (next.kind == "event" and int(next.get("event", -1)) in [WARDEN_EVENT, TRIAL_EVENT])
			var wins := int(state.wins) + int(combat)
			best = maxi(best, wins)
			if best >= 2: return 2
			queue.append({"id": id, "wins": wins, "detour": bool(state.detour) or id not in natural})
	return best

func _useful_field_charges() -> int:
	return mini(ELExpeditionArtifacts.CAPACITY, _remaining_artifact_duels() * artifact_use_limit())

func _later_camp_reachable() -> bool:
	if act < ACTS: return true
	var queue: Array[Dictionary] = [{"id": current, "detour": act in _detours_used}]
	var seen := {}
	while not queue.is_empty():
		var state: Dictionary = queue.pop_back()
		var signature := "%s:%s" % [state.id, state.detour]
		if seen.has(signature): continue
		seen[signature] = true
		var room: Dictionary = _nodes.get(state.id, {})
		if room.get("kind") == "boss": continue
		var next_ids: Array[String] = []
		if room.is_empty():
			for next: Dictionary in _route[0]: next_ids.append(next.id)
		else: next_ids.assign(room.next)
		var natural := next_ids.duplicate()
		if _has_keystone("wayfarer_compass") and not bool(state.detour) and not room.is_empty() and int(room.floor) < _route.size():
			for next: Dictionary in _route[int(room.floor)]:
				if next.id not in next_ids: next_ids.append(next.id)
		for id: String in next_ids:
			if _nodes[id].kind == "rest": return true
			queue.append({"id": id, "detour": bool(state.detour) or id not in natural})
	return false

func _project_completion_text() -> String:
	if finished(): return _tr("Unfinished when the expedition ended.", "Заготовка осталась незавершённой к концу экспедиции.")
	var cost := _merchant_price(PROJECT_FINISH_COST)
	if phase == "haven": return _tr("Finish it here for %d gold before the final duel.", "Завершите его здесь за %d золотых перед последним боем.") % cost
	if phase == "rest": return _tr("Finish it here instead of resting or another camp activity. No gold cost.", "Завершите его здесь вместо отдыха или другого занятия на привале. Золото не требуется.")
	if _later_camp_reachable(): return _tr("Unfinished. Use a later camp's main action to assemble it, or pay %d gold at the Last Haven. It does nothing until finished.", "Не завершён. Соберите его на следующем привале вместо другого занятия или заплатите %d золотых на Последнем привале. До сборки он не действует.") % cost
	return _tr("No later camp is reachable. Completion will cost %d gold at the Last Haven at your current prices. It does nothing until finished.", "Дальнейшие привалы недоступны. При нынешних ценах сборка на Последнем привале обойдётся в %d золотых. До сборки он не действует.") % cost

## Be conservative about future income. Any remaining event, treasure or
## pre-final victory might fund the project; a camp can finish it for free.
## Only a route with none of those opportunities can prove it unaffordable.
func _project_has_completion_route() -> bool:
	if act < ACTS or gold >= _merchant_price(PROJECT_FINISH_COST): return true
	var queue: Array[Dictionary] = [{"id": current, "detour": act in _detours_used}]
	var seen := {}
	while not queue.is_empty():
		var state: Dictionary = queue.pop_back()
		var signature := "%s:%s" % [state.id, state.detour]
		if seen.has(signature): continue
		seen[signature] = true
		var room: Dictionary = _nodes.get(state.id, {})
		if room.get("kind") == "boss": continue
		var next_ids: Array[String] = []
		if room.is_empty():
			for next: Dictionary in _route[0]: next_ids.append(next.id)
		else: next_ids.assign(room.next)
		var natural := next_ids.duplicate()
		if _has_keystone("wayfarer_compass") and not bool(state.detour) and not room.is_empty() and int(room.floor) < _route.size():
			for next: Dictionary in _route[int(room.floor)]:
				if next.id not in next_ids: next_ids.append(next.id)
		for id: String in next_ids:
			if _nodes[id].kind in ["rest", "event", "treasure", "fight", "elite"]: return true
			queue.append({"id": id, "detour": bool(state.detour) or id not in natural})
	# Even a hypothetical later Merchant's Seal cannot lower the fee below
	# 23 gold. Keeping this lower bound avoids blocking speculative discounts.
	return gold >= ceili(PROJECT_FINISH_COST * 0.8)

func _field_choice(id: String, recipe: String, action: String, title: String) -> Dictionary:
	var detail := ELExpeditionArtifacts.find(profile, recipe)
	var offer := _choice(id, title, str(detail.get("description", "")))
	offer.field_recipe = recipe
	offer.artifact_action = action
	offer.context = str(detail.get("context", ""))
	offer.charges_before = field_charges
	offer.charges_after = ELExpeditionArtifacts.CAPACITY if action in ["claim", "complete"] else field_charges
	if action in ["project", "claim", "complete"] and _useful_field_charges() == 1:
		offer.context += "\n" + _tr("Only one duel remains. This hero can use one of the two charges before the expedition ends.", "Остался один бой. До конца экспедиции этот герой сможет использовать лишь один из двух зарядов.")
	return offer

func _field_completion_choice() -> Dictionary:
	var detail := artifact_project_details()
	if detail.is_empty(): return {}
	var offer := _field_choice("complete_project", artifact_project, "complete", _tr("Finish %s", "Завершить: %s") % str(detail.title))
	offer.context += "\n" + _project_completion_text()
	if phase == "haven": _price(offer, _merchant_price(PROJECT_FINISH_COST))
	if _artifact_slots(false) >= ELDuelCosts.EL2_ARTIFACTS:
		_unavailable(offer, _tr("All five artifact slots are occupied. A borrowed artifact leaves after the next duel.", "Все пять мест для артефактов заняты. Одолженный артефакт исчезнет после следующего боя."))
	return offer

func _field_recharge_choice(amount := 1, life_payment := false) -> Dictionary:
	var detail := field_artifact_details()
	if detail.is_empty(): return {}
	var id := "recharge_artifact:%d" % amount if life_payment else "recharge_artifact"
	var offer := _field_choice(id, field_artifact, "recharge", _tr("Recharge %s · +%d charge(s)", "Зарядить: %s · +%d заряд(а)") % [str(detail.title), amount])
	offer.charges_after = field_charges + amount
	if life_payment:
		offer.life_cost = 3 * amount
		offer.context += "\n" + _tr("Spend %d life. This ends the visit to the recharger.", "Потратить %d ед. здоровья. После этого посещение реконструктора завершится.") % int(offer.life_cost)
		if health <= int(offer.life_cost): _unavailable(offer, _tr("You need more than %d life.", "Нужно больше %d ед. здоровья.") % int(offer.life_cost))
	elif shopping():
		_price(offer, _merchant_price(FIELD_RECHARGE_COST))
		offer.context += "\n" + _tr("One charge per merchant visit. Unused charges remain for later duels.", "Один заряд за посещение торговца. Неиспользованные заряды сохраняются для следующих боёв.")
		if "field_charge" in _shop_bought: _unavailable(offer, _tr("Already recharged here.", "Зарядка здесь уже использована."))
	else:
		offer.context += "\n" + _tr("Uses the camp's main action instead of rest, training or another service. Unused charges remain for later duels.", "Занимает привал вместо отдыха, обучения или другого занятия. Неиспользованные заряды сохраняются для следующих боёв.")
	if field_charges + amount > ELExpeditionArtifacts.CAPACITY:
		_unavailable(offer, _tr("The artifact already holds its two charges.", "В артефакте уже два заряда."))
	elif field_charges + amount > _useful_field_charges():
		_unavailable(offer, _tr("No remaining route lets this hero use that extra charge before the expedition ends.", "До конца экспедиции ни на одном пути герой не сможет использовать этот дополнительный заряд."))
	return offer

func _constructor_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _field_recipe_offers(3, 0x15ca7e):
		var detail := ELExpeditionArtifacts.find(profile, id)
		var offer := _field_choice("project:" + id, id, "project", _tr("Take the %s project", "Взять заготовку: %s") % str(detail.title))
		offer.context += "\n" + _project_completion_text()
		# A loan can free a slot after a duel. Permanent artifacts cannot.
		if _artifact_slots(false, false) >= ELDuelCosts.EL2_ARTIFACTS:
			_unavailable(offer, _tr("Your five permanent artifacts leave no slot for the finished project.", "Пять постоянных артефактов не оставляют места для готового изделия."))
		elif _artifact_slots(false) >= ELDuelCosts.EL2_ARTIFACTS and _remaining_artifact_duels() <= 1:
			_unavailable(offer, _tr("All five artifact slots are occupied. The borrowed artifact will not leave before the final duel, so this project cannot be assembled in time.", "Все пять мест заняты. Одолженный артефакт останется до последнего боя, поэтому собрать заготовку вовремя не получится."))
		elif not _project_has_completion_route():
			_unavailable(offer, _tr("No camp or source of gold remains on your route, and you cannot afford completion at the Last Haven.", "На вашем пути не осталось привала или источника золота, а на сборку на Последнем привале не хватает средств."))
		result.append(offer)
	result.append(_choice("constructor_salvage", _tr("Sort the salvage", "Разобрать пригодный металл"), _tr("Gain 12 gold instead of taking a project.", "Получить 12 золотых вместо заготовки.")))
	return result

func _choose_field_artifact(id: String, selected: Dictionary) -> bool:
	if id.begins_with("project:"):
		artifact_project = str(selected.field_recipe)
		_complete_room()
	elif id == "constructor_salvage":
		_gain_gold(12)
		_complete_room()
	elif id.begins_with("claim_artifact:"):
		field_artifact = str(selected.field_recipe)
		field_charges = ELExpeditionArtifacts.CAPACITY
		phase = "reward"
	elif id == "complete_project":
		field_artifact = artifact_project
		field_charges = ELExpeditionArtifacts.CAPACITY
		artifact_project = ""
		if phase == "haven": gold -= int(selected.cost)
		else: _complete_room()
	elif id == "recharge_artifact" or id.begins_with("recharge_artifact:"):
		field_charges = int(selected.charges_after)
		if selected.has("life_cost"):
			health -= int(selected.life_cost)
			_complete_room()
		elif shopping():
			gold -= int(selected.cost)
			_shop_bought.append("field_charge")
		else: _complete_room()
	else: return false
	return true

func practiced() -> bool:
	return _version >= 14

func attuned() -> bool:
	return _version >= 13

func rebalanced() -> bool:
	return _version >= 12

func refined() -> bool:
	return _version >= 11

func owned_copies(code: String) -> int:
	return deck.count(code) + (reserve.count(code) if refined() else 0)

func owned_spells() -> Array[String]:
	var result := deck.duplicate()
	if refined(): result.append_array(reserve)
	return result

func opening_details() -> Dictionary:
	return opening_details_for(deck, reserve)

func opening_details_for(book: Array[String], stored: Array[String]) -> Dictionary:
	if not practiced() or opening_spell.is_empty(): return {}
	var in_book := opening_spell in book
	var owned := in_book or opening_spell in stored
	var active := in_book and not opening_suppressed
	var reason := ""
	var status := _tr("Prepared", "Подготовлено")
	if not owned:
		status = _tr("Preparation lost", "Подготовка потеряна")
		reason = _tr("The last owned copy is gone. This opening preparation will be lost.", "Последняя копия удалена. Подготовка этого заклинания будет потеряна.")
	elif opening_suppressed:
		status = _tr("Set aside", "Отложено")
		reason = _tr("Ordinary random opening. Prepare this spell again for free at camp or the Last Haven; keep a copy in the active book to use it.", "Обычная случайная стартовая рука. Снова подготовить заклинание можно бесплатно на привале или Последнем привале; для применения нужна копия в боевой книге.")
	elif not in_book:
		status = _tr("In reserve", "В запасе")
		reason = _tr("In reserve. Swap it into your active book to prepare it again.", "В запасе. Верните страницу в боевую книгу, чтобы снова готовить её к началу боя.")
	return {"card": opening_spell, "title": _card_title(opening_spell), "active": active, "owned": owned,
		"prepared": not opening_suppressed, "status": status,
		"description": _tr("Start each duel with this spell among your five opening cards. It keeps its normal casting cost, charges and discard rules.", "Каждый бой это заклинание будет среди пяти карт стартовой руки. Его цена, заряды и правила сброса остаются обычными."), "reason": reason}

func _opening_slots() -> Array[int]:
	return [deck.find(opening_spell) if not opening_spell.is_empty() and not opening_suppressed else -1, -1]

func _opening_toggle_choices() -> Array[Dictionary]:
	if not practiced() or opening_spell.is_empty() or phase not in ["rest", "haven"]: return []
	var title := _tr("Prepare %s again", "Снова подготовить: %s") % _card_title(opening_spell) if opening_suppressed else _tr("Set aside opening preparation", "Отложить подготовку стартовой руки")
	var detail := _tr("Free. Use the rehearsed spell in your opening hand whenever a copy is in the active book. This does not use the camp action.", "Бесплатно. Подготовленное заклинание войдёт в стартовую руку, если его копия есть в боевой книге. Действие привала не расходуется.") if opening_suppressed else _tr("Free. Return to ordinary random opening hands and keep the lesson. You can prepare this spell again at camp or the Last Haven. This does not use the camp action.", "Бесплатно. Вернуться к случайной стартовой руке, сохранив изученное заклинание. Снова подготовить его можно на привале или Последнем привале. Действие привала не расходуется.")
	var offer := _choice("prepare_opening" if opening_suppressed else "suppress_opening", title, detail)
	offer.opening_toggle = true
	return [offer]

func _opening_service_available() -> bool:
	return practiced() and (phase in ["rest", "haven"] or (phase == "event" and _event_index() == SCHOLAR_EVENT))

func _opening_cost_text() -> String:
	if phase == "rest": return _tr("Uses this camp action instead of resting, training or gathering supplies.", "Занимает этот привал вместо отдыха, обучения или сбора припасов.")
	if phase == "haven": return _tr("Pay %d gold when you choose the spell. Preparing the same spell again is unnecessary.", "Заплатите %d золотых после выбора заклинания. Готовить то же заклинание повторно не нужно.") % _merchant_price(OPENING_COST)
	return _tr("Take the scholar's lesson instead of the 12-gold copying job.", "Воспользуйтесь уроком учёного вместо работы переписчиком за 12 золотых.")

func _opening_service_choice() -> Dictionary:
	var offer := _choice("opening_select", _tr("Rehearse an opening spell", "Подготовить заклинание к началу боя"), _opening_cost_text())
	offer.context = _tr("Choose an active page. It will occupy one of your normal opening-hand slots in each duel.", "Выберите страницу боевой книги. В каждом бою она займёт одно обычное место в стартовой руке.")
	if phase == "haven": _price(offer, _merchant_price(OPENING_COST))
	return offer

func _opening_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cards: Array[String] = []
	for card: String in deck:
		if card not in cards: cards.append(card)
	cards.sort_custom(func(left: String, right: String) -> bool:
		var a := ELEncyclopaedia.cost(profile, left)
		var b := ELEncyclopaedia.cost(profile, right)
		return a < b if a != b else left < right)
	for card: String in cards:
		var offer := _choice("opening_spell:" + card, _card_title(card), profile.card_description(card), card)
		offer.opening = true
		offer.context = _opening_cost_text()
		if phase == "haven": _price(offer, _merchant_price(OPENING_COST))
		if card == opening_spell:
			_unavailable(offer, _tr("This spell is already rehearsed. Prepare it again for free at camp or the Last Haven.", "Это заклинание уже изучено. Снова подготовить его можно бесплатно на привале или Последнем привале.") if opening_suppressed else _tr("Already prepared for your opening hand.", "Уже подготовлено для стартовой руки."))
		result.append(offer)
	result.append(_choice("back", _text("Back")))
	return result

func charges_per_page() -> int:
	var skills := _starting_skills()
	skills.merge(trained_skills(), true)
	return ELSpellCharges.providence(skills)

func outcome_details() -> Dictionary:
	if not refined() or _last_outcome.is_empty(): return {}
	var lines: Array[String] = []
	for entry: Array in [["gold", _tr("Gold", "Золото")], ["life", _tr("Life", "Здоровье")], ["maximum", _tr("Maximum life", "Максимум здоровья")]]:
		var amount := int(_last_outcome[entry[0]])
		if amount != 0: lines.append("%s: %+d" % [entry[1], amount])
	for entry: Array in [["book_added", _tr("Book +", "Книга +")], ["book_removed", _tr("Book −", "Книга −")], ["reserve_added", _tr("Reserve +", "Запас +")], ["reserve_removed", _tr("Reserve −", "Запас −")]]:
		var names: Array[String] = []
		for code: String in _last_outcome[entry[0]]: names.append(_card_title(code))
		if not names.is_empty(): lines.append("%s: %s" % [entry[1], ", ".join(names)])
	for id: String in _last_outcome.relics_added:
		lines.append(_tr("Relic gained: ", "Получена реликвия: ") + String(ELExpeditionContent.relic(profile, id, balanced()).title))
	for id: String in _last_outcome.relics_removed:
		lines.append(_tr("Relic surrendered: ", "Отдана реликвия: ") + String(ELExpeditionContent.relic(profile, id, balanced()).title))
	if int(_last_outcome.training) > 0: lines.append(_tr("Combat skill trained.", "Боевой навык улучшен."))
	if bool(_last_outcome.prepared): lines.append(_tr("Provisions packed for the next duel.", "Припасы подготовлены к следующему бою."))
	if practiced() and _last_outcome.get("opening_before", "") != _last_outcome.get("opening_after", ""):
		var prepared_spell := str(_last_outcome.get("opening_after", ""))
		lines.append(_tr("Opening spell: %s.", "В стартовой руке: %s.") % _card_title(prepared_spell) if not prepared_spell.is_empty() else _tr("Opening preparation lost: %s.", "Подготовка потеряна: %s.") % _card_title(str(_last_outcome.opening_before)))
	if implements_enabled():
		var before_item := str(_last_outcome.field_artifact_before)
		var after_item := str(_last_outcome.field_artifact_after)
		var before_project := str(_last_outcome.artifact_project_before)
		var after_project := str(_last_outcome.artifact_project_after)
		if after_item != before_item and not after_item.is_empty():
			lines.append(_tr("Artifact ready: %s · %d/2 charges.", "Артефакт готов: %s · %d/2 зарядов.") % [str(ELExpeditionArtifacts.find(profile, after_item).title), int(_last_outcome.field_charges_after)])
			if not before_item.is_empty(): lines.append(_tr("Replaced %s; %d charge(s) left behind.", "Заменён: %s; оставлено зарядов: %d.") % [str(ELExpeditionArtifacts.find(profile, before_item).title), int(_last_outcome.field_charges_before)])
		elif int(_last_outcome.field_charges_before) != int(_last_outcome.field_charges_after):
			lines.append(_tr("Artifact charges: %d → %d.", "Заряды артефакта: %d → %d.") % [int(_last_outcome.field_charges_before), int(_last_outcome.field_charges_after)])
		if after_project != before_project and not after_project.is_empty():
			lines.append(_tr("Packed an unfinished %s. It must be assembled before use.", "Взята заготовка: %s. Перед использованием её нужно собрать.") % str(ELExpeditionArtifacts.find(profile, after_project).title))
			if not before_project.is_empty(): lines.append(_tr("Previous project left behind: %s.", "Предыдущая заготовка оставлена: %s.") % str(ELExpeditionArtifacts.find(profile, before_project).title))
	var story := str(_last_outcome.get("story", ""))
	if rebalanced() and not story.is_empty():
		var scene := ELExpeditionContent.event(profile, int(story.get_slice(":", 0)), true)
		return {"title": str(scene.title), "description": ELExpeditionContent.outcome(profile, story) + "\n" + " · ".join(lines)}
	return {"title": _tr("Last decision", "Последнее решение"), "description": " · ".join(lines)}

func _outcome_state() -> Dictionary:
	var state := {"gold": gold, "life": health, "maximum": max_health, "book": deck.duplicate(),
		"reserve": reserve.duplicate(), "relics": relics.duplicate(), "training": _training_sessions(), "prepared": _prepared,
		"event": _event_index() if phase == "event" else -1}
	if practiced(): state.opening = opening_spell
	if implements_enabled():
		state.field_artifact = field_artifact
		state.field_charges = field_charges
		state.artifact_project = artifact_project
	return state

func _page_difference(after: Array, before: Array) -> Array[String]:
	var remaining := before.duplicate()
	var result: Array[String] = []
	for code: String in after:
		if code in remaining: remaining.erase(code)
		else: result.append(code)
	return result

func _record_outcome(before: Dictionary, action := "") -> void:
	var change := {"gold": gold - int(before.gold), "life": health - int(before.life), "maximum": max_health - int(before.maximum),
		"book_added": _page_difference(deck, before.book), "book_removed": _page_difference(before.book, deck),
		"reserve_added": _page_difference(reserve, before.reserve), "reserve_removed": _page_difference(before.reserve, reserve),
		"relics_added": _page_difference(relics, before.relics), "relics_removed": _page_difference(before.relics, relics),
		"training": _training_sessions() - int(before.training), "prepared": _prepared and not bool(before.prepared)}
	if practiced():
		change.opening_before = str(before.get("opening", ""))
		change.opening_after = opening_spell
	var artifact_changed := false
	if implements_enabled():
		for key: String in ["field_artifact", "field_charges", "artifact_project"]:
			change[key + "_before"] = before[key]
			change[key + "_after"] = get(key)
			artifact_changed = artifact_changed or before[key] != get(key)
	if rebalanced() and int(before.event) >= 0 and phase == "map":
		var story := "%d:%s" % [int(before.event), action.get_slice(":", 0)]
		if not ELExpeditionContent.outcome(profile, story).is_empty(): change.story = story
	if gold != int(before.gold) or health != int(before.life) or max_health != int(before.maximum) or deck != before.book or reserve != before.reserve or relics != before.relics or int(change.training) > 0 or bool(change.prepared) or artifact_changed or (practiced() and str(before.get("opening", "")) != opening_spell):
		_last_outcome = change
	elif change.has("story"):
		_last_outcome = change

func evolved() -> bool:
	return _version >= 10

func _has_keystone(id: String) -> bool:
	return evolved() and id in keystones

func study_details() -> Dictionary:
	if not evolved() or study_path.is_empty(): return {}
	if study_path == "none":
		return {"id": "none", "title": _tr("The Open Road", "Свободный путь"), "description": _tr("Your spell offers remain unrestricted by a study path.", "Школа не влияет на предлагаемые заклинания."), "cards": []}
	return ELExpeditionPaths.find(profile, study_path)

func keystone_details() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in keystones:
		if attuned() and ELExpeditionAttunements.is_power(id): continue
		var detail := ELExpeditionContent.keystone(profile, id)
		detail.context = _keystone_context(id)
		result.append(detail)
	return result

func active_powers() -> Array[String]:
	var result: Array[String] = []
	if not attuned(): return result
	for id: String in keystones:
		if ELExpeditionAttunements.is_power(id) and id not in inactive_powers: result.append(id)
	return result

func ability_details() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not attuned(): return result
	for id: String in keystones:
		if not ELExpeditionAttunements.is_power(id): continue
		var detail := ELExpeditionAttunements.find(profile, id)
		detail.prepared = id not in inactive_powers
		detail.status = _tr("Prepared", "Подготовлено") if detail.prepared else _tr("Dormant", "Не подготовлено")
		if id == "power_transfer_aspects" and detail.prepared and not ELExpeditionAttunements.has_aspect_pair(profile, str(preset.faction), deck):
			detail.readiness = _tr("Your active book cannot supply both aspect targets. Check your reserve; the ability still needs a creature in each plane.", "В боевой книге нет пары целей из обоих планов. Проверьте запас: способности нужны создания в разных планах.")
			detail.context += "\n" + str(detail.readiness)
		result.append(detail)
	return result

func _power_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not attuned() or phase not in ["rest", "haven"]: return result
	for detail: Dictionary in ability_details():
		var prepared: bool = detail.prepared
		var title := _tr("Set aside %s", "Отложить: %s") if prepared else _tr("Prepare %s", "Подготовить: %s")
		var description := _tr("Its effect will not start in the next duel. You can prepare it again at a camp or the Last Haven.", "Эффект не появится в начале следующего боя. Его можно снова подготовить на привале или Последнем привале.") if prepared else str(detail.description)
		var offer := _choice(("suppress_power:" if prepared else "prepare_power:") + str(detail.id), title % str(detail.title), description)
		offer.ability = detail.id
		offer.context = _tr("Free preparation. You can still use the camp's main service.", "Бесплатная подготовка. Основное занятие на привале остаётся доступным.") if phase == "rest" else _tr("Free preparation for the final duel.", "Бесплатная подготовка к последнему бою.")
		result.append(offer)
	return result

func _keystone_context(id: String) -> String:
	if attuned() and ELExpeditionAttunements.is_power(id):
		return str(ELExpeditionAttunements.find(profile, id).get("context", ""))
	match id:
		"blood_crown": return _tr("Camp, event, merchant, relic, and act-transition recovery remain available.", "Лечение на привалах, в событиях, у торговцев, от реликвий и между актами остаётся доступным.")
		"living_heart": return _tr("Current maximum life: %d. Merchant prices show the final cost.", "Сейчас максимум здоровья: %d. У торговцев указаны итоговые цены.") % max_health
		"prismatic_quill": return _tr("This act's redraw has already been used.", "Обновление награды в этом акте уже использовано.") if act in _reroll_used_acts else _tr("A free reward redraw remains in this act.", "В этом акте осталось бесплатное обновление награды.")
		"wayfarer_compass":
			if _nodes.get(current, {}).get("kind") == "boss":
				return _tr("A new detour becomes available in the next act.", "В следующем акте станет доступен новый обход.") if act < ACTS else _tr("No rooms remain for a detour before the final duel.", "Перед последним боем не осталось комнат для обхода.")
			return _tr("This act's detour has been used.", "Обход в этом акте уже использован.") if act in _detours_used else _tr("One disconnected step remains in this act.", "В этом акте остался один переход без пути.")
	return ""

func reward_redraw_cost() -> int:
	return 0 if _has_keystone("prismatic_quill") else REROLL_COST

func _reward_recovery() -> float:
	return 0.0 if _has_keystone("blood_crown") else REWARD_RECOVERY

func balanced() -> bool:
	return _version >= 9

func shopping() -> bool:
	return phase in ["shop", "haven"]

func battle_preview() -> Dictionary:
	var base := mini(20, int(preset.get("level", 1)) + 2 * (act - 1))
	var bonus := 0
	var lines: Array[String] = []
	if _has_relic("aether_prism"):
		bonus += 1
		lines.append(_tr("Ether Prism: +1 level.", "Эфирная призма: +1 уровень."))
	if _has_relic("duelists_crest") and deck.size() <= 12:
		bonus += 2
		lines.append(_tr("Duelist's Crest: +2 levels (12 spells or fewer).", "Герб дуэлянта: +2 уровня (не больше 12 заклинаний)."))
	if _prepared:
		bonus += 1
		lines.append(_tr("Provisions: +1 level for this duel.", "Припасы: +1 уровень на этот бой."))
	if _has_keystone("blood_crown"):
		bonus += 1
		lines.append(_tr("Blood Crown: +1 level; spell rewards cannot heal.", "Кровавая корона: +1 уровень; награды заклинаниями не лечат."))
	var preview := {"level": mini(20, base + bonus), "base_level": base, "bonus_lines": lines}
	if attuned():
		var powers: Array[String] = []
		for detail: Dictionary in ability_details():
			powers.append("%s: %s" % [str(detail.title), str(detail.description) if detail.prepared else str(detail.status)])
			if detail.has("readiness"): powers.append(str(detail.readiness))
		preview.ability_lines = powers
	if practiced() and not opening_spell.is_empty():
		var opening := opening_details()
		preview.opening_line = _tr("Opening hand: %s", "Стартовая рука: %s") % str(opening.title) if opening.active else _tr("Opening spell: %s · %s", "Подготовлено: %s · %s") % [str(opening.title), str(opening.status)]
	if implements_enabled():
		var carried := field_artifact_details()
		var project := artifact_project_details()
		if not carried.is_empty(): preview.artifact_line = _tr("Artifact: %s · %d/2 charges", "Артефакт: %s · %d/2 зарядов") % [str(carried.title), field_charges]
		if not project.is_empty(): preview.project_line = _tr("Unfinished: %s", "Заготовка: %s") % str(project.title)
	return preview

func hero_details() -> Dictionary:
	var hero := ELDuelPresets.choice(profile, preset)
	hero.erase("deck")
	hero.cards = deck.duplicate()
	hero.level = int(battle_preview().level)
	hero.health = health
	hero.title = preset.name
	if not borrowed_artifact.is_empty() or not keepsake_artifact.is_empty() or (implements_enabled() and not field_artifact.is_empty()):
		var artifacts: Array = hero.get("artifacts", []).duplicate(true)
		for name: String in [keepsake_artifact, borrowed_artifact]:
			if not name.is_empty(): artifacts.append({"name": name, "charges": 1})
		if implements_enabled() and not field_artifact.is_empty(): artifacts.append(ELExpeditionArtifacts.battle_entry(profile, field_artifact, field_charges))
		hero.artifacts = artifacts
	hero.skills = _starting_skills()
	hero.skills.merge(trained_skills(), true)
	return ELExpeditionAttunements.prepare_hero(hero, active_powers()) if attuned() else hero

func relic_status(id: String) -> String:
	match id:
		"duelists_crest":
			return _tr("Current book: %d spells. Active.", "Сейчас в книге %d заклинаний. Эффект действует.") % deck.size() if deck.size() <= 12 else _tr("Current book: %d spells. Remove %d to activate; removing pages also removes their spell charges.", "Сейчас в книге %d заклинаний. Для активации уберите %d; удалённые страницы также теряют свои заряды.") % [deck.size(), deck.size() - 12]
		"aether_prism":
			return _tr("Base hero level this act: %d. Combat level cannot exceed 20.", "Базовый уровень героя в этом акте: %d. Боевой уровень не может превышать 20.") % int(battle_preview().base_level)
		"twin_seal":
			var spent := _training_sessions()
			return _tr("Training sessions used: %d. This relic permits up to 3; training starts in Act II.", "Обучений использовано: %d. Эта реликвия разрешает до 3; обучение доступно со II акта.") % spent
		"purifier_stone":
			return _tr("Next merchant removal with this relic: %d gold.", "Следующее удаление у торговца с этой реликвией: %d золотых.") % _removal_price(true)
		"merchant_seal":
			return _tr("Applies to spells, relics, healing, provisions, and removal. Event deals are unchanged.", "Действует на заклинания, реликвии, лечение, припасы и удаление. Сделки в событиях не меняются.")
		"amber_seed", "travel_rations", "pilgrims_flask":
			return _tr("Missing life now: %d. Recovery cannot exceed maximum life.", "Сейчас не хватает %d ед. здоровья. Лечение не превышает максимум.") % maxi(0, max_health - health)
		"glass_compass":
			return _tr("One more option, not one more card. Reward redraw is a separate choice.", "Ещё один вариант на выбор, а не ещё одна карта. Обновление награды доступно отдельно.")
	return ""

func _training_sessions() -> int:
	var count := 0
	for value: int in _training.values(): count += value
	return count

func expanded() -> bool:
	return _version >= 8

func floors_per_act() -> int:
	return EXPANDED_ROOM_ROWS.size() if expanded() else FLOORS

func relic_details() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in relics:
		var detail := ELExpeditionContent.relic(profile, id, balanced())
		if balanced(): detail.context = relic_status(id)
		result.append(detail)
	return result

func journey_effects() -> Array[String]:
	var result: Array[String] = []
	if evolved():
		for id: String in ["wayfarer_compass", "prismatic_quill"]:
			if _has_keystone(id): result.append(str(ELExpeditionContent.keystone(profile, id).title) + ": " + _keystone_context(id))
	if _contract_remaining > 0:
		result.append(_tr("Courier contract: %d more victories for 55 gold.", "Договор курьера: ещё %d побед до выплаты 55 золотых.") % _contract_remaining)
	if _prepared: result.append(_tr("Provisions: +1 hero level in your next duel.", "Припасы: +1 уровень героя в следующем бою."))
	if not _bounty.is_empty():
		var goal := _tr("defeat an elite", "победить элиту") if _bounty.kind == "elite" else _tr("win by round 8", "победить не позднее 8-го раунда")
		result.append(_tr("Bounty: %s within %d victories. Payment: %d gold.", "Заказ: %s за %d победы. Награда: %d золотых.") % [goal, int(_bounty.remaining), 40 if _bounty.kind == "elite" else 30])
	return result

func _tr(en: String, ru: String) -> String:
	return ELExpeditionContent.text(profile, en, ru)

func _has_relic(id: String) -> bool:
	return expanded() and id in relics

func _training_limit() -> int:
	return TRAINING_LIMIT + int(_has_relic("twin_seal"))

func _camp_healing() -> float:
	return 0.45 if _has_relic("pilgrims_flask") else 0.3

func _gain_gold(amount: int) -> void:
	gold = clampi(gold + amount, 0, MAX_GOLD)

static func starters(source: ELProfile) -> Array[Dictionary]:
	if source == null or source.id != "el2": return []
	var result: Array[Dictionary] = []
	for row: Dictionary in ELDuelPresets.shipped(source):
		if row.resource_level != 1 or row.cards.size() != ELDuelCosts.EL2_DECK: continue
		if not row.cards.all(func(card: String): return _valid_card(source, card, row.faction)): continue
		result.append(row)
	return result

static func _valid_card(source: ELProfile, card: String, faction: String) -> bool:
	return ELDuelCosts.spell_allowed(source, card, faction) and not ELCatalog.rule(source, card).is_empty()

func create(source: ELProfile, preset_id: String, run_seed: int, rules_version := SAVE_VERSION, challenge := "standard") -> bool:
	if rules_version < 1 or rules_version > SAVE_VERSION: return _fail("The expedition checkpoint has an unknown format.")
	if challenge not in DIFFICULTIES or (rules_version < 9 and challenge != "standard"): return _fail("Unknown expedition difficulty.")
	var chosen := ELDuelPresets.find(starters(source), preset_id)
	if chosen.is_empty(): return _fail("Choose an Etherlords II starter preset.")
	life_bonus = 0
	borrowed_artifact = ""
	keepsake_artifact = ""
	_previous_paths.clear()
	_training.clear()
	_final_battle.clear()
	_version = rules_version
	difficulty = challenge
	gold = STARTING_GOLD if expanded() else 0
	relics.clear()
	_removals = 0
	_contract_remaining = 0
	_prepared = false
	_reroll_used_acts.clear()
	_bounty.clear()
	study_path = ""
	keystones.clear()
	inactive_powers.clear()
	_keystone_claimed.clear()
	_detours_used.clear()
	reserve.clear()
	opening_spell = ""
	opening_selecting = false
	opening_suppressed = false
	field_artifact = ""
	field_charges = 0
	artifact_project = ""
	_last_outcome.clear()
	_reset(source, chosen, run_seed & 0xffffffff, 1)
	deck.assign(preset.cards)
	health = max_health
	if expanded(): phase = "boon"
	return true

func finished() -> bool:
	return phase in ["won", "lost"]

func retry() -> ELExpeditionRun:
	if not finished(): return null
	var next := ELExpeditionRun.new()
	return next if next.create(profile, preset.id, seed_value, _version, difficulty) else null

func final_battle() -> Dictionary:
	return _final_battle.duplicate()

func _reset(source: ELProfile, chosen: Dictionary, run_seed: int, next_act: int) -> void:
	profile = source
	preset = chosen
	seed_value = run_seed
	act = next_act
	max_health = _life_cap(profile, preset, act) + life_bonus + (8 if _has_keystone("living_heart") else 0)
	current = ""
	visited.clear()
	pending_card = ""
	_battle_checkpoint = {}
	_opponents.clear()
	_clear_room_state()
	phase = "map"
	error = ""
	_build_route()

static func _life_cap(source: ELProfile, chosen: Dictionary, at_act: int) -> int:
	return maxi(STARTING_LIFE, ELDuelPresets.health(source, chosen)) + LIFE_PER_ACT * (at_act - 1)

func _build_route() -> void:
	_route.clear()
	_nodes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 104729 * act
	# Connections have their own stream so they never reroll room content.
	var links := RandomNumberGenerator.new()
	links.seed = seed_value ^ (104729 * act) ^ 0x3dc4f129
	var rows: Array = EXPANDED_ROOM_ROWS if expanded() else ROOM_ROWS
	for floor_index in rows.size():
		var kinds: Array = rows[floor_index].duplicate()
		for index in range(kinds.size() - 1, 0, -1):
			var other := rng.randi_range(0, index)
			var kind: String = kinds[index]
			kinds[index] = kinds[other]
			kinds[other] = kind
		var row: Array[Dictionary] = []
		for column in kinds.size():
			var id := "%d-%d-%d" % [act, floor_index + 1, column + 1]
			var kind: String = kinds[column]
			var room := {"id": id, "kind": kind, "title": _text(ROOM_TITLES[kind]),
				"floor": floor_index + 1, "column": column, "next": [] as Array[String], "seed": rng.randi()}
			if kind == "shop": room.title = _tr("Merchant", "Торговец")
			elif kind == "treasure": room.title = _tr("Treasure", "Сокровищница")
			row.append(room)
			_nodes[id] = room
		if floor_index > 0: _link_rows(_route.back(), row, links)
		_route.append(row)
	if expanded():
		# Assign a shuffled bag to the entire act, not one independent roll per
		# room. Even different branches cannot repeat an event within the act.
		var events: Array[int] = [0, 1, 2, 5, 6, 7, 8, 9, 10, 11]
		if balanced(): events.append_array([12, 13])
		if evolved(): events.append(14)
		if refined(): events.append_array([ANVIL_EVENT, LIBRARY_EVENT])
		if practiced(): events.append(SCHOLAR_EVENT)
		if implements_enabled(): events.append(CONSTRUCTOR_EVENT)
		if act >= 2: events.append_array([RELIQUARY_EVENT, WARDEN_EVENT])
		var event_rng := RandomNumberGenerator.new()
		event_rng.seed = seed_value ^ (act * 32771) ^ 0x197eab3d
		for index in range(events.size() - 1, 0, -1):
			var other := event_rng.randi_range(0, index)
			var value := events[index]
			events[index] = events[other]
			events[other] = value
		var event_index := 0
		for row: Array in _route:
			for room: Dictionary in row:
				if room.kind == "event":
					room.event = events[event_index % events.size()]
					event_index += 1

func _link_rows(previous: Array, row: Array[Dictionary], links: RandomNumberGenerator) -> void:
	if _version < 3 or row.size() != previous.size():
		for room: Dictionary in previous:
			for next: Dictionary in row:
				if absi(room.column - next.column) <= 1 or row.size() == 1: room.next.append(next.id)
		return
	# Straight paths keep every room reachable. Each row adds a fork, with
	# at most one diagonal between neighboring lanes.
	for lane in row.size(): previous[lane].next.append(row[lane].id)
	var fork := links.randi_range(0, row.size() - 2)
	for lane in row.size() - 1:
		if lane != fork and links.randi_range(0, 1) == 0: continue
		if links.randi_range(0, 1) == 0: previous[lane].next.append(row[lane + 1].id)
		else: previous[lane + 1].next.append(row[lane].id)
	for room: Dictionary in previous: room.next.sort()

func route() -> Array[Array]:
	return _route.duplicate(true)

func journey() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for chapter in range(1, act + 1):
		var path: Array = visited if chapter == act else _previous_paths.get(str(chapter), [])
		var nodes := _nodes
		if chapter != act and not path.is_empty():
			var earlier := ELExpeditionRun.new()
			earlier._version = _version
			earlier._reset(profile, preset, seed_value, chapter)
			nodes = earlier._nodes
		var rooms: Array[Dictionary] = []
		for id: String in path:
			var room: Dictionary = nodes[id]
			rooms.append({"kind": room.kind, "floor": room.floor, "column": room.column})
		result.append({"act": chapter, "rooms": rooms, "recorded": chapter == act or not path.is_empty()})
	return result

func available() -> Array[String]:
	return upcoming() if phase == "map" else []

func _next_floor_ids() -> Array[String]:
	var result: Array[String] = []
	if current.is_empty(): return result
	var next_floor := int(_nodes[current].floor)
	if next_floor >= _route.size(): return result
	for room: Dictionary in _route[next_floor]: result.append(room.id)
	return result

func is_detour(id: String) -> bool:
	return (_has_keystone("wayfarer_compass") and act not in _detours_used
		and not current.is_empty() and id not in _nodes[current].next and id in _next_floor_ids())

func upcoming() -> Array[String]:
	if phase not in ["map", "reward", "rest", "event", "shop", "haven", "treasure", "relic_reward", "keystone_reward", "elite_gate"] or _route.is_empty(): return []
	if not current.is_empty():
		var following: Array[String] = _nodes[current].next.duplicate()
		for id: String in _next_floor_ids():
			if is_detour(id): following.append(id)
		return following
	var ids: Array[String] = []
	for room: Dictionary in _route[0]: ids.append(room.id)
	return ids

func choose_node(id: String) -> bool:
	error = ""
	if not available().has(id): return _fail("That expedition room is unavailable.")
	if refined(): _last_outcome.clear()
	if is_detour(id): _detours_used.append(act)
	current = id
	visited.append(id)
	_clear_room_state()
	var kind: String = _nodes[current].kind
	if _version >= 4:
		# A different branch may change the opponent farther along the route.
		for cached: String in _opponents.keys():
			var room: Dictionary = _nodes[cached]
			if room.kind != "boss" and room.floor > _nodes[id].floor: _opponents.erase(cached)
	phase = "battle" if kind in COMBAT_ROOMS else kind
	if evolved() and kind == "elite" and not _base_opponent_at(id).is_empty() and not _base_opponent_at(id).has("scripts"): phase = "elite_gate"
	if balanced() and kind == "boss" and act == ACTS: phase = "haven"
	if expanded():
		if (kind not in COMBAT_ROOMS or phase == "haven") and _has_relic("travel_rations"): health = mini(max_health, health + 2)
		if phase == "haven":
			# Contracts must pay before the final spending opportunity.
			_contract_remaining = 0
			_bounty.clear()
		if kind == "shop" or phase == "haven": _prepare_shop()
	return true

func guardian() -> Dictionary:
	return {} if _route.is_empty() else opponent_at(_route.back()[0].id)

func guardian_at(chapter: int) -> Dictionary:
	if chapter < 1 or chapter > ACTS: return {}
	if chapter == act: return guardian()
	var probe := ELExpeditionRun.new()
	probe._version = _version
	probe.difficulty = difficulty
	probe._reset(profile, preset, seed_value, chapter)
	return probe.guardian()

func _combat_kind(room: Dictionary) -> String:
	var kind := str(room.get("kind", ""))
	if kind != "event": return kind
	var event := int(room.event) if expanded() and room.has("event") else _event_for_seed(int(room.seed))
	return "elite" if event in [WARDEN_EVENT, TRIAL_EVENT] else kind

func _base_opponent_at(id: String) -> Dictionary:
	var room: Dictionary = _nodes.get(id, {})
	var kind := _combat_kind(room)
	if kind not in COMBAT_ROOMS or (room.kind == "event" and id not in visited): return {}
	if not _opponents.has(id):
		var floor_number := (act - 1) * floors_per_act() + int(room.floor)
		var met: Array[String] = []
		if _version >= 4 and kind != "boss":
			for earlier: String in visited:
				var previous: Dictionary = _nodes[earlier]
				if previous.floor >= room.floor: break
				if _combat_kind(previous) != kind: continue
				var foe := opponent_at(earlier)
				if not foe.is_empty(): met.append(foe.id)
		var opponent := ELExpeditionEncounters.build(profile, kind, floor_number, room.seed, _version >= 2, met, expanded(), floors_per_act())
		if opponent.is_empty(): return {}
		if balanced() and difficulty == "veteran":
			opponent.health = ceili(int(opponent.health) * 1.15)
			if kind != "boss" and not opponent.has("scripts"): opponent.level = mini(20, int(opponent.level) + 1)
		_opponents[id] = opponent
	return _opponents[id]

func opponent_at(id: String) -> Dictionary:
	var opponent := _base_opponent_at(id)
	if evolved() and id == current and elite_variant in ["overcharged", "fortified"]:
		return _elite_transform(opponent, elite_variant)
	return opponent

func _elite_transform(opponent: Dictionary, variant: String) -> Dictionary:
	if opponent.is_empty() or opponent.has("scripts") or variant not in ELITE_VARIANTS: return {}
	var result := opponent.duplicate(true)
	if variant == "overcharged":
		if int(result.level) >= 20: return {}
		result.level = int(result.level) + 1
		result.health = maxi(1, ceili(int(result.health) * 0.85))
	elif variant == "fortified":
		if int(result.level) <= 1: return {}
		result.level = int(result.level) - 1
		result.health = ceili(int(result.health) * 1.25)
	return result

func elite_preview(id: String, variant: String) -> Dictionary:
	if not evolved() or _nodes.get(id, {}).get("kind") != "elite": return {}
	# Removing a level from an early elite can outweigh the extra life and
	# make its paid challenge strictly easier for common starting books.
	if variant == "fortified" and act < 2: return {}
	return _elite_transform(_base_opponent_at(id), variant)

func _elite_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for variant: String in ELITE_VARIANTS:
		var title: String = _tr("Face the elite", "Сразиться с элитой")
		var description: String = _tr("The original opponent. Normal elite gold, relic, and spell rewards.", "Обычный противник. Стандартное золото за элиту, реликвия и награда заклинанием.")
		if variant == "overcharged":
			title = _tr("Challenge: Overcharged", "Испытание: Переполнение")
			description = _tr("Enemy level +1, life -15%% (rounded up). Extra victory gold: %d. The spellbook and tactics stay the same.", "Уровень противника +1, здоровье -15%% (округляется вверх). Ещё %d золотых за победу. Книга и тактика не меняются.") % ELITE_VARIANT_GOLD
		elif variant == "fortified":
			title = _tr("Challenge: Fortified", "Испытание: Укрепление")
			description = _tr("Enemy level -1, life +25%% (rounded up). Extra victory gold: %d. The spellbook and tactics stay the same.", "Уровень противника -1, здоровье +25%% (округляется вверх). Ещё %d золотых за победу. Книга и тактика не меняются.") % ELITE_VARIANT_GOLD
		var offer := _choice("elite:" + variant, title, description)
		var foe := elite_preview(current, variant)
		if variant == "fortified" and act < 2: _unavailable(offer, _tr("Fortified challenges unlock in Act II.", "Укреплённые противники доступны со II акта."))
		elif foe.is_empty(): _unavailable(offer, _tr("This opponent cannot take that level change.", "Уровень этого противника не допускает такое изменение."))
		else: offer.context = _text("%d life · Level %d") % [int(foe.health), int(foe.level)]
		result.append(offer)
	return result

func build_battle(fresh := false) -> ELDuel:
	error = ""
	if phase != "battle":
		_fail("There is no active expedition battle.")
		return null
	if evolved() and fresh:
		_fail(_tr("Expedition duels cannot be restarted. Resume the saved duel or surrender the run.", "Бои экспедиции нельзя начать заново. Продолжите сохранённый бой или завершите поход поражением."))
		return null
	if not fresh and not _battle_checkpoint.is_empty(): return _restore_battle(_battle_checkpoint)
	var room: Dictionary = _nodes[current]
	var opponent := opponent_at(current).duplicate(true)
	if opponent.is_empty():
		_fail("The expedition encounter has no usable opponent.")
		return null
	var hero := hero_details()
	# The room's seed picks who moves first in its battle; a fresh restart
	# (Try again, older runs only) flips that coin again.
	var options := {"adventure": true, "players": [hero, opponent],
		"arena": str(opponent.get("arena", "Green.001")), "first_side": (randi() & 1) if fresh else (int(room.seed) & 1)}
	if practiced(): options.opening_slots = _opening_slots()
	for key: String in ["scripts", "script_variables", "script_difficulty"]:
		if opponent.has(key): options[key] = opponent[key]
	var duel := ELDuel.new()
	# The room's seed sets the opponent (and who moves first, above); the cards
	# are drawn afresh each time the room's battle starts.
	if not duel.start(profile, randi() & 0x7fffffff, options):
		_fail(duel.error)
		return null
	if implements_enabled() and _field_battle_charges(duel) < 0:
		_fail(_tr("The carried artifact could not be prepared for this duel.", "Не удалось подготовить походный артефакт к этому бою."))
		return null
	duel.heroes[0].maximum = max_health
	if attuned() and not ELExpeditionAttunements.apply_opening(duel, active_powers()):
		_fail(_tr("A prepared power could not be applied to this duel.", "Не удалось применить подготовленную силу к этому бою."))
		return null
	duel.setup.expedition_room = current
	duel.setup.expedition_seed = seed_value
	if expanded():
		duel.setup.expedition_relics = relics.duplicate()
		duel.setup.expedition_prepared = _prepared
	if balanced(): duel.setup.expedition_difficulty = difficulty
	if evolved(): duel.setup.expedition_identity = _battle_identity()
	if not borrowed_artifact.is_empty(): duel.setup.expedition_artifact = borrowed_artifact
	if not keepsake_artifact.is_empty(): duel.setup.expedition_keepsake = keepsake_artifact
	return duel

func resolve_battle(duel: ELDuel) -> bool:
	error = ""
	if phase != "battle" or duel == null or duel.profile != profile or duel.phase != ELDuel.Phase.FINISHED:
		return _fail("The expedition battle has not finished.")
	if not _battle_belongs_here(duel.setup):
		return _fail("This battle belongs to a different expedition room.")
	if implements_enabled():
		var remaining := _field_battle_charges(duel)
		if remaining < 0: return _fail(_tr("This duel has invalid carried artifact charges.", "В этом бою указаны неверные заряды походного артефакта."))
		field_charges = remaining
	_battle_checkpoint = {}
	borrowed_artifact = ""
	if duel.winner != 0 or int(duel.heroes[0].health) <= 0:
		health = 0
		phase = "lost"
	else:
		health = mini(max_health, int(duel.heroes[0].health))
		phase = "won" if act == ACTS and _nodes[current].kind == "boss" else "reward"
		if expanded():
			_settle_victory(duel)
			if phase != "won" and _combat_kind(_nodes[current]) in ["elite", "boss"]: phase = "relic_reward"
			if evolved() and phase == "relic_reward" and _nodes[current].kind == "boss": phase = "keystone_reward"
	_prepared = false
	if finished():
		_final_battle = {"round": duel.round_number, "opponent_life": maxi(0, int(duel.heroes[1].health))}
	return true

func save_battle(duel: ELDuel) -> bool:
	error = ""
	if phase != "battle" or duel == null or duel.profile != profile or not _battle_belongs_here(duel.setup):
		return _fail("This battle belongs to a different expedition room.")
	if implements_enabled() and _field_battle_charges(duel) < 0:
		return _fail(_tr("This duel has invalid carried artifact charges.", "В этом бою указаны неверные заряды походного артефакта."))
	var next := duel.snapshot()
	if next == _battle_checkpoint: return true
	var previous := _battle_checkpoint
	_battle_checkpoint = next
	if persist(): return true
	_battle_checkpoint = previous
	return false

func _field_battle_charges(duel: ELDuel) -> int:
	if duel.heroes.is_empty() or duel.heroes[0].get("artifacts") is not Array: return -1
	var artifacts: Array = duel.heroes[0].artifacts
	if artifacts.size() > ELDuelCosts.EL2_ARTIFACTS: return -1
	return ELExpeditionArtifacts.remaining_charges(profile, field_artifact, field_charges, artifacts)

func _battle_belongs_here(setup: Dictionary) -> bool:
	if practiced():
		var opening: Variant = setup.get("opening_slots")
		if opening is not Array or opening.size() != 2: return false
		var expected := _opening_slots()
		# JSON stores integral slot numbers as floats. Array equality is
		# type-sensitive, so validate the two integer values individually.
		for side in 2:
			if not ELLuaSave._integer(opening[side], expected[side], expected[side]): return false
	if evolved():
		for key: String in ["expedition_room", "expedition_difficulty", "expedition_identity"]:
			if setup.get(key) is not String: return false
		for key: String in ["expedition_artifact", "expedition_keepsake"]:
			if setup.get(key, "") is not String: return false
		if setup.get("expedition_relics") is not Array or setup.get("expedition_prepared") is not bool: return false
	return (setup.get("expedition_room") == current
		and ELLuaSave._integer(setup.get("expedition_seed"), seed_value, seed_value)
		and (not expanded() or (setup.get("expedition_relics", []) == relics and setup.get("expedition_prepared", false) == _prepared))
		and (not balanced() or setup.get("expedition_difficulty", "standard") == difficulty)
		and (not evolved() or setup.expedition_identity == _battle_identity())
		and setup.get("expedition_artifact", "") == borrowed_artifact
		and setup.get("expedition_keepsake", "") == keepsake_artifact)

func _battle_identity() -> String:
	# A stable string survives JSON's integer-to-float conversion. Direct
	# Dictionary equality would reject an otherwise identical loaded duel.
	var identity := {"rules": _version, "preset": str(preset.get("id", "")), "deck": deck.duplicate(),
		"path": visited.duplicate(), "training": _training.duplicate(), "life": health,
		"maximum": max_health, "keystones": keystones.duplicate(), "study": study_path,
		"elite": elite_variant}
	if refined(): identity.reserve = reserve.duplicate()
	if attuned(): identity.inactive_powers = inactive_powers.duplicate()
	if practiced():
		identity.opening_spell = opening_spell
		identity.opening_suppressed = opening_suppressed
	if implements_enabled():
		identity.field_artifact = field_artifact
		identity.field_charges = field_charges
		identity.artifact_project = artifact_project
	return JSON.stringify(identity, "", true).sha256_text()

func _restore_battle(saved: Dictionary) -> ELDuel:
	var setup: Variant = saved.get("setup")
	if setup is not Dictionary or not _battle_belongs_here(setup) or setup.get("adventure") != true:
		_fail("This battle belongs to a different expedition room.")
		return null
	if implements_enabled():
		# The duel loader normalizes custom definitions, dropping unknown
		# keys. Validate the carried item before that normalization as well.
		var heroes: Variant = saved.get("heroes")
		if heroes is not Array or heroes.is_empty() or heroes[0] is not Dictionary or heroes[0].get("artifacts") is not Array:
			_fail(_tr("The saved duel has invalid carried artifact data.", "В сохранённом бою указаны неверные данные походного артефакта."))
			return null
		if heroes[0].artifacts.size() > ELDuelCosts.EL2_ARTIFACTS or ELExpeditionArtifacts.remaining_charges(profile, field_artifact, field_charges, heroes[0].artifacts) < 0:
			_fail(_tr("The saved duel has invalid carried artifact charges.", "В сохранённом бою указаны неверные заряды походного артефакта."))
			return null
	var duel := ELDuel.new()
	if duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": saved}):
		if implements_enabled() and _field_battle_charges(duel) < 0:
			_fail(_tr("The saved duel has invalid carried artifact charges.", "В сохранённом бою указаны неверные заряды походного артефакта."))
			return null
		if attuned():
			var opening: Variant = duel.setup.get(ELExpeditionAttunements.OPENING_MARKER)
			if opening is not Array or opening != active_powers() or duel.heroes[0].skills != hero_details().skills:
				_fail(_tr("This battle does not match the expedition's prepared powers.", "Этот бой не соответствует подготовленным силам экспедиции."))
				return null
		var trained := trained_skills()
		for code: String in trained:
			if duel.heroes[0].skills.get(code) != trained[code]:
				_fail("This battle does not match the expedition's trained skills.")
				return null
		# Legacy runs deliberately redrew future randomness on resume. New
		# journeys keep the exact random state stored by the duel checkpoint.
		if not refined(): duel.reseed()
		return duel
	_fail(duel.error)
	return null

func _eligible_spells() -> Array[String]:
	var pool: Array[String] = []
	for code: String in profile.table("CombatSpells"):
		if owned_copies(code) < ELDuelCosts.EL2_COPIES and _valid_card(profile, code, preset.faction): pool.append(code)
	pool.sort()
	return pool

func _offered_cards(roll_override := -1) -> Array[String]:
	var spells := profile.table("CombatSpells")
	var pool := _eligible_spells()
	var room: Dictionary = _nodes[current]
	var kind := _combat_kind(room)
	var balanced_offers := _version >= 5 and kind in COMBAT_ROOMS
	var roll := _reward_roll if roll_override < 0 else roll_override
	if balanced() and roll > 0:
		var previous := _offered_cards(0)
		var fresh := pool.filter(func(code: String) -> bool: return code not in previous)
		# Preserve offer count in tiny/custom catalogs; full catalogs get an
		# entirely new set, with the normal creature/rarity preference intact.
		if fresh.size() >= previous.size(): pool.assign(fresh)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(room.seed) ^ 0x61e0a25f ^ (0x2729b63d if balanced() and roll > 0 else 0)
	var result: Array[String] = []
	for index in mini(3, pool.size()):
		var source := pool
		if balanced_offers and index < 2:
			var creature := index == 0
			var options := pool.filter(func(code: String) -> bool: return (spells[code].get("Class") == "Creature") == creature)
			if creature and act == 1 and room.floor <= 2:
				var cheap := options.filter(func(code: String) -> bool: return ELEncyclopaedia.cost(profile, code) <= 3)
				if not cheap.is_empty(): options = cheap
			var faction_spells := options.filter(func(code: String) -> bool: return spells[code].get("Color") == preset.faction)
			if not faction_spells.is_empty(): options = faction_spells
			if not options.is_empty(): source = options
		elif evolved() and balanced_offers and index == 2:
			var focus := _focus_candidates(study_path, pool)
			if not focus.is_empty(): source = focus
		var card: String = source[rng.randi_range(0, source.size() - 1)]
		result.append(card)
		pool.erase(card)
	var bonus := 2 if kind == "boss" else int(kind == "elite")
	if bonus > 0:
		# Higher-risk rooms add choices from the remaining rare and unique spells.
		var rare := pool.filter(func(code: String) -> bool: return spells[code].get("Rarity") in ["Rare", "Unique"])
		for index in mini(bonus, pool.size()):
			var source := rare if not rare.is_empty() else pool
			var code: String = source[rng.randi_range(0, source.size() - 1)]
			rare.erase(code)
			pool.erase(code)
			result.append(code)
	if _has_relic("glass_compass") and not pool.is_empty():
		var card: String = pool[rng.randi_range(0, pool.size() - 1)]
		result.append(card)
		pool.erase(card)
	if _has_keystone("prismatic_quill") and not pool.is_empty():
		result.append(pool[rng.randi_range(0, pool.size() - 1)])
	return result

func _focus_candidates(path_id: String, pool: Array[String]) -> Array[String]:
	var candidates := ELExpeditionPaths.candidates(profile, path_id, pool, act, practiced())
	if not practiced() or act != 1 or path_id != "blue_spirits": return candidates
	var creatures := profile.table("CombatCreatures")
	for code: String in owned_spells():
		if creatures.get(code, {}).get("Race") == "Spirit": return candidates
	var first_spirits: Array[String] = []
	for code: String in candidates:
		if code in ["WRSP", "SHSP"] and profile.table("CombatSpells")[code].get("Class") == "Creature" and creatures.get(code, {}).get("Race") == "Spirit":
			first_spirits.append(code)
	return candidates if first_spirits.is_empty() else first_spirits

func _card_title(card: String) -> String:
	return profile.text(str(profile.table("CombatSpells").get(card, {}).get("Name", card)))

func _text(value: String) -> String:
	return ELRemakeText.t(value, profile)

func _choice(id: String, title: String, description := "", card := "") -> Dictionary:
	var row := {"id": id, "title": title, "description": description}
	if not card.is_empty(): row.card = card
	return row

func _heal_amount(percent: float) -> int:
	return mini(max_health - health, ceili(max_health * percent))

func _study_spell() -> String:
	var card: String = CAMP_STUDY.get(preset.faction, "")
	if act < 2 or card.is_empty() or deck.has(card) or not _valid_card(profile, card, preset.faction): return ""
	if refined() and owned_copies(card) >= ELDuelCosts.EL2_COPIES: return ""
	return card

func _starting_skills() -> Dictionary:
	var skills: Dictionary = preset.skills.duplicate()
	if not skills.has("PRVD") and not ELHeroSkills.definition(profile, "PRVD", 0).is_empty():
		skills["PRVD"] = 0
	return skills

func trained_skills() -> Dictionary:
	var result := {}
	if _training.is_empty(): return result
	var starting := _starting_skills()
	for code: String in _training:
		result[code] = int(starting.get(code, -1)) + int(_training[code])
	return result

func _training_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if act < 2: return result
	var sessions := 0
	for count: int in _training.values(): sessions += count
	if sessions >= _training_limit(): return result
	var skills := _starting_skills()
	skills.merge(trained_skills(), true)
	for code: String in TRAINABLE_SKILLS:
		var rank := int(skills.get(code, -1)) + 1
		var definition := ELHeroSkills.definition(profile, code, rank)
		if definition.is_empty(): continue
		var title := profile.text(str(definition.Name)).strip_edges()
		if attuned() and code == "PRVD": title = _tr("Resources", "Ресурсы")
		elif attuned() and code == "SUPR": title = _tr("Suppression", "Сглаз")
		var description := profile.text(str(definition.get("Description", ""))).strip_edges()
		var offer := _choice("train:" + code, _text("Train %s · Rank %d") % [title, rank + 1], description)
		offer.rank = rank
		result.append(offer)
	return result

func _expedition_artifact(name: String) -> Dictionary:
	if name not in EXPEDITION_ARTIFACTS or preset.artifacts.size() >= ELDuelCosts.EL2_ARTIFACTS: return {}
	var item := ELDuel.artifact_entry(profile, {"name": name, "charges": 1})
	return {} if item.is_empty() or item.spell in preset.artifacts else item

func _artifact_choices(keep: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if keep and (not keepsake_artifact.is_empty() or health <= KEEPSAKE_COST): return result
	if not keep and not borrowed_artifact.is_empty(): return result
	var occupied := _artifact_slots()
	if occupied >= ELDuelCosts.EL2_ARTIFACTS: return result
	for name: String in EXPEDITION_ARTIFACTS:
		if name == borrowed_artifact or name == keepsake_artifact: continue
		var item := _expedition_artifact(name)
		if item.is_empty(): continue
		var description := _text("One charge in your next duel, ready from round %d.") % item.ready_round
		var action := "borrow"
		var title := _text("Borrow %s") % ELSecondArtifacts.title(profile, item)
		if keep:
			action = "keep"
			title = _text("Keep %s") % ELSecondArtifacts.title(profile, item)
			description = _text("Spend %d life. One charge each duel, ready from round %d.") % [KEEPSAKE_COST, item.ready_round]
		var offer := _choice(action + ":" + name, title, description + "\n" + profile.card_description(item.spell))
		offer.artifact = item
		if implements_enabled() and keep and not artifact_project.is_empty() and field_artifact.is_empty() and _artifact_slots(false, false) + 1 >= ELDuelCosts.EL2_ARTIFACTS:
			_unavailable(offer, _tr("This would fill the last permanent artifact slot. Finish your carried project first.", "Это займёт последнее постоянное место для артефакта. Сначала завершите взятую заготовку."))
		elif implements_enabled() and not keep and not artifact_project.is_empty() and field_artifact.is_empty() and _artifact_slots(false) + 1 >= ELDuelCosts.EL2_ARTIFACTS and _remaining_artifact_duels() <= 1:
			_unavailable(offer, _tr("The loan would occupy the last artifact slot until the final duel. Finish your carried project first.", "Одолженный артефакт займёт последнее место до финального боя. Сначала завершите взятую заготовку."))
		result.append(offer)
	return result

func _event_index() -> int:
	var room: Dictionary = _nodes[current]
	return int(room.event) if expanded() and room.has("event") else _event_for_seed(int(room.seed))

func _event_for_seed(room_seed: int) -> int:
	if expanded():
		for room: Dictionary in _nodes.values():
			if int(room.seed) == room_seed and room.has("event"): return int(room.event)
	if _version >= 6 and act >= 2 and ((room_seed >> 10) & 3) == 0: return RELIQUARY_EVENT
	if _version >= 7 and act >= 2 and ((room_seed >> 14) & 3) == 0: return WARDEN_EVENT
	return room_seed % RELIQUARY_EVENT

func _mirror_exchange(require_life := true) -> Dictionary:
	if require_life and health <= MIRROR_EXCHANGE_COST: return {}
	var spells := profile.table("CombatSpells")
	var by_class := {}
	for code: String in _eligible_spells():
		var spell: Dictionary = spells[code]
		if spell.get("Rarity") not in ["Rare", "Unique"]: continue
		var kind: String = spell.get("Class", "")
		if not by_class.has(kind): by_class[kind] = []
		by_class[kind].append(code)
	var outgoing: Array[String] = []
	for code: String in deck:
		var spell: Dictionary = spells[code]
		if spell.get("Rarity") in ["Cantrip", "Common"] and by_class.has(spell.get("Class", "")) and not outgoing.has(code):
			outgoing.append(code)
	if outgoing.is_empty(): return {}
	var random := RandomNumberGenerator.new()
	random.seed = int(_nodes[current].seed) ^ 0x2fe93a85
	var old := outgoing[random.randi_range(0, outgoing.size() - 1)]
	var pool: Array = by_class[spells[old].get("Class", "")]
	var next: String = pool[random.randi_range(0, pool.size() - 1)]
	var offer := _choice("transmute", _text("Transform %s") % _card_title(old),
		_text("Spend %d life to exchange it for %s, a rarer spell of the same type.") % [MIRROR_EXCHANGE_COST, _card_title(next)], old)
	offer.incoming = next
	return offer

func _rebalanced_room_summary() -> Dictionary:
	if pending_reserve >= 0 and pending_reserve < reserve.size():
		return {"title": _tr("Make room for %s", "Подготовить: %s") % _card_title(reserve[pending_reserve]),
			"description": _tr("Choose a page to put in reserve. Both spells stay yours. The swap is free.", "Выберите страницу, которую уберёте в запас. Оба заклинания останутся у вас. Обмен бесплатный.")}
	if not pending_craft.is_empty():
		return {"title": _tr("Rewrite %s", "Переписать: %s") % _card_title(pending_craft),
			"description": _tr("Choose the new spell. You can read each offer before paying, or go back and keep your pages.", "Выберите новое заклинание. Можно изучить предложения до оплаты или вернуться и сохранить свои страницы.")}
	if not pending_card.is_empty():
		var detail := _tr("Add this spell, replace a page, or save it in reserve.", "Добавьте заклинание в боевую книгу, замените страницу или оставьте его в запасе.")
		if phase == "rest": detail = _tr("Choose a page to replace. This uses your camp action.", "Выберите страницу для замены. Это займёт привал.")
		elif phase == "haven": detail = _tr("Add this spell to your book or replace a page. Pay when you choose its place.", "Добавьте заклинание в боевую книгу или замените страницу. Оплата — после выбора места.")
		elif shopping(): detail += " " + _tr("Pay when you choose its place.", "Оплата — после выбора места.")
		return {"title": _tr("Keep %s", "Взять: %s") % _card_title(pending_card), "description": detail}
	match phase:
		"boon":
			return {"title": _tr("A gift for the road", "Дар в дорогу"), "description": _tr("Choose a relic to carry. You have 40 gold for the journey.", "Выберите реликвию в дорогу. На поход у вас 40 золотых.")}
		"discipline":
			return {"title": _tr("Choose a school", "Выберите школу"), "description": _tr("Your school guides one spell offer after battle and one at ordinary merchants. Other offers stay varied. Or take 10 gold and keep your options open.", "Школа влияет на одно предложение после боя и одно у обычных торговцев. Остальные заклинания остаются разными. Можно взять 10 золотых и обойтись без школы.")}
		"keystone_reward":
			return {"title": _tr("The guardian's legacy", "Наследие стража"), "description": _tr("Keep one keystone, or take gold and healing supplies. A spell reward comes next.", "Возьмите один краеугольный камень или золото с целебными припасами. Затем получите награду заклинанием."), "receipt": _reward_receipt().strip_edges()}
		"elite_gate":
			return {"title": _tr("Choose your challenge", "Выберите испытание"), "description": _tr("Face the elite as you found them, or change their strength for 10 more gold. Check their level and life before you commit.", "Сразитесь с элитой на обычных условиях или измените её силу ради ещё 10 золотых. Перед боем сравните уровень и здоровье противника.")}
		"treasure", "relic_reward":
			var detail := _tr("Keep one relic, or take gold and healing supplies.", "Возьмите одну реликвию или золото с целебными припасами.")
			if phase == "relic_reward": detail += " " + _tr("A spell reward comes next.", "Затем получите награду заклинанием.")
			return {"title": _tr("Choose a relic", "Выберите реликвию"), "description": detail, "receipt": _reward_receipt().strip_edges()}
		"shop":
			return {"title": _tr("The wandering merchant", "Странствующий торговец"), "description": _tr("Spells, relics and supplies lie on a worn blanket. Each offer can be bought once.", "На потёртом покрывале разложены заклинания, реликвии и припасы. Каждое предложение доступно один раз.")}
		"haven":
			return {"title": _tr("The Last Haven", "Последний привал"), "description": _tr("One duel remains: the White Lord. Spend your gold and arrange your book here. Reserve swaps are free. Unfinished contracts have expired.", "Остался один бой — с Белым Лордом. Здесь можно потратить золото и подготовить книгу. Обмен страниц с запасом бесплатный. Незавершённые договоры уже истекли.")}
		"rest":
			return {"title": _tr("By the campfire", "У костра"), "description": _tr("Choose one: rest, gather supplies, or work on your spells. You can swap reserve pages for free before you decide.", "Отдохните, соберите припасы или займитесь заклинаниями — на всё времени не хватит. До этого можно бесплатно обменять страницы с запасом.")}
		"event":
			var index := _event_index()
			var summary := ELExpeditionContent.event(profile, index, true)
			if index in [WARDEN_EVENT, TRIAL_EVENT]: summary.illustration = "warden"
			elif index == RELIQUARY_EVENT: summary.illustration = "reliquary"
			if index == 12 and not pending_relic.is_empty():
				summary.description = _tr("The broker has set %s aside. Choose the relic you will give up; the exchange costs 12 gold.", "Меняла отложил для вас реликвию «%s». Выберите, какую реликвию отдадите; доплата — 12 золотых.") % ELExpeditionContent.relic(profile, pending_relic, true).title
			return summary
		"reward":
			var title := _text("Battle reward")
			var kind := _combat_kind(_nodes[current])
			if kind == "elite": title = _text("Elite battle reward")
			elif kind == "boss": title = _text("Guardian reward")
			var detail := _tr("Choose one spell, or leave it behind.", "Выберите одно заклинание или откажитесь от награды.")
			if health < max_health and _reward_recovery() > 0: detail = _tr("Choose one spell, or recover life instead.", "Возьмите одно заклинание или восстановите здоровье.")
			elif _has_keystone("blood_crown"): detail += " " + _tr("Blood Crown removes the healing choice.", "С Кровавой короной нельзя взять лечение вместо заклинания.")
			return {"title": title, "description": detail, "receipt": _reward_receipt().strip_edges()}
	return {}

func _attuned_room_summary() -> Dictionary:
	var summary := _rebalanced_room_summary()
	# Placement submenus retain the exact instructions for their pending page.
	if pending_reserve >= 0 or not pending_card.is_empty() or not pending_craft.is_empty(): return summary
	match phase:
		"boon":
			summary.description = _tr("The road crosses the lands of all four ethers. Choose a relic to carry; you have 40 gold for supplies.", "Дорога проходит через земли четырёх стихий эфира. Выберите реликвию в дорогу; на припасы у вас 40 золотых.")
		"discipline":
			summary.description = _tr("Choose a school within your hero's magic. It guides one spell offer after battle and one at ordinary merchants. Or take 10 gold and study whatever you find.", "Выберите школу магии своего героя. Она влияет на одно предложение после боя и одно у обычных торговцев. Можно взять 10 золотых и изучать всё, что найдётся в пути.")
		"keystone_reward":
			summary.title = _tr("The guardian's teachings", "Знания стража")
			summary.description = _tr("Learn one combat power or keep one keystone. Powers are prepared for each duel; activated abilities still pay their usual ether costs. You can set a power aside at camp. Gold and healing are also available. A spell reward comes next.", "Изучите одну боевую силу или возьмите краеугольный камень. Силы готовятся к каждому бою; применение их способностей требует обычных затрат эфира. На привале силу можно отложить. Вместо этого можно взять золото и лечение. Затем получите награду заклинанием.")
		"shop":
			summary.description = _tr("Kinet manuscripts lie beside Synthet salvage and bundles of Forest herbs. The merchant names a price for each. Every offer can be bought once.", "Рядом с рукописями кинетов лежат детали машин синтетов и пучки трав из Леса. Торговец называет цену за каждую вещь. Каждое предложение можно купить один раз.")
		"haven":
			summary.description = _tr("The Temple of Time lies ahead. Before facing the White Lord, spend your gold, arrange your spellbook and choose which powers to prepare. Reserve swaps and power preparation are free. Unfinished contracts have expired.", "Впереди Храм Времени. Перед встречей с Белым Лордом потратьте золото, соберите книгу и подготовьте нужные силы. Обмен с запасом и подготовка сил бесплатны. Незавершённые договоры уже истекли.")
		"rest":
			summary.description = _tr("Set down the spellbook and tend the fire. Rest, gather supplies, or work on your spells: choose one. First, you can freely swap reserve pages and prepare or set aside learned powers.", "Отложите книгу и подбросьте дров в костёр. Отдохните, соберите припасы или займитесь заклинаниями — выберите что-то одно. До этого можно бесплатно обменять страницы с запасом и подготовить или отложить изученные силы.")
	return summary

func room_summary() -> Dictionary:
	if practiced():
		if opening_selecting:
			return {"title": _tr("Rehearse your opening", "Отрепетировать начало боя"), "description": _opening_cost_text() + " " + _tr("Choose a spell from your active book. It will take one of your five opening hand slots in every duel. Casting costs and charges stay the same. Back cancels without spending anything.", "Выберите заклинание из боевой книги. В каждом бою оно займёт одно из пяти мест в стартовой руке. Стоимость применения и заряды не меняются. «Назад» отменяет выбор без затрат.")}
		var summary := _attuned_room_summary()
		if pending_reserve >= 0 or not pending_card.is_empty() or not pending_craft.is_empty(): return summary
		if phase == "rest":
			summary.description = _tr("Tend the fire and lay out your pages. Rest, gather supplies, rehearse an opening spell, or work on the book: choose one. You can freely swap reserve pages and prepare learned powers before you decide.", "Подбросьте дров в костёр и разложите страницы. Отдохните, соберите припасы, подготовьте стартовое заклинание или займитесь книгой — выберите одно. До этого можно бесплатно обменять страницы с запасом и подготовить изученные силы.")
		elif phase == "shop" and _nodes.get(current, {}).get("kind") == "event" and _event_index() == 5 and _shop_bought.is_empty():
			summary.description += " " + _tr("You can return to the caravan and take the guiding job until you make a purchase.", "Пока вы ничего не купили, можно вернуться к каравану и взять работу проводника.")
		if implements_enabled():
			if phase == "rest" and (not field_artifact.is_empty() or not artifact_project.is_empty()):
				summary.description = _tr("Lay out your pages and tools beside the fire. Rest, gather supplies, work on the book, or tend an artifact: choose one. Reserve swaps and preparation of learned powers are free.", "Разложите страницы и инструменты у костра. Отдохните, соберите припасы, займитесь книгой или артефактом — выберите одно. Обмен с запасом и подготовка изученных сил бесплатны.")
			elif phase == "relic_reward" and _artifact_slots(false) < ELDuelCosts.EL2_ARTIFACTS and not _field_recipe_offers(1, 0x15e117e).is_empty():
				summary.title = _tr("The spoils of the duel", "Добыча после боя")
				summary.description = _tr("Keep one relic or a charged artifact, or take gold and healing supplies. A spell reward comes next.", "Возьмите реликвию, заряженный артефакт или золото с целебными припасами. Затем получите награду заклинанием.")
		return summary
	if attuned(): return _attuned_room_summary()
	if rebalanced(): return _rebalanced_room_summary()
	if refined():
		if pending_reserve >= 0 and pending_reserve < reserve.size():
			return {"title": _tr("Prepare a reserved spell", "Подготовить запасное заклинание"), "description": _tr("Choose which active page to exchange for %s. Both pages remain yours. Back cancels; the service is spent only on confirmation.", "Выберите, какую боевую страницу обменять на %s. Обе карты останутся у вас. «Назад» отменяет выбор; услуга расходуется только после подтверждения.") % _card_title(reserve[pending_reserve])}
		if not pending_craft.is_empty():
			return {"title": _tr("Inspect the binding", "Изучить переплёт"), "description": _tr("Choose a replacement for %s. Both offers are fixed for this room and source page. Inspect the printed cost, effect, and lost charges before confirming; Back costs nothing.", "Выберите замену для %s. Оба предложения закреплены за этой комнатой и исходной страницей. Перед подтверждением изучите базовую стоимость, эффект и потерю зарядов; «Назад» ничего не стоит.") % _card_title(pending_craft)}
		if not rebalanced() and phase == "event" and _event_index() == LIBRARY_EVENT and not pending_card.is_empty():
			return {"title": _tr("Pack a library spell", "Взять заклинание из библиотеки"), "description": _tr("%s goes into reserve, not the active book. Choose a free slot or replace a reserved page. A later camp or paid Haven exchange is needed before it can be used in combat.", "%s попадёт в запас, а не в боевую книгу. Выберите свободное место или замените запасную страницу. Для использования в бою понадобится обмен на привале или платный обмен на Последнем привале.") % _card_title(pending_card)}
	if expanded():
		if evolved() and phase == "discipline":
			return {"title": _tr("Choose a study path", "Выберите школу"), "description": _tr("A study path steers one spell-reward option and one regular merchant slot toward its theme when an affordable legal spell is available. The final Haven prioritizes its counterspell. Other offers remain varied. Or take 10 gold and keep an open book.", "Школа направляет один вариант награды и одно место в обычной лавке к своей теме, если есть доступное подходящее заклинание. На Последнем привале приоритет у заклинания против чар. Остальные предложения остаются разнообразными. Или возьмите 10 золотых и сохраните свободный выбор.")}
		if evolved() and phase == "keystone_reward":
			return {"title": _tr("The guardian's legacy", "Наследие стража"), "description": _tr("Choose one keystone to shape the rest of your expedition. Read its benefits and conditions before committing. You may take field supplies instead; the spell reward follows.", "Выберите один краеугольный камень на оставшийся поход. Изучите преимущества и условия перед выбором. Можно взять походные припасы; затем последует награда заклинанием."), "receipt": _reward_receipt().strip_edges()}
		if evolved() and phase == "elite_gate":
			return {"title": _tr("Choose your challenge", "Выберите испытание"), "description": _tr("Face the original elite or change its combat profile for extra gold. Compare its life and level with your book. Every option risks the run; once the duel begins it cannot be restarted.", "Сразитесь с обычной элитой или измените её боевые параметры ради дополнительного золота. Сопоставьте здоровье и уровень с вашей книгой. Любой бой опасен для похода; начавшийся бой нельзя начать заново.")}
		if phase == "boon":
			return {"title": _tr("A gift for the road", "Дар в дорогу"), "description": _tr("Choose a starting relic. Its effect lasts for the entire run. You also begin with 40 gold to spend at merchants.", "Выберите стартовую реликвию. Её эффект действует весь поход. Вы также начинаете с 40 золотыми для покупок у торговцев.")}
		if phase in ["treasure", "relic_reward"]:
			var title := _tr("Choose a relic", "Выберите реликвию")
			var detail := _tr("Take one permanent passive, or take 25 gold instead.", "Возьмите одну постоянную реликвию или 25 золотых.")
			if phase == "relic_reward":
				detail = _tr("Take one permanent passive, or take 20 gold instead. Your spell reward follows.", "Возьмите одну постоянную реликвию или 20 золотых. Затем получите награду заклинанием.")
			if balanced():
				detail = _tr("Choose a permanent passive, or take field supplies: gold and life recovery.", "Выберите постоянную реликвию или возьмите припасы: золото и восстановление здоровья.")
				if phase == "relic_reward": detail += " " + _tr("Your spell reward follows.", "Затем получите награду заклинанием.")
			return {"title": title, "description": detail if balanced() else _reward_receipt() + detail, "receipt": _reward_receipt().strip_edges() if balanced() else ""}
		if shopping():
			var detail := _tr("Buy any number of offers while you can afford them. Each item, the heal, and the spell removal can be bought once here. Leave when ready.", "Покупайте товары, пока хватает золота. Каждый товар, лечение и удаление заклинания доступны здесь один раз. Уходите, когда закончите.")
			if not pending_card.is_empty(): detail = _tr("Choose a place for %s. Gold is spent only when you confirm; Back cancels the purchase.", "Выберите место для %s. Золото тратится лишь после подтверждения; «Назад» отменяет покупку.") % _card_title(pending_card)
			if phase == "haven":
				detail = _tr("Spend your remaining gold before facing White Lord. This is the last merchant: buy spells, heal, refine the book, or prepare for the final duel. Unfinished courier and bounty contracts expire here.", "Потратьте оставшееся золото перед встречей с Белым Лордом. Это последний торговец: купите заклинания, исцелитесь, измените книгу или подготовьтесь к последнему бою. Незавершённые договоры курьера и заказы здесь истекают.") if pending_card.is_empty() else detail
			return {"title": _tr("The Last Haven", "Последний привал") if phase == "haven" else _tr("The wandering merchant", "Странствующий торговец"), "description": detail}
	if current.is_empty() or phase not in ["event", "rest", "reward"]: return {}
	var title: String = _nodes[current].title
	var description := ""
	var illustration := ""
	match phase:
		"event":
			var index := _event_index()
			if expanded() and index >= 5:
				var summary := ELExpeditionContent.event(profile, index)
				if index == TRIAL_EVENT: summary.illustration = "warden"
				if index == 12 and not pending_relic.is_empty():
					var offer := ELExpeditionContent.relic(profile, pending_relic, true)
					summary.description = _tr("Choose a relic to exchange for %s. Pay 12 gold only when you confirm. Back cancels.", "Выберите реликвию для обмена на %s. 12 золотых спишутся после подтверждения. «Назад» отменяет обмен.") % offer.title
				return summary
			var event: Array = EVENTS[index]
			title = _text(event[0])
			description = _text(event[1])
			if index == RELIQUARY_EVENT: illustration = "reliquary"
			elif index == WARDEN_EVENT: illustration = "warden"
		"rest":
			description = _text("Recover some life or remove a spell from your spellbook.")
			if not pending_card.is_empty():
				description = _text("Choose a spell to replace with %s.") % _card_title(pending_card)
			elif not _study_spell().is_empty():
				description = _text("Recover life, remove a spell, or study a counter to enchantments.")
			if pending_card.is_empty() and not _training_choices().is_empty():
				description += " " + _text("You can also train a skill for the rest of the expedition.")
		"reward":
			match _combat_kind(_nodes[current]):
				"elite": title = _text("Elite battle reward")
				"boss": title = _text("Guardian reward")
				_: title = _text("Battle reward")
			description = _text("Choose one spell to add or use as a replacement.") if pending_card.is_empty() else _text("Choose how to use %s.") % _card_title(pending_card)
			if pending_card.is_empty() and health < max_health and _reward_recovery() > 0:
				description = _text("Choose a spell for your spellbook or recover life.")
			elif pending_card.is_empty() and _has_keystone("blood_crown"):
				description += " " + _tr("Blood Crown prevents recovery from spell rewards.", "Кровавая корона запрещает лечение наградами за заклинания.")
			if expanded() and not balanced(): description = _reward_receipt() + description
	var summary := {"title": title, "description": description}
	if balanced() and phase == "reward": summary.receipt = _reward_receipt().strip_edges()
	if not illustration.is_empty(): summary.illustration = illustration
	return summary

func _event_choices() -> Array[Dictionary]:
	if expanded() and _event_index() >= 5: return _expanded_event_choices()
	var result: Array[Dictionary] = []
	match _event_index():
		0:
			result.append(_choice("recover", _text("Drink from the spring"), _text("Recover %d life.") % _heal_amount(0.2)))
			var offers := _offered_cards()
			if health > 3 and deck.size() < MAX_DECK and not offers.is_empty():
				result.append(_choice("trade", _text("Trade with the wayfarer"), _text("Spend 3 life to learn %s.") % _card_title(offers[0]), offers[0]))
				if rebalanced(): result.back().title = _tr("Copy a spell in blood", "Переписать заклинание кровью")
			result.append_array(_artifact_choices(false))
		1:
			if refined(): result.append_array(_craft_source_choices())
			else:
				var exchange := _mirror_exchange()
				if not exchange.is_empty(): result.append(exchange)
			var listed := {}
			for index in deck.size():
				var card := deck[index]
				if listed.has(card): continue
				listed[card] = true
				if deck.size() > MIN_DECK:
					result.append(_choice("purge:%d" % index, _text("Erase %s") % _card_title(card), _text("Remove this spell and recover %d life.") % _heal_amount(0.1), card))
				if health > 4 and deck.size() < MAX_DECK and owned_copies(card) < ELDuelCosts.EL2_COPIES:
					result.append(_choice("echo:%d" % index, _text("Copy %s") % _card_title(card), _text("Spend 4 life to add another copy of this spell."), card))
		2:
			if health > 5 and life_bonus < MAX_LIFE_BONUS:
				result.append(_choice("oath", _text("Swear the blood oath"), _text("Spend 5 life to gain 4 maximum life.")))
			result.append(_choice("mend", _text("Make a small offering"), _text("Recover %d life.") % mini(2, max_health - health)))
			if rebalanced(): result.back().title = _tr("Take the herbs", "Взять травы")
		RELIQUARY_EVENT:
			result.append_array(_artifact_choices(true))
			if implements_enabled() and not field_artifact.is_empty():
				for amount in range(1, ELExpeditionArtifacts.CAPACITY - field_charges + 1): result.append(_field_recharge_choice(amount, true))
			if health < max_health:
				result.append(_choice("mend", _text("Drink the draught"), _text("Recover %d life.") % mini(2, max_health - health)))
		WARDEN_EVENT:
			var opponent := opponent_at(current)
			if not opponent.is_empty():
				var detail := "%s\n%s" % [opponent.title, _text("%d life · Level %d") % [opponent.health, opponent.level]]
				if rebalanced(): detail += "\n" + _tr("Win for elite rewards. Defeat ends the expedition.", "Победа даёт награды за элиту. Поражение завершает поход.")
				result.append(_choice("challenge", _text("Accept the duel"), detail))
	result.append(_choice("leave", _text("Leave")))
	return result

func choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if practiced() and opening_selecting: return _opening_choices()
	if refined():
		if pending_reserve >= 0: return _reserve_exchange_choices()
		if not pending_craft.is_empty(): return _craft_choices()
		if not rebalanced() and phase == "event" and _event_index() == LIBRARY_EVENT and not pending_card.is_empty():
			result.append_array(_reserve_placement_choices())
			result.append(_choice("back", _text("Back")))
			return result
	var library_placement := rebalanced() and phase == "event" and _event_index() == LIBRARY_EVENT and not pending_card.is_empty()
	if (phase in ["rest", "reward", "shop", "haven"] or library_placement) and not pending_card.is_empty():
		if (phase in ["reward", "shop", "haven"] or library_placement) and deck.size() < MAX_DECK:
			result.append(_choice("add", _text("Add %s to the spellbook") % _card_title(pending_card), "", pending_card))
		for index in deck.size():
			# Buying a spell over an identical copy would spend gold and stock
			# without changing the book. Only offer real merchant replacements.
			if (shopping() or rebalanced()) and deck[index] == pending_card: continue
			result.append(_choice("replace:%d" % index, _text("Replace %s") % _card_title(deck[index]), "", deck[index]))
		# A final-Haven purchase should be placed directly into the active
		# book. Storing it and paying to swap it in adds a dominated fee.
		if refined() and (phase in ["reward", "shop"] or library_placement): result.append_array(_reserve_placement_choices())
		result.append(_choice("back", _text("Back")))
		if shopping():
			for offer: Dictionary in result:
				if offer.id != "back": _price(offer, _shop_card_price(pending_card))
		return result
	match phase:
		"discipline":
			if evolved(): return _study_choices(true)
		"keystone_reward":
			if evolved(): return _keystone_choices()
		"elite_gate":
			if evolved(): return _elite_choices()
		"boon", "treasure", "relic_reward":
			if not expanded(): return []
			var pool: Array = ELExpeditionContent.STARTING_RELICS if phase == "boon" else _relic_offers(3)
			for id: String in pool: result.append(_relic_choice("relic:" + id, id))
			if implements_enabled() and phase == "relic_reward" and _combat_kind(_nodes[current]) == "elite" and _artifact_slots(false) < ELDuelCosts.EL2_ARTIFACTS:
				for id: String in _field_recipe_offers(1, 0x15e117e):
					var detail := ELExpeditionArtifacts.find(profile, id)
					var artifact := _field_choice("claim_artifact:" + id, id, "claim", _tr("Take %s", "Взять: %s") % str(detail.title))
					artifact.context += "\n" + _tr("Take this finished artifact with two charges instead of a relic or supplies. The spell reward still follows.", "Взять готовый артефакт с двумя зарядами вместо реликвии или припасов. После этого останется награда заклинанием.")
					result.append(artifact)
			if phase != "boon":
				var offer := _choice("skip_relic", _tr("Take gold instead", "Взять золото"), _tr("Gain %d gold.", "Получить %d золотых.") % (25 if phase == "treasure" else 20))
				if balanced():
					offer.title = _tr("Take field supplies", "Взять походные припасы")
					offer.description += " " + _text("Recover %d life.") % _heal_amount(0.2)
				result.append(offer)
		"shop", "haven":
			if expanded(): return _shop_choices()
		"reward":
			for card: String in _offered_cards():
				result.append(_choice("card:" + card, _card_title(card), profile.card_description(card), card))
			if health < max_health and _reward_recovery() > 0:
				result.append(_choice("recover_reward", _text("Recover life instead"), _text("Recover %d life.") % _heal_amount(_reward_recovery())))
			if balanced():
				var reroll := _price(_choice("reroll_reward", _tr("Redraw the spell reward", "Обновить заклинания в награде"), _tr("Once per act. Replace the offered spells; their new selection survives reloads. You still choose one reward.", "Один раз за акт. Заменяет предложенные заклинания; новый выбор сохраняется при загрузке. Взять можно только одну награду.")), reward_redraw_cost())
				if rebalanced():
					reroll.title = _tr("Look for other spells", "Поискать другие заклинания")
					reroll.description = _tr("Change these offers. Once per act; you still take one reward.", "Заменить предложения. Один раз за акт; взять можно только одну награду.")
				if not evolved(): reroll.description = _tr("Once per act. Replace the offered spells; their new selection survives reloads. You still choose one spell or recovery.", "Один раз за акт. Заменяет предложенные заклинания; новый выбор сохраняется при загрузке. Вы всё равно берёте одно заклинание или лечение.")
				if act in _reroll_used_acts: _unavailable(reroll, _tr("You already redrew a reward in this act.", "Вы уже обновляли награду в этом акте."))
				elif not _can_redraw_reward(): _unavailable(reroll, _tr("No different spell selection is available to redraw.", "Нет другого набора заклинаний для обновления."))
				result.append(reroll)
			result.append(_choice("skip", _text("Skip reward")))
		"rest":
			var rest := _choice("heal", _text("Rest"), _text("Recover %d life.") % _heal_amount(_camp_healing()))
			if rebalanced() and health >= max_health: _unavailable(rest, _tr("Your life is already full.", "Здоровье уже полное."))
			result.append(rest)
			if expanded(): result.append(_choice("forage", _tr("Gather supplies to sell", "Собрать припасы на продажу"), _tr("Gain 18 gold instead of resting.", "Получить 18 золотых вместо отдыха.")))
			if practiced(): result.append(_opening_service_choice())
			if implements_enabled():
				if not artifact_project.is_empty(): result.append(_field_completion_choice())
				if not field_artifact.is_empty(): result.append(_field_recharge_choice())
			var study := _study_spell()
			if not study.is_empty():
				result.append(_choice("study", _text("Study %s") % _card_title(study), profile.card_description(study), study))
			result.append_array(_training_choices())
			if refined(): result.append_array(_reserve_select_choices())
			if attuned(): result.append_array(_power_choices())
			if practiced(): result.append_array(_opening_toggle_choices())
			if deck.size() > MIN_DECK:
				for index in deck.size():
					result.append(_choice("remove:%d" % index, _text("Remove %s") % _card_title(deck[index]), "", deck[index]))
		"event":
			return _event_choices()
	return result

func choose(id: String) -> bool:
	error = ""
	var selected := {}
	for option: Dictionary in choices():
		if option.id == id:
			selected = option
			break
	if selected.is_empty(): return _fail("That expedition choice is unavailable.")
	if bool(selected.get("disabled", false)):
		return _fail(str(selected.get("reason", _tr("You cannot afford that choice.", "Для этого выбора не хватает ресурсов."))))
	var before := _outcome_state() if refined() else {}
	var applied := _apply_choice(id, selected)
	if applied and practiced() and not opening_spell.is_empty() and owned_copies(opening_spell) == 0:
		opening_spell = ""
		opening_suppressed = false
	if applied and refined(): _record_outcome(before, id)
	return applied

func _apply_choice(id: String, selected: Dictionary) -> bool:
	if implements_enabled() and _choose_field_artifact(id, selected): return true
	if practiced():
		if id in ["prepare_opening", "suppress_opening"]:
			opening_suppressed = id == "suppress_opening"
			return true
		if id == "opening_select":
			opening_selecting = true
			return true
		if opening_selecting and id == "back":
			opening_selecting = false
			return true
		if id.begins_with("opening_spell:"):
			opening_spell = str(selected.card)
			opening_selecting = false
			opening_suppressed = false
			if phase == "haven": gold -= int(selected.cost)
			else: _complete_room()
			return true
		if id == "scholar_notes":
			_gain_gold(12)
			_complete_room()
			return true
		if id == "caravan_back":
			_clear_room_state()
			phase = "event"
			return true
	if attuned():
		if id.begins_with("prepare_power:"):
			inactive_powers.erase(id.trim_prefix("prepare_power:"))
			return true
		if id.begins_with("suppress_power:"):
			inactive_powers.append(id.trim_prefix("suppress_power:"))
			inactive_powers.sort()
			return true
	if refined() and _choose_refined(id, selected): return true
	if expanded() and _choose_expanded(id, selected): return true
	if id == "challenge":
		phase = "battle"
		return true
	if id.begins_with("card:"):
		pending_card = id.trim_prefix("card:")
		return true
	if id == "study":
		pending_card = selected.card
		return true
	if id == "back":
		pending_card = ""
		return true
	if id == "add": deck.append(pending_card)
	elif id.begins_with("replace:"): deck[int(id.get_slice(":", 1))] = pending_card
	elif id.begins_with("remove:"): deck.remove_at(int(id.get_slice(":", 1)))
	elif id.begins_with("train:"):
		var code := id.trim_prefix("train:")
		_training[code] = int(_training.get(code, 0)) + 1
	elif id == "heal": health += _heal_amount(_camp_healing())
	elif id == "recover_reward": health += _heal_amount(_reward_recovery())
	elif id == "recover": health += _heal_amount(0.2)
	elif id == "mend": health += mini(2, max_health - health)
	elif id == "trade":
		deck.append(_offered_cards()[0])
		health -= 3
	elif id.begins_with("borrow:"): borrowed_artifact = selected.artifact.name
	elif id.begins_with("keep:"):
		keepsake_artifact = selected.artifact.name
		health -= KEEPSAKE_COST
	elif id == "transmute":
		deck[deck.find(selected.card)] = selected.incoming
		health -= MIRROR_EXCHANGE_COST
	elif id.begins_with("purge:"):
		deck.remove_at(int(id.get_slice(":", 1)))
		health += _heal_amount(0.1)
	elif id.begins_with("echo:"):
		deck.append(deck[int(id.get_slice(":", 1))])
		health -= 4
	elif id == "oath":
		life_bonus += 4
		max_health += 4
		health -= 5
	_complete_room()
	return true

func _can_pack_spell(code: String) -> bool:
	return reserve.size() < RESERVE_LIMIT or reserve.any(func(stored: String) -> bool: return stored != code)

func _reserve_placement_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if pending_card.is_empty(): return result
	if reserve.size() < RESERVE_LIMIT:
		var offer := _choice("reserve_add", _tr("Pack %s in reserve", "Положить %s в запас") % _card_title(pending_card), _tr("Uses this spell reward or purchase. Reserved pages give no combat charges. Exchange one at camp instead of another service, or pay for one exchange at the Last Haven.", "Расходует награду или покупку. Страницы в запасе не дают зарядов в бою. Обменяйте одну на привале вместо другой услуги или заплатите за один обмен на Последнем привале."), pending_card)
		if rebalanced(): offer.description = _tr("Keep this page for later. Swap it into your book for free at a camp or the Last Haven.", "Оставить страницу на потом. На привале или Последнем привале её можно бесплатно обменять со страницей боевой книги.")
		offer.storage = "reserve_add"
		result.append(offer)
	for index in reserve.size():
		if reserve[index] == pending_card: continue
		var offer := _choice("reserve_replace:%d" % index, _tr("Replace reserved %s", "Заменить в запасе: %s") % _card_title(reserve[index]), _tr("Discard this reserved page and pack the new spell. Your active book does not change.", "Убрать эту страницу из запаса и положить новое заклинание. Боевая книга не изменится."), reserve[index])
		offer.incoming = pending_card
		offer.storage = "reserve_replace"
		offer.reserve_index = index
		result.append(offer)
	return result

func _reserve_select_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var shown := {}
	for index in reserve.size():
		var code := reserve[index]
		if shown.has(code): continue
		shown[code] = true
		var offer := _choice("swap_select:%d" % index, _tr("Prepare %s from reserve", "Подготовить из запаса: %s") % _card_title(code), _tr("Exchange it with one active page. Book size and total ownership stay unchanged. Uses this camp visit instead of resting or another service.", "Обменять с одной страницей боевой книги. Размер книги и общее число карт не меняются. Расходует привал вместо отдыха или другой услуги."), code)
		if rebalanced(): offer.description = _tr("Swap with a page in your book for free. You can still use the camp's main service.", "Бесплатно обменять со страницей боевой книги. После обмена можно отдохнуть или выбрать другое занятие на привале.") if phase == "rest" else _tr("Swap with a page in your book for free. You can rearrange both reserve pages before the final duel.", "Бесплатно обменять со страницей боевой книги. Перед последним боем можно подготовить обе запасные страницы.")
		offer.storage = "reserve_select"
		offer.reserve_index = index
		if phase == "haven" and not rebalanced():
			offer.description = _tr("Exchange it with one active page. One reserve exchange at the Last Haven; payment happens only after choosing the outgoing page.", "Обменять с одной страницей боевой книги. Один обмен запаса на Последнем привале; плата списывается только после выбора отдаваемой страницы.")
			_price(offer, _merchant_price(RESERVE_SWAP_COST))
			if "reserve_swap" in _shop_bought: _unavailable(offer, _tr("The reserve exchange was already used here.", "Обмен запаса здесь уже использован."))
		result.append(offer)
	return result

func _reserve_exchange_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if pending_reserve < 0 or pending_reserve >= reserve.size(): return result
	var incoming := reserve[pending_reserve]
	var shown := {}
	for index in deck.size():
		var code := deck[index]
		if code == incoming or shown.has(code): continue
		shown[code] = true
		var offer := _choice("swap_with:%d" % index, _tr("Pack %s; prepare %s", "Убрать %s; подготовить %s") % [_card_title(code), _card_title(incoming)], _tr("The outgoing page goes into reserve. Neither page is destroyed, and your active book stays the same size.", "Отдаваемая страница уходит в запас. Обе карты сохраняются, размер боевой книги не меняется."), code)
		offer.incoming = incoming
		offer.storage = "reserve_swap"
		offer.reserve_index = pending_reserve
		if phase == "haven" and not rebalanced(): _price(offer, _merchant_price(RESERVE_SWAP_COST))
		result.append(offer)
	result.append(_choice("back", _text("Back")))
	return result

func _craft_recipes() -> Array[Dictionary]:
	if not refined() or phase != "event" or _event_index() not in [1, 7, ANVIL_EVENT]: return []
	var consume := 2 if _event_index() == ANVIL_EVENT else 1
	if deck.size() - consume + 1 < MIN_DECK: return []
	return ELExpeditionCrafting.recipes(profile, preset.faction, deck, owned_spells(), act, int(_nodes[current].seed), study_path, consume)

func _craft_payment(offer: Dictionary) -> Dictionary:
	if _event_index() == 1:
		offer.life_cost = MIRROR_EXCHANGE_COST
		offer.description += " " + _tr("Costs 3 life on confirmation.", "При подтверждении тратится 3 ед. здоровья.")
		if health <= MIRROR_EXCHANGE_COST: _unavailable(offer, _tr("You need more than 3 life.", "Нужно больше 3 ед. здоровья."))
	else: _price(offer, ANVIL_COST if _event_index() == ANVIL_EVENT else 32)
	return offer

func _craft_source_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe: Dictionary in _craft_recipes():
		var consume := int(recipe.consume)
		var title := _tr("Refine %s", "Переписать: %s") % _card_title(recipe.source)
		var detail := _tr("Inspect up to two rarer spells of the same type before exchanging this page. Printed cost is limited to this act's 3 / 5 / 8 ether ceiling. Back cancels without payment.", "Изучите до двух более редких заклинаний того же типа перед обменом страницы. Базовая стоимость ограничена 3 / 5 / 8 эфира по акту. «Назад» отменяет выбор без оплаты.")
		if rebalanced():
			title = _tr("Rewrite %s", "Переписать: %s") % _card_title(recipe.source)
			detail = _tr("Choose a rarer spell of the same type. Read the offers before trading this page.", "Выберите более редкое заклинание того же типа. Перед обменом можно изучить предложения.")
		if consume == 2:
			title = _tr("Bind two copies of %s", "Соединить две копии: %s") % _card_title(recipe.source)
			detail = _tr("Choose a rarer spell of the same type. Two identical active pages become one: the book loses one page and its duel charges. Back cancels without payment.", "Выберите более редкое заклинание того же типа. Две одинаковые боевые страницы станут одной: книга потеряет страницу и её заряды. «Назад» отменяет выбор без оплаты.")
			if rebalanced(): detail = _tr("Trade two copies for one rarer spell of the same type. Your book loses one page and %d charges per duel.", "Обменяйте две копии на одно более редкое заклинание того же типа. Книга потеряет одну страницу и %d зарядов на бой.") % charges_per_page()
		var offer := _craft_payment(_choice("craft_select:" + recipe.source, title, detail, recipe.source))
		offer.consume = consume
		result.append(offer)
	return result

func _craft_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe: Dictionary in _craft_recipes():
		if recipe.source != pending_craft: continue
		for code: String in recipe.incoming:
			var detail := _tr("Exchange %d copy/copies of %s for one %s. Rarity does not guarantee that a spell suits your book.", "Обменять %d копии %s на одну %s. Редкость не гарантирует, что заклинание подходит вашей книге.") % [int(recipe.consume), _card_title(pending_craft), _card_title(code)]
			if rebalanced():
				detail = _tr("Give up: %s × %d. Take: %s.", "Отдать: %s × %d. Получить: %s.") % [_card_title(pending_craft), int(recipe.consume), _card_title(code)]
			var offer := _craft_payment(_choice("craft:" + code, _tr("Bind %s", "Создать: %s") % _card_title(code), detail, pending_craft))
			offer.incoming = code
			offer.consume = int(recipe.consume)
			result.append(offer)
	result.append(_choice("back", _text("Back")))
	return result

func _library_offers() -> Array[String]:
	return ELExpeditionCrafting.library_offers(profile, preset.faction, owned_spells(), act, int(_nodes[current].seed), study_path)

func _choose_refined(id: String, selected: Dictionary) -> bool:
	if id == "back" and (pending_reserve >= 0 or not pending_craft.is_empty() or (phase == "event" and _event_index() == LIBRARY_EVENT and not pending_card.is_empty())):
		pending_reserve = -1
		pending_craft = ""
		pending_card = ""
		return true
	if id.begins_with("swap_select:"):
		pending_reserve = int(selected.reserve_index)
		return true
	if id.begins_with("swap_with:"):
		var index := int(id.get_slice(":", 1))
		var outgoing := deck[index]
		deck[index] = reserve[pending_reserve]
		reserve[pending_reserve] = outgoing
		pending_reserve = -1
		if phase == "haven" and not rebalanced():
			gold -= int(selected.cost)
			_shop_bought.append("reserve_swap")
		elif not rebalanced(): _complete_room()
		return true
	if id == "reserve_add" or id.begins_with("reserve_replace:"):
		if id == "reserve_add": reserve.append(pending_card)
		else: reserve[int(selected.reserve_index)] = pending_card
		if shopping():
			gold -= int(selected.cost)
			_shop_bought.append("card:" + pending_card)
			pending_card = ""
		else: _complete_room()
		return true
	if id.begins_with("craft_select:"):
		pending_craft = selected.card
		return true
	if id.begins_with("craft:"):
		var index := deck.find(pending_craft)
		deck[index] = selected.incoming
		if int(selected.consume) == 2: deck.remove_at(deck.find(pending_craft))
		if _event_index() == 1: health -= MIRROR_EXCHANGE_COST
		else: gold -= int(selected.cost)
		_complete_room()
		return true
	if id.begins_with("library_card:"):
		pending_card = selected.card
		return true
	if id in ["library_notes", "anvil_salvage"]:
		_gain_gold(12 if id == "library_notes" else 10)
		_complete_room()
		return true
	return false

func _clear_room_state() -> void:
	opening_selecting = false
	pending_reserve = -1
	pending_craft = ""
	_shop_stock.clear()
	_shop_relic = ""
	_shop_bought.clear()
	_last_reward.clear()
	pending_relic = ""
	_reward_roll = 0
	elite_variant = ""

func _study_choices(initial: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for path: Dictionary in ELExpeditionPaths.paths(profile, str(preset.faction)):
		if not initial and path.id == study_path: continue
		var offer := _choice(("study:" if initial else "refocus:") + str(path.id), path.title, path.description)
		var examples: Array[String] = []
		for code: String in _focus_candidates(str(path.id), _eligible_spells()).slice(0, 3): examples.append(_card_title(code))
		offer.context = _tr("Examples available this act: %s.", "Примеры доступных в этом акте заклинаний: %s.") % ", ".join(examples) if not examples.is_empty() else _tr("No affordable example is currently available; normal offers are used until one becomes legal.", "Сейчас нет доступного примера; до появления подходящих заклинаний используются обычные предложения.")
		if rebalanced() and examples.is_empty(): offer.context = _tr("No matching spells to offer yet. Other spells will appear until then.", "Подходящих заклинаний пока нет. До их появления будут предложены другие.")
		if path.cards.is_empty(): _unavailable(offer, _tr("This catalog has no supported spells for this study path.", "В этом каталоге нет поддерживаемых заклинаний для этой школы."))
		if not initial:
			_price(offer, REFOCUS_COST)
			if practiced() and not _refocus_has_future_use(str(path.id)):
				_unavailable(offer, _tr("No remaining spell offer would change with this school.", "Эта школа уже не изменит ни одного предложения заклинаний."))
		result.append(offer)
	if initial:
		result.append(_choice("study:none", _tr("Take the Open Road", "Выбрать свободный путь"), _tr("Gain 10 gold. Keep the normal unrestricted spell selection.", "Получить 10 золотых. Сохранить обычный выбор заклинаний без влияния школы.")))
	elif study_path != "none":
		var road := _price(_choice("refocus:none", _tr("Return to the Open Road", "Вернуться на свободный путь"), _tr("Remove your study focus. Future rewards use the normal unrestricted selection.", "Отказаться от школы. Будущие награды используют обычный свободный выбор.")), REFOCUS_COST)
		if practiced() and not _refocus_has_future_use("none"):
			_unavailable(road, _tr("No remaining spell offer would change without a school.", "Отказ от школы уже не изменит ни одного предложения заклинаний."))
		result.append(road)
	return result

## Reject only a provably ineffective late change. An intervening battle,
## camp, merchant, or event may alter the book, so remains a possible benefit.
## Treasure cannot change pages; compare the actual Haven stock after its
## mandatory counter-spell replacement, including available Compass detours.
func _refocus_has_future_use(path_id: String) -> bool:
	if not practiced() or act < ACTS or current.is_empty(): return true
	var queue: Array[Dictionary] = [{"id": current, "detour": act in _detours_used}]
	var seen := {}
	while not queue.is_empty():
		var state: Dictionary = queue.pop_back()
		var signature := "%s:%s" % [state.id, state.detour]
		if seen.has(signature): continue
		seen[signature] = true
		var room: Dictionary = _nodes.get(state.id, {})
		if room.is_empty(): return true
		var next_ids: Array[String] = []
		next_ids.assign(room.next)
		var natural := next_ids.duplicate()
		if _has_keystone("wayfarer_compass") and not bool(state.detour) and int(room.floor) < _route.size():
			for next: Dictionary in _route[int(room.floor)]:
				if next.id not in next_ids: next_ids.append(next.id)
		for id: String in next_ids:
			var next: Dictionary = _nodes[id]
			if next.kind in COMBAT_ROOMS and next.kind != "boss": return true
			if next.kind in ["rest", "shop", "event"]: return true
			if next.kind == "boss":
				var original := _shop_cards_for(int(next.seed), study_path, true)
				var changed := _shop_cards_for(int(next.seed), path_id, true)
				original.sort()
				changed.sort()
				if original != changed: return true
				continue
			queue.append({"id": id, "detour": bool(state.detour) or id not in natural})
	return false

func _keystone_offers() -> Array[String]:
	var pool: Array[String] = []
	for id: String in ELExpeditionContent.KEYSTONES:
		if id not in keystones: pool.append(id)
	pool.sort()
	var random := RandomNumberGenerator.new()
	random.seed = int(_nodes.get(current, {}).get("seed", seed_value)) ^ 0x5ae6317b
	var result: Array[String] = []
	if attuned():
		var powers: Array[String] = []
		for detail: Dictionary in ELExpeditionAttunements.available(profile, str(preset.faction), owned_spells(), keystones):
			# A learned rank must improve the hero instead of consuming a major
			# reward for a skill the starter already possesses.
			if str(detail.get("skill", "")) == "CONC" and int(_starting_skills().get("CONC", -1)) >= int(detail.get("rank", 1)): continue
			powers.append(str(detail.id))
		powers.sort()
		# Two combat plans and one familiar run reward. A depleted or sparse
		# mounted catalog falls back to the remaining old rewards.
		while result.size() < 2 and not powers.is_empty():
			var at := random.randi_range(0, powers.size() - 1)
			result.append(powers[at])
			powers.remove_at(at)
	while result.size() < 3 and not pool.is_empty():
		var at := random.randi_range(0, pool.size() - 1)
		result.append(pool[at])
		pool.remove_at(at)
	return result

func _keystone_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _keystone_offers():
		var power := attuned() and ELExpeditionAttunements.is_power(id)
		var detail := ELExpeditionAttunements.find(profile, id) if power else ELExpeditionContent.keystone(profile, id)
		var offer := _choice("keystone:" + id, detail.title, detail.description)
		offer.keystone = id
		if power: offer.ability = id
		offer.context = _keystone_context(id)
		result.append(offer)
	result.append(_choice("skip_keystone", _tr("Take field supplies", "Взять походные припасы"), _tr("Gain 20 gold and recover %d life. Continue without a keystone.", "Получить 20 золотых и восстановить %d ед. здоровья. Продолжить без краеугольного камня.") % _heal_amount(0.2)))
	return result

func _can_redraw_reward() -> bool:
	var previous := _offered_cards(0)
	var next := _offered_cards(1)
	previous.sort()
	next.sort()
	return not previous.is_empty() and previous != next

func _settle_victory(duel: ELDuel) -> void:
	var room: Dictionary = _nodes[current]
	var kind := _combat_kind(room)
	var random := RandomNumberGenerator.new()
	random.seed = int(room.seed) ^ 0x4ac38721
	var earned := (45 + 5 * act if kind == "boss" else (28 + 3 * act if kind == "elite" else 13 + 2 * act)) + random.randi_range(0, 5)
	if balanced() and difficulty == "veteran": earned = ceili(earned * 1.15)
	var challenge_gold := ELITE_VARIANT_GOLD if evolved() and elite_variant in ["overcharged", "fortified"] else 0
	earned += challenge_gold
	if _has_relic("silver_scale"): earned += 6
	if _has_relic("hunters_badge") and kind in ["elite", "boss"]: earned += 20
	if _has_relic("ember_purse") and duel.round_number <= (SWIFT_ROUND_LIMIT if balanced() else 6): earned += 12
	if room.kind == "event" and _event_index() == TRIAL_EVENT and duel.round_number <= 6: earned += 30
	var paid := 0
	if _contract_remaining > 0:
		_contract_remaining -= 1
		if _contract_remaining == 0:
			paid = COURIER_REWARD
			earned += paid
	var bounty_paid := 0
	if balanced() and not _bounty.is_empty():
		var met: bool = kind == "elite" if _bounty.kind == "elite" else duel.round_number <= SWIFT_ROUND_LIMIT
		if met:
			bounty_paid = 40 if _bounty.kind == "elite" else 30
			earned += bounty_paid
			_bounty.clear()
		else:
			_bounty.remaining = int(_bounty.remaining) - 1
			if int(_bounty.remaining) <= 0: _bounty.clear()
	var before := gold
	_gain_gold(earned)
	var healed := mini(max_health - health, 2) if _has_relic("amber_seed") else 0
	health += healed
	_last_reward = {"gold": gold - before, "healed": healed, "contract": paid}
	if balanced(): _last_reward.bounty = bounty_paid
	if evolved(): _last_reward.challenge = challenge_gold

func _reward_receipt() -> String:
	if _last_reward.is_empty(): return ""
	var text := _tr("Victory: +%d gold.", "Победа: +%d золотых.") % int(_last_reward.get("gold", 0))
	if int(_last_reward.get("healed", 0)) > 0:
		text += " " + _tr("Relics restored %d life.", "Реликвии восстановили %d ед. здоровья.") % int(_last_reward.healed)
	if int(_last_reward.get("contract", 0)) > 0:
		text += " " + _tr("The courier paid your 55-gold contract.", "Курьер выплатил 55 золотых по договору.")
	if int(_last_reward.get("bounty", 0)) > 0:
		text += " " + _tr("Bounty completed: %d gold included.", "Заказ выполнен: выплата включает %d золотых.") % int(_last_reward.bounty)
	if int(_last_reward.get("challenge", 0)) > 0:
		text += " " + _tr("Elite challenge: %d bonus gold included.", "Испытание элиты: выплата включает %d дополнительных золотых.") % int(_last_reward.challenge)
	return text + "\n\n"

func _relic_offers(count: int, salt := 0, merchant_only := false) -> Array[String]:
	var pool: Array[String] = []
	for id: String in ELExpeditionContent.RELICS:
		if id not in relics and _useful_relic(id) and (not merchant_only or _merchant_relic_viable(id)): pool.append(id)
	pool.sort()
	var random := RandomNumberGenerator.new()
	random.seed = int(_nodes.get(current, {}).get("seed", seed_value)) ^ 0x1d7e3b45 ^ salt
	var result: Array[String] = []
	while result.size() < count and not pool.is_empty():
		var at := random.randi_range(0, pool.size() - 1)
		result.append(pool[at])
		pool.remove_at(at)
	return result

func _relic_choice(action: String, id: String) -> Dictionary:
	var detail := ELExpeditionContent.relic(profile, id, balanced())
	var offer := _choice(action, detail.title, detail.description)
	offer.relic = id
	if balanced(): offer.context = relic_status(id)
	return offer

func _useful_relic(id: String) -> bool:
	if refined() and id == "twin_seal" and not _can_use_extra_training(): return false
	if not balanced() or act < ACTS or int(_nodes.get(current, {}).get("floor", 0)) < floors_per_act() - 1: return true
	# At the last elite/treasure and Haven, only offer effects that can still
	# influence the final fight or the preparations immediately before it.
	match id:
		"aether_prism": return int(battle_preview().level) < 20
		"duelists_crest": return deck.size() <= 13 and int(battle_preview().level) < 20
		"glass_compass": return phase == "relic_reward"
		"merchant_seal": return phase != "haven" or not _shop_stock.is_empty()
		"purifier_stone": return deck.size() > MIN_DECK and "remove" not in _shop_bought
	return false

## An optimistic ceiling, not an expected return. Each future floor takes
## its best room even when branches do not connect, so this can never rule
## out a purchase that could pay back through a legal route or detour.
func _remaining_opportunity_bound(kind: String, include_current := false) -> int:
	var total := 0
	var floor_now := int(_nodes.get(current, {}).get("floor", 0))
	for chapter in range(act, ACTS + 1):
		var rows := _route
		if chapter != act:
			var probe := ELExpeditionRun.new()
			probe._version = _version
			probe._reset(profile, preset, seed_value, chapter)
			rows = probe._route
		for row: Array in rows:
			var best := 0
			for room: Dictionary in row:
				if chapter == act and (int(room.floor) < floor_now or (int(room.floor) == floor_now and (not include_current or room.id != current))): continue
				var event := int(room.get("event", -1))
				var victory: bool = room.kind in COMBAT_ROOMS or (room.kind == "event" and event in [WARDEN_EVENT, TRIAL_EVENT])
				var elite: bool = room.kind in ["elite", "boss"] or (room.kind == "event" and event in [WARDEN_EVENT, TRIAL_EVENT])
				var value := 0
				match kind:
					"wins": value = int(victory and not (chapter == ACTS and room.kind == "boss"))
					"elites": value = int(elite and not (chapter == ACTS and room.kind == "boss"))
					"merchants": value = int(room.kind == "shop" or (room.kind == "event" and event == 5) or (chapter == ACTS and room.kind == "boss"))
					"training": value = int(chapter >= 2 and (room.kind == "rest" or (room.kind == "event" and event == 7)))
				best = maxi(best, value)
			total += best
	return total

func _can_use_extra_training() -> bool:
	var spent := _training_sessions()
	if spent >= 3: return true
	if spent + _remaining_opportunity_bound("training", true) < 3: return false
	var skills := _starting_skills()
	skills.merge(trained_skills(), true)
	var available_ranks := 0
	for code: String in TRAINABLE_SKILLS:
		for rank in range(int(skills.get(code, -1)) + 1, 3):
			if not ELHeroSkills.definition(profile, code, rank).is_empty(): available_ranks += 1
	return spent + available_ranks >= 3

func _merchant_relic_viable(id: String) -> bool:
	if not refined(): return true
	var cost := _shop_relic_price(id)
	match id:
		"silver_scale": return 6 * _remaining_opportunity_bound("wins") > cost
		"ember_purse": return 12 * _remaining_opportunity_bound("wins") > cost
		"hunters_badge": return 20 * _remaining_opportunity_bound("elites") > cost
		"purifier_stone": return _merchant_price(25) * _remaining_opportunity_bound("merchants", true) > cost
		"twin_seal": return _can_use_extra_training()
	return true

## Maximum remaining scheduled wins on a reachable route before the last
## market. Optional event duels are deliberately not promised by a contract.
func _future_combat_capacity(elites_only := false) -> int:
	if act < ACTS: return 2
	var best := {}
	for index in range(_route.size() - 1, -1, -1):
		for room: Dictionary in _route[index]:
			var own := int(room.kind == "elite") if elites_only else int(room.kind in ["fight", "elite"])
			var next := 0
			for id: String in room.next: next = maxi(next, int(best.get(id, 0)))
			best[room.id] = own + next
	var result := 0
	var following: Array = _nodes.get(current, {}).get("next", [])
	for id: String in following: result = maxi(result, int(best.get(id, 0)))
	return result

## Offers must be possible within the actual two-victory deadline. An
## intervening guardian spends a victory but never fulfills an elite bounty.
## Only scheduled fights are promised; optional event duels remain a bonus.
func _contract_reachable(goal: String) -> bool:
	var chapters := {}
	for chapter in range(act, ACTS + 1):
		if chapter == act: chapters[chapter] = {"nodes": _nodes, "route": _route}
		else:
			var probe := ELExpeditionRun.new()
			probe._version = _version
			probe._reset(profile, preset, seed_value, chapter)
			chapters[chapter] = {"nodes": probe._nodes, "route": probe._route}
	var queue: Array[Dictionary] = [{"act": act, "id": current, "wins": 0, "detour": act in _detours_used}]
	var seen := {}
	while not queue.is_empty():
		var state: Dictionary = queue.pop_back()
		var signature := "%d:%s:%d:%s" % [state.act, state.id, state.wins, state.detour]
		if seen.has(signature): continue
		seen[signature] = true
		var chapter := int(state.act)
		var nodes: Dictionary = chapters[chapter].nodes
		var route_rows: Array = chapters[chapter].route
		var room: Dictionary = nodes.get(state.id, {})
		var next_ids: Array[String] = []
		if room.is_empty():
			for next: Dictionary in route_rows[0]: next_ids.append(next.id)
		elif room.kind == "boss":
			if chapter < ACTS: queue.append({"act": chapter + 1, "id": "", "wins": state.wins, "detour": false})
			continue
		else: next_ids.assign(room.next)
		var natural := next_ids.duplicate()
		if _has_keystone("wayfarer_compass") and not bool(state.detour) and not room.is_empty() and int(room.floor) < route_rows.size():
			for next: Dictionary in route_rows[int(room.floor)]:
				if next.id not in next_ids: next_ids.append(next.id)
		for id: String in next_ids:
			var next: Dictionary = nodes[id]
			# The final boss is after the payment deadline and cannot pay a contract.
			if chapter == ACTS and next.kind == "boss": continue
			var wins := int(state.wins) + int(next.kind in COMBAT_ROOMS)
			if next.kind in COMBAT_ROOMS:
				if goal == "elite" and next.kind == "elite": return true
				if goal == "swift": return true
				if goal == "courier" and wins >= 2: return true
			if wins >= 2: continue
			queue.append({"act": chapter, "id": id, "wins": wins, "detour": bool(state.detour) or id not in natural})
	return false

func _price(offer: Dictionary, cost: int) -> Dictionary:
	offer.cost = cost
	if gold < cost:
		offer.disabled = true
		offer.reason = _tr("Need %d more gold.", "Не хватает ещё %d золотых.") % (cost - gold)
	return offer

func _unavailable(offer: Dictionary, reason: String) -> Dictionary:
	offer.disabled = true
	offer.reason = reason
	return offer

func _merchant_price(base: int) -> int:
	var multiplier := 0.8 if _has_relic("merchant_seal") else 1.0
	if _has_keystone("living_heart"): multiplier *= 1.2
	return ceili(base * multiplier)

func _removal_price(with_stone := false) -> int:
	var stone := with_stone or _has_relic("purifier_stone")
	if stone and not balanced(): return 0
	return _merchant_price(maxi(0, 40 + 15 * _removals - (25 if stone else 0)))

func _shop_relic_price(id: String) -> int:
	return _merchant_price(int(ELExpeditionContent.RELIC_SHOP_PRICES.get(id, 75))) if balanced() else _merchant_price(75 + 8 * (act - 1))

func _shop_card_price(code: String) -> int:
	var rarity := str(profile.table("CombatSpells").get(code, {}).get("Rarity", "Common"))
	var base := int({"Cantrip": 20, "Common": 30, "Rare": 48, "Unique": 62}.get(rarity, 30))
	return _merchant_price(base + 3 * (act - 1))

## Generate spell stock without mutating the visit. Archive previews use the
## same rules and random stream as a real merchant, including the final counter.
func _shop_cards_for(room_seed: int, path_id: String, haven := false) -> Array[String]:
	var result: Array[String] = []
	var pool := _eligible_spells()
	var spells := profile.table("CombatSpells")
	var random := RandomNumberGenerator.new()
	random.seed = room_seed ^ 0x3619ce05
	for index in mini(4, pool.size()):
		var preferred: Array = []
		if index == 0:
			preferred = pool.filter(func(code: String) -> bool: return spells[code].get("Class") == "Creature" and ELEncyclopaedia.cost(profile, code) <= 3)
		elif index == 1:
			preferred = pool.filter(func(code: String) -> bool: return spells[code].get("Class") != "Creature")
		elif index == 2:
			preferred = pool.filter(func(code: String) -> bool: return spells[code].get("Rarity") in ["Rare", "Unique"])
		elif evolved() and index == 3:
			preferred = _focus_candidates(path_id, pool)
		var source: Array = preferred if not preferred.is_empty() else pool
		var card: String = source[random.randi_range(0, source.size() - 1)]
		result.append(card)
		pool.erase(card)
	if balanced() and haven:
		var counter := _study_spell()
		if not counter.is_empty() and counter not in result:
			if result.size() == 4: result.pop_back()
			result.append(counter)
	return result

func _prepare_shop() -> void:
	_shop_stock.assign(_shop_cards_for(int(_nodes[current].seed), study_path, phase == "haven"))
	_shop_bought.clear()
	var relic_offer := _relic_offers(1, 0x343a9d, refined())
	_shop_relic = relic_offer[0] if not relic_offer.is_empty() else ""

func _shop_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for code: String in _shop_stock:
		var offer := _price(_choice("buy_card:" + code, _card_title(code), profile.card_description(code), code), _shop_card_price(code))
		if "card:" + code in _shop_bought:
			_unavailable(offer, _tr("Already bought here.", "Уже куплено здесь."))
		elif owned_copies(code) >= ELDuelCosts.EL2_COPIES:
			_unavailable(offer, _tr("Your active book and reserve already own four copies.", "В боевой книге и запасе уже четыре копии.") if refined() else _tr("Your spellbook already has four copies.", "В книге уже четыре копии."))
		result.append(offer)
	if not _shop_relic.is_empty():
		var offer := _price(_relic_choice("buy_relic:" + _shop_relic, _shop_relic), _shop_relic_price(_shop_relic))
		if "relic" in _shop_bought or _shop_relic in relics: _unavailable(offer, _tr("Already bought here.", "Уже куплено здесь."))
		result.append(offer)
	var heal := _price(_choice("shop_heal", _tr("Buy healing supplies", "Купить целебные припасы"), _text("Recover %d life.") % _heal_amount(0.35)), _merchant_price(24))
	if "heal" in _shop_bought: _unavailable(heal, _tr("Already bought here.", "Уже куплено здесь."))
	elif health >= max_health: _unavailable(heal, _tr("Your life is already full.", "Здоровье уже полное."))
	result.append(heal)
	if balanced():
		var prepare := _price(_choice("shop_prepare", _tr("Buy provisions for the next duel", "Купить припасы для следующего боя"), _tr("Fight one level higher in your next duel only. Does not stack; maximum level 20.", "Провести следующий бой на один уровень выше. Не складывается с другими припасами; максимум — 20-й уровень.")), _merchant_price(16))
		if _prepared or "prepare" in _shop_bought: _unavailable(prepare, _tr("You already have provisions for the next duel.", "У вас уже есть припасы для следующего боя."))
		elif refined() and int(battle_preview().level) >= 20: _unavailable(prepare, _tr("Your hero already fights at the maximum level.", "Герой уже сражается на максимальном уровне."))
		result.append(prepare)
	if deck.size() > MIN_DECK:
		var cost := _removal_price()
		var shown := {}
		for index in deck.size():
			var code := deck[index]
			if shown.has(code): continue
			shown[code] = true
			var offer := _price(_choice("shop_remove:%d" % index, _text("Remove %s") % _card_title(code), _tr("Remove one copy. One removal per merchant; later paid removals cost more.", "Удалить одну копию. Одно удаление у каждого торговца; следующие платные удаления дороже."), code), cost)
			if "remove" in _shop_bought: _unavailable(offer, _tr("The removal service was already used here.", "Удаление здесь уже использовано."))
			result.append(offer)
	if refined() and phase == "haven": result.append_array(_reserve_select_choices())
	if attuned() and phase == "haven": result.append_array(_power_choices())
	if practiced() and phase == "haven": result.append(_opening_service_choice())
	if practiced() and phase == "haven": result.append_array(_opening_toggle_choices())
	if implements_enabled():
		if not field_artifact.is_empty(): result.append(_field_recharge_choice())
		if phase == "haven" and not artifact_project.is_empty(): result.append(_field_completion_choice())
	if practiced() and phase == "shop" and _nodes.get(current, {}).get("kind") == "event" and _event_index() == 5 and _shop_bought.is_empty():
		result.append(_choice("caravan_back", _tr("Return to the caravan", "Вернуться к каравану"), _tr("Close the wares. You can still take the guiding job for 12 gold.", "Отложить покупки. Ещё можно взять работу проводника за 12 золотых.")))
	result.append(_choice("enter_guardian", _tr("Face White Lord", "Встретиться с Белым Лордом"), _tr("Finish preparations and begin the final duel.", "Завершить приготовления и начать последний бой.")) if phase == "haven" else _choice("leave", _text("Leave")))
	return result

func _cartographer_trade() -> Dictionary:
	return {"life": 3 + act, "gold": 20 + 4 * act} if rebalanced() else {"life": 4, "gold": 38}

func _expanded_event_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match _event_index():
		5:
			result.append(_choice("caravan_shop", _tr("Browse the caravan", "Посмотреть товары"), _tr("Open a merchant with spells, a relic, healing, and one removal service.", "Открыть лавку с заклинаниями, реликвией, лечением и одним удалением карты.")))
			if rebalanced(): result.back().description = _tr("See what they have for sale.", "Посмотреть, что у них на продажу.")
			if practiced(): result.back().description = _tr("Inspect the wares. Until you buy something, you can come back and take the guiding job.", "Осмотреть товары. Пока ничего не куплено, можно вернуться и взять работу проводника.")
			result.append(_choice("caravan_guide", _tr("Guide the caravan", "Проводить караван"), _tr("Gain 12 gold and continue.", "Получить 12 золотых и продолжить путь.")))
		6:
			var offer := _price(_choice("courier_contract", _tr("Fund the supply route", "Оплатить восстановление пути"), _tr("After your next two victories, receive 55 gold. Only one courier contract can be active.", "После двух следующих побед получить 55 золотых. Одновременно действует лишь один договор курьера.")), COURIER_COST)
			if rebalanced(): offer.title = _tr("Pay for the repairs", "Оплатить починку")
			if _contract_remaining > 0: _unavailable(offer, _tr("A courier contract is already active.", "Договор с курьером уже действует."))
			elif (evolved() and not _contract_reachable("courier")) or (balanced() and not evolved() and _future_combat_capacity() < 2): _unavailable(offer, _tr("No route offers two more scheduled victories before the Last Haven.", "Ни на одном пути не осталось двух запланированных побед до Последнего привала."))
			if balanced(): offer.description += " " + _tr("Complete it before the Last Haven; unfinished contracts expire there.", "Завершите договор до Последнего привала; там незавершённые договоры истекают.")
			result.append(offer)
			result.append(_choice("courier_wages", _tr("Take a small delivery job", "Взять небольшое поручение"), _tr("Gain 10 gold now.", "Получить 10 золотых сейчас.")))
		7:
			if refined(): result.append_array(_craft_source_choices())
			else:
				var exchange := _mirror_exchange(false)
				if not exchange.is_empty():
					exchange.id = "forge_exchange"
					exchange.description = _tr("Exchange one copy for %s, a rarer spell of the same type. Your spellbook stays the same size.", "Обменять одну копию на %s — более редкое заклинание того же типа. Размер книги не изменится.") % _card_title(exchange.incoming)
					result.append(_price(exchange, 32))
			for offer: Dictionary in _training_choices():
				offer.id = "forge_train:" + String(offer.id).trim_prefix("train:")
				result.append(_price(offer, 38))
		8:
			var trade := _cartographer_trade()
			var help := _choice("cartographer_help", _tr("Carry the cartographer through", "Перенести картографа через перевал"), _tr("Spend %d life. Gain %d gold.", "Потратить %d ед. здоровья. Получить %d золотых.") % [int(trade.life), int(trade.gold)])
			if health <= int(trade.life): _unavailable(help, _tr("You need more than %d life.", "Нужно больше %d ед. здоровья.") % int(trade.life))
			result.append(help)
			var heal := _price(_choice("cartographer_heal", _tr("Buy the medicine", "Купить лекарство"), _text("Recover %d life.") % _heal_amount(0.4)), 22)
			if health == max_health: _unavailable(heal, _tr("Your life is already full.", "Здоровье уже полное."))
			result.append(heal)
		TRIAL_EVENT:
			var opponent := opponent_at(current)
			if not opponent.is_empty():
				result.append(_choice("challenge", _tr("Accept the veteran's trial", "Принять испытание ветерана"), "%s\n%s\n%s" % [opponent.title, _text("%d life · Level %d") % [opponent.health, opponent.level], _tr("Relic and spell reward. +30 gold if won by round 6.", "Реликвия и заклинание. +30 золотых при победе не позднее 6-го раунда.")]))
				if rebalanced(): result.back().description += " " + _tr("Defeat ends the expedition.", "Поражение завершает поход.")
		10:
			var offers := _relic_offers(1, 0x31bed7)
			if not offers.is_empty():
				var relic := offers[0]
				var bought := _relic_choice("vault_buy:" + relic, relic)
				bought.title = _tr("Buy %s", "Купить: %s") % bought.title
				result.append(_price(bought, 50 if balanced() else 55))
				var blood := _relic_choice("vault_blood:" + relic, relic)
				blood.title = _tr("Break the ward for %s", "Сломать печать ради: %s") % blood.title
				var life_cost := 12 if balanced() else 8
				blood.description = (_tr("Spend %d life. ", "Потратить %d ед. здоровья. ") % life_cost) + String(blood.description)
				if health <= life_cost: _unavailable(blood, _tr("You need more than %d life.", "Нужно больше %d ед. здоровья.") % life_cost)
				result.append(blood)
		11:
			result.append(_choice("feast_meal", _tr("Share a modest meal", "Разделить скромную трапезу"), _text("Recover %d life.") % _heal_amount(0.15)))
			var feast := _price(_choice("feast_heal", _tr("Buy a restorative feast", "Купить сытный обед"), _text("Recover %d life.") % _heal_amount(0.6)), 25)
			if health == max_health: _unavailable(feast, _tr("Your life is already full.", "Здоровье уже полное."))
			elif refined() and _heal_amount(0.6) <= _heal_amount(0.15): _unavailable(feast, _tr("The modest meal already restores all missing life.", "Скромная трапеза уже восстановит всё недостающее здоровье."))
			result.append(feast)
			var prepared := _price(_choice("feast_prepare", _tr("Provision the next duel", "Запастись припасами для боя"), _tr("Your hero fights one level higher in the next duel only, up to level 20. Does not stack.", "Герой проведёт следующий бой на один уровень выше, до 20-го уровня. Припасы не складываются.")), 16)
			if _prepared: _unavailable(prepared, _tr("You already have provisions for the next duel.", "У вас уже есть припасы для следующего боя."))
			elif refined() and int(battle_preview().level) >= 20: _unavailable(prepared, _tr("Your hero already fights at the maximum level.", "Герой уже сражается на максимальном уровне."))
			result.append(prepared)
		12:
			if pending_relic.is_empty():
				for id: String in _relic_offers(2, 0x2be638):
					result.append(_price(_relic_choice("broker_select:" + id, id), BROKER_COST))
			else:
				for id: String in relics:
					var old := ELExpeditionContent.relic(profile, id, true)
					var offer := _price(_choice("broker_exchange:" + id, _tr("Exchange %s", "Обменять: %s") % old.title, _tr("Lose this effect: ", "Потерять этот эффект: ") + String(old.description)), BROKER_COST)
					if id == "twin_seal" and _training_sessions() > TRAINING_LIMIT: _unavailable(offer, _tr("This relic is supporting your third training session.", "Эта реликвия поддерживает третье обучение."))
					result.append(offer)
				result.append(_choice("back", _text("Back")))
		13:
			for goal: String in ["elite", "swift"]:
				var title := _tr("Hunt an elite", "Охота на элиту") if goal == "elite" else _tr("Win a swift duel", "Быстрая победа")
				var detail := _tr("Defeat an elite within your next two victories for 40 gold. Guardians do not count.", "Победите элиту за две следующие победы и получите 40 золотых. Стражи не учитываются.") if goal == "elite" else _tr("Win by round 8 within your next two victories for 30 gold.", "За две следующие победы выиграйте не позднее 8-го раунда и получите 30 золотых.")
				if rebalanced() and goal == "elite": detail = _tr("Defeat an elite in either of your next two victories to collect 40 gold. A guardian victory uses up one chance but does not complete this bounty.", "Победите элиту в одном из двух следующих боёв, чтобы получить 40 золотых. Победа над стражем расходует одну попытку, но не выполняет заказ.")
				var offer := _price(_choice("bounty:" + goal, title, detail + " " + _tr("Unfinished contracts expire at the Last Haven.", "На Последнем привале незавершённые заказы истекают.")), BOUNTY_COST)
				if rebalanced() and act == ACTS and _remaining_opportunity_bound("wins") == 1: offer.context = _tr("At most one more victory can pay before the Last Haven.", "До Последнего привала остаётся не больше одной победы, за которую можно получить плату.")
				if not _bounty.is_empty(): _unavailable(offer, _tr("A bounty is already active.", "Заказ уже принят."))
				elif (evolved() and not _contract_reachable(goal)) or (not evolved() and _future_combat_capacity(goal == "elite") == 0): _unavailable(offer, _tr("No suitable scheduled opponent can be reached within two victories before the Last Haven.", "До Последнего привала за две победы нельзя добраться до подходящего запланированного противника.") if evolved() else _tr("No suitable scheduled opponent remains before the Last Haven.", "До Последнего привала не осталось подходящего запланированного противника."))
				result.append(offer)
		14:
			if evolved():
				result.append_array(_study_choices(false))
				result.append(_choice("archive_notes", _tr("Sell copies of your travel notes", "Продать копии путевых заметок"), _tr("Gain 12 gold and keep your current study path.", "Получить 12 золотых и сохранить текущую школу.")))
		ANVIL_EVENT:
			if refined():
				result.append_array(_craft_source_choices())
				result.append(_choice("anvil_salvage", _tr("Salvage unused binding metal", "Собрать оставшийся переплётный металл"), _tr("Gain 10 gold and keep every page.", "Получить 10 золотых и сохранить все страницы.")))
		LIBRARY_EVENT:
			if refined():
				for code: String in _library_offers():
					var offer := _choice("library_card:" + code, _tr("Pack %s for later", "Взять %s на будущее") % _card_title(code), _tr("Reserve only. Choose a free reserve slot or replace a reserved page. To use this spell, exchange it into the active book at camp or the Last Haven.", "Только в запас. Выберите свободное место или замените запасную страницу. Для использования обменяйте её со страницей боевой книги на привале или Последнем привале."), code)
					if rebalanced():
						offer.title = _tr("Take %s", "Взять: %s") % _card_title(code)
						offer.description = _tr("Add it to your book, replace a page, or keep it in reserve.", "Добавить в боевую книгу, заменить страницу или оставить в запасе.")
					elif not _can_pack_spell(code): _unavailable(offer, _tr("Both reserve slots already contain this spell. Choose a different page or the catalogue payment.", "Оба места в запасе уже заняты этим заклинанием. Выберите другую страницу или плату за каталог."))
					result.append(offer)
				result.append(_choice("library_notes", _tr("Sell the library catalogue", "Продать каталог библиотеки"), _tr("Gain 12 gold instead of packing a spell.", "Получить 12 золотых вместо запасного заклинания.")))
				if rebalanced(): result.back().description = _tr("Gain 12 gold instead of a spell.", "Получить 12 золотых вместо заклинания.")
		SCHOLAR_EVENT:
			if practiced():
				result.append(_opening_service_choice())
				result.append(_choice("scholar_notes", _tr("Copy the scholar's notes", "Переписать заметки учёного"), _tr("Gain 12 gold. Keep your current opening preparation.", "Получить 12 золотых. Подготовка стартовой руки не меняется.")))
		CONSTRUCTOR_EVENT:
			if implements_enabled(): result.append_array(_constructor_choices())
	result.append(_choice("leave", _text("Leave")))
	return result

## All callers first resolve an enabled entry in choices(). This dispatcher
## handles only v8 actions; legacy choices keep their original behavior.
func _choose_expanded(id: String, selected: Dictionary) -> bool:
	if evolved():
		if id.begins_with("study:"):
			study_path = id.trim_prefix("study:")
			if study_path == "none": _gain_gold(10)
			phase = "map"
			return true
		if id.begins_with("refocus:"):
			gold -= int(selected.cost)
			study_path = id.trim_prefix("refocus:")
			_complete_room()
			return true
		if id == "archive_notes":
			_gain_gold(12)
			_complete_room()
			return true
		if id.begins_with("elite:"):
			elite_variant = id.trim_prefix("elite:")
			phase = "battle"
			return true
		if phase == "keystone_reward":
			if id.begins_with("keystone:"):
				var chosen := id.trim_prefix("keystone:")
				keystones.append(chosen)
				if chosen == "living_heart":
					max_health += 8
					health = mini(max_health, health + 8)
			else:
				_gain_gold(20)
				health += _heal_amount(0.2)
			_keystone_claimed.append(act)
			phase = "reward"
			return true
	if balanced():
		if id == "reroll_reward":
			gold -= reward_redraw_cost()
			_reward_roll = 1
			_reroll_used_acts.append(act)
			return true
		if id.begins_with("broker_select:"):
			pending_relic = selected.relic
			return true
		if id == "back" and not pending_relic.is_empty():
			pending_relic = ""
			return true
		if id.begins_with("broker_exchange:"):
			gold -= BROKER_COST
			relics[relics.find(id.trim_prefix("broker_exchange:"))] = pending_relic
			_complete_room()
			return true
		if id.begins_with("bounty:"):
			gold -= BOUNTY_COST
			_bounty = {"kind": id.trim_prefix("bounty:"), "remaining": 2}
			_complete_room()
			return true
	if phase in ["boon", "treasure", "relic_reward"]:
		var previous := phase
		if id.begins_with("relic:"): relics.append(id.trim_prefix("relic:"))
		elif id == "skip_relic":
			_gain_gold(25 if phase == "treasure" else 20)
			if balanced(): health += _heal_amount(0.2)
		if previous == "boon": phase = "discipline" if evolved() else "map"
		elif previous == "relic_reward": phase = "reward"
		else: _complete_room()
		return true
	if shopping():
		if id.begins_with("buy_card:"):
			pending_card = selected.card
			return true
		if id == "back":
			pending_card = ""
			return true
		if id == "add" or id.begins_with("replace:"):
			gold -= int(selected.cost)
			if id == "add": deck.append(pending_card)
			else: deck[int(id.get_slice(":", 1))] = pending_card
			_shop_bought.append("card:" + pending_card)
			pending_card = ""
			return true
		if id.begins_with("buy_relic:"):
			gold -= int(selected.cost)
			relics.append(_shop_relic)
			_shop_bought.append("relic")
			return true
		if id == "shop_heal":
			gold -= int(selected.cost)
			health += _heal_amount(0.35)
			_shop_bought.append("heal")
			return true
		if id == "shop_prepare":
			gold -= int(selected.cost)
			_prepared = true
			_shop_bought.append("prepare")
			return true
		if id.begins_with("shop_remove:"):
			gold -= int(selected.cost)
			deck.remove_at(int(id.get_slice(":", 1)))
			_shop_bought.append("remove")
			_removals += 1
			return true
		if id == "leave":
			_complete_room()
			return true
		if id == "enter_guardian":
			_clear_room_state()
			phase = "battle"
			return true
	if id == "caravan_shop":
		_prepare_shop()
		phase = "shop"
		return true
	var handled := true
	match id:
		"forage": _gain_gold(18)
		"caravan_guide": _gain_gold(12)
		"courier_contract":
			gold -= COURIER_COST
			_contract_remaining = 2
		"courier_wages": _gain_gold(10)
		"forge_exchange":
			gold -= int(selected.cost)
			deck[deck.find(selected.card)] = selected.incoming
		"cartographer_help":
			var trade := _cartographer_trade()
			health -= int(trade.life)
			_gain_gold(int(trade.gold))
		"cartographer_heal":
			gold -= int(selected.cost)
			health += _heal_amount(0.4)
		"feast_meal": health += _heal_amount(0.15)
		"feast_heal":
			gold -= int(selected.cost)
			health += _heal_amount(0.6)
		"feast_prepare":
			gold -= int(selected.cost)
			_prepared = true
		_:
			if id.begins_with("forge_train:"):
				gold -= int(selected.cost)
				var code := id.trim_prefix("forge_train:")
				_training[code] = int(_training.get(code, 0)) + 1
			elif id.begins_with("vault_buy:") or id.begins_with("vault_blood:"):
				relics.append(selected.relic)
				if id.begins_with("vault_buy:"): gold -= int(selected.cost)
				else: health -= 12 if balanced() else 8
			else: handled = false
	if handled: _complete_room()
	return handled

func _complete_room() -> void:
	pending_card = ""
	_clear_room_state()
	if _nodes[current].kind != "boss":
		phase = "map"
	else:
		_previous_paths[str(act)] = visited.duplicate()
		_reset(profile, preset, seed_value, act + 1)
		health += _heal_amount(0.3)

static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func snapshot() -> Dictionary:
	var data := {"format": SAVE_FORMAT, "version": _version, "seed": seed_value, "act": act,
		"preset": str(preset.get("id", "")), "health": health, "deck": deck.duplicate(),
		"visited": visited.duplicate(), "phase": phase, "pending_card": pending_card, "life_bonus": life_bonus}
	if not borrowed_artifact.is_empty(): data.borrowed_artifact = borrowed_artifact
	if not keepsake_artifact.is_empty(): data.keepsake_artifact = keepsake_artifact
	if not _previous_paths.is_empty(): data.previous_paths = _previous_paths.duplicate(true)
	if not _training.is_empty(): data.training = _training.duplicate()
	if not _final_battle.is_empty(): data.final_battle = _final_battle.duplicate()
	if not _battle_checkpoint.is_empty(): data.battle = _battle_checkpoint.duplicate(true)
	if expanded():
		data.gold = gold
		data.relics = relics.duplicate()
		data.removals = _removals
		data.contract_remaining = _contract_remaining
		data.prepared = _prepared
		if shopping(): data.shop = {"stock": _shop_stock.duplicate(), "relic": _shop_relic, "bought": _shop_bought.duplicate()}
		if not _last_reward.is_empty(): data.last_reward = _last_reward.duplicate()
	if balanced():
		data.difficulty = difficulty
		data.reroll_used_acts = _reroll_used_acts.duplicate()
		data.reward_roll = _reward_roll
		if not pending_relic.is_empty(): data.pending_relic = pending_relic
		if not _bounty.is_empty(): data.bounty = _bounty.duplicate()
	if evolved():
		data.study_path = study_path
		data.keystones = keystones.duplicate()
		data.keystone_claimed = _keystone_claimed.duplicate()
		data.detours_used = _detours_used.duplicate()
		data.elite_variant = elite_variant
	if refined():
		data.reserve = reserve.duplicate()
		data.pending_reserve = pending_reserve
		data.pending_craft = pending_craft
		data.last_outcome = _last_outcome.duplicate(true)
	if attuned(): data.inactive_powers = inactive_powers.duplicate()
	if practiced():
		data.opening_spell = opening_spell
		data.opening_selecting = opening_selecting
		data.opening_suppressed = opening_suppressed
	if implements_enabled():
		data.field_artifact = field_artifact
		data.field_charges = field_charges
		data.artifact_project = artifact_project
	return data

func persist() -> bool:
	error = ""
	if profile == null or preset.is_empty(): return _fail("There is no expedition to save.")
	var bytes := JSON.stringify(snapshot(), "", true, true).to_utf8_buffer()
	if bytes.size() > MAX_SAVE_BYTES: return _fail("The expedition checkpoint is too large.")
	if not ELSafeFile.write_bytes(SAVE_PATH, bytes): return _fail("Could not write the expedition checkpoint.")
	return true

func restore(source: ELProfile) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null: return _fail("No expedition checkpoint is available.")
	if file.get_length() > MAX_SAVE_BYTES: return _fail("The expedition checkpoint is too large.")
	return restore_snapshot(source, JSON.parse_string(file.get_as_text()))

func restore_snapshot(source: ELProfile, raw: Variant) -> bool:
	if raw is not Dictionary or raw.get("format") != SAVE_FORMAT:
		return _fail("The expedition checkpoint has an unknown format.")
	var version: Variant = raw.get("version")
	if not ELLuaSave._integer(version, 1, SAVE_VERSION):
		return _fail("The expedition checkpoint has an unknown format.")
	if not ELLuaSave._integer(raw.get("seed"), 0, 0xffffffff) or not ELLuaSave._integer(raw.get("act"), 1, ACTS) or raw.get("preset") is not String:
		return _fail("The expedition checkpoint has invalid run settings.")
	if not ELLuaSave._integer(raw.get("life_bonus", 0), 0, MAX_LIFE_BONUS) or int(raw.get("life_bonus", 0)) % 4 != 0:
		return _fail("The expedition checkpoint has an invalid life bonus.")
	var candidate := ELExpeditionRun.new()
	var challenge: Variant = raw.get("difficulty", "standard") if int(version) >= 9 else "standard"
	if challenge is not String: return _fail("Unknown expedition difficulty.")
	if not candidate.create(source, raw.preset, int(raw.seed), int(version), challenge): return _fail(candidate.error)
	var loan: Variant = raw.get("borrowed_artifact", "")
	if loan is not String or (not loan.is_empty() and candidate._expedition_artifact(loan).is_empty()):
		return _fail("The expedition checkpoint has an invalid borrowed artifact.")
	candidate.borrowed_artifact = loan
	var keepsake: Variant = raw.get("keepsake_artifact", "")
	if keepsake is not String or (not keepsake.is_empty() and (int(version) < 6 or int(raw.act) < 2
		or candidate._expedition_artifact(keepsake).is_empty() or keepsake == loan)):
		return _fail("The expedition checkpoint has an invalid keepsake.")
	if candidate.preset.artifacts.size() + int(not loan.is_empty()) + int(not keepsake.is_empty()) > ELDuelCosts.EL2_ARTIFACTS:
		return _fail("The expedition checkpoint has too many artifacts.")
	candidate.keepsake_artifact = keepsake
	candidate.life_bonus = int(raw.get("life_bonus", 0))
	if not candidate._restore_refinement(raw):
		return _fail(_tr("The expedition checkpoint has invalid reserve or preparation data.", "В сохранении экспедиции указаны неверные запас или подготовка."))
	if not candidate._restore_evolution(raw):
		return _fail(_tr("The expedition checkpoint has invalid study, keystone, or detour data.", "В сохранении экспедиции указаны неверные школа, краеугольные камни или обходы."))
	var previous: Variant = raw.get("previous_paths", {})
	if not candidate._restore_previous_paths(previous, int(raw.act)):
		return _fail("The expedition checkpoint has an invalid journey.")
	candidate._reset(source, candidate.preset, int(raw.seed), int(raw.act))
	if not candidate._restore_expansion(raw):
		return _fail(_tr("The expedition checkpoint has invalid relics, gold, or merchant stock.", "В сохранении экспедиции указаны неверные реликвии, золото или товары торговца."))
	if not candidate._restore_balanced(raw):
		return _fail(_tr("The expedition checkpoint has invalid preparation or contract data.", "В сохранении экспедиции указаны неверные приготовления или договоры."))
	if not candidate._restore_training(raw.get("training", {})):
		return _fail("The expedition checkpoint has invalid skill training.")
	if not candidate._restore_opening_fields(raw):
		return _fail(_tr("The expedition checkpoint has invalid opening preparation.", "В сохранении экспедиции указана неверная подготовка стартовой руки."))
	if not candidate._restore_field_artifacts(raw):
		return _fail(_tr("The expedition checkpoint has invalid artifact or project data.", "В сохранении экспедиции указаны неверные артефакт или заготовка."))
	if not candidate._restore_position(raw):
		return _fail(candidate.error if not candidate.error.is_empty() else "The expedition checkpoint has an invalid room or spellbook.")
	life_bonus = candidate.life_bonus
	_version = candidate._version
	difficulty = candidate.difficulty
	study_path = candidate.study_path
	keystones.assign(candidate.keystones)
	inactive_powers.assign(candidate.inactive_powers)
	_keystone_claimed.assign(candidate._keystone_claimed)
	_detours_used.assign(candidate._detours_used)
	reserve.assign(candidate.reserve)
	opening_spell = candidate.opening_spell
	opening_suppressed = candidate.opening_suppressed
	field_artifact = candidate.field_artifact
	field_charges = candidate.field_charges
	artifact_project = candidate.artifact_project
	_reset(source, candidate.preset, candidate.seed_value, candidate.act)
	deck.assign(candidate.deck)
	visited.assign(candidate.visited)
	current = candidate.current
	phase = candidate.phase
	pending_card = candidate.pending_card
	borrowed_artifact = candidate.borrowed_artifact
	keepsake_artifact = candidate.keepsake_artifact
	health = candidate.health
	_battle_checkpoint = candidate._battle_checkpoint
	_previous_paths = candidate._previous_paths
	_training = candidate._training
	_final_battle = candidate._final_battle
	gold = candidate.gold
	relics.assign(candidate.relics)
	_shop_stock.assign(candidate._shop_stock)
	_shop_relic = candidate._shop_relic
	_shop_bought.assign(candidate._shop_bought)
	_removals = candidate._removals
	_contract_remaining = candidate._contract_remaining
	_prepared = candidate._prepared
	_last_reward = candidate._last_reward
	pending_relic = candidate.pending_relic
	_reroll_used_acts.assign(candidate._reroll_used_acts)
	_reward_roll = candidate._reward_roll
	_bounty = candidate._bounty
	elite_variant = candidate.elite_variant
	pending_reserve = candidate.pending_reserve
	pending_craft = candidate.pending_craft
	opening_selecting = candidate.opening_selecting
	_last_outcome = candidate._last_outcome.duplicate(true)
	return true

func _restore_refinement(raw: Dictionary) -> bool:
	if not refined(): return true
	var pages: Variant = raw.get("reserve")
	var slot: Variant = raw.get("pending_reserve")
	var recipe: Variant = raw.get("pending_craft")
	var outcome: Variant = raw.get("last_outcome")
	if pages is not Array or pages.size() > RESERVE_LIMIT or not ELLuaSave._integer(slot, -1, RESERVE_LIMIT - 1) or recipe is not String or outcome is not Dictionary: return false
	for code: Variant in pages:
		if code is not String or not _valid_card(profile, code, preset.faction): return false
		reserve.append(code)
	if not recipe.is_empty() and not _valid_card(profile, recipe, preset.faction): return false
	if raw.get("phase") in ["boon", "discipline"] and (not reserve.is_empty() or int(slot) != -1 or not recipe.is_empty()): return false
	if raw.get("phase") == "boon" and not outcome.is_empty(): return false
	if outcome.is_empty(): return true
	var life_limit := _life_cap(profile, preset, int(raw.act)) + MAX_LIFE_BONUS + 8
	var has_story: bool = outcome.has("story")
	if has_story and (not rebalanced() or outcome.story is not String or ELExpeditionContent.outcome(profile, outcome.story).is_empty()): return false
	if has_story and not practiced() and int(String(outcome.story).get_slice(":", 0)) == SCHOLAR_EVENT: return false
	if has_story and not implements_enabled() and (int(String(outcome.story).get_slice(":", 0)) == CONSTRUCTOR_EVENT or outcome.story == "3:recharge_artifact"): return false
	if outcome.size() != 11 + int(has_story) + (2 if practiced() else 0) + (6 if implements_enabled() else 0) or not ELLuaSave._integer(outcome.get("gold"), -MAX_GOLD, MAX_GOLD) or not ELLuaSave._integer(outcome.get("life"), -life_limit, life_limit) or not ELLuaSave._integer(outcome.get("maximum"), 0, 12): return false
	if practiced():
		for key: String in ["opening_before", "opening_after"]:
			var code: Variant = outcome.get(key)
			if code is not String or (not code.is_empty() and not _valid_card(profile, code, preset.faction)): return false
	if implements_enabled():
		for suffix: String in ["before", "after"]:
			var item: Variant = outcome.get("field_artifact_" + suffix)
			var project: Variant = outcome.get("artifact_project_" + suffix)
			var charges: Variant = outcome.get("field_charges_" + suffix)
			if not _valid_field_id(item) or not _valid_field_id(project) or not ELLuaSave._integer(charges, 0, ELExpeditionArtifacts.CAPACITY): return false
			if item.is_empty() and int(charges) != 0: return false
			if not project.is_empty() and project == item: return false
	if not ELLuaSave._integer(outcome.get("training"), 0, 1) or outcome.get("prepared") is not bool: return false
	for key: String in ["book_added", "book_removed", "reserve_added", "reserve_removed", "relics_added", "relics_removed"]:
		var list: Variant = outcome.get(key)
		if list is not Array or list.size() > (2 if key == "book_removed" else 1): return false
		for id: Variant in list:
			if id is not String: return false
			if key.begins_with("relics_"):
				if not ELExpeditionContent.RELICS.has(id): return false
			elif not _valid_card(profile, id, preset.faction): return false
	_last_outcome = outcome.duplicate(true)
	for key: String in ["gold", "life", "maximum", "training"]: _last_outcome[key] = int(_last_outcome[key])
	if implements_enabled():
		for key: String in ["field_charges_before", "field_charges_after"]: _last_outcome[key] = int(_last_outcome[key])
	return true

func _restore_evolution(raw: Dictionary) -> bool:
	if not evolved(): return true
	var study: Variant = raw.get("study_path")
	var stones: Variant = raw.get("keystones")
	var claimed: Variant = raw.get("keystone_claimed")
	var detours: Variant = raw.get("detours_used")
	if study is not String or stones is not Array or claimed is not Array or detours is not Array: return false
	if study.is_empty() != (raw.get("phase") in ["boon", "discipline"]): return false
	if not study.is_empty() and study != "none":
		var path := ELExpeditionPaths.find(profile, study)
		if path.is_empty() or path.faction != preset.faction: return false
	study_path = study
	if stones.size() > 2 or claimed.size() > 2 or stones.size() > claimed.size() or detours.size() > 2: return false
	for id: Variant in stones:
		if id is not String or id in keystones: return false
		if not ELExpeditionContent.KEYSTONES.has(id):
			if not attuned() or not ELExpeditionAttunements.is_power(id): return false
			var power := ELExpeditionAttunements.find(profile, id)
			if power.is_empty() or str(power.get("faction", "")) not in ["Colorless", str(preset.faction)]: return false
		keystones.append(id)
	if attuned():
		var inactive: Variant = raw.get("inactive_powers")
		if inactive is not Array or inactive.size() > stones.size(): return false
		for id: Variant in inactive:
			if id is not String or id not in keystones or not ELExpeditionAttunements.is_power(id) or id in inactive_powers: return false
			inactive_powers.append(id)
		inactive_powers.sort()
	for index in claimed.size():
		if not ELLuaSave._integer(claimed[index], index + 1, index + 1) or int(claimed[index]) > int(raw.act): return false
		_keystone_claimed.append(int(claimed[index]))
	for chapter: Variant in detours:
		if not ELLuaSave._integer(chapter, 2, int(raw.act)) or int(chapter) in _detours_used or not _has_keystone("wayfarer_compass"): return false
		_detours_used.append(int(chapter))
	if raw.get("phase") in ["boon", "discipline"] and (not stones.is_empty() or not claimed.is_empty() or not detours.is_empty()): return false
	return true

func _restore_expansion(raw: Dictionary) -> bool:
	if not expanded(): return true
	if not ELLuaSave._integer(raw.get("gold"), 0, MAX_GOLD): return false
	if not ELLuaSave._integer(raw.get("removals", 0), 0, ACTS * floors_per_act()): return false
	if not ELLuaSave._integer(raw.get("contract_remaining", 0), 0, 2) or raw.get("prepared", false) is not bool: return false
	var saved_relics: Variant = raw.get("relics")
	if saved_relics is not Array or saved_relics.size() > ELExpeditionContent.RELICS.size(): return false
	for id: Variant in saved_relics:
		if id is not String or not ELExpeditionContent.RELICS.has(id) or id in relics: return false
		relics.append(id)
	gold = int(raw.gold)
	_removals = int(raw.get("removals", 0))
	_contract_remaining = int(raw.get("contract_remaining", 0))
	_prepared = raw.get("prepared", false)
	var shop: Variant = raw.get("shop", {})
	if shop is not Dictionary: return false
	if raw.get("phase") not in ["shop", "haven"] and not shop.is_empty(): return false
	if raw.get("phase") in ["shop", "haven"]:
		var stock: Variant = shop.get("stock")
		var bought: Variant = shop.get("bought")
		var offered_relic: Variant = shop.get("relic")
		if stock is not Array or stock.size() > 4 or bought is not Array or bought.size() > (10 if implements_enabled() else (9 if refined() else (8 if balanced() else 7))) or offered_relic is not String: return false
		for code: Variant in stock:
			if code is not String or code in _shop_stock or not _valid_card(profile, code, preset.faction): return false
			_shop_stock.append(code)
		if not offered_relic.is_empty() and not ELExpeditionContent.RELICS.has(offered_relic): return false
		_shop_relic = offered_relic
		for purchase: Variant in bought:
			if purchase is not String or purchase in _shop_bought: return false
			var service: bool = purchase in ["relic", "heal", "remove"] or (balanced() and purchase == "prepare")
			if implements_enabled() and purchase == "field_charge": service = true
			if refined() and purchase == "reserve_swap":
				if rebalanced() or raw.get("phase") != "haven" or reserve.is_empty(): return false
				service = true
			if not service and (not purchase.begins_with("card:") or purchase.trim_prefix("card:") not in _shop_stock): return false
			_shop_bought.append(purchase)
		if ("relic" in _shop_bought) != (_shop_relic in relics): return false
		if "remove" in _shop_bought and _removals == 0: return false
		if "prepare" in _shop_bought and not _prepared: return false
	var receipt: Variant = raw.get("last_reward", {})
	if receipt is not Dictionary: return false
	if not receipt.is_empty():
		if raw.get("phase") not in ["reward", "relic_reward", "won"] and not (evolved() and raw.get("phase") == "keystone_reward"): return false
		if receipt.size() != (5 if evolved() else (4 if balanced() else 3)) or not ELLuaSave._integer(receipt.get("gold"), 0, MAX_GOLD) or not ELLuaSave._integer(receipt.get("healed"), 0, 2) or not ELLuaSave._integer(receipt.get("contract"), 0, COURIER_REWARD): return false
		if int(receipt.contract) not in [0, COURIER_REWARD]: return false
		_last_reward = {"gold": int(receipt.gold), "healed": int(receipt.healed), "contract": int(receipt.contract)}
		if balanced():
			if not ELLuaSave._integer(receipt.get("bounty"), 0, 40) or int(receipt.bounty) not in [0, 30, 40]: return false
			_last_reward.bounty = int(receipt.bounty)
		if evolved():
			if not ELLuaSave._integer(receipt.get("challenge"), 0, ELITE_VARIANT_GOLD) or int(receipt.challenge) not in [0, ELITE_VARIANT_GOLD]: return false
			_last_reward.challenge = int(receipt.challenge)
	return true

func _restore_balanced(raw: Dictionary) -> bool:
	if not balanced(): return true
	var rerolls: Variant = raw.get("reroll_used_acts", [])
	if rerolls is not Array or rerolls.size() > ACTS or not ELLuaSave._integer(raw.get("reward_roll", 0), 0, 1): return false
	for chapter: Variant in rerolls:
		if not ELLuaSave._integer(chapter, 1, act) or int(chapter) in _reroll_used_acts: return false
		_reroll_used_acts.append(int(chapter))
	_reward_roll = int(raw.get("reward_roll", 0))
	if _reward_roll > 0 and (raw.get("phase") != "reward" or act not in _reroll_used_acts): return false
	var pending: Variant = raw.get("pending_relic", "")
	if pending is not String or (not pending.is_empty() and (not ELExpeditionContent.RELICS.has(pending) or pending in relics)): return false
	pending_relic = pending
	var contract: Variant = raw.get("bounty", {})
	if contract is not Dictionary: return false
	if not contract.is_empty():
		if contract.size() != 2 or contract.get("kind") not in ["elite", "swift"] or not ELLuaSave._integer(contract.get("remaining"), 1, 2): return false
		_bounty = {"kind": contract.kind, "remaining": int(contract.remaining)}
	if raw.get("phase") == "haven" and (_contract_remaining > 0 or not _bounty.is_empty()): return false
	if raw.get("phase") == "boon" and (not _reroll_used_acts.is_empty() or not _bounty.is_empty()): return false
	return true

func _valid_field_id(id: Variant) -> bool:
	return id is String and (id.is_empty() or id in ELExpeditionArtifacts.available(profile))

func _restore_field_artifacts(raw: Dictionary) -> bool:
	if not implements_enabled(): return true
	var item: Variant = raw.get("field_artifact")
	var charges: Variant = raw.get("field_charges")
	var project: Variant = raw.get("artifact_project")
	if not _valid_field_id(item) or not _valid_field_id(project) or not ELLuaSave._integer(charges, 0, ELExpeditionArtifacts.CAPACITY): return false
	if item.is_empty() and int(charges) != 0: return false
	if not project.is_empty() and item == project: return false
	if raw.get("phase") in ["boon", "discipline"] and (not item.is_empty() or not project.is_empty()): return false
	field_artifact = item
	field_charges = int(charges)
	artifact_project = project
	if _artifact_slots() > ELDuelCosts.EL2_ARTIFACTS: return false
	if not project.is_empty() and _artifact_slots(false, false) >= ELDuelCosts.EL2_ARTIFACTS: return false
	if "field_charge" in _shop_bought and (item.is_empty() or int(charges) == 0): return false
	return true

func _restore_opening_fields(raw: Dictionary) -> bool:
	if not practiced(): return true
	var code: Variant = raw.get("opening_spell")
	var selecting: Variant = raw.get("opening_selecting")
	var suppressed: Variant = raw.get("opening_suppressed")
	if code is not String or selecting is not bool or suppressed is not bool: return false
	if code.is_empty() and suppressed: return false
	if not code.is_empty() and not _valid_card(profile, code, preset.faction): return false
	opening_spell = code
	opening_selecting = selecting
	opening_suppressed = suppressed
	return true

func _restore_training(raw: Variant) -> bool:
	if raw is not Dictionary or (act < 2 and not raw.is_empty()): return false
	var starting := _starting_skills()
	var sessions := 0
	for code: Variant in raw:
		if code not in TRAINABLE_SKILLS: return false
		if not ELLuaSave._integer(raw[code], 1, _training_limit()): return false
		var count := int(raw[code])
		if ELHeroSkills.definition(profile, code, int(starting.get(code, -1)) + count).is_empty(): return false
		sessions += count
		_training[code] = count
	return sessions <= _training_limit()

func _restore_previous_paths(previous: Variant, current_act: int) -> bool:
	if previous is not Dictionary or previous.size() >= current_act: return false
	if evolved() and previous.size() != current_act - 1: return false
	for chapter: Variant in previous:
		if chapter is not String or chapter not in ["1", "2"] or int(chapter) >= current_act: return false
		var path: Variant = previous[chapter]
		if path is not Array or path.size() != floors_per_act(): return false
		_reset(profile, preset, seed_value, int(chapter))
		var detours := 0
		for id: Variant in path:
			if id is not String: return false
			var step := _restore_path_step(id, detours == 0 and act in _detours_used)
			if step < 0: return false
			detours += step
			current = id
		if evolved() and (detours == 1) != (act in _detours_used): return false
		_previous_paths[chapter] = path.duplicate()
	return true

func _restore_path_step(id: String, allow_detour: bool) -> int:
	if not _nodes.has(id): return -1
	if current.is_empty(): return 0 if id in _route[0].map(func(room: Dictionary) -> String: return str(room.id)) else -1
	if id in _nodes[current].next: return 0
	if evolved() and act >= 2 and _has_keystone("wayfarer_compass") and allow_detour and id in _next_floor_ids(): return 1
	return -1

func _restore_position(raw: Dictionary) -> bool:
	var cards: Variant = raw.get("deck")
	var path: Variant = raw.get("visited")
	var saved_phase: Variant = raw.get("phase")
	var pending: Variant = raw.get("pending_card", "")
	if not borrowed_artifact.is_empty() and saved_phase in ["reward", "won", "lost"]: return false
	if cards is not Array or cards.size() < MIN_DECK or cards.size() > MAX_DECK or path is not Array or path.size() > floors_per_act() or pending is not String:
		return false
	var counts := {}
	for card: Variant in cards:
		if card is not String or not _valid_card(profile, card, preset.faction): return false
		counts[card] = int(counts.get(card, 0)) + 1
		if int(counts[card]) > ELDuelCosts.EL2_COPIES: return false
	if refined():
		for card: String in reserve:
			counts[card] = int(counts.get(card, 0)) + 1
			if int(counts[card]) > ELDuelCosts.EL2_COPIES: return false
	deck.assign(cards)
	if practiced():
		if not opening_spell.is_empty() and owned_copies(opening_spell) == 0: return false
		if saved_phase in ["boon", "discipline"] and (not opening_spell.is_empty() or opening_selecting): return false
	var detours := 0
	for id: Variant in path:
		if id is not String: return false
		var step := _restore_path_step(id, detours == 0 and act in _detours_used)
		if step < 0: return false
		detours += step
		current = id
		visited.append(id)
	if evolved() and (detours == 1) != (act in _detours_used): return false
	var kind := str(_nodes.get(current, {}).get("kind", ""))
	match saved_phase:
		"boon":
			if not expanded() or act != 1 or not current.is_empty() or not relics.is_empty() or gold != STARTING_GOLD or cards != preset.cards or life_bonus != 0 or _removals != 0 or _contract_remaining != 0 or _prepared: return false
		"discipline":
			if not evolved() or act != 1 or not current.is_empty() or relics.size() != 1 or relics[0] not in ELExpeditionContent.STARTING_RELICS or gold != STARTING_GOLD or cards != preset.cards or life_bonus != 0 or _removals != 0 or _contract_remaining != 0 or _prepared or not _reroll_used_acts.is_empty() or not _bounty.is_empty(): return false
		"map":
			if kind == "boss": return false
		"event", "rest":
			if kind != saved_phase: return false
		"shop":
			if not expanded() or (kind != "shop" and not (kind == "event" and _event_index() == 5)): return false
		"haven":
			if not balanced() or kind != "boss" or act != ACTS: return false
		"treasure":
			if not expanded() or kind != "treasure": return false
		"relic_reward":
			if not expanded() or _combat_kind(_nodes.get(current, {})) not in ["elite", "boss"] or (kind == "boss" and act == ACTS): return false
			if evolved() and kind == "boss": return false
		"keystone_reward":
			if not evolved() or kind != "boss" or act == ACTS: return false
		"elite_gate":
			if not evolved() or kind != "elite" or _base_opponent_at(current).is_empty() or _base_opponent_at(current).has("scripts"): return false
		"battle", "reward", "lost":
			if _combat_kind(_nodes.get(current, {})) not in COMBAT_ROOMS: return false
		"won":
			if kind != "boss" or act != ACTS: return false
		_: return false
	if not ELLuaSave._integer(raw.get("health"), 0 if saved_phase == "lost" else 1, 0 if saved_phase == "lost" else max_health): return false
	if refined(): health = int(raw.health)
	if saved_phase in ["boon", "discipline"] and int(raw.health) != max_health: return false
	if evolved():
		var expected_claims := act - 1 + int(kind == "boss" and act < ACTS and saved_phase == "reward")
		if _keystone_claimed.size() != expected_claims: return false
		var variant: Variant = raw.get("elite_variant", "")
		if variant is not String or (not variant.is_empty() and variant not in ELITE_VARIANTS): return false
		var needs_variant: bool = kind == "elite" and saved_phase in ["battle", "reward", "relic_reward", "lost"] and not _base_opponent_at(current).has("scripts")
		if needs_variant:
			if variant.is_empty() or elite_preview(current, variant).is_empty(): return false
		elif not variant.is_empty(): return false
		elite_variant = variant
		if not _last_reward.is_empty() and int(_last_reward.challenge) != (ELITE_VARIANT_GOLD if elite_variant in ["overcharged", "fortified"] else 0): return false
	if refined(): phase = saved_phase
	if not pending.is_empty():
		match saved_phase:
			"reward": if pending not in _offered_cards(): return false
			"rest": if pending != _study_spell(): return false
			"shop", "haven":
				if pending not in _shop_stock or "card:" + pending in _shop_bought or owned_copies(pending) >= ELDuelCosts.EL2_COPIES or gold < _shop_card_price(pending): return false
			"event":
				if not refined() or _event_index() != LIBRARY_EVENT or pending not in _library_offers() or (not rebalanced() and not _can_pack_spell(pending)): return false
			_: return false
	phase = saved_phase
	if not pending_relic.is_empty():
		if not balanced() or phase != "event" or _event_index() != 12 or pending_relic not in _relic_offers(2, 0x2be638) or gold < BROKER_COST: return false
	pending_card = pending
	if refined():
		var slot := int(raw.pending_reserve)
		var recipe := str(raw.pending_craft)
		var stages := int(not pending.is_empty()) + int(not recipe.is_empty()) + int(slot >= 0) + int(not pending_relic.is_empty()) + int(practiced() and opening_selecting)
		if stages > 1: return false
		if practiced() and opening_selecting:
			if not _opening_service_available() or (phase == "haven" and gold < _merchant_price(OPENING_COST)): return false
		if slot >= 0:
			if phase not in ["rest", "haven"] or slot >= reserve.size(): return false
			var allowed := false
			for option: Dictionary in _reserve_select_choices():
				if int(option.reserve_index) == slot and not bool(option.get("disabled", false)): allowed = true
			if not allowed: return false
			pending_reserve = slot
		if not recipe.is_empty():
			if phase != "event" or _event_index() not in [1, 7, ANVIL_EVENT]: return false
			var allowed := false
			for option: Dictionary in _craft_source_choices():
				if option.card == recipe and not bool(option.get("disabled", false)): allowed = true
			if not allowed: return false
			pending_craft = recipe
	health = int(raw.health)
	# Version-one runs could stop on a reward after defeating the last guardian.
	if phase == "reward" and kind == "boss" and act == ACTS:
		phase = "won"
		pending_card = ""
	var result: Variant = raw.get("final_battle", {})
	if result is not Dictionary: return false
	if not result.is_empty():
		if not finished() or not ELLuaSave._integer(result.get("round"), 1, 0x7fffffff) or not ELLuaSave._integer(result.get("opponent_life"), 0, 0x7fffffff): return false
		_final_battle = {"round": int(result.round), "opponent_life": int(result.opponent_life)}
	if raw.has("battle"):
		if phase != "battle" or raw.battle is not Dictionary or raw.battle.is_empty(): return false
		var restored := _restore_battle(raw.battle)
		if restored == null: return false
		_battle_checkpoint = restored.snapshot()
	return true

func _fail(reason: String) -> bool:
	error = reason
	return false
