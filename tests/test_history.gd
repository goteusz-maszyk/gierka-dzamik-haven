extends TestHarness
## PlayerHistory boundaries: exact record times, between/before records,
## truncation semantics. All times are hand-picked minutes.


func test_before_first_returns_first() -> void:
	var history := PlayerHistory.new()
	history.record_station(100.0, "lodz")
	var state := history.state_at(50.0)
	eq(state["kind"], "station", "before first: kind")
	eq(state["station_id"], "lodz", "before first: station")
	eq(state["train_id"], "", "before first: no train")


func test_between_records_returns_earlier() -> void:
	var history := PlayerHistory.new()
	history.record_station(100.0, "lodz")
	history.record_train(110.0, "L2-F-0", 0)
	history.record_station(150.0, "krakow")
	var between := history.state_at(125.0)
	eq(between["kind"], "train", "between records: kind")
	eq(between["train_id"], "L2-F-0", "between records: train")
	eq(between["station_id"], "", "between records: no station")
	var just_before := history.state_at(149.999)
	eq(just_before["train_id"], "L2-F-0", "just before third: still the train")


func test_exact_record_time_returns_that_record() -> void:
	var history := PlayerHistory.new()
	history.record_station(100.0, "lodz")
	history.record_train(110.0, "L2-F-0", 0)
	var at_board := history.state_at(110.0)
	eq(at_board["kind"], "train", "exact boarding time: kind")
	eq(at_board["train_id"], "L2-F-0", "exact boarding time: train")
	var at_start := history.state_at(100.0)
	eq(at_start["kind"], "station", "exact first time: kind")
	eq(at_start["station_id"], "lodz", "exact first time: station")
	var after_last := history.state_at(1000.0)
	eq(after_last["kind"], "train", "after last: latest record wins")
	eq(after_last["train_id"], "L2-F-0", "after last: train id")


func test_latest_record_wins_including_equal_times() -> void:
	var history := PlayerHistory.new()
	history.record_station(100.0, "lodz")
	history.record_train(100.0, "L2-F-0", 0)
	history.record_station(100.0, "czestochowa")
	var state := history.state_at(100.0)
	eq(state["kind"], "station", "equal times: last appended wins")
	eq(state["station_id"], "czestochowa", "equal times: last station")


func test_truncate_drops_strictly_later_only() -> void:
	var history := PlayerHistory.new()
	history.record_station(100.0, "lodz")
	history.record_train(110.0, "L2-F-0", 0)
	history.record_station(150.0, "czestochowa")
	history.truncate_after(110.0)
	eq(history.state_at(150.0)["train_id"], "L2-F-0", "truncate at boundary: later record gone")
	eq(history.state_at(110.0)["kind"], "train", "truncate at boundary: boundary record kept")
	eq(history.state_at(105.0)["station_id"], "lodz", "truncate at boundary: earlier kept")


func test_truncate_between_records() -> void:
	var history := PlayerHistory.new()
	history.record_station(100.0, "lodz")
	history.record_train(110.0, "L2-F-0", 0)
	history.truncate_after(105.0)
	eq(history.state_at(200.0)["station_id"], "lodz", "truncate between: train record gone")
	eq(history.state_at(105.0)["kind"], "station", "truncate between: station kept")


func test_record_after_truncate_continues_monotonically() -> void:
	var history := PlayerHistory.new()
	history.record_station(100.0, "lodz")
	history.record_train(110.0, "L2-F-0", 0)
	history.truncate_after(100.0)
	history.record_train(102.0, "L5-F-3", 1)
	var state := history.state_at(102.0)
	eq(state["train_id"], "L5-F-3", "record after truncate: new record")
	eq(history.state_at(101.0)["station_id"], "lodz", "record after truncate: gap resolves to earlier")


func test_state_is_a_snapshot() -> void:
	var history := PlayerHistory.new()
	history.record_station(100.0, "lodz")
	var state := history.state_at(100.0)
	state["station_id"] = "hacked"
	eq(history.state_at(100.0)["station_id"], "lodz", "mutating returned state must not corrupt history")
