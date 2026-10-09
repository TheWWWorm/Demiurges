class_name ELBriefingVoice
extends AudioStreamPlayer
## First game's voiced briefings (Briefings\*.wav in the sound archive), at
## the effects volume over the interface music:
## - campaign text screen: campaign1.wav for the Evil campaign, campaign2.wav
##   for the other, at once;
## - campaign info screen: the chosen scenario's file name + ".wav", one
##   second after the screen opens, while its description scrolls with the
##   voice (top at the start, bottom at the end).
## Leaving the screen stops the voice.

const EVIL_CAMPAIGN := "{19AB7C81-CF73-4fa8-B4FD-C8B2DC7AC511}"
const INFO_DELAY := 1.0

## The file waiting for its delay, the time left, and the text that follows
## the voice.
var pending := ""
var wait := 0.0
var playing_path := ""
var follow: RichTextLabel
var _profile: ELProfile

## Campaign text voice for a campaign id.
static func campaign_file(campaign_id: String) -> String:
	return "Briefings/campaign1.wav" if campaign_id.to_upper() == EVIL_CAMPAIGN.to_upper() else "Briefings/campaign2.wav"

## Campaign info voice: the scenario's file name without folder or extension.
static func mission_file(scenario: Dictionary) -> String:
	var file := str(scenario.get("file_name", "")).replace("\\", "/").get_file()
	if file.is_empty(): return ""
	if file.get_extension().length() > 0: file = file.get_basename()
	return "Briefings/" + file + ".wav"

func _init() -> void:
	name = "BriefingVoice"

## Starts `path` after `delay` seconds (0: at once) at `volume` (0..1).
func start(profile: ELProfile, path: String, volume: float, delay := 0.0, text: RichTextLabel = null) -> void:
	stop_voice()
	if path.is_empty() or profile == null: return
	_profile = profile
	follow = text
	volume_db = linear_to_db(maxf(volume, 0.0001))
	pending = path
	wait = delay
	if delay <= 0.0: _begin()

func stop_voice() -> void:
	pending = ""
	playing_path = ""
	follow = null
	if playing: stop()
	stream = null

func set_volume(volume: float) -> void:
	volume_db = linear_to_db(maxf(volume, 0.0001))

## The briefing heard now ("" for none).
func current() -> String:
	return playing_path if playing else ""

func _process(delta: float) -> void:
	if not pending.is_empty():
		wait -= delta
		if wait <= 0.0: _begin()
		return
	if not playing or follow == null or not is_instance_valid(follow) or stream == null: return
	var length := stream.get_length()
	if length <= 0.0: return
	var bar := follow.get_v_scroll_bar()
	bar.value = (bar.max_value - bar.page) * clampf(get_playback_position() / length, 0.0, 1.0)

func _begin() -> void:
	var path := pending
	pending = ""
	var sound := ELAudio.sound(_profile, path)
	if sound == null:
		push_warning("Briefing not found: " + path)
		return
	stream = sound
	playing_path = path
	play()
