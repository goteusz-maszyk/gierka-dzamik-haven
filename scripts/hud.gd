class_name Hud
extends CanvasLayer
## HUD: clock/deadline/time-left, rewind bar, current train, message, plus the
## departure board, pause and end panels. All visuals are Control nodes; this
## script only sets their properties from Run state each frame.

var _cfg: Dictionary
var _rewind_total: float

@onready var _clock: Label = $TopLeft/Clock
@onready var _deadline: Label = $TopLeft/Deadline
@onready var _time_left: Label = $TopLeft/TimeLeft
@onready var _view_label: Label = $TopRight/ViewLabel
@onready var _seed_label: Label = $TopRight/SeedLabel
@onready var _train_info: Label = $BottomLeft/TrainInfo
@onready var _hint: Label = $BottomLeft/Hint
@onready var _rewind_bar: ProgressBar = $BottomRight/RewindBar
@onready var _message: Label = $Message
@onready var _board: Panel = $Board
@onready var _pause: Panel = $PausePanel
@onready var _end: Panel = $EndPanel


func setup(cfg: Dictionary) -> void:
	_cfg = cfg
	_rewind_total = ConfigData.load_file("time").rewind_meter_minutes
	var pad: float = cfg.hud_pad
	var line_gap: float = cfg.hud_line_gap - cfg.hud_small_font_size
	_style_label(_clock, cfg.hud_font_size, cfg.hud_color)
	_style_label(_deadline, cfg.hud_small_font_size, cfg.hud_muted_color)
	_style_label(_time_left, cfg.hud_small_font_size, cfg.hud_muted_color)
	_style_label(_view_label, cfg.hud_small_font_size, cfg.hud_muted_color)
	_style_label(_seed_label, cfg.hud_small_font_size, cfg.hud_muted_color)
	_style_label(_train_info, cfg.hud_small_font_size, cfg.hud_color)
	_style_label(_hint, cfg.hud_hint_font_size, cfg.hud_muted_color)
	_style_label(_message, cfg.hud_small_font_size, cfg.destination_color)
	_hint.text = "Tab view · Space rewind · E board · B board train · N disembark · Esc pause · R restart"
	$TopLeft.offset_left = pad
	$TopLeft.offset_top = pad
	$TopLeft.add_theme_constant_override("separation", int(line_gap))
	$TopRight.offset_left = -cfg.hud_right_col_width - pad
	$TopRight.offset_right = -pad
	$TopRight.offset_top = pad
	$TopRight.add_theme_constant_override("separation", int(line_gap))
	$BottomLeft.offset_left = pad
	$BottomLeft.offset_top = -pad
	$BottomLeft.add_theme_constant_override("separation", int(line_gap))
	$BottomRight.offset_left = -cfg.rewind_bar_width - pad
	$BottomRight.offset_right = -pad
	$BottomRight.offset_top = -pad
	$BottomRight.add_theme_constant_override("separation", int(cfg.rewind_bar_caption_gap))
	_style_label($BottomRight/RewindCaption, cfg.hud_small_font_size, cfg.hud_muted_color)
	_rewind_bar.custom_minimum_size = Vector2(cfg.rewind_bar_width, cfg.rewind_bar_height)
	_rewind_bar.max_value = _rewind_total
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color.from_string(cfg.rewind_bar_bg_color, Color.WHITE)
	_rewind_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color.from_string(cfg.rewind_bar_color, Color.WHITE)
	_rewind_bar.add_theme_stylebox_override("fill", fill)
	_message.offset_left = -cfg.message_width * 0.5
	_message.offset_right = cfg.message_width * 0.5
	_message.offset_top = -cfg.message_gap - cfg.hud_small_font_size
	_message.offset_bottom = -cfg.message_gap
	_board.setup(cfg)
	_pause.setup(cfg)
	_end.setup(cfg)

func refresh(main: Node2D) -> void:
	var run: Run = main.run()
	_clock.text = TimeFormat.format_time(run.clock)
	_deadline.text = "Deadline %s" % TimeFormat.format_time(run.deadline)
	_view_label.text = "View: %s (Tab)" % main.view_name()
	_seed_label.text = "Seed %d" % run.seed_value
	_rewind_bar.value = run.rewind_meter
	_train_info.text = _train_info_text(run, main)
	_message.text = main.message()
	_message.visible = _message.text != ""
	if main.is_board_open():
		var station: String = run.player_station if run.player_station != "" else run.start_station
		_board.refresh(main.station_name(station), run.world.departures(station, run.clock, _cfg.board_rows))
	else:
		_board.visible = false
	if main.is_paused():
		_pause.show_panel("PAUSED", "Esc to resume")
	else:
		_pause.hide_panel()
	if run.finished:
		var late := run.minutes_late()
		var verdict := "%d min early" % int(round(-late)) if late < 0 else "%d min late" % int(round(late))
		var body := "Arrival %s   Deadline %s\n%s\nSeed %d\nR for a new run" % [
			TimeFormat.format_time(run.arrival_time), TimeFormat.format_time(run.deadline), verdict, run.seed_value]
		_end.show_panel("ARRIVED IN KRAKÓW", body)
	else:
		_end.hide_panel()


func _train_info_text(run: Run, main: Node2D) -> String:
	if run.player_train == "":
		return "At %s — B to board a standing train" % main.station_name(run.player_station)
	var info := run.world.train_info(run.player_train)
	var state := run.world.train_state(run.player_train, run.clock)
	var where := "moving"
	if state.phase == "dwelling":
		where = "at " + main.station_name(state.station_id)
	elif state.phase == "finished":
		where = "terminated"
	return "%s (%s) → %s — %s — N to disembark" % [info.train_number, info.line_name, info.destination, where]


func _style_label(label: Label, font_size: int, hex: String) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.from_string(hex, Color.WHITE))
