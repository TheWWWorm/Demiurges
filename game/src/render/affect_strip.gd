class_name ELAffectStrip
extends Control
## The second game's hero affect icons at the top right, on the map and over
## a battle: one 50 px icon per affect of the hero, the first 60 px from the
## right edge and 10 px from the top, each next one 60 px further left, in the
## order the hero got them. An icon is the AffectsList row's Icon cell: 25 per
## sheet (AFFECTS_01, then AFFECTS_02), five columns of five 50 px cells
## filled top to bottom; an affect without a row shows cell 0. The
## WORLD_SYMBOLS_MAP frame (140,0)-(190,50) is drawn over each. The tooltip is
## the row's Tooltip; an affect that runs out after some days adds a line with
## Tooltip2 and the days left. Range battlegrounds act on a hero within their
## reach, so they are listed while it is there.
## Not ported: the original fades icons in and out as they come and go.

const ICON := 50.0
const STEP := 60.0
const TOP := 10.0
const RIGHT := 60.0
const PER_SHEET := 25
const COLUMN := 5
const FRAME := Rect2(140, 0, 50, 50)

var profile: ELProfile
var sheets: Array[Texture2D] = []
var frame: Texture2D
## {icon: int, tooltip: String, name: String}
var entries: Array[Dictionary] = []
## Screen pixels per original pixel (the battle panel's factor; 1 on the map,
## whose panel layer is already scaled).
var ui_scale := 1.0:
	set(value):
		if is_equal_approx(ui_scale, value): return
		ui_scale = value
		queue_redraw()
var _signature := ""

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name = "AffectStrip"

func setup(source: ELProfile) -> void:
	profile = source
	sheets.clear()
	frame = null
	if profile == null: return
	var paths := {}
	for row: Dictionary in profile.table("InterfaceTextures").values():
		paths[str(row.get("Name", ""))] = "Interface/" + str(row.get("Path", "")).replace("\\", "/")
	for sheet: String in ["AFFECTS_01", "AFFECTS_02"]:
		var texture := profile.texture(paths.get(sheet, "")) if paths.has(sheet) else null
		sheets.append(texture)
	if paths.has("WORLD_SYMBOLS_MAP"): frame = profile.texture(paths.WORLD_SYMBOLS_MAP)

## The hero's affects as icon entries (see the class notes).
static func list(state: ELAdventureSession, hero_uid: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state == null or state.map.profile.id != "el2": return result
	var hero := state.object(hero_uid)
	if hero.is_empty() or not hero.get("alive", true): return result
	var profile := state.map.profile
	var rows := profile.table("AffectsList")
	var affects: Array = hero.get("affects", []).duplicate()
	for affect: Dictionary in ELBattleScripts.battle_affects(state, hero):
		if affect.get("kind") == "range": affects.append(affect)
	for entry: Variant in affects:
		if entry is not Dictionary: continue
		var name := str(entry.get("name", ""))
		var row: Dictionary = rows.get(name, {})
		var tooltip := profile.text(str(row.get("Tooltip", ""))) if row.has("Tooltip") else name
		if entry.has("ticks") and row.has("Tooltip2"):
			var days := profile.text(str(row.Tooltip2))
			if days.contains("%d"): tooltip += "\n" + days.replace("%d", str(int(entry.ticks)))
		result.append({"icon": int(row.get("Icon", 0)), "tooltip": tooltip, "name": name})
	return result

## Shows the hero's affects; redraws only when they changed.
func show_hero(state: ELAdventureSession, hero_uid: int) -> void:
	set_entries(list(state, hero_uid))

func set_entries(value: Array[Dictionary]) -> void:
	var signature := str(value)
	if signature == _signature: return
	_signature = signature
	entries = value
	queue_redraw()

func clear() -> void:
	set_entries([] as Array[Dictionary])

## The source cell of an icon index: sheet, then the cell in it.
static func cell(icon: int) -> Dictionary:
	var index := maxi(icon, 0)
	var rest := index % PER_SHEET
	return {"sheet": index / PER_SHEET, "region": Rect2(float(rest / COLUMN) * ICON, float(rest % COLUMN) * ICON, ICON, ICON)}

## Where the n-th icon is drawn, in this control's coordinates.
func icon_rect(index: int) -> Rect2:
	var width := size.x / maxf(ui_scale, 0.001)
	return Rect2(Vector2(width - RIGHT - STEP * index, TOP) * ui_scale, Vector2(ICON, ICON) * ui_scale)

func _draw() -> void:
	for index in entries.size():
		var rect := icon_rect(index)
		var source := cell(int(entries[index].icon))
		var sheet: Texture2D = sheets[source.sheet] if source.sheet < sheets.size() else null
		if sheet != null: draw_texture_rect_region(sheet, rect, source.region)
		if frame != null: draw_texture_rect_region(frame, rect, FRAME)

func _has_point(point: Vector2) -> bool:
	return _hovered(point) >= 0

func _hovered(point: Vector2) -> int:
	for index in entries.size():
		if icon_rect(index).has_point(point): return index
	return -1

func _get_tooltip(at_position: Vector2) -> String:
	var index := _hovered(at_position)
	return str(entries[index].tooltip) if index >= 0 else ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: queue_redraw()
