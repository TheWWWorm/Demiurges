class_name ELContentLibrary
extends RefCounted
## Where each edition's original files live on platforms without a normal game
## folder. Desktop builds read an installed folder in place. Android copies the
## player's installer or data pack into app-private storage. The browser keeps
## the player's files in its own storage; the page serves them read-only under
## WEB_ROOT, one folder per edition, so the engine reads them like any folder.

const WEB_ROOT := "/gamedata"
const EDITIONS := ["el1", "el2"]
## Files every edition needs; the campaign file tells the editions apart.
const REQUIRED := ["resources/figures.res", "resources/crfigures.res", "resources/textures.res",
	"resources/regs.res", "resources/text.res"]
const MARKERS := {"el1": "campaigns/good.cpg", "el2": "campaigns/white.cpg"}
## Folders of an installation the engine reads. Top-level files are kept when
## they are archives or settings (EL2 keeps regs.res and text.res there).
const FOLDERS := ["resources", "campaigns", "maps", "duel", "tutorial", "replays"]
const TOP_FILES := ["res", "ini", "hl"]
const PACK_MAGIC := "ELPACK01"


static func title(edition: String) -> String:
	return "Etherlords I" if edition == "el1" else "Etherlords II"


## True where the player imports files instead of choosing a game folder.
static func uses_import() -> bool:
	return OS.has_feature("web") or OS.has_feature("android")


## Whether a lower-case, "/"-separated installation path is worth keeping.
static func wanted(name: String) -> bool:
	var path := name.replace("\\", "/").to_lower()
	if path.contains("/"):
		return path.get_slice("/", 0) in FOLDERS and not path.get_extension() in ["exe", "dll", "asi"]
	return path.get_extension() in TOP_FILES


## The edition whose required files are all in `names` (lower-case keys), or "".
static func detect_names(names: Dictionary) -> String:
	for path: String in REQUIRED:
		if not names.has(path): return ""
	for edition: String in EDITIONS:
		if names.has(MARKERS[edition]): return edition
	return ""


## The edition installed in `folder` (an installed game or an import), or "".
static func detect(folder: String) -> String:
	if not DirAccess.dir_exists_absolute(folder): return ""
	var names := {}
	for directory: String in ["resources", "campaigns"]:
		var actual := _child(folder, directory)
		if actual.is_empty(): continue
		for file in DirAccess.get_files_at(folder.path_join(actual)):
			names[directory + "/" + file.to_lower()] = true
	return detect_names(names)


## Case-insensitive child folder name of `folder`, or "".
static func _child(folder: String, lower: String) -> String:
	for name in DirAccess.get_directories_at(folder):
		if name.to_lower() == lower: return name
	return ""


## The folder that holds an imported edition on this platform.
static func managed_root(edition: String) -> String:
	if OS.has_feature("web"): return WEB_ROOT.path_join(edition)
	return OS.get_user_data_dir().path_join("content").path_join(edition)


## Imported editions present on this device: {edition: folder}.
static func managed_roots() -> Dictionary:
	var result := {}
	if not uses_import(): return result
	if OS.has_feature("web") and web_files() == null: return result
	for edition: String in EDITIONS:
		var root := managed_root(edition)
		if DirAccess.dir_exists_absolute(root): result[edition] = root
	return result


## The page's file bridge (EtherFiles in web/files.js), or null outside it.
static func web_files() -> JavaScriptObject:
	if not OS.has_feature("web"): return null
	return JavaScriptBridge.get_interface("EtherFiles")


## Remove an imported edition. Saves and settings are kept.
static func forget(edition: String) -> void:
	if OS.has_feature("web"):
		var files := web_files()
		if files != null: files.forget(edition)
		return
	remove_tree(managed_root(edition))


static func remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path): return
	for name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
