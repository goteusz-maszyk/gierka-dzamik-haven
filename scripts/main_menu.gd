extends Control

func _ready() -> void:
	MusicManager.stop_music()
	MusicManager.play_music(preload("res://assets/tomek_i_przyjaciele.mp3"))

func _on_start_btn_click() -> void:
	get_tree().change_scene_to_file("res://scene/game.tscn")


func _on_exit_btn_click() -> void:
	get_tree().quit()


func _on_options_btn_click() -> void:
	get_tree().change_scene_to_file("res://scene/options.tscn")
