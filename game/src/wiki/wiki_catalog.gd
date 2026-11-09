class_name ELWikiCatalog
extends RefCounted
## Encyclopedia pages built from the loaded games (as the EI remake's
## WikiCatalog): one page for every creature, sorcery, enchantment, artifact,
## skill and specialisation, and one list page per kind. Both games share one
## pool: a card both games have (the same code) gets one page showing both
## editions side by side, with the values Etherlords II changed highlighted; a
## card only one game has says so. Names, descriptions and statistics come from
## the installed games' own tables and texts, so the in-game wiki follows the
## player's copies and their language; the page labels follow the wiki
## language. tools/export_wiki.gd runs the same builder for the hosted wiki.
##
## Pages: {key, title, category, summary, html, search, games, card, kind,
## models}. Card pages carry `<figure data-card="CODE" data-kind="creature|card"
## data-games="el1 el2">`: the in-game reader shows the live model (or icon) of
## those editions beside the article, the website the exported pictures.
## Highlighted cells are `<td class="changed">`.

const EDITIONS := ["el1", "el2"]
const KINDS := ["creatures", "spells", "artifacts", "skills", "specializations"]
## The list page of each kind; it is also the kind's category id.
const LISTS := {"creatures": "all-creatures", "spells": "all-spells", "artifacts": "all-artifacts",
	"skills": "all-skills", "specializations": "all-specializations"}
const COLORS := ["Red", "Green", "Blue", "Black", "White"]
const RACE_KEYS := {"Red": "T_VL_CHAOTS", "Green": "T_VL_VITALS", "Blue": "T_VL_KINETS", "Black": "T_VL_SYNTHETS", "White": "T_RACE_NAME_0"}
## EL1 resource columns in the order of T_RESOURCE_NAME_1..7; EL2 uses three.
const RESOURCES := {"el1": ["Root", "Lotus", "Ruby", "Emerald", "Sapphire", "Diamond", "Stone"], "el2": ["Root", "Ruby", "Stone"]}
## The first game's text table keeps resource names in the genitive; the
## Russian page labels use these nominatives of the same names.
const RU_RESOURCES := {"Root": "Корни Мандрагоры", "Lotus": "Чёрный Лотос", "Ruby": "Кровавые Рубины", "Emerald": "Ядовитые Изумруды",
	"Sapphire": "Звёздные Сапфиры", "Diamond": "Дымчатые Алмазы", "Stone": "Замёрзшее Пламя"}
## Creature flags and the in-game captions of their icons.
const FLAG_KEYS := {"NoAttack": "T_CREATURE_ICON_03C", "Fly": "T_CREATURE_ICON_04C", "FS": "T_CREATURE_ICON_05C",
	"Trample": "T_CREATURE_ICON_06C", "Restless": "T_CREATURE_ICON_07C", "Lifetap": "T_CREATURE_ICON_08C",
	"Regen": "T_CREATURE_ICON_09C", "Discard": "T_CREATURE_ICON_10C", "Disenchant": "T_CREATURE_ICON_11C",
	"Destroy": "T_CREATURE_ICON_12C", "NoUntap": "T_CREATURE_ICON_13C", "UB": "T_CREATURE_ICON_14C",
	"NSS": "T_CREATURE_ICON_15C", "Berserk": "T_CREATURE_ICON_16C", "TeamAttack": "T_CREATURE_ICON_17C",
	"Elusive": "T_CREATURE_ICON_18C", "Outerplanar": "T_CREATURE_ICON_19C", "NoTarget": "ETAMNm"}
const LABELS := {
	"en": {"el1": "Etherlords", "el2": "Etherlords II", "el1_short": "I", "el2_short": "II",
		"creatures": "creatures", "spells": "spells", "artifacts": "artifacts", "skills": "skills", "specializations": "specializations",
		"creatures_title": "All creatures", "spells_title": "All sorceries and enchantments", "artifacts_title": "All artifacts",
		"skills_title": "All hero skills", "specializations_title": "All specializations",
		"games": "Games", "type": "Type", "race": "Race", "rarity": "Rarity", "cost": "Ether cost", "power": "Power", "toughness": "Toughness",
		"abilities": "Abilities", "artifact": "Artifact", "yes": "yes", "name": "Name", "price": "Price", "description": "Description",
		"resource": "Resource", "shop": "Price in shops and the duel editor", "rune": "Price of a rune", "ability": "Ability",
		"Cantrip": "Cantrip", "Common": "Common", "Rare": "Rare", "Unique": "Unique", "NoAffect": "Unaffected",
		"level": "Rank", "effect": "Effect", "duel_price": "Duel editor price", "chance": "Chance", "colors": "Races",
		"Ulow": "very low", "Low": "low", "Med": "medium", "High": "high", "other": "Other",
		"both": "In Etherlords and Etherlords II", "only": "Only in %s",
		"changes": "Changes in Etherlords II", "changed_from": "%s: %s → %s", "old_text": "%s in Etherlords:",
		"same": "Etherlords II keeps this card unchanged.",
		"count": "%d entries. Select a name for its page.", "back": "All %s",
		"legend": "Games: I is Etherlords, II is Etherlords II. A highlighted value changed in Etherlords II (Etherlords → Etherlords II).",
		"intro_creatures": "Every creature of both games with its race, ether cost, power, toughness and abilities, by race.",
		"intro_spells": "Every sorcery and enchantment of both games with its type, rarity and ether cost, by race.",
		"intro_artifacts": "Every artifact of both games. Artifacts are used during battle a limited number of times; some of them summon a creature.",
		"intro_skills": "Hero skills of both games. A hero learns at most five, each up to rank 3.",
		"intro_specializations": "Hero specializations of both games: chance-based talents in battle.",
		"source": "Names, descriptions and values come from the games' own data."},
	"ru": {"el1": "Демиурги", "el2": "Демиурги II", "el1_short": "I", "el2_short": "II",
		"creatures": "создания", "spells": "заклинания", "artifacts": "артефакты", "skills": "навыки", "specializations": "специализации",
		"creatures_title": "Все создания", "spells_title": "Всё колдовство и чары", "artifacts_title": "Все артефакты",
		"skills_title": "Все навыки героев", "specializations_title": "Все специализации",
		"games": "Игры", "type": "Вид", "race": "Раса", "rarity": "Редкость", "cost": "Стоимость в эфире", "power": "Сила", "toughness": "Стойкость",
		"abilities": "Способности", "artifact": "Артефакт", "yes": "да", "name": "Название", "price": "Цена", "description": "Описание",
		"resource": "Ресурс", "shop": "Цена в лавках и редакторе дуэли", "rune": "Цена руны", "ability": "Способность",
		"Cantrip": "Примитив", "Common": "Обычное", "Rare": "Редкое", "Unique": "Тайное", "NoAffect": "Невосприимчивость",
		"level": "Ступень", "effect": "Действие", "duel_price": "Цена в редакторе дуэли", "chance": "Шанс", "colors": "Расы",
		"Ulow": "очень низкий", "Low": "низкий", "Med": "средний", "High": "высокий", "other": "Прочие",
		"both": "Есть в «Демиургах» и «Демиургах II»", "only": "Только в игре «%s»",
		"changes": "Изменения в «Демиургах II»", "changed_from": "%s: %s → %s", "old_text": "%s в «Демиургах»:",
		"same": "В «Демиургах II» эта карта не изменилась.",
		"count": "Записей: %d. Выберите название, чтобы открыть страницу.", "back": "Все %s",
		"legend": "Игры: I — «Демиурги», II — «Демиурги II». Выделенное значение изменилось в «Демиургах II» («Демиурги» → «Демиурги II»).",
		"intro_creatures": "Все создания обеих игр по расам: стоимость в эфире, сила, стойкость и способности.",
		"intro_spells": "Всё колдовство и все чары обеих игр по расам: вид, редкость и стоимость в эфире.",
		"intro_artifacts": "Все артефакты обеих игр. Артефакты применяются в бою ограниченное число раз; некоторые призывают создание.",
		"intro_skills": "Навыки героев обеих игр. Герой знает не больше пяти навыков, каждый до 3-й ступени.",
		"intro_specializations": "Специализации героев обеих игр — случайные таланты в бою.",
		"source": "Названия, описания и значения взяты из данных самих игр."},
}

## The loaded games: {edition: ELProfile}.
var sources: Dictionary = {}
var language := "en"
var pages: Array[Dictionary] = []
## When not empty, only these card, skill and specialisation pages are built
## (the exporter keeps two language editions to the same set of pages).
var allowed: Dictionary = {}

## All pages of the games in `from` ({edition: ELProfile}, one or both) with
## labels in `lang` ("en" or "ru").
static func build(from: Dictionary, lang: String, only: Dictionary = {}) -> ELWikiCatalog:
	var catalog := ELWikiCatalog.new()
	for edition: String in EDITIONS:
		var profile: ELProfile = from.get(edition)
		if profile != null and not profile.archives.is_empty(): catalog.sources[edition] = profile
	catalog.language = lang if LABELS.has(lang) else "en"
	catalog.allowed = only
	if not catalog.sources.is_empty(): catalog._build()
	return catalog

static func card_key(code: String) -> String:
	return "card-" + _slug(code)

static func _slug(value: String) -> String:
	var out := ""
	for c: String in value.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "-"
	while "--" in out: out = out.replace("--", "-")
	return out.strip_edges().trim_prefix("-").trim_suffix("-")

func _l(key: String) -> String:
	return str(LABELS[language].get(key, LABELS.en.get(key, key)))

func _t(edition: String, key: String) -> String:
	var value: String = sources[edition].text(key)
	return "" if value == key else value

static func _e(value: String) -> String:
	return value.xml_escape(true)

static func _clean(value: String) -> String:
	var out := value.replace("\r", "").strip_edges()
	while "  " in out: out = out.replace("  ", " ")
	return out

## Paragraphs of a game text (its line breaks start new paragraphs).
static func _paragraphs(value: String) -> String:
	var out := ""
	for line: String in value.replace("\r", "").split("\n", false):
		var clean := _clean(line)
		if not clean.is_empty(): out += "<p>%s</p>" % _e(clean)
	return out

func _race(edition: String, color: String) -> String:
	var value := _t(edition, RACE_KEYS.get(color, ""))
	return value if not value.is_empty() else (color if not color.is_empty() else _l("other"))

func _type(edition: String, row: Dictionary) -> String:
	var key: String = {"Creature": "T_SPELL_TYPE", "Sorcery": "T_SPELL_TYPE2", "Enchantment": "T_SPELL_TYPE3"}.get(str(row.get("Class", "")), "")
	# The first game's Russian table spells "Создание" with a Latin C.
	return _t(edition, key).replace("Cоздание", "Создание") if not key.is_empty() else str(row.get("Class", ""))

func _resource(edition: String, column: String) -> String:
	if language == "ru" and edition == "el1": return RU_RESOURCES.get(column, column)
	var index: int = RESOURCES[edition].find(column)
	var value := _t(edition, "T_RESOURCE_NAME_%d" % (index + 1)) if index >= 0 else ""
	if not value.is_empty(): return value
	return RU_RESOURCES.get(column, column) if language == "ru" else str(ELResources.LABELS.get(column, column))

func _flag(edition: String, flag: String) -> String:
	var base := flag.get_slice("(", 0)
	var amount := flag.get_slice("(", 1).trim_suffix(")") if "(" in flag else ""
	var value := _t(edition, FLAG_KEYS.get(base, "")) if FLAG_KEYS.has(base) else ""
	if value.is_empty(): value = _l(base) if LABELS.en.has(base) else base
	# English icon captions read "Flying ability."; the page lists the names.
	value = value.trim_suffix(".").trim_suffix(" ability")
	return value + (" (%s)" % amount if not amount.is_empty() else "")

static func _flags(row: Dictionary) -> Array:
	var value: Variant = row.get("Flags", [])
	if value is String: return [] if str(value).is_empty() else [value]
	return value if value is Array else []

func _row(cells: Array, header := false) -> String:
	var tag := "th" if header else "td"
	var out := "<tr>"
	for cell: Variant in cells:
		# A cell given as [text, true] is highlighted as changed.
		if cell is Array: out += "<td class=\"changed\">%s</td>" % cell[0] if cell[1] else "<%s>%s</%s>" % [tag, cell[0], tag]
		else: out += "<%s>%s</%s>" % [tag, cell, tag]
	return out + "</tr>"

func _table(rows: Array, columns: int) -> String:
	return "<table data-columns=\"%d\">%s</table>" % [columns, "".join(rows)]

func _link(key: String, label: String) -> String:
	return "<a href=\"wiki://%s\">%s</a>" % [key, _e(label)]

func _prices(edition: String, row: Dictionary, prefix: String) -> Array:
	var rows: Array = []
	for column: String in RESOURCES[edition]:
		var amount := int(row.get(prefix + column, 0))
		if amount > 0: rows.append([_e(_resource(edition, column)), str(amount)])
	return rows

func _price_text(edition: String, row: Dictionary, prefix: String) -> String:
	var parts: Array = []
	for price: Array in _prices(edition, row, prefix): parts.append("%s %s" % [price[1], price[0]])
	return ", ".join(parts)

## The editions of `records` ({edition: record}) in order.
static func _games(records: Dictionary) -> Array:
	var out: Array = []
	for edition: String in EDITIONS:
		if records.has(edition): out.append(edition)
	return out

func _games_line(games: Array) -> String:
	var text := _l("both") if games.size() > 1 else _l("only") % _l(games[0])
	return "<p class=\"games\">%s</p>" % _e(text)

func _games_short(games: Array) -> String:
	var parts: Array = []
	for edition: String in games: parts.append(_l(edition + "_short"))
	return ", ".join(parts)

## One comparison table of facts: `facts` is {edition: [[label, value], ...]}
## (values already escaped). With two editions each row shows both, and a
## value Etherlords II changed is highlighted; changes are appended to
## `changes` as list items.
func _compare(games: Array, facts: Dictionary, changes: Array) -> String:
	var labels: Array = []
	var values := {}
	for edition: String in games:
		values[edition] = {}
		for fact: Array in facts[edition]:
			if not fact[0] in labels: labels.append(fact[0])
			values[edition][fact[0]] = fact[1]
	var rows: Array = []
	if games.size() == 1:
		for label: String in labels: rows.append(_row([_e(label), values[games[0]][label]]))
		return _table(rows, 2)
	rows.append(_row(["", _e(_l("el1")), _e(_l("el2"))], true))
	for label: String in labels:
		var old: String = values.el1.get(label, "—")
		var now: String = values.el2.get(label, "—")
		var changed := old != now
		if changed: changes.append("<li>%s</li>" % (_l("changed_from") % [_e(label), old, now]))
		rows.append(_row([_e(label), [old, changed], [now, changed]]))
	return _table(rows, 3)

# --- Records --------------------------------------------------------------------

func _build() -> void:
	var cards := {}
	for edition: String in sources:
		var profile: ELProfile = sources[edition]
		var spells := profile.table("CombatSpells")
		var creatures := profile.table("CombatCreatures")
		for code: String in spells:
			var row: Dictionary = spells[code]
			var title := _t(edition, str(row.get("Name", "")))
			# Unused records, and internal helpers whose name is only their code.
			if str(row.get("Use", "+")) != "+" or title.is_empty() or title == code: continue
			if not allowed.is_empty() and not allowed.has(card_key(code)): continue
			var artifact := str(row.get("IsArtifact", "False")) == "True"
			# Artifact creatures (Maggot, Konung, ...) are creatures too: their
			# pages show the model.
			var creature: Dictionary = creatures.get(code, {}) if str(row.get("Class", "")) == "Creature" else {}
			if not cards.has(code): cards[code] = {}
			cards[code][edition] = {"row": row, "creature": creature, "title": title,
				"description": _clean(_t(edition, str(row.get("ToolTip", "")))),
				"ability": _clean(_t(edition, str(row.get("AbilityText", "")))),
				"kind": "artifacts" if artifact else ("creatures" if not creature.is_empty() else "spells")}
	var lists := {}
	for kind: String in KINDS: lists[kind] = []
	for code: String in cards:
		var page := _card_page(code, cards[code])
		pages.append(page)
		lists[page.list].append({"page": page, "records": cards[code]})
	_skills(lists)
	_specializations(lists)
	for kind: String in KINDS:
		var entries: Array = lists[kind]
		entries.sort_custom(func(a, b): return str(a.page.title).naturalnocasecmp_to(str(b.page.title)) < 0)
		pages.append(_list_page(kind, entries))
	for page: Dictionary in pages: page.erase("list")

## Whether two editions draw a creature differently (another model or skin;
## the first game has no sizes).
static func _same_model(a: Dictionary, b: Dictionary) -> bool:
	for field: String in ["Model", "Texture"]:
		if str(a.get(field, "")) != str(b.get(field, "")): return false
	return true

func _card_facts(edition: String, record: Dictionary) -> Array:
	var row: Dictionary = record.row
	var facts: Array = [[_l("type"), _e(_type(edition, row))], [_l("race"), _e(_race(edition, str(row.get("Color", ""))))],
		[_l("rarity"), _e(_l(str(row.get("Rarity", ""))))], [_l("cost"), str(row.get("Cost", 0))]]
	if record.kind == "artifacts": facts.append([_l("artifact"), _l("yes")])
	var creature: Dictionary = record.creature
	if not creature.is_empty():
		facts.append([_l("power"), str(creature.get("Power", 0))])
		facts.append([_l("toughness"), str(creature.get("Toughness", 0))])
		var abilities: Array = []
		for flag: String in _flags(creature): abilities.append(_flag(edition, flag))
		facts.append([_l("abilities"), _e(", ".join(abilities)) if not abilities.is_empty() else "—"])
	return facts

func _card_page(code: String, records: Dictionary) -> Dictionary:
	var games := _games(records)
	var latest: String = games.back()
	var main: Dictionary = records[latest]
	var kind: String = main.kind
	var creature: bool = not main.creature.is_empty()
	# Pictures: the newest edition's, and the first game's too when it draws
	# the creature differently.
	var shown: Array = [latest]
	if creature and games.size() > 1 and not records.el1.creature.is_empty() and not _same_model(records.el1.creature, main.creature):
		shown = games
	var html := "<h1>%s</h1>" % _e(main.title)
	html += "<figure data-card=\"%s\" data-kind=\"%s\" data-games=\"%s\"></figure>" % [code, "creature" if creature else "card", " ".join(shown)]
	html += _games_line(games)
	html += _paragraphs(main.description)
	var changes: Array = []
	var facts := {}
	# Both editions in the newest one's words: only real changes differ.
	for edition: String in games: facts[edition] = _card_facts(latest, records[edition])
	html += _compare(games, facts, changes)
	if games.size() > 1:
		if records.el1.description != main.description and not records.el1.description.is_empty():
			changes.append("<li>%s%s</li>" % [_e(_l("old_text") % _l("description")), _paragraphs(records.el1.description)])
		if records.el1.ability != main.ability and not records.el1.ability.is_empty() and not records.el1.ability in records.el1.description:
			changes.append("<li>%s%s</li>" % [_e(_l("old_text") % _l("ability")), _paragraphs(records.el1.ability)])
	if not main.ability.is_empty() and not main.ability in main.description:
		html += "<h2>%s</h2>%s" % [_l("ability"), _paragraphs(main.ability)]
	if games.size() > 1:
		html += "<h2>%s</h2>" % _l("changes")
		html += "<ul>%s</ul>" % "".join(changes) if not changes.is_empty() else "<p>%s</p>" % _e(_l("same"))
	var price_html := ""
	for edition: String in games:
		var row: Dictionary = records[edition].row
		var shop := _prices(edition, row, "Cost")
		var runes := _prices(edition, row, "Charge") if edition == "el1" else []
		if shop.is_empty() and runes.is_empty(): continue
		if games.size() > 1: price_html += "<h3>%s</h3>" % _e(_l(edition))
		for part: Array in [[shop, "shop"], [runes, "rune"]]:
			if part[0].is_empty(): continue
			var rows: Array = [_row([_l("resource"), _l(part[1])], true)]
			for price: Array in part[0]: rows.append(_row(price))
			price_html += _table(rows, 2)
	if not price_html.is_empty(): html += "<h2>%s</h2>%s" % [_l("price"), price_html]
	html += "<p>%s</p>" % _link(LISTS[kind], _l("back") % _l(kind))
	var summary := " · ".join([_type(latest, main.row), _race(latest, str(main.row.get("Color", ""))), str(main.row.get("Cost", 0))])
	if creature: summary += " · %s/%s" % [main.creature.get("Power", 0), main.creature.get("Toughness", 0)]
	summary += " · " + _games_short(games)
	var words := ""
	for edition: String in games:
		var record: Dictionary = records[edition]
		words += " %s %s %s" % [record.title, record.description, record.ability]
		for flag: String in _flags(record.creature): words += " " + _flag(edition, flag)
	return {"key": card_key(code), "title": main.title, "category": LISTS[kind], "summary": summary, "html": html,
		"search": words.strip_edges().to_lower(), "games": games, "card": code, "models": shown,
		"kind": "creature" if creature else "card", "list": kind}

func _skills(lists: Dictionary) -> void:
	var skills := {}
	for edition: String in sources:
		for value: Variant in sources[edition].table("HeroesSkills").values():
			var row: Dictionary = value
			var code := str(row.get("Code", ""))
			if str(row.get("InUse", "True")) == "False" or code.is_empty(): continue
			if not skills.has(code): skills[code] = {}
			if not skills[code].has(edition): skills[code][edition] = []
			skills[code][edition].append(row)
	for code: String in skills:
		var key := "skill-" + _slug(code)
		if not allowed.is_empty() and not allowed.has(key): continue
		var records: Dictionary = skills[code]
		for edition: String in records:
			records[edition].sort_custom(func(a, b): return int(a.get("Level", 0)) < int(b.get("Level", 0)))
		var games := _games(records)
		var latest: String = games.back()
		var title := _t(latest, str(records[latest][0].get("Name", "")))
		if title.is_empty(): continue
		var html := "<h1>%s</h1>%s" % [_e(title), _games_line(games)]
		var words := title
		var effects := {}
		for edition: String in games:
			effects[edition] = {}
			for row: Dictionary in records[edition]: effects[edition][str(row.get("Level", ""))] = _clean(_t(edition, str(row.get("Description", ""))))
		var changed := 0
		for edition: String in games:
			if games.size() > 1: html += "<h2>%s</h2>" % _e(_l(edition))
			var rows: Array = [_row([_l("level"), _l("effect"), _l("duel_price")], true)]
			for row: Dictionary in records[edition]:
				var level := str(row.get("Level", ""))
				var effect: String = effects[edition][level]
				words += " " + effect
				var differs: bool = edition == "el2" and games.size() > 1 and effects.el1.get(level, "") != effect
				if differs: changed += 1
				var price := _price_text(edition, row, "DuelCost") if str(row.get("Duel", "True")) == "True" else "—"
				rows.append(_row([level, [_e(effect), differs], _e(price)]))
			html += _table(rows, 3)
		if games.size() > 1 and changed == 0: html += "<p>%s</p>" % _e(_l("same"))
		html += "<p>%s</p>" % _link(LISTS.skills, _l("back") % _l("skills"))
		var page := {"key": key, "title": title, "category": LISTS.skills, "summary": _games_short(games), "html": html,
			"search": words.to_lower(), "games": games, "card": "", "models": [], "kind": "skill"}
		pages.append(page)
		lists.skills.append({"page": page, "records": records})

func _specializations(lists: Dictionary) -> void:
	var specs := {}
	for edition: String in sources:
		var table: Dictionary = sources[edition].table("HeroesSpecs")
		for code: String in table:
			var row: Dictionary = table[code]
			var name_key := str(row.get("Name", ""))
			# A duplicate record named after another specialisation (the first
			# game's second "Dragon Skin") is left to that one.
			var named_after := name_key.right(code.length())
			if named_after != code and table.has(named_after): continue
			var title := _t(edition, name_key)
			if title.is_empty() or title == code: continue
			if not specs.has(code): specs[code] = {}
			specs[code][edition] = {"row": row, "title": title, "effect": _clean(_t(edition, str(row.get("Desc", ""))))}
	for code: String in specs:
		var key := "spec-" + _slug(code)
		if not allowed.is_empty() and not allowed.has(key): continue
		var records: Dictionary = specs[code]
		var games := _games(records)
		var latest: String = games.back()
		var main: Dictionary = records[latest]
		var facts := {}
		var races := {}
		for edition: String in games:
			var row: Dictionary = records[edition].row
			var colors: Variant = row.get("MagicColor", [])
			var names: Array = []
			for color: Variant in (colors if colors is Array else [colors]): names.append(_race(latest, str(color)))
			races[edition] = ", ".join(names)
			facts[edition] = [[_l("chance"), _e(_l(str(row.get("Chance", ""))))], [_l("colors"), _e(races[edition])]]
			var price := _price_text(edition, row, "DuelCost")
			if not price.is_empty(): facts[edition].append([_l("duel_price"), _e(price)])
		var changes: Array = []
		var html := "<h1>%s</h1>%s%s" % [_e(main.title), _games_line(games), _paragraphs(main.effect)]
		html += _compare(games, facts, changes)
		if games.size() > 1:
			if records.el1.effect != main.effect and not records.el1.effect.is_empty():
				changes.append("<li>%s%s</li>" % [_e(_l("old_text") % _l("description")), _paragraphs(records.el1.effect)])
			html += "<h2>%s</h2>" % _l("changes")
			html += "<ul>%s</ul>" % "".join(changes) if not changes.is_empty() else "<p>%s</p>" % _e(_l("same"))
		html += "<p>%s</p>" % _link(LISTS.specializations, _l("back") % _l("specializations"))
		var page := {"key": key, "title": main.title, "category": LISTS.specializations, "summary": "%s · %s" % [races[latest], _games_short(games)],
			"html": html, "search": (main.title + " " + main.effect).to_lower(), "games": games, "card": "", "models": [], "kind": "specialization"}
		pages.append(page)
		lists.specializations.append({"page": page, "records": records})

# --- Lists ----------------------------------------------------------------------

## A list cell: the value of both editions ("old → new", highlighted when
## Etherlords II changed it) or of the one that has the entry.
func _cell(records: Dictionary, value: Callable) -> Variant:
	var games := _games(records)
	# Both editions are named in the newest one's words, so a value differs
	# only when the game changed it (not its wording).
	var latest: String = games.back()
	if games.size() == 1: return _e(str(value.call(latest, records[latest])))
	var old := str(value.call(latest, records.el1))
	var now := str(value.call(latest, records.el2))
	if old == now: return _e(now)
	return [_e("%s → %s" % [old if not old.is_empty() else "—", now if not now.is_empty() else "—"]), true]

func _abilities(edition: String, record: Dictionary) -> String:
	var names: Array = []
	for flag: String in _flags(record.creature): names.append(_flag(edition, flag))
	return ", ".join(names)

func _colors(edition: String, record: Dictionary) -> String:
	var colors: Variant = record.row.get("MagicColor", [])
	var names: Array = []
	for color: Variant in (colors if colors is Array else [colors]): names.append(_race(edition, str(color)))
	return ", ".join(names)

func _list_page(kind: String, entries: Array) -> Dictionary:
	var key: String = LISTS[kind]
	var title := _l(kind + "_title")
	var html := "<h1>%s</h1><p>%s</p><p>%s</p>" % [_e(title), _e(_l("intro_" + kind)), _e(_l("count") % entries.size())]
	if sources.size() > 1: html += "<p class=\"note\">%s</p>" % _e(_l("legend"))
	var games_cell := func(entry: Dictionary) -> String: return _games_short(_games(entry.records))
	var name_cell := func(entry: Dictionary) -> String: return _link(entry.page.key, entry.page.title)
	var cost := func(edition: String, record: Dictionary) -> String: return str(record.row.get("Cost", 0))
	match kind:
		"creatures", "spells":
			# Grouped by race (the newest edition's), as the games' spellbooks.
			var groups := {}
			for entry: Dictionary in entries:
				var records: Dictionary = entry.records
				var color := str(records[_games(records).back()].row.get("Color", ""))
				if not groups.has(color): groups[color] = []
				groups[color].append(entry)
			var order: Array = COLORS.duplicate()
			for color: String in groups:
				if not color in order: order.append(color)
			var latest: String = "el2" if sources.has("el2") else "el1"
			for color: String in order:
				if not groups.has(color): continue
				html += "<h2>%s</h2>" % _e(_race(latest, color))
				var rows: Array = []
				if kind == "creatures":
					rows.append(_row([_l("name"), _l("games"), _l("cost"), _l("power"), _l("toughness"), _l("abilities")], true))
					for entry: Dictionary in groups[color]:
						var records: Dictionary = entry.records
						rows.append(_row([name_cell.call(entry), games_cell.call(entry), _cell(records, cost),
							_cell(records, func(_ed, r): return str(r.creature.get("Power", 0))),
							_cell(records, func(_ed, r): return str(r.creature.get("Toughness", 0))),
							_cell(records, _abilities)]))
					html += _table(rows, 6)
				else:
					rows.append(_row([_l("name"), _l("games"), _l("type"), _l("rarity"), _l("cost")], true))
					for entry: Dictionary in groups[color]:
						var records: Dictionary = entry.records
						rows.append(_row([name_cell.call(entry), games_cell.call(entry), _cell(records, func(ed, r): return _type(ed, r.row)),
							_cell(records, func(_ed, r): return _l(str(r.row.get("Rarity", "")))), _cell(records, cost)]))
					html += _table(rows, 5)
		"artifacts":
			var rows: Array = [_row([_l("name"), _l("games"), _l("type"), _l("race"), _l("cost")], true)]
			for entry: Dictionary in entries:
				var records: Dictionary = entry.records
				rows.append(_row([name_cell.call(entry), games_cell.call(entry), _cell(records, func(ed, r): return _type(ed, r.row)),
					_cell(records, func(ed, r): return _race(ed, str(r.row.get("Color", "")))), _cell(records, cost)]))
			html += _table(rows, 5)
		"specializations":
			var rows: Array = [_row([_l("name"), _l("games"), _l("colors"), _l("chance")], true)]
			for entry: Dictionary in entries:
				var records: Dictionary = entry.records
				rows.append(_row([name_cell.call(entry), games_cell.call(entry),
					_cell(records, _colors),
					_cell(records, func(_ed, r): return _l(str(r.row.get("Chance", ""))))]))
			html += _table(rows, 4)
		_:
			var rows: Array = [_row([_l("name"), _l("games")], true)]
			for entry: Dictionary in entries: rows.append(_row([name_cell.call(entry), games_cell.call(entry)]))
			html += _table(rows, 2)
	html += "<p class=\"note\">%s</p>" % _e(_l("source"))
	return {"key": key, "title": title, "category": key, "summary": _l("count") % entries.size(), "html": html,
		"search": title.to_lower(), "games": sources.keys(), "card": "", "models": [], "kind": "list", "order": -1, "list": kind}
