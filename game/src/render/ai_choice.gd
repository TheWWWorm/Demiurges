class_name ELAIChoice
## The computer players' strength as dropdowns: "duel_ai" (the battle
## opponent, both games) and "world_ai" (computer players on the first
## game's map), ELSettings.DUEL_AI_LEVELS and WORLD_AI_LEVELS. Options and
## the screens where a campaign's difficulty is chosen use the same lists;
## each item's tooltip says what it does.

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

## A dropdown of `key`'s levels showing the current value; choosing one
## stores it in `settings` (written to `path` when given: the campaign
## screens have no OK to confirm with).
static func picker(settings: ELSettings, key: String, profile: ELProfile, path := "") -> OptionButton:
	var pick := OptionButton.new()
	pick.name = "DuelAi" if key == "duel_ai" else "WorldAi"
	pick.focus_mode = Control.FOCUS_NONE
	var list := levels(key)
	for i in list.size():
		pick.add_item(level_name(String(list[i][0]), profile))
		pick.set_item_tooltip(i, ELRemakeText.t(String(list[i][1]), profile))
	pick.select(clampi(int(settings.values.get(key, ELSettings.SHARED[key])), 0, list.size() - 1))
	pick.tooltip_text = ELRemakeText.t(String(list[pick.selected][1]), profile)
	pick.item_selected.connect(func(index: int):
		settings.values[key] = index
		pick.tooltip_text = ELRemakeText.t(String(list[index][1]), profile)
		if not path.is_empty(): settings.save_file(path))
	return pick
