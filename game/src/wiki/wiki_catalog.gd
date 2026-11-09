class_name ELWikiCatalog
extends RefCounted
## Encyclopedia pages built from a loaded game (as the EI remake's WikiCatalog):
## one page for every creature, sorcery, enchantment, artifact, skill and
## specialisation of the edition, plus a list page per category. Names,
## descriptions and statistics come from the installed game's own tables and
## texts, so the in-game wiki follows the player's copy and its language. The
## page labels follow the wiki language. tools/export_wiki.gd runs the same
## builder for the hosted wiki.
##
## Pages: {key, title, category, summary, html, search, game, card, kind}.
## Card pages carry `<figure data-card="<game>/<CODE>" data-kind="...">`: the
## in-game reader shows the live model or icon beside the article, the website
## the exported screenshot.

const KINDS := ["creatures", "spells", "artifacts", "skills", "specializations"]
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
	"en": {"el1": "Etherlords", "el2": "Etherlords II",
		"creatures": "creatures", "spells": "spells", "artifacts": "artifacts", "skills": "skills", "specializations": "specializations",
		"creatures_title": "Creatures", "spells_title": "Sorceries and enchantments", "artifacts_title": "Artifacts",
		"skills_title": "Skills", "specializations_title": "Specializations",
		"game": "Game", "type": "Type", "race": "Race", "rarity": "Rarity", "cost": "Ether cost", "power": "Power", "toughness": "Toughness",
		"abilities": "Abilities", "artifact": "Artifact", "yes": "yes", "name": "Name", "price": "Price",
		"resource": "Resource", "shop": "Price in shops and the duel editor", "rune": "Price of a rune", "ability": "Ability",
		"Cantrip": "Cantrip", "Common": "Common", "Rare": "Rare", "Unique": "Unique", "NoAffect": "Unaffected",
		"level": "Rank", "effect": "Effect", "duel_price": "Duel editor price", "chance": "Chance", "colors": "Races",
		"Ulow": "very low", "Low": "low", "Med": "medium", "High": "high", "all_of": "All %s of %s",
		"count": "%d pages. Select a name for its page.", "back": "All %s", "intro_creatures": "Every creature spell of the game with its race, ether cost, power, toughness and abilities.",
		"intro_spells": "Every sorcery and enchantment of the game with its race, rarity and ether cost.",
		"intro_artifacts": "Every artifact of the game. Artifacts are used during battle a limited number of times.",
		"intro_skills": "Hero skills of the game. A hero learns at most five, each up to rank 3.",
		"intro_specializations": "Hero specializations of the game: chance-based talents in battle.",
		"source": "Names, descriptions and values come from the game's own data."},
	"ru": {"el1": "Демиурги", "el2": "Демиурги II",
		"creatures": "создания", "spells": "заклинания", "artifacts": "артефакты", "skills": "навыки", "specializations": "специализации",
		"creatures_title": "Создания", "spells_title": "Колдовство и чары", "artifacts_title": "Артефакты",
		"skills_title": "Навыки", "specializations_title": "Специализации",
		"game": "Игра", "type": "Вид", "race": "Раса", "rarity": "Редкость", "cost": "Стоимость в эфире", "power": "Сила", "toughness": "Стойкость",
		"abilities": "Способности", "artifact": "Артефакт", "yes": "да", "name": "Название", "price": "Цена",
		"resource": "Ресурс", "shop": "Цена в лавках и редакторе дуэли", "rune": "Цена руны", "ability": "Способность",
		"Cantrip": "Примитив", "Common": "Обычное", "Rare": "Редкое", "Unique": "Тайное", "NoAffect": "Невосприимчивость",
		"level": "Ступень", "effect": "Действие", "duel_price": "Цена в редакторе дуэли", "chance": "Шанс", "colors": "Расы",
		"Ulow": "очень низкий", "Low": "низкий", "Med": "средний", "High": "высокий", "all_of": "Все %s: %s",
		"count": "Страниц: %d. Выберите название, чтобы открыть страницу.", "back": "Все %s", "intro_creatures": "Все заклинания-создания игры: раса, стоимость в эфире, сила, стойкость и способности.",
		"intro_spells": "Всё колдовство и все чары игры: раса, редкость и стоимость в эфире.",
		"intro_artifacts": "Все артефакты игры. Артефакты применяются в бою ограниченное число раз.",
		"intro_skills": "Навыки героев. Герой знает не больше пяти навыков, каждый до 3-й ступени.",
		"intro_specializations": "Специализации героев — случайные таланты в бою.",
		"source": "Названия, описания и значения взяты из данных самой игры."},
}

var profile: ELProfile
var game := ""
var language := "en"
var pages: Array[Dictionary] = []
## When not empty, only these card, skill and specialisation pages are built
## (the exporter keeps two language editions to the same set of pages).
var allowed: Dictionary = {}

## All pages of `source` with labels in `lang` ("en" or "ru").
static func build(source: ELProfile, lang: String, only: Dictionary = {}) -> ELWikiCatalog:
	var catalog := ELWikiCatalog.new()
	catalog.profile = source
	catalog.game = source.id
	catalog.language = lang if LABELS.has(lang) else "en"
	catalog.allowed = only
	catalog._build()
	return catalog

## Category ids in display order, with their titles in `lang`.
static func categories(edition: String, lang: String) -> Array[Dictionary]:
	var labels: Dictionary = LABELS.get(lang, LABELS.en)
	var out: Array[Dictionary] = []
	for kind: String in KINDS:
		out.append({"id": "%s-%s" % [edition, kind], "title": "%s: %s" % [labels[edition], labels[kind]]})
	return out

static func card_key(edition: String, code: String) -> String:
	return "%s-%s" % [edition, _slug(code)]

static func _slug(value: String) -> String:
	var out := ""
	for c: String in value.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "-"
	while "--" in out: out = out.replace("--", "-")
	return out.strip_edges().trim_prefix("-").trim_suffix("-")

func _l(key: String) -> String:
	return str(LABELS[language].get(key, LABELS.en.get(key, key)))

func _t(key: String) -> String:
	var value := profile.text(key)
	return "" if value == key else value

static func _e(value: String) -> String:
	return value.xml_escape(true)

## Paragraphs of a game text (its line breaks start new paragraphs).
static func _paragraphs(value: String) -> String:
	var out := ""
	for line: String in value.replace("\r", "").split("\n", false):
		var clean := line.strip_edges()
		while "  " in clean: clean = clean.replace("  ", " ")
		if not clean.is_empty(): out += "<p>%s</p>" % _e(clean)
	return out

func _race(color: String) -> String:
	var value := _t(RACE_KEYS.get(color, ""))
	return value if not value.is_empty() else color

func _kind_of(row: Dictionary) -> String:
	if str(row.get("IsArtifact", "False")) == "True": return "artifacts"
	return "creatures" if str(row.get("Class", "")) == "Creature" else "spells"

func _type(row: Dictionary) -> String:
	var key: String = {"Creature": "T_SPELL_TYPE", "Sorcery": "T_SPELL_TYPE2", "Enchantment": "T_SPELL_TYPE3"}.get(str(row.get("Class", "")), "")
	# The first game's Russian table spells "Создание" with a Latin C.
	return _t(key).replace("Cоздание", "Создание") if not key.is_empty() else str(row.get("Class", ""))

func _resource(column: String) -> String:
	if language == "ru" and game == "el1": return RU_RESOURCES.get(column, column)
	var index: int = RESOURCES[game].find(column)
	var value := _t("T_RESOURCE_NAME_%d" % (index + 1)) if index >= 0 else ""
	if not value.is_empty(): return value
	return RU_RESOURCES.get(column, column) if language == "ru" else str(ELResources.LABELS.get(column, column))

func _flag(flag: String) -> String:
	var base := flag.get_slice("(", 0)
	var amount := flag.get_slice("(", 1).trim_suffix(")") if "(" in flag else ""
	var value := _t(FLAG_KEYS.get(base, "")) if FLAG_KEYS.has(base) else ""
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
	for cell: Variant in cells: out += "<%s>%s</%s>" % [tag, cell, tag]
	return out + "</tr>"

func _table(rows: Array, columns: int) -> String:
	return "<table data-columns=\"%d\">%s</table>" % [columns, "".join(rows)]

func _link(key: String, label: String) -> String:
	return "<a href=\"wiki://%s\">%s</a>" % [key, _e(label)]

func _price_rows(row: Dictionary, prefix: String) -> Array:
	var rows: Array = []
	for column: String in RESOURCES[game]:
		var amount := int(row.get(prefix + column, 0))
		if amount > 0: rows.append([_e(_resource(column)), str(amount)])
	return rows

func _build() -> void:
	var spells := profile.table("CombatSpells")
	var creatures := profile.table("CombatCreatures")
	var lists := {}
	for kind: String in KINDS: lists[kind] = []
	for code: String in spells:
		var row: Dictionary = spells[code]
		var title := _t(str(row.get("Name", "")))
		# Unused records, and internal helpers whose name is only their code.
		if str(row.get("Use", "+")) != "+" or title.is_empty() or title == code: continue
		if not allowed.is_empty() and not allowed.has(card_key(game, code)): continue
		var kind := _kind_of(row)
		var creature: Dictionary = creatures.get(code, {}) if kind == "creatures" else {}
		var page := _card_page(code, row, creature, title, kind)
		pages.append(page)
		lists[kind].append({"page": page, "row": row, "creature": creature})
	_skills(lists)
	_specializations(lists)
	for kind: String in KINDS:
		var entries: Array = lists[kind]
		entries.sort_custom(func(a, b): return str(a.page.title).naturalnocasecmp_to(str(b.page.title)) < 0)
		pages.append(_list_page(kind, entries))

func _card_page(code: String, row: Dictionary, creature: Dictionary, title: String, kind: String) -> Dictionary:
	var color := str(row.get("Color", ""))
	var description := _t(str(row.get("ToolTip", "")))
	var html := "<h1>%s</h1>" % _e(title)
	html += "<figure data-card=\"%s/%s\" data-kind=\"%s\"></figure>" % [game, code, "creature" if not creature.is_empty() else "card"]
	html += _paragraphs(description)
	var facts: Array = [_row([_l("game"), _e(_l(game))]), _row([_l("type"), _e(_type(row))]), _row([_l("race"), _e(_race(color))]),
		_row([_l("rarity"), _e(_l(str(row.get("Rarity", ""))))]), _row([_l("cost"), str(row.get("Cost", 0))])]
	var abilities: Array = []
	if not creature.is_empty():
		facts.append(_row([_l("power"), str(creature.get("Power", 0))]))
		facts.append(_row([_l("toughness"), str(creature.get("Toughness", 0))]))
		for flag: String in _flags(creature): abilities.append(_flag(flag))
		if not abilities.is_empty(): facts.append(_row([_l("abilities"), _e(", ".join(abilities))]))
	if kind == "artifacts": facts.append(_row([_l("artifact"), _l("yes")]))
	html += _table(facts, 2)
	var ability := _t(str(row.get("AbilityText", "")))
	if not ability.is_empty() and not ability in description:
		html += "<h2>%s</h2>%s" % [_l("ability"), _paragraphs(ability)]
	var prices := _price_rows(row, "Cost")
	if not prices.is_empty():
		var rows: Array = [_row([_l("resource"), _l("shop")], true)]
		for price: Array in prices: rows.append(_row(price))
		html += "<h2>%s</h2>%s" % [_l("price"), _table(rows, 2)]
	var runes := _price_rows(row, "Charge") if game == "el1" else []
	if not runes.is_empty():
		var rows: Array = [_row([_l("resource"), _l("rune")], true)]
		for price: Array in runes: rows.append(_row(price))
		html += _table(rows, 2)
	var list_key := "%s-%s" % [game, kind]
	html += "<p>%s</p>" % _link(list_key, _l("back") % _l(kind))
	var summary := " · ".join([_type(row), _race(color), str(row.get("Cost", 0))])
	if not creature.is_empty(): summary += " · %s/%s" % [creature.get("Power", 0), creature.get("Toughness", 0)]
	return {"key": card_key(game, code), "title": title, "category": list_key, "summary": summary, "html": html,
		"search": (title + " " + description + " " + " ".join(abilities)).to_lower(), "game": game, "card": code,
		"kind": "creature" if not creature.is_empty() else "card"}

func _skills(lists: Dictionary) -> void:
	var by_code := {}
	for value: Variant in profile.table("HeroesSkills").values():
		var row: Dictionary = value
		if str(row.get("InUse", "True")) == "False": continue
		var code := str(row.get("Code", ""))
		if code.is_empty(): continue
		if not by_code.has(code): by_code[code] = []
		by_code[code].append(row)
	for code: String in by_code:
		var levels: Array = by_code[code]
		levels.sort_custom(func(a, b): return int(a.get("Level", 0)) < int(b.get("Level", 0)))
		var title := _t(str(levels[0].get("Name", "")))
		if title.is_empty() or not allowed.is_empty() and not allowed.has("%s-skill-%s" % [game, _slug(code)]): continue
		var rows: Array = [_row([_l("level"), _l("effect"), _l("duel_price")], true)]
		var words := title
		for row: Dictionary in levels:
			var effect := _t(str(row.get("Description", "")))
			words += " " + effect
			var prices: Array = []
			for price: Array in _price_rows(row, "DuelCost"): prices.append("%s %s" % [price[1], price[0]])
			rows.append(_row([str(row.get("Level", "")), _e(effect), _e(", ".join(prices)) if str(row.get("Duel", "True")) == "True" else "—"]))
		var key := "%s-skill-%s" % [game, _slug(code)]
		var html := "<h1>%s</h1>%s<p>%s</p>" % [_e(title), _table(rows, 3), _link("%s-skills" % game, _l("back") % _l("skills"))]
		var page := {"key": key, "title": title, "category": "%s-skills" % game, "summary": _l(game), "html": html,
			"search": words.to_lower(), "game": game, "card": "", "kind": "skill"}
		pages.append(page)
		lists.skills.append({"page": page, "row": levels[0], "creature": {}})

func _specializations(lists: Dictionary) -> void:
	var specs := profile.table("HeroesSpecs")
	for code: String in specs:
		var row: Dictionary = specs[code]
		var title := _t(str(row.get("Name", "")))
		if title.is_empty() or title == code or not allowed.is_empty() and not allowed.has("%s-spec-%s" % [game, _slug(code)]): continue
		var effect := _t(str(row.get("Desc", "")))
		var colors: Variant = row.get("MagicColor", [])
		var races: Array = []
		for color: Variant in (colors if colors is Array else [colors]): races.append(_race(str(color)))
		var prices: Array = []
		for price: Array in _price_rows(row, "DuelCost"): prices.append("%s %s" % [price[1], price[0]])
		var facts: Array = [_row([_l("game"), _e(_l(game))]), _row([_l("chance"), _e(_l(str(row.get("Chance", ""))))]),
			_row([_l("colors"), _e(", ".join(races))])]
		if not prices.is_empty(): facts.append(_row([_l("duel_price"), _e(", ".join(prices))]))
		var key := "%s-spec-%s" % [game, _slug(code)]
		var html := "<h1>%s</h1>%s%s<p>%s</p>" % [_e(title), _paragraphs(effect), _table(facts, 2), _link("%s-specializations" % game, _l("back") % _l("specializations"))]
		var page := {"key": key, "title": title, "category": "%s-specializations" % game, "summary": ", ".join(races), "html": html,
			"search": (title + " " + effect).to_lower(), "game": game, "card": "", "kind": "specialization"}
		pages.append(page)
		lists.specializations.append({"page": page, "row": row, "creature": {}})

func _list_page(kind: String, entries: Array) -> Dictionary:
	var key := "%s-%s" % [game, kind]
	var title := "%s: %s" % [_l(game), _l(kind + "_title")]
	var html := "<h1>%s</h1><p>%s</p><p>%s</p>" % [_e(title), _e(_l("intro_" + kind)), _e(_l("count") % entries.size())]
	var rows: Array = []
	match kind:
		"creatures":
			rows.append(_row([_l("name"), _l("race"), _l("cost"), _l("power"), _l("toughness"), _l("abilities")], true))
			for entry: Dictionary in entries:
				var abilities: Array = []
				for flag: String in _flags(entry.creature): abilities.append(_flag(flag))
				rows.append(_row([_link(entry.page.key, entry.page.title), _e(_race(str(entry.row.get("Color", "")))), str(entry.row.get("Cost", 0)),
					str(entry.creature.get("Power", 0)), str(entry.creature.get("Toughness", 0)), _e(", ".join(abilities))]))
			html += _table(rows, 6)
		"spells", "artifacts":
			rows.append(_row([_l("name"), _l("type"), _l("race"), _l("rarity"), _l("cost")], true))
			for entry: Dictionary in entries:
				rows.append(_row([_link(entry.page.key, entry.page.title), _e(_type(entry.row)), _e(_race(str(entry.row.get("Color", "")))),
					_e(_l(str(entry.row.get("Rarity", "")))), str(entry.row.get("Cost", 0))]))
			html += _table(rows, 5)
		_:
			html += "<ul>"
			for entry: Dictionary in entries: html += "<li>%s</li>" % _link(entry.page.key, entry.page.title)
			html += "</ul>"
	html += "<p class=\"note\">%s</p>" % _e(_l("source"))
	return {"key": key, "title": title, "category": key, "summary": _l("count") % entries.size(), "html": html,
		"search": title.to_lower(), "game": game, "card": "", "kind": "list", "order": -1}
