extends Control

@onready var music_slider: HSlider = $PanelContainer/OptionsContainer/VBoxContainer/MusicVolumeSlider
@onready var sfx_slider: HSlider = $PanelContainer/OptionsContainer/VBoxContainer2/SFXVolumeSlider

func _ready() -> void:
	MusicManager.stop_music()
	var music_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	music_slider.value = music_slider.max_value - db_to_linear(music_db)

	var sfx_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	sfx_slider.value = db_to_linear(sfx_db) * sfx_slider.max_value

func _on_music_slider(value: float) -> void:
	_set_bus_volume("Music", music_slider.max_value - value)

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
