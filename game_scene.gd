extends Control
# ============================================================
# PRISON IDLE TYCOON — Godot 4.7 Monolithic Port
# Attach this script to a Control node (root of the scene).
# Android-ready. Uses touch-friendly UI. Saves to user://
# ============================================================

const TICK_SEC := 1.0            # 1 sec = 1 in-game hour
const HOURS_PER_DAY := 24
const SAVE_PATH := "user://prison_idle_save.json"

# ---------- Colors ----------
const C_BG     := Color("#0f0d0b")
const C_PANEL  := Color("#1a1715")
const C_PANEL2 := Color("#241f1c")
const C_LINE   := Color("#3a322c")
const C_AMBER  := Color("#f59e0b")
const C_TEXT   := Color("#f0ece8")
const C_DIM    := Color("#9c948c")
const C_GOOD   := Color("#34d399")
const C_WARN   := Color("#fbbf24")
const C_BAD    := Color("#f87171")
const C_DARK   := Color("#1a1206")

# ============================================================
# DATA
# ============================================================
var BUILDINGS := [
	{"id":"cell",      "name":"Cell Block",   "icon":"BED", "base":600.0,  "growth":1.28, "desc":"+4 inmate capacity"},
	{"id":"canteen",   "name":"Canteen",      "icon":"FOOD","base":900.0,  "growth":1.34, "desc":"Feeds 8 inmates"},
	{"id":"shower",    "name":"Shower Block", "icon":"SHWR","base":750.0,  "growth":1.34, "desc":"Hygiene for 8 inmates"},
	{"id":"yard",      "name":"Exercise Yard","icon":"YARD","base":1000.0, "growth":1.34, "desc":"Recreation for 8 inmates"},
	{"id":"infirmary", "name":"Infirmary",    "icon":"MED", "base":1600.0, "growth":1.38, "desc":"Medical care for 6 inmates"},
	{"id":"guardpost", "name":"Guard Post",   "icon":"GRD", "base":1300.0, "growth":1.34, "desc":"Security for 10 inmates"},
	{"id":"workshop",  "name":"Workshop",     "icon":"WRK", "base":2500.0, "growth":1.42, "desc":"5 jobs - $25/day each"},
	{"id":"laundry",   "name":"Laundry",      "icon":"LND", "base":1800.0, "growth":1.40, "desc":"4 jobs - $16/day each"},
]

var STAFF := [
	{"id":"guard",   "name":"Guard",   "icon":"G", "wage":140.0, "desc":"+8 security coverage"},
	{"id":"cook",    "name":"Cook",    "icon":"C", "wage":100.0, "desc":"+6 food coverage"},
	{"id":"janitor", "name":"Janitor", "icon":"J", "wage":80.0,  "desc":"+6 hygiene coverage"},
	{"id":"doctor",  "name":"Doctor",  "icon":"D", "wage":180.0, "desc":"+5 medical coverage"},
	{"id":"foreman", "name":"Foreman", "icon":"F", "wage":150.0, "desc":"+20% prison labour income"},
]

var UPGRADES := [
	{"id":"food",    "name":"Nutrition Program", "cost":6000.0,  "desc":"+30% food coverage"},
	{"id":"scanner", "name":"Metal Detectors",   "cost":9000.0,  "desc":"+30% security coverage"},
	{"id":"trade",   "name":"Trade Contracts",   "cost":14000.0, "desc":"+35% prison labour income"},
	{"id":"solar",   "name":"Solar Panels",      "cost":18000.0, "desc":"-35% utility costs"},
	{"id":"cctv",    "name":"CCTV Network",      "cost":22000.0, "desc":"Danger rises 40% slower"},
	{"id":"rehab",   "name":"Rehab Program",     "cost":30000.0, "desc":"+25% government grant"},
	{"id":"union",   "name":"Staff Union Deal",  "cost":45000.0, "desc":"-20% staff wages"},
	{"id":"maxsec",  "name":"Max Security Wing", "cost":60000.0, "desc":"+50% government grant"},
]

var TABS := [
	{"id":"prison",  "label":"Prison"},
	{"id":"build",   "label":"Build"},
	{"id":"staff",   "label":"Staff"},
	{"id":"upgrade", "label":"Upgrade"},
	{"id":"stats",   "label":"Stats"},
]

# ============================================================
# STATE
# ============================================================
var state: Dictionary = {}

# ============================================================
# UI REFERENCES
# ============================================================
var ui_money: Dictionary
var ui_day: Dictionary
var ui_pop: Dictionary
var hud_sat_bar: ProgressBar
var hud_dgr_bar: ProgressBar
var hud_sat_lbl: Label
var hud_dgr_lbl: Label
var view_vbox: VBoxContainer
var view_scroll: ScrollContainer
var tab_btns: Dictionary = {}

var _tick_acc: float = 0.0
var _save_acc: float = 0.0
var _view_refresh_acc: int = 0

var rewarded_ad: RewardedAd
var rewarded_load_callback := RewardedAdLoadCallback.new()


# ============================================================
# LIFECYCLE
# ============================================================
func _ready() -> void:
	MobileAds.initialize()
	
	rewarded_load_callback.on_ad_loaded = func(ad:RewardedAd):
		rewarded_ad = ad
		print("rewarded ad loaded success")
	rewarded_load_callback.on_ad_failed_to_load = func(error: LoadAdError):
		print("failed to load ad", error.message)
	randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

	if not _load_game():
		state = _default_state()
		_add_log("Prison opened. 6 inmates transferred in.", "good")
		_add_log("Tip: keep every need above 60% to avoid riots.", "dim")
	else:
		_apply_offline()
		_add_log("Welcome back, Warden.", "dim")

	_refresh_tabs()
	_refresh_view()
	_update_hud()
	_load_rewarded_ad()

func _process(delta: float) -> void:
	_tick_acc += delta
	while _tick_acc >= TICK_SEC:
		_tick_acc -= TICK_SEC
		_tick()

	_save_acc += delta
	if _save_acc >= 10.0:
		_save_acc = 0.0
		_save_game()

	_view_refresh_acc += 1
	if _view_refresh_acc >= 3:
		_view_refresh_acc = 0
		_update_hud()
		_refresh_view()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED \
	or what == NOTIFICATION_WM_CLOSE_REQUEST \
	or what == NOTIFICATION_WM_GO_BACK_REQUEST \
	or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_save_game()
	elif what == NOTIFICATION_APPLICATION_RESUMED \
	  or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_apply_offline()
		_update_hud()
		_refresh_view()

# ============================================================
# DEFAULT STATE
# ============================================================
func _default_state() -> Dictionary:
	return {
		"money": 4000.0,
		"day": 1,
		"hour": 6,
		"reputation": 50.0,
		"satisfaction": 92.0,
		"danger": 4.0,
		"population": 6,
		"buildings": {"cell":2, "canteen":1, "shower":1, "yard":1, "guardpost":1, "infirmary":1},
		"staff": {},
		"upgrades": {},
		"totals": {"earned":0.0, "spent":0.0, "intake":0, "released":0,
				   "escapes":0, "riots":0, "built":0},
		"log": [],
		"tab": "prison",
		"last_save": Time.get_unix_time_from_system(),
	}

# ============================================================
# ACCESSORS
# ============================================================
func _bcount(id: String) -> int:
	return int(state["buildings"].get(id, 0))

func _scount(id: String) -> int:
	return int(state["staff"].get(id, 0))

func _has_up(id: String) -> bool:
	return state["upgrades"].has(id) and state["upgrades"][id]

func _total_buildings() -> int:
	var s := 0
	for v in state["buildings"].values():
		s += int(v)
	return s

func _building_cost(b: Dictionary) -> float:
	return floor(b["base"] * pow(b["growth"], _bcount(b["id"])))

# ============================================================
# FORMATTING
# ============================================================
func _fmt(n: float) -> String:
	var neg := n < 0.0
	n = abs(n)
	var out := ""
	if n < 1000.0:
		out = str(int(floor(n)))
	else:
		var units := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx"]
		var i := 0
		while n >= 1000.0 and i < units.size() - 1:
			n /= 1000.0
			i += 1
		var dec := 2 if n < 10.0 else (1 if n < 100.0 else 0)
		out = ("%.*f%s" % [dec, n, units[i]])
	return ("-$" if neg else "$") + out

# ============================================================
# DERIVED / ECONOMY
# ============================================================
func _derived() -> Dictionary:
	var pop: float = max(1.0, float(state["population"]))

	var food_cap    := (_bcount("canteen")  * 8.0 + _scount("cook")    * 6.0) * (1.3 if _has_up("food") else 1.0)
	var hygiene_cap := (_bcount("shower")   * 8.0 + _scount("janitor") * 6.0)
	var rec_cap     := (_bcount("yard")     * 8.0)
	var health_cap  := (_bcount("infirmary")* 6.0 + _scount("doctor")  * 5.0)
	var sec_cap     := (_bcount("guardpost")* 10.0 + _scount("guard")  * 8.0) * (1.3 if _has_up("scanner") else 1.0)

	var needs := [
		{"id":"food",     "label":"Food",       "score": clampf(food_cap    / pop * 100.0, 0.0, 100.0)},
		{"id":"hygiene",  "label":"Hygiene",    "score": clampf(hygiene_cap / pop * 100.0, 0.0, 100.0)},
		{"id":"rec",      "label":"Recreation", "score": clampf(rec_cap     / pop * 100.0, 0.0, 100.0)},
		{"id":"health",   "label":"Health",     "score": clampf(health_cap  / pop * 100.0, 0.0, 100.0)},
		{"id":"security", "label":"Security",   "score": clampf(sec_cap     / pop * 100.0, 0.0, 100.0)},
	]

	var capacity := _bcount("cell") * 4
	var job_slots := _bcount("workshop") * 5 + _bcount("laundry") * 4
	var job_value := _bcount("workshop") * 5.0 * 25.0 + _bcount("laundry") * 4.0 * 16.0

	var wage_mult := 0.8 if _has_up("union") else 1.0
	var wages := 0.0
	for s in STAFF:
		wages += float(_scount(s["id"])) * float(s["wage"]) * wage_mult

	var grant_per := (60.0 + float(state["reputation"]) * 0.6) \
		* (1.0 + (0.25 if _has_up("rehab") else 0.0) + (0.5 if _has_up("maxsec") else 0.0))
	var grant_income := float(state["population"]) * grant_per

	var active_jobs := int(min(job_slots, floor(float(state["population"]) * 0.7)))
	var job_income := 0.0
	if job_slots > 0:
		job_income = (job_value / float(job_slots)) * float(active_jobs) \
			* (1.35 if _has_up("trade") else 1.0) \
			* (1.0 + float(_scount("foreman")) * 0.2)

	var food_cost := float(state["population"]) * 9.0
	var utility := (float(state["population"]) * 3.0 + float(_total_buildings()) * 6.0) \
		* (0.65 if _has_up("solar") else 1.0)

	var expenses := wages + food_cost + utility
	var net := grant_income + job_income - expenses

	return {
		"needs": needs, "capacity": capacity,
		"grant_income": grant_income, "job_income": job_income,
		"wages": wages, "food_cost": food_cost, "utility": utility,
		"expenses": expenses, "net": net,
		"job_slots": job_slots, "active_jobs": active_jobs,
		"grant_per": grant_per,
	}

# ============================================================
# LOG
# ============================================================
func _add_log(msg: String, cls: String = "") -> void:
	state["log"].push_front({"d": state["day"], "m": msg, "c": cls})
	if state["log"].size() > 40:
		state["log"].resize(40)

# ============================================================
# ACTIONS
# ============================================================
func _buy_building(id: String) -> void:
	for b in BUILDINGS:
		if b["id"] == id:
			var cost := _building_cost(b)
			if state["money"] < cost:
				return
			state["money"] -= cost
			state["totals"]["spent"] += cost
			state["totals"]["built"] += 1
			state["buildings"][id] = _bcount(id) + 1
			_add_log("Built a %s for %s." % [b["name"], _fmt(cost)], "dim")
			Input.vibrate_handheld(15)
			return


func _hire_staff(id: String) -> void:
	for s in STAFF:
		if s["id"] == id:
			var fee: float = float(s["wage"]) * 2.0
			if state["money"] < fee:
				return
			state["money"] -= fee
			state["totals"]["spent"] += fee
			state["staff"][id] = _scount(id) + 1
			_add_log("Hired a %s (fee %s)." % [s["name"], _fmt(fee)], "dim")
			Input.vibrate_handheld(15)
			return


func _fire_staff(id: String) -> void:
	if _scount(id) <= 0:
		return
	state["staff"][id] = _scount(id) - 1
	if int(state["staff"][id]) <= 0:
		state["staff"].erase(id)
	for s in STAFF:
		if s["id"] == id:
			_add_log("A %s was laid off." % s["name"], "warn")
			break


func _buy_upgrade(id: String) -> void:
	if _has_up(id):
		return
	for u in UPGRADES:
		if u["id"] == id:
			if state["money"] < u["cost"]:
				return
			state["money"] -= u["cost"]
			state["totals"]["spent"] += u["cost"]
			state["upgrades"][id] = true
			_add_log("Purchased %s for %s." % [u["name"], _fmt(u["cost"])], "good")
			Input.vibrate_handheld(30)
			return

# ============================================================
# SIMULATION TICK (1 hour)
# ============================================================
func _tick() -> void:
	state["hour"] += 1
	if state["hour"] >= HOURS_PER_DAY:
		state["hour"] = 0
		_end_of_day()

	var d := _derived()

	# Satisfaction chases coverage average
	var target := 0.0
	for n in d["needs"]:
		target += n["score"]
	target /= float(d["needs"].size())
	state["satisfaction"] = lerpf(state["satisfaction"], target, 0.08)

	# Danger
	var sat: float = state["satisfaction"]
	var dgr: float = state["danger"]
	if sat < 55.0:
		dgr += (55.0 - sat) * 0.01 * (0.6 if _has_up("cctv") else 1.0)
	else:
		dgr -= 0.25
	state["danger"] = clampf(dgr, 0.0, 100.0)

	# Reputation drifts to satisfaction
	state["reputation"] = clampf(
		float(state["reputation"]) + (sat - float(state["reputation"])) * 0.012,
		0.0, 100.0)

	# Money accrues hourly
	var hourly: float = float(d["net"]) / float(HOURS_PER_DAY)
	state["money"] += hourly
	if hourly > 0.0:
		state["totals"]["earned"] += hourly
	else:
		state["totals"]["spent"] += -hourly

	# Riot
	if state["danger"] >= 100.0:
		_riot()


func _end_of_day() -> void:
	state["day"] += 1
	var pop: int = state["population"]

	# Parole
	var rel: int = min(pop, int(round(float(pop) * 0.03 * randf_range(0.5, 1.5))))
	if rel > 0:
		state["population"] = pop - rel
		state["totals"]["released"] += rel
		_add_log("Release: %d inmate%s freed on parole." % [rel, "s" if rel > 1 else ""], "dim")
		pop = state["population"]

	# Intake
	var cap := _bcount("cell") * 4
	var free := cap - pop
	if free > 0 and float(state["reputation"]) > 5.0:
		var want = max(1, int(round(float(state["reputation"]) / 16.0)))
		var arrive = min(free, int(round(float(want) * randf_range(0.6, 1.4))))
		if arrive > 0:
			state["population"] = pop + arrive
			state["totals"]["intake"] += arrive
			_add_log("Intake: %d new inmate%s." % [arrive, "s" if arrive > 1 else ""], "good")
	elif free <= 0:
		_add_log("Prison at full capacity - intake halted.", "warn")

	# Escape
	if state["danger"] > 45.0 and randf() < (float(state["danger"]) - 45.0) / 380.0:
		var esc: int = max(1, int(round(float(state["population"]) * 0.05)))
		state["population"] = max(0, state["population"] - esc)
		state["reputation"] = clampf(float(state["reputation"]) - 6.0, 0.0, 100.0)
		state["totals"]["escapes"] += esc
		_add_log("%d inmate%s escaped! Reputation -6." % [esc, "s" if esc > 1 else ""], "bad")

	# Random events
	var r := randf()
	if r < 0.07 and state["population"] > 0:
		var gain: int = int(round(float(state["population"]) * 25.0))
		state["money"] += gain
		state["totals"]["earned"] += gain
		_add_log("Inspection passed. Bonus %s." % _fmt(gain), "good")
	elif r < 0.12 and state["population"] > 2:
		var loss: int = int(round(float(state["population"]) * 18.0))
		state["money"] -= loss
		state["totals"]["spent"] += loss
		_add_log("Disease outbreak. Costs %s." % _fmt(loss), "warn")
	elif r < 0.16 and state["population"] > 3:
		state["population"] -= 1
		state["totals"]["escapes"] += 1
		_add_log("Contraband found. 1 inmate isolated.", "warn")


func _riot() -> void:
	var loss: int = int(floor(float(state["money"]) * 0.25))
	state["money"] -= loss
	state["totals"]["spent"] += loss
	var esc: int = int(round(float(state["population"]) * 0.1))
	state["population"] = max(0, state["population"] - esc)
	state["totals"]["escapes"] += esc
	state["reputation"] = clampf(float(state["reputation"]) - 12.0, 0.0, 100.0)
	state["danger"] = 25.0
	state["satisfaction"] = max(float(state["satisfaction"]), 40.0)
	state["totals"]["riots"] += 1
	_add_log("RIOT! Lost %s, %d escaped. Rep -12." % [_fmt(loss), esc], "bad")
	Input.vibrate_handheld(200)

# ============================================================
# SAVE / LOAD
# ============================================================
func _save_game() -> void:
	state["last_save"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state))
		f.close()


func _load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return false

	state = _default_state()
	for k in data.keys():
		if typeof(data[k]) == TYPE_DICTIONARY and typeof(state.get(k)) == TYPE_DICTIONARY:
			for k2 in data[k].keys():
				state[k][k2] = data[k][k2]
		else:
			state[k] = data[k]
	return true


func _apply_offline() -> void:
	var last := float(state.get("last_save", Time.get_unix_time_from_system()))
	var now := Time.get_unix_time_from_system()
	var elapsed := now - last
	if elapsed < 60.0:
		return
	var hours := minf(240.0, elapsed / 2.0)
	var d := _derived()
	var gain := (float(d["net"]) / 24.0) * hours
	if gain > 0.0:
		state["money"] += gain
		state["totals"]["earned"] += gain
		_add_log("Away %dh real. Prison earned %s." % [int(elapsed / 3600.0), _fmt(gain)], "good")

# ============================================================
# UI BUILD
# ============================================================
func _build_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Root margin
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 8)
	root.add_theme_constant_override("margin_right", 8)
	root.add_theme_constant_override("margin_top", 8)
	root.add_theme_constant_override("margin_bottom", 0)
	add_child(root)

	var main_v := VBoxContainer.new()
	main_v.add_theme_constant_override("separation", 6)
	root.add_child(main_v)

	_build_hud(main_v)

	# Scroll area
	view_scroll = ScrollContainer.new()
	view_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_v.add_child(view_scroll)

	view_vbox = VBoxContainer.new()
	view_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_vbox.add_theme_constant_override("separation", 8)
	view_scroll.add_child(view_vbox)

	_build_tabs(main_v)


func _build_hud(parent: VBoxContainer) -> void:
	var hud := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c1815")
	sb.border_color = C_LINE
	sb.border_width_bottom = 1
	hud.add_theme_stylebox_override("panel", sb)
	parent.add_child(hud)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 6)
	m.add_theme_constant_override("margin_right", 6)
	m.add_theme_constant_override("margin_top", 5)
	m.add_theme_constant_override("margin_bottom", 5)
	hud.add_child(m)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	m.add_child(v)

	# Top stats row
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 5)
	v.add_child(top)

	ui_money = _make_stat_box(top)
	ui_money["title"].text = "FUNDS"
	ui_day   = _make_stat_box(top)
	ui_day["title"].text = "DAY"
	ui_pop   = _make_stat_box(top)
	ui_pop["title"].text = "INMATES"

	# Satisfaction / Danger bars
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 4)
	v.add_child(bars)

	hud_sat_bar = _make_bar(C_GOOD)
	bars.add_child(hud_sat_bar)
	hud_sat_lbl = _bar_overlay(hud_sat_bar, "Order")

	hud_dgr_bar = _make_bar(C_BAD)
	bars.add_child(hud_dgr_bar)
	hud_dgr_lbl = _bar_overlay(hud_dgr_bar, "Danger")
	
	# Ads button — funds box ke neeche ya bagal me
	var ad_btn := _make_button("📺 Watch Ad  +$500", "ghost", 0.0)
	ad_btn.custom_minimum_size = Vector2(0, 38)
	ad_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ad_btn.pressed.connect(_show_rewarded_ad)
	v.add_child(ad_btn)   # 'v' wahi VBoxContainer hai jisme bars hain


func _make_stat_box(parent: HBoxContainer) -> Dictionary:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL2
	sb.border_color = C_LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 5.0
	sb.content_margin_right = 5.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	panel.add_child(v)

	var title := Label.new()
	title.text = "LABEL"
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", C_DIM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(title)

	var value := Label.new()
	value.text = "0"
	value.add_theme_font_size_override("font_size", 17)
	value.add_theme_color_override("font_color", C_AMBER)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(value)

	var sub := Label.new()
	sub.text = ""
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", C_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sub)

	return {"panel": panel, "title": title, "value": value, "sub": sub}


func _make_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	bar.max_value = 100.0
	bar.value = 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = C_PANEL2
	bg.border_color = C_LINE
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(9)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _bar_overlay(bar: ProgressBar, prefix: String) -> Label:
	var l := Label.new()
	l.text = prefix + " 0%"
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", C_TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(l)
	return l


func _build_tabs(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#131110")
	sb.border_color = C_LINE
	sb.border_width_top = 1
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var tabs_hbox = HBoxContainer.new()
	tabs_hbox.add_theme_constant_override("separation", 0)
	panel.add_child(tabs_hbox)

	for t in TABS:
		var b := Button.new()
		b.text = t["label"]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_font_size_override("font_size", 11)
		var empty := StyleBoxEmpty.new()
		b.add_theme_stylebox_override("normal", empty)
		b.add_theme_stylebox_override("hover", empty)
		b.add_theme_stylebox_override("pressed", empty)
		b.add_theme_stylebox_override("focus", empty)
		b.pressed.connect(_on_tab_pressed.bind(t["id"]))
		tabs_hbox.add_child(b)
		tab_btns[t["id"]] = b


func _refresh_tabs() -> void:
	for id in tab_btns.keys():
		var b: Button = tab_btns[id]
		var active: bool = (id == state["tab"])
		var col := C_AMBER if active else C_DIM
		b.add_theme_color_override("font_color", col)
		b.add_theme_color_override("font_color_hover", col)
		b.add_theme_color_override("font_color_pressed", col)

# ============================================================
# UI HELPERS
# ============================================================
func _make_card(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.border_color = C_LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(13)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	return v


func _add_card_title(parent: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", C_DIM)
	parent.add_child(l)


func _add_econ_row(parent: VBoxContainer, left: String, right: String, col: Color, bold: bool = false) -> void:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := Label.new()
	l.text = left
	l.add_theme_font_size_override("font_size", 12 if not bold else 13)
	l.add_theme_color_override("font_color", C_DIM if not bold else C_TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var r := Label.new()
	r.text = right
	r.add_theme_font_size_override("font_size", 12 if not bold else 13)
	r.add_theme_color_override("font_color", col)
	h.add_child(r)


func _make_button(text: String, style: String = "primary", min_w: float = 86.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 42)
	b.add_theme_font_size_override("font_size", 12)
	var bg := C_AMBER
	var fg := C_DARK
	if style == "ghost":
		bg = C_PANEL2
		fg = C_TEXT
	elif style == "bad":
		bg = Color("#b91c1c")
		fg = Color("#ffffff")
	elif style == "done":
		bg = Color("#1f3a2c")
		fg = C_GOOD
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	var sb_p := sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = bg.darkened(0.15)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_p)
	b.add_theme_stylebox_override("pressed", sb_p)
	b.add_theme_stylebox_override("focus", sb)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_color_hover", fg)
	b.add_theme_color_override("font_color_pressed", fg)
	return b


func _make_row_panel(parent: VBoxContainer) -> HBoxContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL2
	sb.border_color = C_LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(11)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	panel.add_child(h)
	return h


func _clear_view() -> void:
	for c in view_vbox.get_children():
		view_vbox.remove_child(c)
		c.queue_free()

# ============================================================
# UPDATE HUD
# ============================================================
func _update_hud() -> void:
	var d := _derived()
	ui_money["value"].text = _fmt(state["money"])
	ui_money["value"].add_theme_color_override("font_color",
		C_BAD if state["money"] < 0.0 else C_AMBER)
	var net: float = d["net"]
	ui_money["sub"].text = ("+" if net >= 0 else "-") + _fmt(abs(net)).substr(1) + "/day"

	ui_day["value"].text = "Day " + str(state["day"])
	ui_day["sub"].text = "%02d:00" % state["hour"]

	ui_pop["value"].text = "%d/%d" % [state["population"], d["capacity"]]
	ui_pop["sub"].text = "Rep " + ("%.1f" % float(state["reputation"]))

	var sat: float = clampf(float(state["satisfaction"]), 0.0, 100.0)
	var dgr: float = clampf(float(state["danger"]), 0.0, 100.0)
	hud_sat_bar.value = sat
	hud_dgr_bar.value = dgr
	hud_sat_lbl.text = "Order %d%%" % int(round(sat))
	hud_dgr_lbl.text = "Danger %d%%" % int(round(dgr))

# ============================================================
# VIEWS
# ============================================================
func _refresh_view() -> void:
	var sv := view_scroll.scroll_vertical
	_clear_view()
	match state["tab"]:
		"prison":  _view_prison()
		"build":   _view_build()
		"staff":   _view_staff()
		"upgrade": _view_upgrade()
		"stats":   _view_stats()
	view_scroll.scroll_vertical = sv


func _view_prison() -> void:
	var d := _derived()
	var sat: float = float(state["satisfaction"])
	var dgr: float = float(state["danger"])

	# Overview card
	var c1 := _make_card(view_vbox)
	_add_card_title(c1, "Warden's Overview")
	_add_econ_row(c1, "Population", "%d / %d" % [state["population"], d["capacity"]], C_GOOD)
	_add_econ_row(c1, "Free cells", str(max(0, d["capacity"] - state["population"])), C_TEXT)
	_add_econ_row(c1, "Inmate satisfaction", "%d%%" % int(sat),
		C_GOOD if sat >= 60 else (C_WARN if sat >= 35 else C_BAD))
	_add_econ_row(c1, "Danger level", "%d%%" % int(dgr),
		C_BAD if dgr >= 70 else (C_WARN if dgr >= 40 else C_GOOD))
	_add_econ_row(c1, "Reputation", "%.1f" % float(state["reputation"]), C_TEXT)
	var status := ""
	var scol := C_GOOD
	if dgr >= 70.0:
		status = "CRITICAL - Riot imminent!"
		scol = C_BAD
	elif dgr >= 40.0:
		status = "Tense - improve conditions"
		scol = C_WARN
	elif sat >= 80.0:
		status = "Orderly & well managed"
		scol = C_GOOD
	else:
		status = "Stable but unhappy"
		scol = C_WARN
	var line := HSeparator.new()
	line.add_theme_stylebox_override("separator", _sep_style())
	c1.add_child(line)
	_add_econ_row(c1, "Status", status, scol, true)

	# Needs card
	var c2 := _make_card(view_vbox)
	_add_card_title(c2, "Inmate Needs")
	for n in d["needs"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		c2.add_child(row)
		var nl := Label.new()
		nl.text = n["label"]
		nl.add_theme_font_size_override("font_size", 12)
		nl.add_theme_color_override("font_color", C_TEXT)
		nl.custom_minimum_size = Vector2(80, 0)
		row.add_child(nl)
		var pb := ProgressBar.new()
		pb.show_percentage = false
		pb.max_value = 100.0
		pb.value = float(n["score"])
		pb.custom_minimum_size = Vector2(0, 12)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bg := StyleBoxFlat.new()
		bg.bg_color = C_PANEL2
		bg.set_corner_radius_all(6)
		pb.add_theme_stylebox_override("background", bg)
		var fl := StyleBoxFlat.new()
		fl.bg_color = _bar_color(float(n["score"]))
		fl.set_corner_radius_all(6)
		pb.add_theme_stylebox_override("fill", fl)
		row.add_child(pb)
		var vl := Label.new()
		vl.text = "%d%%" % int(round(float(n["score"])))
		vl.add_theme_font_size_override("font_size", 11)
		vl.add_theme_color_override("font_color", C_DIM)
		vl.custom_minimum_size = Vector2(34, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(vl)

	# Economy card
	var c3 := _make_card(view_vbox)
	_add_card_title(c3, "Daily Economy")
	_add_econ_row(c3, "Government grants", "+" + _fmt(d["grant_income"]), C_GOOD)
	_add_econ_row(c3, "Prison labour (%d/%d jobs)" % [d["active_jobs"], d["job_slots"]],
		"+" + _fmt(d["job_income"]), C_GOOD)
	_add_econ_row(c3, "Food", "-" + _fmt(d["food_cost"]), C_BAD)
	_add_econ_row(c3, "Utilities", "-" + _fmt(d["utility"]), C_BAD)
	_add_econ_row(c3, "Staff wages", "-" + _fmt(d["wages"]), C_BAD)
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", _sep_style())
	c3.add_child(sep)
	var net: float = d["net"]
	_add_econ_row(c3, "Net profit",
		("+" if net >= 0 else "-") + _fmt(abs(net)) + "/day",
		C_GOOD if net >= 0 else C_BAD, true)

	# Log card
	var c4 := _make_card(view_vbox)
	_add_card_title(c4, "Event Log")
	var log_scroll := ScrollContainer.new()
	log_scroll.custom_minimum_size = Vector2(0, 180)
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	c4.add_child(log_scroll)
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_constant_override("separation", 3)
	log_scroll.add_child(lv)
	if state["log"].size() == 0:
		var empty := Label.new()
		empty.text = "No events yet."
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", C_DIM)
		lv.add_child(empty)
	else:
		for entry in state["log"]:
			var el := Label.new()
			el.text = "D%d - %s" % [entry["d"], entry["m"]]
			el.add_theme_font_size_override("font_size", 11)
			var c := C_DIM
			if entry["c"] == "good": c = C_GOOD
			elif entry["c"] == "bad": c = C_BAD
			elif entry["c"] == "warn": c = C_WARN
			el.add_theme_color_override("font_color", c)
			el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lv.add_child(el)


func _view_build() -> void:
	var info := _make_card(view_vbox)
	_add_card_title(info, "Prison Facilities")
	_add_econ_row(info, "Available funds", _fmt(state["money"]), C_GOOD)
	_add_econ_row(info, "Total structures", str(_total_buildings()), C_TEXT)

	for b in BUILDINGS:
		var cost := _building_cost(b)
		var can := float(state["money"]) >= cost
		var row := _make_row_panel(view_vbox)

		var nm := VBoxContainer.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var title := Label.new()
		title.text = "%s  x%d" % [b["name"], _bcount(b["id"])]
		title.add_theme_font_size_override("font_size", 13)
		title.add_theme_color_override("font_color", C_TEXT)
		nm.add_child(title)
		var desc := Label.new()
		desc.text = b["desc"]
		desc.add_theme_font_size_override("font_size", 10)
		desc.add_theme_color_override("font_color", C_DIM)
		nm.add_child(desc)

		var btn := _make_button(_fmt(cost), "primary" if can else "ghost")
		btn.disabled = not can
		btn.pressed.connect(_buy_building.bind(b["id"]))
		row.add_child(btn)


func _view_staff() -> void:
	var info := _make_card(view_vbox)
	_add_card_title(info, "Staff Management")
	var total_staff := 0
	for s in STAFF:
		total_staff += _scount(s["id"])
	_add_econ_row(info, "Total employees", str(total_staff), C_TEXT)
	var d := _derived()
	_add_econ_row(info, "Daily wage bill", "-" + _fmt(d["wages"]), C_BAD)
	_add_econ_row(info, "Net daily profit",
		("+" if d["net"] >= 0 else "-") + _fmt(abs(d["net"])),
		C_GOOD if d["net"] >= 0 else C_BAD, true)
	_add_econ_row(info, "Hiring fee = 2 days' wages", "", C_DIM)

	for s in STAFF:
		var fee: float = float(s["wage"]) * 2.0
		var can := float(state["money"]) >= fee
		var cnt := _scount(s["id"])
		var row := _make_row_panel(view_vbox)

		var nm := VBoxContainer.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var t := Label.new()
		t.text = "%s  x%d" % [s["name"], cnt]
		t.add_theme_font_size_override("font_size", 13)
		t.add_theme_color_override("font_color", C_TEXT)
		nm.add_child(t)
		var ds := Label.new()
		ds.text = "%s  -  %s/day" % [s["desc"], _fmt(float(s["wage"]))]
		ds.add_theme_font_size_override("font_size", 10)
		ds.add_theme_color_override("font_color", C_DIM)
		nm.add_child(ds)

		var hb := _make_button("+" + _fmt(fee), "primary" if can else "ghost", 72.0)
		hb.disabled = not can
		hb.pressed.connect(_hire_staff.bind(s["id"]))
		row.add_child(hb)

		if cnt > 0:
			var fb := _make_button("-", "bad", 42.0)
			fb.pressed.connect(_fire_staff.bind(s["id"]))
			row.add_child(fb)


func _view_upgrade() -> void:
	var info := _make_card(view_vbox)
	_add_card_title(info, "Prison Upgrades")
	var owned := 0
	for id in state["upgrades"].keys():
		if state["upgrades"][id]:
			owned += 1
	_add_econ_row(info, "Purchased", "%d / %d" % [owned, UPGRADES.size()], C_TEXT)
	_add_econ_row(info, "Available funds", _fmt(state["money"]), C_GOOD)

	for u in UPGRADES:
		var have := _has_up(u["id"])
		var can := not have and float(state["money"]) >= float(u["cost"])
		var row := _make_row_panel(view_vbox)

		var nm := VBoxContainer.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var t := Label.new()
		t.text = u["name"]
		t.add_theme_font_size_override("font_size", 13)
		t.add_theme_color_override("font_color", C_TEXT)
		nm.add_child(t)
		var ds := Label.new()
		ds.text = u["desc"]
		ds.add_theme_font_size_override("font_size", 10)
		ds.add_theme_color_override("font_color", C_DIM)
		nm.add_child(ds)

		if have:
			var b := _make_button("OWNED", "done", 78.0)
			b.disabled = true
			row.add_child(b)
		else:
			var b2 := _make_button(_fmt(float(u["cost"])), "primary" if can else "ghost")
			b2.disabled = not can
			b2.pressed.connect(_buy_upgrade.bind(u["id"]))
			row.add_child(b2)


func _view_stats() -> void:
	var t: Dictionary = state["totals"]
	var d := _derived()
	var net_worth: float = float(state["money"]) + float(_total_buildings()) * 500.0

	var c1 := _make_card(view_vbox)
	_add_card_title(c1, "Career Statistics")
	_add_econ_row(c1, "Days as Warden", str(state["day"]), C_TEXT)
	_add_econ_row(c1, "Total earned", _fmt(t["earned"]), C_GOOD)
	_add_econ_row(c1, "Total spent", _fmt(t["spent"]), C_BAD)
	_add_econ_row(c1, "Structures built", str(t["built"]), C_TEXT)
	_add_econ_row(c1, "Total intake", str(t["intake"]), C_TEXT)
	_add_econ_row(c1, "Total released", str(t["released"]), C_TEXT)
	_add_econ_row(c1, "Total escapes", str(t["escapes"]), C_BAD)
	_add_econ_row(c1, "Riots survived", str(t["riots"]), C_BAD)
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", _sep_style())
	c1.add_child(sep)
	_add_econ_row(c1, "Estimated net worth", _fmt(net_worth), C_GOOD, true)

	var c2 := _make_card(view_vbox)
	_add_card_title(c2, "Current Rates")
	_add_econ_row(c2, "Grant per inmate", _fmt(float(d["grant_per"])) + "/day", C_TEXT)
	_add_econ_row(c2, "Jobs filled", "%d / %d" % [d["active_jobs"], d["job_slots"]], C_TEXT)
	var net: float = d["net"]
	_add_econ_row(c2, "Net per day",
		("+" if net >= 0 else "-") + _fmt(abs(net)),
		C_GOOD if net >= 0 else C_BAD)
	_add_econ_row(c2, "Net per hour",
		("+" if net >= 0 else "-") + _fmt(abs(net) / 24.0),
		C_GOOD if net >= 0 else C_BAD)

	var c3 := _make_card(view_vbox)
	_add_card_title(c3, "Danger Zone")
	var sb := _make_button("Save Game", "ghost")
	sb.custom_minimum_size = Vector2(0, 44)
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.pressed.connect(func():
		_save_game()
		_add_log("Game saved.", "dim")
		_refresh_view())
	c3.add_child(sb)
	var rb := _make_button("Reset All Progress", "bad")
	rb.custom_minimum_size = Vector2(0, 44)
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rb.pressed.connect(func():
		state = _default_state()
		_save_game()
		_refresh_tabs()
		_refresh_view()
		_update_hud())
	c3.add_child(rb)


func _bar_color(pct: float) -> Color:
	if pct >= 70.0: return C_GOOD
	if pct >= 40.0: return C_WARN
	return C_BAD


func _sep_style() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = C_LINE
	s.thickness = 1
	return s



func _load_rewarded_ad() -> void:
	if rewarded_ad != null:
		return   # pehle se loaded hai

	var unit_id := "ca-app-pub-3940256099942544/5224354917"  # TEST Android ID
	# Production me apna real ID daalna:
	# var unit_id := "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"

	RewardedAdLoader.new().load(unit_id, AdRequest.new(), rewarded_load_callback)




# ============================================================
# SIGNAL HANDLERS
# ============================================================
func _on_tab_pressed(id: String) -> void:
	state["tab"] = id
	_refresh_tabs()
	_refresh_view()
	_update_hud()




#
#
#
func _show_rewarded_ad() -> void:
	if rewarded_ad == null:
		_add_log("Ad not ready yet. Please wait...", "warn")
		_load_rewarded_ad()   # dobara load try karo
		return

	# Reward listener — jab user ad poora dekhe
	var reward_listener := OnUserEarnedRewardListener.new()
	

	rewarded_ad.show(reward_listener)

	# Ad band hone ke baad naya ad preload karo
	rewarded_ad = null
	_load_rewarded_ad()


func _grant_ad_reward() -> void:
	state["money"] += 500.0
	state["totals"]["earned"] += 500.0
	_add_log("+$500 from rewarded ad!", "good")
	Input.vibrate_handheld(30)
	_update_hud()
	_refresh_view()








	
