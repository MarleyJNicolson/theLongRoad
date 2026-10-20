class_name Scoreboard
extends RefCounted

# The scoreboard (port of scoreboard.js): a plain text file, a ranked table
# you can read or edit by hand, which is also where the scores are read back
# from (rows split on `|`). Same layout as the JS version's scoreboard.txt, so
# an old board can be copied over. Your last name is kept in settings.cfg.

const FILE := "user://scoreboard.txt"
const SETTINGS := "user://settings.cfg"
const KEEP := 100 # runs kept on the board
const COLUMNS := ["Rank", "Name", "Score", "Distance", "Felled", "Gold", "Region", "Fate", "Date"]


static func score(run: Dictionary) -> int:
	return run.distance + run.kills * 20 + run.gold * 5


static func read() -> Array:
	var runs := []
	if not FileAccess.file_exists(FILE):
		return runs
	var row := RegEx.create_from_string("^\\s*\\d+\\s*\\|")
	for line in FileAccess.get_file_as_string(FILE).split("\n"):
		if not row.search(line):
			continue
		var c := Array(line.split("|")).map(func(s: String) -> String: return s.strip_edges())
		if c.size() < 9:
			continue
		runs.append({"name": c[1], "score": int(c[2]), "distance": int(c[3]), "kills": int(c[4]), "gold": int(c[5]),
			"region": c[6], "fate": c[7], "date": c[8]})
	return runs


static func write(runs: Array) -> void:
	var rows := []
	for k in runs.size():
		var r: Dictionary = runs[k]
		rows.append([str(k + 1), r.name, str(r.score), "%d m" % r.distance, str(r.kills), str(r.gold), r.region, r.fate, r.date])
	var widths := []
	for i in COLUMNS.size():
		var w: int = COLUMNS[i].length()
		for row in rows:
			w = maxi(w, row[i].length())
		widths.append(w)
	var line := func(cells: Array) -> String:
		var out := []
		for i in cells.size():
			# Numbers line up on the right
			var right := i == 0 or (i >= 2 and i < 6)
			out.append(cells[i].lpad(widths[i]) if right else cells[i].rpad(widths[i]))
		return " | ".join(out)
	var text := ["SCOREBOARD", "Score = metres travelled + 20 per raider felled + 5 per gold piece", "", line.call(COLUMNS),
		"-+-".join(widths.map(func(w: int) -> String: return "-".repeat(w)))]
	for row in rows:
		text.append(line.call(row))
	text.append("")
	var file := FileAccess.open(FILE, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(text))


# Put a finished run on the board: { name, distance, kills, gold, region, fate }.
# Returns { rank (0 if it didn't make the board), entry, top }.
static func add(run: Dictionary) -> Dictionary:
	var clean := func(s: Variant) -> String: return str(s).replace("|", " ").replace("\n", " ").left(60)
	var entry := {
		"name": clean.call(run.name).left(20).strip_edges(),
		"distance": maxi(0, run.distance),
		"kills": maxi(0, run.kills),
		"gold": maxi(0, run.gold),
		"region": clean.call(run.region),
		"fate": clean.call(run.fate),
		"date": _now(),
	}
	if entry.name == "":
		entry.name = "Anonymous"
	entry.score = score(entry)
	var runs := read()
	runs.append(entry)
	runs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	runs = runs.slice(0, KEEP)
	write(runs)
	return {"rank": runs.find(entry) + 1, "entry": entry, "top": runs.slice(0, 10)}


# e.g. 2026-10-19 18:25, local time
static func _now() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]


static func last_name() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) != OK:
		return ""
	return cfg.get_value("scoreboard", "name", "")


static func remember_name(name: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("scoreboard", "name", name)
	cfg.save(SETTINGS)
