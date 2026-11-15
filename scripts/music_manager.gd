extends Node

var music_player: AudioStreamPlayer

func _ready():
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	add_child(music_player)

func play_music(stream: AudioStream):
	if music_player.stream == stream and music_player.playing:
		return

	music_player.stream = stream
	music_player.play()

func stop_music():
	music_player.stop()

func set_volume(value: float):
	music_player.volume_db = linear_to_db(max(value, 0.001))
