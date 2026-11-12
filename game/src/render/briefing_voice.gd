class_name ELBriefingVoice
extends AudioStreamPlayer
## Voiced campaign descriptions and mission briefings, at the effects volume
## over the interface music (both games play them as ordinary samples; the
## music keeps playing).
## First game (Briefings\*.wav in the sound archive):
## - campaign text screen: campaign1.wav for the Evil campaign, campaign2.wav
##   for the other, at once;
## - campaign info screen: the chosen scenario's file name + ".wav", one
##   second after the screen opens, while its description scrolls with the
##   voice (top at the start, bottom at the end).
## Second game (MissionVoices\<text key>.mp3): the text window the campaign
## choice's Info button opens speaks the campaign's description key (the .cpg
## `description`, e.g. MT_E2C_RED_DESC), and the campaign map's Briefing
## button the chapter's briefing key (the scenario's `briefing`, e.g.
## MT_E2C_M11_DESC), at once.
## Leaving the screen stops the voice. A missing file plays nothing.

const EVIL_CAMPAIGN := "{19AB7C81-CF73-4fa8-B4FD-C8B2DC7AC511}"
const INFO_DELAY := 1.0

## Debug (--campaign-probe): every start, stop and missing file is printed.
static var log_events := false
## Recent events: {"time", "event", "path"} ("start", "stop", "end", "missing").
static var events: Array[Dictionary] = []

## The file waiting for its delay, the time left, and the text that follows
## the voice.
var pending := ""
var wait := 0.0
var playing_path := ""
var follow: RichTextLabel
var _profile: ELProfile
var _volume := 1.0

## Campaign text voice for a campaign id.
static func campaign_file(campaign_id: String) -> String:
	return "Briefings/campaign1.wav" if campaign_id.to_upper() == EVIL_CAMPAIGN.to_upper() else "Briefings/campaign2.wav"

## Campaign info voice: the scenario's file name without folder or extension.
static func mission_file(scenario: Dictionary) -> String:
	var file := str(scenario.get("file_name", "")).replace("\\", "/").get_file()
	if file.is_empty(): return ""
	if file.get_extension().length() > 0: file = file.get_basename()
	return "Briefings/" + file + ".wav"

## Second game: the voice of a text key (campaign description or chapter
## briefing); "" for no key.
static func text_file(key: String) -> String:
	key = key.strip_edges()
	return "" if key.is_empty() else "MissionVoices/" + key + ".mp3"

## The stream of a voice file, or null when the archive has none.
static func load_stream(profile: ELProfile, path: String) -> AudioStream:
	if profile == null or path.is_empty(): return null
	if path.get_extension().to_lower() == "mp3":
		var bytes := profile.read("sfx", ELArchive.key(path))
		if bytes.is_empty(): return null
		var mp3 := AudioStreamMP3.new()
		mp3.data = bytes
		return mp3 if mp3.get_length() > 0.0 else null
	return ELAudio.sound(profile, path)

static func note(event: String, path: String) -> void:
	events.append({"time": Time.get_ticks_msec() / 1000.0, "event": event, "path": path})
	if events.size() > 64: events = events.slice(events.size() - 64)
	if log_events: print("[voice] %.3f %s %s" % [Time.get_ticks_msec() / 1000.0, event, path])

func _init() -> void:
	name = "BriefingVoice"
	finished.connect(func():
		if not playing_path.is_empty(): note("end", playing_path)
		playing_path = "")

## Starts `path` after `delay` seconds (0: at once) at `volume` (0..1, the
## effects setting).
func start(profile: ELProfile, path: String, volume: float, delay := 0.0, text: RichTextLabel = null) -> void:
	stop_voice()
	if path.is_empty() or profile == null: return
	_profile = profile
	follow = text
	set_volume(volume)
	pending = path
	wait = delay
	if delay <= 0.0: _begin()

func stop_voice() -> void:
	if not playing_path.is_empty() and playing: note("stop", playing_path)
	pending = ""
	playing_path = ""
	follow = null
	if playing: stop()
	stream = null

func set_volume(volume: float) -> void:
	_volume = clampf(volume, 0.0, 1.0)
	var edition := _profile.id if _profile != null else ""
	volume_db = linear_to_db(maxf(ELAudio.option_gain(_volume, edition), 0.0001))

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
	var sound := load_stream(_profile, path)
	if sound == null:
		note("missing", path)
		return
	stream = sound
	playing_path = path
	play()
	note("start", path)
