class_name ELAutochessCommands
extends RefCounted
## Player actions by name, so the local screen, the host and online guests
## change a company through exactly the same validated operations.

const NAMES := ["buy", "refresh", "train", "lock", "sell", "deploy", "bench", "swap", "equip", "choose_item", "undo", "arrange", "ready", "speed"]

## Applies `op` for `seat`; returns "" or an English error message.
static func apply(game: ELAutochessMatch, seat: int, op: String, args: Array) -> String:
	if game == null or seat < 0 or seat >= game.companies.size() or op not in NAMES: return "Unknown action."
	# The fight speed is shared by the whole table (every machine plays the
	# battles itself), and anyone, eliminated players watching included, may change it.
	if op == "speed":
		game.speed = 2.0 if _float(args, 0) >= 2.0 else 1.0
		game.changed.emit()
		return ""
	var company := game.companies[seat]
	if company.health <= 0: return "You have left the tournament."
	if op in ["deploy", "bench", "swap", "equip", "choose_item", "undo", "arrange", "ready"] and game.stage != "prepare":
		if op != "bench": return "Arrange your army between battles."
	var error := ""
	match op:
		"buy": error = company.buy(_int(args, 0))
		"refresh": error = company.refresh()
		"train": error = company.train()
		"lock": company.lock_offer(_int(args, 0))
		"sell": error = company.sell(_int(args, 0))
		"deploy": error = company.deploy(_int(args, 0), Vector2(_float(args, 1), _float(args, 2)))
		"bench": error = company.bench(_int(args, 0), _int(args, 1, -1))
		"swap": error = company.swap_from_bench(_int(args, 0), _int(args, 1))
		"equip": error = company.equip_item(_int(args, 0), _int(args, 1))
		"choose_item": error = company.choose_item(_int(args, 0))
		"undo": company.undo()
		"arrange": company.arrange()
		"ready": game.set_ready(seat, bool(args[0]) if not args.is_empty() else true)
	if error.is_empty(): game.changed.emit()
	return error

static func _int(args: Array, index: int, fallback := 0) -> int:
	if index >= args.size(): return fallback
	var value: Variant = args[index]
	return int(value) if (value is int or value is float) and is_finite(float(value)) else fallback

static func _float(args: Array, index: int) -> float:
	if index >= args.size(): return NAN
	var value: Variant = args[index]
	return float(value) if value is int or value is float else NAN
