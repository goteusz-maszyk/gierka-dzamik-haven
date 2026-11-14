extends SceneTree
## Runs one test file: godot --headless --path . -s tests/run_one.gd -- res://tests/test_x.gd


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("usage: godot --headless -s tests/run_one.gd -- res://tests/test_x.gd")
		quit(1)
		return
	quit(_run_file(args[0]))


func _run_file(path: String) -> int:
	if not ResourceLoader.exists(path):
		printerr("MISSING test script: " + path)
		return 1
	var script: GDScript = load(path)
	var test: TestHarness = script.new()
	var methods: Array = script.get_script_method_list().map(func(m: Dictionary) -> String: return m.name)
	methods = methods.filter(func(n: String) -> bool: return n.begins_with("test_"))
	methods.sort()
	print("== " + path)
	return test.run(methods)
