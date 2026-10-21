class_name ELUiSounds
extends RefCounted
## Interface button sounds, the same in both games. Every original button
## (PushButton, AutoButton, CheckButton, RadioButton, MultyButton) plays one
## sound from the sound archive when it acts: "Buttons/<Sound>.wav" from its
## Controls row, or Buttons/Click.wav when the row names none. A click on a
## disabled button plays Buttons/Error.wav instead. Nothing plays on hover.
## A radio button that is already chosen does not act and plays nothing.
## The sound uses the effects volume; a new interface sound replaces the one
## still playing (one interface channel).
const DEFAULT := "Buttons/Click.wav"
const ERROR := "Buttons/Error.wav"
const BUTTON_TYPES := ["PushButton", "AutoButton", "CheckButton", "RadioButton", "MultyButton"]
const HISTORY := 32

## Effects volume (0..1) of the edition being played; the settings, the
## Options previews and the audio hosts keep it current.
static var volume := 0.8
## The interface sounds played, newest last (at most HISTORY).
static var history: Array[String] = []
static var _player: AudioStreamPlayer

## The sound a control plays: its Controls "Sound", the default click for a
## button without one or a control the original tables do not list, "" for a
## control that is not a button.
static func sound_of(profile: ELProfile, control: String) -> String:
	if profile == null: return DEFAULT
	if profile.button_sounds.is_empty():
		for row: Dictionary in profile.table("Controls").values():
			var type := str(row.get("Type", ""))
			var sound := str(row.get("Sound", ""))
			var path := ""
			if type in BUTTON_TYPES: path = DEFAULT if sound.is_empty() else "Buttons/%s.wav" % sound
			profile.button_sounds[str(row.get("Name", ""))] = path
		profile.button_sounds["_loaded"] = ""
	return str(profile.button_sounds.get(control, DEFAULT))

## Gives a button its original sound. `control` defaults to the node name.
## Binding again only changes the sound.
static func bind(button: BaseButton, profile: ELProfile, control := "") -> void:
	if button == null or profile == null: return
	var bound := button.has_meta("ui_sound")
	button.set_meta("ui_sound", sound_of(profile, control if not control.is_empty() else String(button.name)))
	if bound: return
	button.pressed.connect(func(): play(profile, str(button.get_meta("ui_sound", ""))))
	button.gui_input.connect(func(event: InputEvent):
		if button.disabled and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			play(profile, ERROR))

## Gives a button a sound path of its own (screens whose original code sets one).
static func bind_path(button: BaseButton, profile: ELProfile, path: String) -> void:
	bind(button, profile)
	button.set_meta("ui_sound", path)

static func play(profile: ELProfile, path: String) -> bool:
	if path.is_empty() or profile == null: return false
	history.append(path)
	if history.size() > HISTORY: history = history.slice(history.size() - HISTORY)
	if volume <= 0.0: return false
	var stream := ELAudio.sound(profile, path)
	if stream == null: return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null: return false
	if _player == null or not is_instance_valid(_player):
		_player = AudioStreamPlayer.new()
		_player.name = "InterfaceSounds"
		tree.root.add_child(_player)
	_player.stream = stream
	_player.volume_db = linear_to_db(maxf(0.0001, ELAudio.option_gain(volume, profile.id)))
	_player.play()
	return true

## The effects volume from a settings or volume dictionary.
static func use_volumes(values: Dictionary) -> void:
	volume = clampf(float(values.get("effects", volume)), 0.0, 1.0)
