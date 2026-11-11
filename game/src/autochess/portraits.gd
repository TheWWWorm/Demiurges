class_name ELAutochessPortraits
extends Node
## Small still renders of creature models (the damage list, the evolution
## path). Each creature is rendered once into its own little viewport, which
## then stops updating; its texture is shared by every row that shows it.

const SIZE := 72

var profile: ELProfile
var _views := {}
var _settling := {}

func texture(code: String) -> Texture2D:
	if code.is_empty() or profile == null: return null
	if not _views.has(code):
		var view := ELWikiPreview.stage(profile, code, Vector2i(SIZE, SIZE), true)
		if view == null:
			_views[code] = null
			return profile.card_icon(code)
		for node: Node in view.get_children():
			if node is WorldEnvironment: (node as WorldEnvironment).environment.background_mode = Environment.BG_CLEAR_COLOR
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(view)
		(view.get_node("Model") as ELModel).play("cidle")
		_views[code] = view
		_settling[code] = 0
	var found: SubViewport = _views[code]
	return found.get_texture() if found != null else profile.card_icon(code)

## Portraits still settling into their framing.
func settling() -> int:
	return _settling.size()

func _process(_delta: float) -> void:
	for code: String in _settling.keys():
		var view: SubViewport = _views[code]
		_settling[code] = int(_settling[code]) + 1
		var frames := int(_settling[code])
		if frames == 3: ELAutochessFigure.aim(view, deg_to_rad(-28.0), deg_to_rad(10.0), 0.95)
		elif frames > 4 and frames % 2 == 1 and frames < 22:
			var factor := ELAutochessFigure.refine(view, 0.92)
			if factor > 0.0 and absf(factor - 1.0) < 0.04: frames = 23
		if frames >= 23:
			view.render_target_update_mode = SubViewport.UPDATE_ONCE
			(view.get_node("Model") as ELModel).set_process(false)
			_settling.erase(code)
