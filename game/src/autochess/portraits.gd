class_name ELAutochessPortraits
extends Node
## Small still renders of creature models (the damage list, the evolution
## path). Each creature is rendered once into its own little viewport, which
## then stops updating; its texture is shared by every row that shows it.

const SIZE := 72

var profile: ELProfile:
	set(value):
		if profile == value: return
		profile = value
		_clear_views()
var _views := {}
var _settling := {}
var _source_generation := -1

func _init() -> void:
	set_process(false)

func _ready() -> void:
	set_process(not _settling.is_empty())

func _clear_views() -> void:
	for view: Variant in _views.values():
		if is_instance_valid(view):
			view.render_target_update_mode = SubViewport.UPDATE_DISABLED
			view.process_mode = Node.PROCESS_MODE_DISABLED
			view.queue_free()
	_views.clear()
	_settling.clear()
	_source_generation = profile.generation if profile != null else -1
	set_process(false)

func texture(code: String) -> Texture2D:
	if code.is_empty() or profile == null: return null
	if profile.generation != _source_generation: _clear_views()
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
		set_process(true)
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
			# The result is a still image. Freeze the whole stage, including
			# its original effect emitters, after the final framing draw.
			view.process_mode = Node.PROCESS_MODE_DISABLED
			_settling.erase(code)
	if _settling.is_empty(): set_process(false)
