class_name TestHarness
extends RefCounted
## Minimal assertion harness for headless tests. Exit code 0 = all passed.

var _failures: Array[String] = []
var _checks: int = 0
var _current: String = ""


func run(method_names: Array) -> int:
	for method_name in method_names:
		_current = method_name
		call(method_name)
	print("TESTS %d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		printerr("FAIL " + failure)
	return 1 if not _failures.is_empty() else 0


func ok(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("%s: %s" % [_current, message])


func eq(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: %s (got %s, want %s)" % [_current, message, str(actual), str(expected)])


func near(actual: float, expected: float, epsilon: float, message: String) -> void:
	_checks += 1
	if absf(actual - expected) > epsilon:
		_failures.append("%s: %s (got %f, want %f +/- %f)" % [_current, message, actual, expected, epsilon])
