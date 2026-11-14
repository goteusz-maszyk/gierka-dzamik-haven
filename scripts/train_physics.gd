class_name TrainPhysics
extends RefCounted
## Closed-form standstill-to-standstill section running (no integration loops).
## Config speeds are km/h, internal speeds m/s; returned times are minutes.

const SECONDS_PER_MINUTE := 60.0
const METERS_PER_KM := 1000.0
const KMH_PER_MPS := 3.6


static func section_time(distance_km: float, max_speed_kmh: float,
		accel_mps2: float, brake_mps2: float, speed_factor: float = 1.0) -> float:
	assert(accel_mps2 > 0.0 and brake_mps2 > 0.0, "TrainPhysics: accel and brake must be positive")
	if distance_km <= 0.0:
		return 0.0
	if max_speed_kmh * speed_factor <= 0.0:
		return INF  # zero speed cap: the section can never be covered
	var profile := _profile(distance_km, max_speed_kmh, accel_mps2, brake_mps2, speed_factor)
	return float(profile["total_s"]) / SECONDS_PER_MINUTE


## Distance fraction (0..1) covered after elapsed_minutes inside the section.
## speed_factor scales the speed cap only, exactly as in section_time.
static func section_progress(distance_km: float, max_speed_kmh: float,
		accel_mps2: float, brake_mps2: float, speed_factor: float,
		elapsed_minutes: float) -> float:
	assert(accel_mps2 > 0.0 and brake_mps2 > 0.0, "TrainPhysics: accel and brake must be positive")
	if distance_km <= 0.0:
		return 1.0
	if max_speed_kmh * speed_factor <= 0.0:
		return 0.0
	var profile := _profile(distance_km, max_speed_kmh, accel_mps2, brake_mps2, speed_factor)
	var total_s: float = profile["total_s"]
	var tau := clampf(elapsed_minutes * SECONDS_PER_MINUTE, 0.0, total_s)
	var t_accel: float = profile["t_accel"]
	var covered: float
	if tau <= t_accel:
		covered = 0.5 * accel_mps2 * tau * tau
	elif tau <= t_accel + float(profile["t_cruise"]):
		covered = float(profile["d_accel"]) + float(profile["cap"]) * (tau - t_accel)
	else:
		# Braking mirrors acceleration: remaining distance = b/2 * remaining_time².
		var remaining := total_s - tau
		covered = float(profile["dist_m"]) - 0.5 * brake_mps2 * remaining * remaining
	return covered / float(profile["dist_m"])


## Accel/cruise/brake profile. Triangular (no cruise) when the section is too
## short to reach the capped speed: peak v from v²/(2a) + v²/(2b) = distance.
static func _profile(distance_km: float, max_speed_kmh: float,
		accel_mps2: float, brake_mps2: float, speed_factor: float) -> Dictionary:
	var dist_m := distance_km * METERS_PER_KM
	var cap := max_speed_kmh * speed_factor / KMH_PER_MPS
	var d_accel := cap * cap / (2.0 * accel_mps2)
	var d_brake := cap * cap / (2.0 * brake_mps2)
	var t_accel: float
	var t_brake: float
	var t_cruise := 0.0
	if d_accel + d_brake <= dist_m:
		t_accel = cap / accel_mps2
		t_brake = cap / brake_mps2
		t_cruise = (dist_m - d_accel - d_brake) / cap
	else:
		var peak := sqrt(2.0 * dist_m * accel_mps2 * brake_mps2 / (accel_mps2 + brake_mps2))
		t_accel = peak / accel_mps2
		t_brake = peak / brake_mps2
		d_accel = peak * peak / (2.0 * accel_mps2)
	return {"dist_m": dist_m, "cap": cap, "d_accel": d_accel, "t_accel": t_accel,
		"t_cruise": t_cruise, "total_s": t_accel + t_cruise + t_brake}
