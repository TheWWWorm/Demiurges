class_name ELCampaign
extends RefCounted
var id := ""
## The campaign document's own id attribute (a GUID in the first game).
var guid := ""
var title := ""
var description := ""
var scenarios: Array[Dictionary] = []
var error := ""

static func available(profile: ELProfile) -> Array[String]:
	var result: Array[String] = []
	for name: String in (["Good", "Evil"] if profile.id == "el1" else ["Green", "Red", "Blue", "Black", "White"]):
		if not profile.file("Campaigns/" + name + ".cpg").is_empty(): result.append(name)
	return result

static func find_scenario(profile: ELProfile, map_id: String, script_name := "") -> Dictionary:
	for campaign_id: String in available(profile):
		var campaign := ELCampaign.new()
		if not campaign.load_campaign(profile, campaign_id): continue
		for scenario: Dictionary in campaign.scenarios:
			if scenario.file_name != map_id: continue
			if not script_name.is_empty() and String(scenario.get("script", "")).replace("\\", "/").to_lower() != script_name.replace("\\", "/").to_lower(): continue
			return scenario.duplicate()
	return {"file_name": map_id, "script": script_name}

func load_campaign(profile: ELProfile, campaign_id: String) -> bool:
	error = ""
	id = campaign_id
	scenarios.clear()
	var path := profile.file("Campaigns/" + id + ".cpg")
	if path.is_empty():
		error = "Missing campaign: " + id
		return false
	var document := ELXml.parse(FileAccess.get_file_as_bytes(path))
	if document.get("tag") != "campaign":
		error = String(document.get("error", "Invalid campaign document."))
		return false
	guid = String(document.attrs.get("id", ""))
	title = profile.text(String(document.attrs.get("name", id)))
	description = profile.text(String(document.attrs.get("description", "")))
	for scenario: Dictionary in ELXml.children(ELXml.child(document, "scenarios"), "scenario"):
		var row: Dictionary = scenario.attrs.duplicate()
		if not row.has("file_name") or profile.file("Maps/" + String(row.file_name) + ".map").is_empty():
			error = "Missing campaign scenario."
			return false
		scenarios.append(row)
	return not scenarios.is_empty()

## First-game chapter score: 1000 adjusted by days against a par for the map
## size, never negative, then scaled by difficulty.
const FIRST_PAR := {20: [7, 100], 40: [30, 30], 80: [45, 20], 120: [60, 15], 160: [100, 10]}
const FIRST_DIFFICULTY := [0.75, 1.0, 1.25, 1.5, 2.0]
const FIRST_FINAL_NUMBER := 9
const FIRST_BRANCH_NUMBER := 7

static func first_score(map_size: int, days: int, difficulty: int) -> int:
	var par: Array = FIRST_PAR.get(map_size, FIRST_PAR[80])
	var chapter := maxi(0, 1000 + (int(par[0]) - days) * int(par[1]))
	return int(roundf(chapter * float(FIRST_DIFFICULTY[clampi(difficulty, 0, 4)])))

## Chapters that follow a finished one. A win advances the chapter number; a loss
## offers the same number again. The final step follows the branch chosen at seven.
func first_next(number: int, branch: int, won: bool) -> Array[Dictionary]:
	var target := number + 1 if won else number
	var result: Array[Dictionary] = []
	if target >= FIRST_FINAL_NUMBER: return result
	for row: Dictionary in scenarios:
		if int(row.get("number", 0)) != target: continue
		if target == FIRST_BRANCH_NUMBER + 1 and branch > 0 and int(row.get("subnumber", 0)) != branch: continue
		result.append(row)
	return result
