class_name ELDiscordPresence
extends Node
## Optional Discord activity: shows which game is played and what the player
## does in it (the words come from ELDiscordStatus), through the locally
## running Discord desktop app (its local IPC pipe or socket, opened by the
## native ELDiscordIpc). No account, token or network access is used, and no
## player or save names are published. Desktop builds only; without the
## native library or Discord the node does nothing.
##
## The application ID comes from the project setting discord/application_id;
## DEMIURGES_DISCORD_APP_ID overrides it for testing another application.

const MAX_FRAME := 65528
## Discord accepts about five activity updates in 20 seconds. A new scene
## (another screen, map or battle) is sent after SCENE_SECONDS; changes within
## a scene (a new turn, life lost) wait UPDATE_SECONDS, so a battle never sends
## more than one update in that time.
const UPDATE_SECONDS := 15.0
const SCENE_SECONDS := 5.0
const RETRY_SECONDS := 15.0
## Opcodes of Discord's IPC framing.
const HANDSHAKE := 0
const FRAME := 1
const CLOSE := 2
const PING := 3
const PONG := 4

## Called every couple of seconds for the activity to show ({} for none).
var source: Callable
## The "discord_activity" preference.
var enabled := true
var application_id := ""
var handle := -1
var ready_to_send := false
var incoming := PackedByteArray()
var outgoing := PackedByteArray()
var desired: Dictionary = {}
var sent: Dictionary = {}
## The scene of the activity wanted and of the one sent.
var desired_scene := ""
var sent_scene := ""
## When each current scene began (Unix seconds): the activity's scene and its
## parent, which keeps its time while the scene inside it lasts.
var scene_starts: Dictionary = {}
var next_connect := 0.0
var connected_at := 0.0
var last_send := -INF
var sample_at := 0.0
var started := int(Time.get_unix_time_from_system())
var nonce := 0
var active := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	application_id = OS.get_environment("DEMIURGES_DISCORD_APP_ID").strip_edges()
	if application_id.is_empty(): application_id = str(ProjectSettings.get_setting("discord/application_id", "")).strip_edges()
	active = ClassDB.class_exists("ELDiscordIpc") and DisplayServer.get_name() != "headless" \
		and OS.get_name() in ["Windows", "Linux", "macOS"] and not OS.get_cmdline_args().has("--script")

static func valid_id(value: String) -> bool:
	return value.length() >= 17 and value.length() <= 20 and value.is_valid_int() and value.lstrip("0123456789").is_empty()

## Discord limits these fields to 128 bytes of UTF-8.
static func activity_text(value: String) -> String:
	var text := value.left(128)
	while text.to_utf8_buffer().size() > 128: text = text.left(text.length() - 1)
	return text

## `parts` joined with " · ", leaving out the last ones that do not fit
## Discord's 128 bytes (a single part is cut short instead).
static func fitting(parts: Array) -> String:
	var kept: Array[String] = []
	for part: Variant in parts:
		if not str(part).strip_edges().is_empty(): kept.append(str(part).strip_edges())
	while kept.size() > 1 and " · ".join(kept).to_utf8_buffer().size() > 128: kept.pop_back()
	return activity_text(" · ".join(kept))

## An activity: what is played (`details`) and what is happening (`state`),
## timed from the start of its `scene` (or of the game without one). A scene
## inside another (a battle on a map) names it as `parent`: the parent keeps
## its start while the inner scene lasts.
func activity(details: String, state := "", scene := "", parent := "") -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var starts := {}
	for key: String in [parent, scene]:
		if not key.is_empty(): starts[key] = scene_starts.get(key, now)
	scene_starts = starts
	desired_scene = scene
	var result := {"details": activity_text(details), "timestamps": {"start": scene_starts.get(scene, started)}, "instance": false}
	if not state.is_empty(): result.state = activity_text(state)
	return result

func _process(_delta: float) -> void:
	if not active: return
	var now := Time.get_ticks_msec() / 1000.0
	if not enabled or not valid_id(application_id):
		if _open():
			if ready_to_send: _set_activity({})
			_flush()
			_disconnect(now)
		return
	if now >= sample_at:
		sample_at = now + 2.0
		desired_scene = ""
		desired = source.call() if source.is_valid() else {}
	if not _open():
		if now < next_connect: return
		next_connect = now + RETRY_SECONDS
		for path: String in ipc_paths():
			handle = int(_ipc("open", [path]))
			if handle >= 0:
				connected_at = now
				ready_to_send = false
				incoming.clear()
				outgoing.clear()
				sent.clear()
				_send(HANDSHAKE, {"v": 1, "client_id": application_id})
				break
		if not _open(): return
	_flush()
	incoming.append_array(_ipc("read", [handle]))
	if not _open() or incoming.size() > MAX_FRAME + 8:
		_disconnect(now)
		return
	while incoming.size() >= 8:
		var opcode := incoming.decode_u32(0)
		var length := incoming.decode_u32(4)
		if length > MAX_FRAME:
			_disconnect(now)
			return
		if incoming.size() < length + 8: break
		var payload := incoming.slice(8, length + 8)
		incoming = incoming.slice(length + 8)
		match opcode:
			PING: _send_bytes(PONG, payload)
			FRAME:
				var data: Variant = JSON.parse_string(payload.get_string_from_utf8())
				if data is not Dictionary or data.get("evt") == "ERROR":
					_disconnect(now)
					return
				if data.get("evt") == "READY": ready_to_send = true
			_:
				_disconnect(now)
				return
	if not ready_to_send and now - connected_at > 10.0:
		_disconnect(now)
		return
	var wait := SCENE_SECONDS if desired_scene != sent_scene else UPDATE_SECONDS
	if ready_to_send and desired != sent and now - last_send >= wait:
		_set_activity(desired)
		sent = desired.duplicate(true)
		sent_scene = desired_scene
		last_send = now
	_flush()

## The native class is called by name: builds without it (web, Android)
## still load this script.
static func _ipc(method: StringName, args: Array) -> Variant:
	return ClassDB.class_call_static.callv([&"ELDiscordIpc", method] + args)

func _open() -> bool:
	return handle >= 0 and int(_ipc("is_open", [handle])) == 1

func _send(opcode: int, value: Dictionary) -> void:
	_send_bytes(opcode, JSON.stringify(value).to_utf8_buffer())

func _send_bytes(opcode: int, bytes: PackedByteArray) -> void:
	if bytes.size() > MAX_FRAME or outgoing.size() + bytes.size() + 8 > MAX_FRAME + 8:
		_disconnect(Time.get_ticks_msec() / 1000.0)
		return
	var header := PackedByteArray()
	header.resize(8)
	header.encode_u32(0, opcode)
	header.encode_u32(4, bytes.size())
	outgoing.append_array(header)
	outgoing.append_array(bytes)

func _set_activity(value: Dictionary) -> void:
	nonce += 1
	_send(FRAME, {"cmd": "SET_ACTIVITY", "args": {"pid": OS.get_process_id(), "activity": null if value.is_empty() else value}, "nonce": str(nonce)})

func _flush() -> void:
	if outgoing.is_empty() or not _open(): return
	var count := int(_ipc("write", [handle, outgoing]))
	if count > 0: outgoing = outgoing.slice(count)
	elif count < 0: _disconnect(Time.get_ticks_msec() / 1000.0)

func _disconnect(now: float) -> void:
	if handle >= 0: _ipc("close", [handle])
	handle = -1
	ready_to_send = false
	incoming.clear()
	outgoing.clear()
	sent.clear()
	last_send = -INF
	next_connect = now + RETRY_SECONDS

func _exit_tree() -> void:
	if not _open(): return
	if ready_to_send:
		_set_activity({})
		_flush()
	_ipc("close", [handle])
	handle = -1

## Where the Discord desktop app listens: its numbered pipes on Windows, its
## sockets in the runtime or temporary folder elsewhere (also inside the
## Flatpak and Snap app folders).
static func ipc_paths() -> Array[String]:
	var paths: Array[String] = []
	if OS.get_name() == "Windows":
		for i in 10: paths.append("\\\\.\\pipe\\discord-ipc-%d" % i)
		return paths
	var roots: Array[String] = []
	for key: String in ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"]:
		var value := OS.get_environment(key)
		if value.is_absolute_path() and value not in roots: roots.append(value)
	if "/tmp" not in roots: roots.append("/tmp")
	for root: String in roots:
		for folder: String in [root, root.path_join("app/com.discordapp.Discord"), root.path_join("snap.discord")]:
			for i in 10: paths.append(folder.path_join("discord-ipc-%d" % i))
	return paths
