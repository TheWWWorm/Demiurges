class_name ELContentSetup
extends Control
## Game files screen, on every platform. The player chooses which game to set
## up, then its installed folder (desktop, or a desktop browser), the GOG
## installer (read, never run) or a data pack made with
## tools/prepare_game_data.py. Each edition is kept separately; either one is
## enough to play, and the screen switches between those present.
signal opened(edition: String, folder: String)
signal chosen(edition: String)
signal closed
signal removed(edition: String)
## Before adding the screen: the editions the game can play now
## ({edition: folder}) and the one to show first.
var mounted: Dictionary = {}
var selected := "el1"
var _status: Label
var _current: Label
var _choice: ELGameChoice
var _buttons: Array[Button] = []
var _play: Button
var _folder: Button
var _forget: Button
var _unlink: Button
var _cancel: Button
var _close: Button
var _import: ELContentImport
var _dialog: FileDialog
var _folder_dialog: FileDialog
var _callback: JavaScriptObject
var _scroll: ScrollContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color(0.06, 0.06, 0.08)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	_scroll.add_child(box)
	var heading := Label.new()
	heading.text = "Demiurges"
	heading.add_theme_font_size_override("font_size", 30)
	box.add_child(heading)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Use the files of your own copy of Etherlords or Etherlords II. They stay on this device; nothing is uploaded. Choose the game first; either one is enough, and you can add the other later.\n"
	if OS.has_feature("web"):
		info.text += "Choose the GOG installer (setup_etherlords*.exe): the browser unpacks it without running it. The installed game folder or a data pack (.elpack) also work."
	elif ELContentLibrary.uses_import():
		info.text += "Choose the GOG installer (setup_etherlords*.exe) or a data pack (.elpack). The installer is unpacked without being run; a data pack is much faster."
	else:
		info.text += "Choose the installed game folder (the one containing Resources and Campaigns), or the GOG installer (setup_etherlords*.exe) or a data pack (.elpack). The installer is unpacked once without being run."
	box.add_child(info)
	_choice = ELGameChoice.new()
	_choice.selected.connect(_select)
	_choice.missing.connect(_select)
	box.add_child(_choice)
	_current = Label.new()
	_current.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_current.modulate = Color(0.75, 0.85, 0.95)
	box.add_child(_current)
	_play = _add(box, "", func(): chosen.emit(selected))
	if OS.has_feature("web"):
		_callback = JavaScriptBridge.create_callback(_browser_result)
		_add(box, "Choose installer or data pack…", func(): _choose_web(false))
		_add(box, "Choose game folder…", func(): _choose_web(true))
	else:
		_import = ELContentImport.new()
		add_child(_import)
		_import.progress.connect(func(message: String): _status.text = message)
		_import.failed.connect(func(message: String):
			_busy(false)
			_status.text = message)
		_import.completed.connect(func(edition: String, folder: String):
			_busy(false)
			_status.text = ELContentLibrary.title(edition) + " is ready."
			opened.emit(edition, folder))
		if not ELContentLibrary.uses_import():
			_folder_dialog = FileDialog.new()
			_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
			_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
			_folder_dialog.use_native_dialog = true
			_folder_dialog.dir_selected.connect(_link)
			add_child(_folder_dialog)
			_folder = _add(box, "", func(): _folder_dialog.popup_centered_ratio(0.7))
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = true
		# Phone pickers may grey out unknown extensions; files are recognised by their contents.
		if not OS.has_feature("mobile"):
			_dialog.filters = PackedStringArray(["*.exe,*.elpack ; Etherlords installer or data pack"])
		_dialog.file_selected.connect(func(path: String):
			_busy(true)
			_import.import_file(path))
		add_child(_dialog)
		_add(box, "Choose installer or data pack…", func(): _dialog.popup_centered_ratio(0.8))
	_cancel = Button.new()
	_cancel.text = "Cancel import"
	_cancel.custom_minimum_size.y = 48
	_cancel.hide()
	_cancel.pressed.connect(func():
		if _import != null: _import.cancelled = true
		var files := ELContentLibrary.web_files()
		if files != null: files.cancel())
	box.add_child(_cancel)
	_forget = _add(box, "", func(): _remove(selected))
	_unlink = _add(box, "", func(): _unlink_folder(selected))
	_close = _add(box, "Back", func(): closed.emit())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	if OS.has_feature("web") and not OS.is_userfs_persistent():
		_status.text = "Browser storage is unavailable, so saves will not be kept. Allow site storage before playing."
	_refresh()
	_layout()
	resized.connect(_layout)


func _layout() -> void:
	var side := maxf(16.0, (size.x - 760.0) * 0.5)
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = side
	_scroll.offset_right = -side
	_scroll.offset_top = 24
	_scroll.offset_bottom = -24


func _select(edition: String) -> void:
	selected = edition
	_status.text = ""
	_refresh()


func _refresh() -> void:
	var title := ELContentLibrary.title(selected)
	var imported := ELContentLibrary.managed_roots()
	var linked := ELContentLibrary.linked_folders()
	_choice.show_state(selected, mounted)
	if mounted.has(selected):
		_current.text = title + " is installed: " + str(mounted[selected])
	else:
		_current.text = title + " is not installed yet."
	_play.text = "Play " + title
	_play.visible = mounted.has(selected)
	if _folder != null: _folder.text = "Choose the " + title + " game folder…"
	_forget.text = "Remove imported " + title
	_forget.visible = imported.has(selected)
	_unlink.text = "Stop using this " + title + " folder"
	_unlink.tooltip_text = "The folder and its files are kept; only this link is removed."
	_unlink.visible = linked.has(selected) and not imported.has(selected)
	_close.visible = not mounted.is_empty()


func _add(box: VBoxContainer, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 48
	button.pressed.connect(action)
	box.add_child(button)
	_buttons.append(button)
	return button


func _busy(value: bool) -> void:
	for button in _buttons: button.disabled = value
	for button: Button in _choice.buttons.values(): button.disabled = value
	_cancel.visible = value


## Desktop: an installed folder is used where it is; the folder's contents,
## not the button pressed, decide which game it is.
func _link(folder: String) -> void:
	var edition := ELContentLibrary.detect(folder)
	if edition.is_empty():
		_status.text = "No Etherlords game was found in that folder. Choose the folder that contains Resources and Campaigns."
		return
	if not ELContentLibrary.link_folder(edition, folder):
		_status.text = "Could not remember the folder."
		return
	if edition != selected: _status.text = "That folder holds " + ELContentLibrary.title(edition) + "."
	opened.emit(edition, folder)


func _choose_web(folder: bool) -> void:
	var files := ELContentLibrary.web_files()
	if files == null:
		_status.text = "This page cannot read local files. Reload it and try again."
		return
	files.choose(_callback, folder)


## EtherFiles callbacks: (kind, message or edition, optional number).
func _browser_result(args: Array) -> void:
	if args.size() < 2: return
	var kind := str(args[0])
	var message := str(args[1])
	if args.size() > 2 and args[2] != null and message.contains("%"):
		message = message % (int(args[2]) if args[2] is float else args[2])
	_busy(kind == "progress")
	if kind == "complete":
		_status.text = ELContentLibrary.title(message) + " is ready."
		opened.emit(message, ELContentLibrary.managed_root(message))
	else:
		_status.text = message


func _remove(edition: String) -> void:
	ELContentLibrary.forget(edition)
	_status.text = ELContentLibrary.title(edition) + " was removed from this device. Saves and settings are kept."
	_gone(edition)


func _unlink_folder(edition: String) -> void:
	ELContentLibrary.link_folder(edition, "")
	_status.text = ELContentLibrary.title(edition) + " is no longer used. Its folder, saves and settings are kept."
	_gone(edition)


func _gone(edition: String) -> void:
	mounted.erase(edition)
	removed.emit(edition)
	_refresh()
