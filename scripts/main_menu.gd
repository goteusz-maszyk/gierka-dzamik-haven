extends Control


func _on_start_btn_click() -> void:
	get_tree().change_scene_to_file("res://scene/game.tscn")


func _on_exit_btn_click() -> void:
	get_tree().quit()
