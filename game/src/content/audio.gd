class_name ELAudio
extends RefCounted
## External RIFF PCM / Microsoft IMA ADPCM. The block decoder is shared with
## the companion EI remake; caches belong to the selected edition.

const INDEX_TABLE := [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]
const MS_ADAPT := [230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230]
const STEP_TABLE := [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60,
	66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494,
	544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024,
	3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289,
	16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]

const POSITIONAL_BUS := &"Positional"

## Bus for sounds placed in the scene. The Options "reverse stereo" switch
## mirrors their left/right placement (an inverted stereo enhance swaps the
## channels); music and interface sounds are not placed and stay as they are.
static func positional_bus(reverse: bool) -> StringName:
	var index := AudioServer.get_bus_index(POSITIONAL_BUS)
	if index < 0:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, POSITIONAL_BUS)
		AudioServer.set_bus_send(index, &"Master")
		var swap := AudioEffectStereoEnhance.new()
		swap.pan_pullout = -1.0
		AudioServer.add_bus_effect(index, swap)
	AudioServer.set_bus_effect_enabled(index, 0, reverse)
	return POSITIONAL_BUS

## Quits after stopping every sound. A stopped stream is only released on
## the audio thread's next mix, so quitting in the same frame left music and
## ambience streams alive at exit (leak warnings in the log).
static func quiet_quit(tree: SceneTree) -> void:
	for node: Node in tree.root.find_children("*", "AudioStreamPlayer", true, false) + tree.root.find_children("*", "AudioStreamPlayer3D", true, false):
		node.stop()
		node.stream = null
	for frame in 3: await tree.process_frame
	await tree.create_timer(0.05, true, false, true).timeout
	tree.quit()

## Stereo placement of a sound in both games: the angle between
## the listener's level forward direction and the ground-plane direction to
## the source sets the pan, centred ahead or behind and fully to one side at
## a right angle (±100 as whole numbers, sent to the mixer as (p + 100) / 200).
## Returns -1 (left) .. 1 (right) for an AudioEffectPanner.
static func stereo_pan(listener: Vector3, forward: Vector3, source: Vector3) -> float:
	var to := Vector2(source.x - listener.x, source.z - listener.z)
	var ahead := Vector2(forward.x, forward.z)
	var distance := to.length()
	if distance <= 0.0 or ahead.length() <= 0.0: return 0.0
	ahead = ahead.normalized()
	var along := absf(to.dot(ahead))
	if along > distance: return 0.0
	var amount := roundi(100.0 / (PI / 2.0) * acos(along / distance))
	# Right of the listener: forward (x, z) turned a quarter to (-z, x).
	var right := Vector2(-ahead.y, ahead.x)
	return (amount if to.dot(right) >= 0.0 else -amount) / 100.0

## A bus with its own panner for one placed voice, sent through the
## positional bus (and so through the reverse-stereo switch).
static func pan_bus(name: String, reverse: bool) -> StringName:
	var through := positional_bus(reverse)
	var bus := StringName("Positional " + name)
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, through)
		AudioServer.add_bus_effect(index, AudioEffectPanner.new())
		AudioServer.add_bus_effect(index, AudioEffectAmplify.new())
	return bus

## Sets a placed voice's pan (-1..1, from stereo_pan) the way each game's
## mixer applies it. The first game's mixer (Miles 5) keeps the near side at
## full level and fades the far side linearly, which is the panner's balance.
## The second game's (Miles 6.5) gives the left side (1 - q)^0.3 and the right
## q^0.3 of the level, q = (pan + 1) / 2; every sound in that game is sent
## centred (q = 0.5) unless placed, so the gains are taken relative to the
## centre value and built from the panner's balance plus a boost.
static func set_pan(bus: StringName, pan: float, edition := "") -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0: return
	var panner := AudioServer.get_bus_effect(index, 0) as AudioEffectPanner
	var boost := AudioServer.get_bus_effect(index, 1) as AudioEffectAmplify if AudioServer.get_bus_effect_count(index) > 1 else null
	var balance := clampf(pan, -1.0, 1.0)
	var gain := 1.0
	if edition == "el2":
		var gains := channel_gains(balance, edition)
		var near := maxf(gains.x, gains.y)
		var far := minf(gains.x, gains.y)
		gain = near
		balance = signf(balance) * (1.0 - far / near) if near > 0.0 else 0.0
	if panner != null: panner.pan = balance
	if boost != null: boost.volume_db = linear_to_db(gain)

## Left and right level of a pan in each game's mixer (centre = 1, 1).
static func channel_gains(pan: float, edition := "") -> Vector2:
	pan = clampf(pan, -1.0, 1.0)
	if edition == "el2":
		var q := (pan + 1.0) / 2.0
		var centre := pow(0.5, 0.3)
		return Vector2(pow(1.0 - q, 0.3), pow(q, 0.3)) / centre
	return Vector2(clampf(1.0 - pan, 0.0, 1.0), clampf(1.0 + pan, 0.0, 1.0))

## The level of a Music or Sound slider (0..1). The second game sends the
## option times the sound's own level to its mixer as the volume, which the
## mixer raises to the power 5/3;
## the first game's mixer applies its volume as it is.
static func option_gain(value: float, edition := "") -> float:
	return placed_gain(value, edition)

## A placed sound's level from its distance fade (0..1). The second game's
## mixer raises the volume it is given to the power 5/3; the first game's
## applies it as it is.
static func placed_gain(fade: float, edition := "") -> float:
	fade = clampf(fade, 0.0, 1.0)
	return pow(fade, 5.0 / 3.0) if edition == "el2" else fade

static func sound(profile: ELProfile, path: String) -> AudioStreamWAV:
	var key := ELArchive.key(path)
	if profile.sound_cache.has(key): return profile.sound_cache[key]
	var stream := decode_wav(profile.read("sfx", key))
	if stream != null:
		while profile.sound_bytes + stream.data.size() > 32 * 1024 * 1024 and not profile.sound_cache.is_empty():
			var oldest: String = profile.sound_cache.keys()[0]
			var old: AudioStreamWAV = profile.sound_cache[oldest]
			if old != null: profile.sound_bytes -= old.data.size()
			profile.sound_cache.erase(oldest)
		profile.sound_bytes += stream.data.size()
	profile.sound_cache[key] = stream
	return stream

static func decode_wav(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE": return null
	var format := 0
	var channels := 0
	var rate := 0
	var align := 0
	var bits := 0
	var samples := 0
	var coefficients := PackedInt32Array()
	var pcm := PackedByteArray()
	var offset := 12
	while offset + 8 <= bytes.size():
		var id := bytes.slice(offset, offset + 4).get_string_from_ascii()
		var size := bytes.decode_u32(offset + 4)
		if offset + 8 + size > bytes.size(): return null
		var start := offset + 8
		if id == "fmt ":
			if size < 16: return null
			format = bytes.decode_u16(start)
			channels = bytes.decode_u16(start + 2)
			rate = bytes.decode_u32(start + 4)
			align = bytes.decode_u16(start + 12)
			bits = bytes.decode_u16(start + 14)
			if format == 2:
				if size < 22: return null
				var count := bytes.decode_u16(start + 20)
				if count < 1 or 22 + count * 4 > size: return null
				for i in count * 2: coefficients.append(bytes.decode_s16(start + 22 + i * 2))
		elif id == "fact" and size >= 4: samples = bytes.decode_u32(start)
		elif id == "data": pcm = bytes.slice(start, start + size)
		offset += 8 + size + (size & 1)
	if channels not in [1, 2] or rate < 1 or rate > 192000 or pcm.is_empty(): return null
	var stream := AudioStreamWAV.new()
	stream.mix_rate = rate
	stream.stereo = channels == 2
	if format == 17 and bits == 4:
		pcm = _ima_decode(pcm, align, channels)
		if samples > 0 and samples * channels * 2 < pcm.size(): pcm.resize(samples * channels * 2)
		stream.format = AudioStreamWAV.FORMAT_16_BITS
	elif format == 2 and bits == 4:
		pcm = _ms_decode(pcm, align, channels, coefficients)
		if samples > 0 and samples * channels * 2 < pcm.size(): pcm.resize(samples * channels * 2)
		stream.format = AudioStreamWAV.FORMAT_16_BITS
	elif format == 1 and bits in [8, 16]:
		stream.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
		if bits == 8:
			for i in pcm.size(): pcm[i] = (pcm[i] - 128) & 0xff
	else: return null
	if pcm.is_empty(): return null
	stream.data = pcm
	return stream

static func _ms_decode(src: PackedByteArray, align: int, channels: int, coefficients: PackedInt32Array) -> PackedByteArray:
	var header := channels * 7
	if align <= header: return PackedByteArray()
	var output := PackedByteArray()
	var total := 0
	for pos in range(0, src.size() - header + 1, align):
		total += channels * 2 + (mini(pos + align, src.size()) - pos - header) * 2
	output.resize(total * 2)
	var at := 0
	for pos in range(0, src.size() - header + 1, align):
		var predictors: Array[int] = []
		var deltas: Array[int] = []
		var first: Array[int] = []
		var second: Array[int] = []
		for c in channels:
			if src[pos + c] * 2 + 1 >= coefficients.size(): return PackedByteArray()
			predictors.append(src[pos + c] * 2)
			deltas.append(maxi(16, src.decode_u16(pos + channels + c * 2)))
			first.append(src.decode_s16(pos + channels * 3 + c * 2))
			second.append(src.decode_s16(pos + channels * 5 + c * 2))
		for values in [second, first]:
			for sample: int in values:
				output.encode_s16(at, sample)
				at += 2
		for i in range(pos + header, mini(pos + align, src.size())):
			for shift: int in [4, 0]:
				var c := 1 if channels == 2 and shift == 0 else 0
				var nibble := (src[i] >> shift) & 15
				var signed_nibble := nibble - 16 if nibble >= 8 else nibble
				var prediction: int = (first[c] * coefficients[predictors[c]] + second[c] * coefficients[predictors[c] + 1]) >> 8
				var sample := clampi(prediction + signed_nibble * deltas[c], -32768, 32767)
				second[c] = first[c]
				first[c] = sample
				deltas[c] = maxi(16, (MS_ADAPT[nibble] * deltas[c]) / 256)
				output.encode_s16(at, sample)
				at += 2
	return output

static func _ima_decode(src: PackedByteArray, align: int, channels: int) -> PackedByteArray:
	if align <= 4 * channels:
		return PackedByteArray()
	_tables()
	var dtab := _diff_tab
	var ntab := _next_tab
	var hdr := 4 * channels
	# Output size: each block gives its header samples plus two per mono body
	# byte, or eight per channel per 4-byte group in stereo.
	var total := 0
	var pos := 0
	while pos + hdr <= src.size():
		var blen := mini(src.size(), pos + align) - pos
		pos += align
		var body := blen - hdr
		total += channels + (body * 2 if channels == 1 else (body / (4 * channels)) * 8 * channels)
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	var o := 0
	pos = 0
	while pos + hdr <= src.size():
		var bend := mini(src.size(), pos + align)
		var start := o
		if channels == 1:
			var pred := src.decode_s16(pos)
			var idx := clampi(src[pos + 2], 0, 88)
			bytes.encode_s16(o, pred)
			o += 2
			for i in range(pos + 4, bend):
				var b := src[i]
				var k := (idx << 4) | (b & 0x0f)
				pred = clampi(pred + dtab[k], -32768, 32767)
				idx = ntab[k]
				bytes.encode_s16(o, pred)
				k = (idx << 4) | (b >> 4)
				pred = clampi(pred + dtab[k], -32768, 32767)
				idx = ntab[k]
				bytes.encode_s16(o + 2, pred)
				o += 4
		else:
			var pred := PackedInt32Array()
			var idx := PackedInt32Array()
			pred.resize(channels)
			idx.resize(channels)
			for c in channels:
				pred[c] = src.decode_s16(pos + c * 4)
				idx[c] = clampi(src[pos + c * 4 + 2], 0, 88)
				bytes.encode_s16(o, pred[c])
				o += 2
			# Stereo: 4 bytes (8 samples) per channel, interleaved.
			var body := pos + hdr
			var groups := (bend - body) / (4 * channels)
			for g in groups:
				for c in channels:
					var p := pred[c]
					var x := idx[c]
					var at := o + c * 2
					for kk in 4:
						var b := src[body + g * 4 * channels + c * 4 + kk]
						var k := (x << 4) | (b & 0x0f)
						p = clampi(p + dtab[k], -32768, 32767)
						x = ntab[k]
						bytes.encode_s16(at, p)
						at += channels * 2
						k = (x << 4) | (b >> 4)
						p = clampi(p + dtab[k], -32768, 32767)
						x = ntab[k]
						bytes.encode_s16(at, p)
						at += channels * 2
					pred[c] = p
					idx[c] = x
				o += 16 * channels
		pos += align
		if start == o:
			break
	return bytes


static var _diff_tab := PackedInt32Array()
static var _next_tab := PackedInt32Array()


## Signed predictor change and next step index for every (index, nibble).
static func _tables() -> void:
	if not _diff_tab.is_empty():
		return
	_diff_tab.resize(89 * 16)
	_next_tab.resize(89 * 16)
	for idx in 89:
		for nib in 16:
			var step: int = STEP_TABLE[idx]
			var diff := step >> 3
			if nib & 4:
				diff += step
			if nib & 2:
				diff += step >> 1
			if nib & 1:
				diff += step >> 2
			_diff_tab[(idx << 4) | nib] = -diff if nib & 8 else diff
			_next_tab[(idx << 4) | nib] = clampi(idx + INDEX_TABLE[nib], 0, 88)
