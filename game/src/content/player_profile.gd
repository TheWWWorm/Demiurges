class_name ELPlayerProfile
extends RefCounted
## First game: the player's name and blazon chosen on the campaign screen or
## the Single player panel. They replace the map's name and blazon of the
## human player at every chapter start, are saved with the player, and name
## the Hall of Fame records.

## The edit takes 20 characters plus the one its limit check lets through.
const NAME_LIMIT := 21
## The Single player panel's slot edits (12 + 1).
const SLOT_NAME_LIMIT := 13
const LOGOS := 72
const COLOURS := 16
## Side defaults on the campaign screen: Vital (Good) logo 8 colour 13,
## Chaos (Evil) logo 31 colour 7.
const SIDE_BLAZON := {"Good": Vector2i(8, 13), "Evil": Vector2i(31, 7)}

## Session profile: the name persists while the game runs; the blazon starts
## at logo 0, colour 0 (neither is saved in the settings).
static var chosen_name := ""
static var _named := false
static var blazon := Vector2i(0, 0)

static func default_name(profile: ELProfile) -> String:
	var value := profile.text("T_DEF_PLAYER_NAME")
	return value if value != "T_DEF_PLAYER_NAME" and not value.is_empty() else "Player"

static func current_name(profile: ELProfile) -> String:
	return chosen_name if _named else default_name(profile)

static func choose_name(value: String) -> void:
	chosen_name = clip(value, NAME_LIMIT)
	_named = true

static func reset() -> void:
	chosen_name = ""
	_named = false
	blazon = Vector2i(0, 0)

## Characters the edit refuses (Backspace, Tab, Escape, Enter) are dropped.
static func clip(value: String, limit: int) -> String:
	var kept := ""
	for character: String in value:
		if character in ["\b", "\t", "\u001b", "\r", "\n"]: continue
		kept += character
	return kept.left(limit)

static func valid_blazon(value: Vector2i) -> bool:
	return value.x >= 0 and value.x < LOGOS and value.y >= 0 and value.y < COLOURS

## Gives the human player the chosen name and blazon.
static func apply(state: ELAdventureSession, player_name: String, logo: int, colour: int) -> void:
	if not state.players.has(state.current_player): return
	state.players[state.current_player].name = player_name
	if valid_blazon(Vector2i(logo, colour)): state.players[state.current_player].blazon = [logo, colour]

## The blazon a player shows: the chosen one for the human, else the map's.
static func player_blazon(state: ELAdventureSession, player: int) -> Vector2i:
	var chosen: Variant = state.players.get(player, {}).get("blazon")
	if chosen is Array and chosen.size() == 2: return Vector2i(int(chosen[0]), int(chosen[1]))
	for row: Dictionary in state.map.players:
		if int(row.attrs.get("id", -1)) == player:
			var fore := str(row.attrs.get("blazon", "-1"))
			var back := str(row.attrs.get("blazon_color", "-1"))
			return Vector2i(int(fore) if fore.is_valid_int() else -1, int(back) if back.is_valid_int() else -1)
	return Vector2i(-1, -1)

## Saved player fields: a name string and a [logo, colour] pair, both optional.
static func valid_saved(record: Dictionary) -> bool:
	if record.has("name") and (not record.name is String or String(record.name).length() > NAME_LIMIT): return false
	if record.has("blazon"):
		var value: Variant = record.blazon
		if not value is Array or value.size() != 2: return false
		if not ELLuaSave._integer(value[0], 0, LOGOS - 1) or not ELLuaSave._integer(value[1], 0, COLOURS - 1): return false
	return true
