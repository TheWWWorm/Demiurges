class_name ELCrashReportBox
extends AcceptDialog
## The box that offers a report (ELCrashReport): at start-up after a session
## that ended unexpectedly, and from Remake settings › "Export log…" at any
## time. "Save report" writes a text file to a folder the player can open and
## shows where; "Copy to clipboard" copies the system information and the
## log's last lines. OK or Esc closes it.

## The previous session's information; {} for Export log.
var prev := {}
var status: Label
var save_button: Button
var copy_button: Button

## The box over `parent` when the previous session ended unexpectedly (once).
static func offer(parent: Node) -> ELCrashReportBox:
	var report := ELCrashReport.instance
	if report == null or report.previous.is_empty(): return null
	var box := open(parent, report.previous)
	report.previous = {}
	return box

static func open(parent: Node, previous: Dictionary) -> ELCrashReportBox:
	var box := ELCrashReportBox.new()
	box.prev = previous
	box.name = "CrashReportBox"
	box.exclusive = true
	if previous.is_empty():
		box.title = "Export log"
		box._build("Save the game's log with the system information, or copy it, to send it with a bug report.")
	else:
		box.title = "The game closed unexpectedly"
		box._build("The game closed unexpectedly last time. A report with the log of that session helps to find the cause. Save it or copy it, and attach it to a bug report.")
	parent.add_child(box)
	box.popup_centered(Vector2i(460, 250))
	return box

func _build(message: String) -> void:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	add_child(rows)
	var text := Label.new()
	text.text = message
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 420
	rows.add_child(text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	rows.add_child(buttons)
	save_button = Button.new()
	save_button.name = "SaveReport"
	save_button.text = "Save report"
	save_button.tooltip_text = "Saves the report as a text file: Download on Android, Downloads on a computer. The box shows where."
	save_button.pressed.connect(act.bind(0))
	buttons.add_child(save_button)
	copy_button = Button.new()
	copy_button.name = "CopyReport"
	copy_button.text = "Copy to clipboard"
	copy_button.tooltip_text = "Copies the system information and the log's last lines, to paste into a message or a bug report."
	copy_button.pressed.connect(act.bind(1))
	buttons.add_child(copy_button)
	status = Label.new()
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	status.custom_minimum_size.x = 420
	status.modulate = Color(0.8, 0.8, 0.8)
	rows.add_child(status)
	confirmed.connect(queue_free)
	canceled.connect(queue_free)

## Uses button `index`: the report saved (the box shows where) or copied.
func act(index: int) -> void:
	var report := ELCrashReport.instance
	if report == null: return
	if index == 0:
		var path := report.save_report(prev)
		status.text = "Report saved: " + path if path != "" else "The report could not be saved."
		var checking := ELCrashReport.save_dir_override != ""
		if path != "" and not checking and not OS.has_feature("mobile") and not OS.has_feature("web"):
			OS.shell_show_in_file_manager(path)
	else:
		report.copy_report(prev)
		status.text = "Copied to the clipboard."
