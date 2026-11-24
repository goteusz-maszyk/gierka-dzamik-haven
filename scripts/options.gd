extends Control

@onready var music_slider: HSlider = $PanelContainer/OptionsContainer/VBoxContainer/MusicVolumeSlider
@onready var sfx_slider: HSlider = $PanelContainer/OptionsContainer/VBoxContainer2/SFXVolumeSlider

func _ready() -> void:
	MusicManager.stop_music()
	_sync_volume_slider(music_slider, "Music")
	_sync_volume_slider(sfx_slider, "SFX")

func _sync_volume_slider(slider: HSlider, bus_name: String) -> void:
	var volume_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus_name))
	var value := db_to_linear(volume_db) * slider.max_value
	# Reserve the left endpoint for silence, even for levels below one slider step.
	slider.set_value_no_signal(maxf(value, slider.step) if value > 0.0 else 0.0)

func _on_music_slider(value: float) -> void:
	_set_bus_volume("Music", value / music_slider.max_value)

func _on_sfx_slider(value: float) -> void:
	_set_bus_volume("SFX", value / sfx_slider.max_value)

func _set_bus_volume(bus_name: String, linear_volume: float) -> void:
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index(bus_name),
		linear_to_db(linear_volume)
	)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scene/main_menu.tscn")

func _on_exit_btn() -> void:
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")
