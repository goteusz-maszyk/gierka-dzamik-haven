extends SceneTree
## Full suite: godot --headless --path . -s tests/run_all.gd

const TEST_SCRIPTS: Array[String] = [
	"res://tests/test_config_data.gd",
	"res://tests/test_train_physics.gd",
	"res://tests/test_timetable.gd",
	"res://tests/test_world.gd",
	"res://tests/test_events.gd",
	"res://tests/test_route_planner.gd",
	"res://tests/test_run.gd",
	"res://tests/test_history.gd",
	"res://tests/test_integration.gd",
]


func _initialize() -> void:
	var failures := 0
	for path in TEST_SCRIPTS:
		if not ResourceLoader.exists(path):
			printerr("MISSING test script: " + path)
			failures += 1
			continue
		var script: GDScript = load(path)
		var test: TestHarness = script.new()
		var methods: Array = script.get_script_method_list().map(func(m: Dictionary) -> String: return m.name)
		methods = methods.filter(func(n: String) -> bool: return n.begins_with("test_"))
		methods.sort()
		print("== " + path)
		failures += test.run(methods)
	quit(failures)
