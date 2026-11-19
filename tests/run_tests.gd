extends SceneTree
## Headless test runner (no test framework needed).
##
## Run from the project root:
##   godot --headless --path . --import
##   godot --headless --path . -s res://tests/run_tests.gd
## Exit code 0 means all tests passed. Tests that check invalid input expect
## "SoundFalloff: ..." errors in the log; they are printed by push_error.
##
## Reference vectors come from the tested Python core (trainhorn_calc.acoustics),
## which uses the same formulas.

const EPS: float = 1e-6
const DEMO_SCENE: String = "res://addons/sound_falloff/demo/crossing_demo.tscn"

var _passed: int = 0
var _failed: int = 0
var _current: String = ""
var _started_node_tests: bool = false


func _initialize() -> void:
	print("sound_falloff tests on Godot %s" % Engine.get_version_info().string)
	_run("level_at_distance core vectors", _test_level_core_vectors)
	_run("level_at_distance with air absorption", _test_level_absorption)
	_run("distance_for_level free field", _test_distance_free_field)
	_run("distance_for_level with absorption (bisection)", _test_distance_absorption)
	_run("round trip level <-> distance", _test_round_trip)
	_run("distance_ratio_loss and db_per_doubling", _test_ratio_loss)
	_run("combine_levels", _test_combine)
	_run("dB <-> linear conversions", _test_conversions)
	_run("invalid input returns NAN", _test_invalid_input)
	_run("air absorption table", _test_absorption_table)


func _process(_delta: float) -> bool:
	# Node tests run on the first frame, once the root viewport is in the tree.
	if _started_node_tests:
		return false
	_started_node_tests = true
	_run("AudioDistanceAttenuator sets volume_db", _test_attenuator_basic)
	_run("AudioDistanceAttenuator clamp and min_distance", _test_attenuator_clamp)
	_run("AudioDistanceAttenuator absorption and world units", _test_attenuator_absorption)
	_run("AudioDistanceAttenuator signal and missing listener", _test_attenuator_signal)
	_run("demo scene loads and updates", _test_demo_scene)
	print("")
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
	return false


func _run(name: String, test: Callable) -> void:
	_current = name
	var failed_before: int = _failed
	var finished: Variant = test.call()
	if finished != true:
		_check(false, "the test stopped early (script error above)")
	if _failed == failed_before:
		_passed += 1
		print("PASS  %s" % name)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed += 1
		printerr("FAIL  %s: %s" % [_current, message])


func _near(actual: float, expected: float, message: String, eps: float = EPS) -> void:
	_check(absf(actual - expected) <= eps, "%s: expected %.10f, got %.10f" % [message, expected, actual])


func _test_level_core_vectors() -> bool:
	# 150 dB at 10 ft -> 130.0 dB at 100 ft (the core vector).
	_near(SoundFalloff.level_at_distance(150.0, 100.0, 10.0), 130.0, "150@10 ft -> 100 ft")
	_near(SoundFalloff.level_at_distance(150.0, 5.0, 10.0), 156.02059991327963, "150@10 ft -> 5 ft")
	_near(SoundFalloff.level_at_distance(150.0, 10.0, 10.0), 150.0, "at the reference distance")
	_near(SoundFalloff.level_at_distance(110.0, 60.96, 30.48), 103.97940008672037, "one doubling")
	_near(SoundFalloff.attenuation_db(100.0, 10.0), -20.0, "attenuation for x10")
	_near(SoundFalloff.attenuation_db(1.0, 10.0), 20.0, "gain when closer")
	return true


func _test_level_absorption() -> bool:
	var ft: float = SoundFalloff.METERS_PER_FOOT
	_near(SoundFalloff.level_at_distance(150.0, 1000.0, 10.0, 1.9, ft), 109.4266712, "150@10 ft -> 1000 ft, 1.9 dB/km")
	_near(SoundFalloff.level_at_distance(120.0, 500.0, 1.0, 1.9), 65.07249991327963, "120@1 m -> 500 m, 1.9 dB/km")
	return true


func _test_distance_free_field() -> bool:
	_near(SoundFalloff.distance_for_level(150.0, 130.0, 10.0), 100.0, "150@10 ft reaches 130 dB at 100 ft")
	_near(SoundFalloff.distance_for_level(150.0, 160.0, 10.0), 3.1622776601683795, "higher target is closer")
	_near(SoundFalloff.distance_for_level(150.0, 150.0, 10.0), 10.0, "same level at the reference")
	return true


func _test_distance_absorption() -> bool:
	var ft: float = SoundFalloff.METERS_PER_FOOT
	_near(SoundFalloff.distance_for_level(150.0, 100.0, 10.0, 1.9, ft), 2651.6094429801187, "150->100 dB, ft, 1.9 dB/km", 1e-6)
	_near(SoundFalloff.distance_for_level(120.0, 60.0, 1.0, 3.7), 732.3263042232177, "120->60 dB, m, 3.7 dB/km", 1e-6)
	_near(SoundFalloff.distance_for_level(150.0, 160.0, 10.0, 1.9, ft), 3.163719354263083, "inside the reference", 1e-9)
	return true


func _test_round_trip() -> bool:
	for absorption: float in [0.0, 1.0, 9.7]:
		for target: float in [140.0, 120.0, 95.0, 70.0]:
			var d: float = SoundFalloff.distance_for_level(150.0, target, 3.048, absorption)
			_near(SoundFalloff.level_at_distance(150.0, d, 3.048, absorption), target, "round trip %s dB/km, %s dB" % [absorption, target], 1e-7)
	return true


func _test_ratio_loss() -> bool:
	_near(SoundFalloff.distance_ratio_loss(10.0), 20.0, "ratio 10")
	_near(SoundFalloff.distance_ratio_loss(1.0), 0.0, "ratio 1")
	_near(SoundFalloff.db_per_doubling(), 6.020599913279624, "per doubling")
	return true


func _test_combine() -> bool:
	_near(SoundFalloff.combine_levels([100.0, 100.0]), 103.01029995663981, "two equal sources")
	_near(SoundFalloff.combine_levels([90, 100, 80]), 100.45322978786658, "three sources, int input")
	_near(SoundFalloff.combine_levels([1000.0, 1000.0]), 1003.0102999566398, "large values do not overflow", 1e-9)
	_near(SoundFalloff.combine_levels([42.0]), 42.0, "single source")
	return true


func _test_conversions() -> bool:
	_near(SoundFalloff.db_to_amplitude(-6.020599913279624), 0.5, "-6.02 dB amplitude")
	_near(SoundFalloff.db_to_amplitude(-12.0), db_to_linear(-12.0), "matches db_to_linear")
	_near(SoundFalloff.amplitude_to_db(0.1), -20.0, "amplitude 0.1")
	_near(SoundFalloff.db_to_power(10.0), 10.0, "power +10 dB")
	_near(SoundFalloff.power_to_db(0.5), -3.010299956639812, "power 0.5")
	_check(SoundFalloff.amplitude_to_db(0.0) == -INF, "amplitude 0 is -INF")
	_check(SoundFalloff.power_to_db(0.0) == -INF, "power 0 is -INF")
	_near(SoundFalloff.feet_to_meters(100.0), 30.48, "100 ft")
	_near(SoundFalloff.meters_to_feet(3.048), 10.0, "3.048 m")
	return true


func _test_invalid_input() -> bool:
	print("      (the SoundFalloff errors below are expected)")
	_check(is_nan(SoundFalloff.level_at_distance(150.0, 0.0, 10.0)), "distance 0")
	_check(is_nan(SoundFalloff.level_at_distance(150.0, -5.0, 10.0)), "negative distance")
	_check(is_nan(SoundFalloff.level_at_distance(150.0, 5.0, 0.0)), "reference 0")
	_check(is_nan(SoundFalloff.level_at_distance(NAN, 5.0, 10.0)), "NaN level")
	_check(is_nan(SoundFalloff.level_at_distance(150.0, 5.0, 10.0, -1.0)), "negative absorption")
	_check(is_nan(SoundFalloff.distance_for_level(150.0, INF, 10.0)), "infinite target")
	_check(is_nan(SoundFalloff.distance_for_level(1.0e6, -1.0e6, 10.0)), "levels too far apart")
	_check(is_nan(SoundFalloff.distance_ratio_loss(0.0)), "ratio 0")
	_check(is_nan(SoundFalloff.combine_levels([])), "empty list")
	_check(is_nan(SoundFalloff.combine_levels(["loud"])), "non-number")
	_check(is_nan(SoundFalloff.amplitude_to_db(-1.0)), "negative amplitude")
	return true


func _test_absorption_table() -> bool:
	var keys: Array = SoundFalloff.AIR_ABSORPTION_DB_PER_KM.keys()
	_check(keys.size() == 8, "8 octave bands")
	var previous: float = -1.0
	for band: int in [63, 125, 250, 500, 1000, 2000, 4000, 8000]:
		var value: float = SoundFalloff.AIR_ABSORPTION_DB_PER_KM[band]
		_check(value > previous, "absorption rises with frequency at %d Hz" % band)
		previous = value
	_near(SoundFalloff.AIR_ABSORPTION_DB_PER_KM[500], 1.9, "500 Hz value")
	return true


func _make_rig(listener_offset: Vector3) -> Dictionary:
	var rig_root := Node3D.new()
	var player := AudioStreamPlayer3D.new()
	var listener := Node3D.new()
	listener.name = "Listener"
	listener.position = listener_offset
	rig_root.add_child(player)
	rig_root.add_child(listener)
	var attenuator := AudioDistanceAttenuator.new()
	attenuator.listener_path = NodePath("../../Listener")
	attenuator.auto_update = false
	player.add_child(attenuator)
	get_root().add_child(rig_root)
	return {"root": rig_root, "player": player, "listener": listener, "attenuator": attenuator}


func _test_attenuator_basic() -> bool:
	var rig: Dictionary = _make_rig(Vector3(0.0, 0.0, 10.0))
	var player: AudioStreamPlayer3D = rig.player
	var attenuator: AudioDistanceAttenuator = rig.attenuator
	_check(attenuator.get_player() == player, "parent player found")
	_check(player.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED, "built-in attenuation disabled")
	attenuator.reference_distance = 1.0
	attenuator.reference_volume_db = 0.0
	attenuator.use_clamp = false
	_near(attenuator.update_volume(), -20.0, "10 m from a 0 dB @ 1 m source")
	_near(player.volume_db, -20.0, "player volume_db set")
	_near(attenuator.get_last_distance(), 10.0, "distance measured")
	# 150 dB at 10 ft mapped to 0 dB: at 100 ft the player sits 20 dB lower.
	attenuator.reference_distance = 3.048
	attenuator.reference_volume_db = 0.0
	rig.listener.position = Vector3(30.48, 0.0, 0.0)
	_near(attenuator.update_volume(), -20.0, "10 ft reference -> 100 ft")
	(rig.root as Node).free()
	return true


func _test_attenuator_clamp() -> bool:
	var rig: Dictionary = _make_rig(Vector3(0.0, 0.0, 0.0))
	var attenuator: AudioDistanceAttenuator = rig.attenuator
	attenuator.reference_distance = 10.0
	attenuator.reference_volume_db = 0.0
	attenuator.use_clamp = true
	attenuator.min_volume_db = -30.0
	attenuator.max_volume_db = 6.0
	attenuator.min_distance = 0.5
	_near(attenuator.update_volume(), 6.0, "distance 0 is clamped to max")
	_near(attenuator.volume_db_for_distance(1000.0), -30.0, "far distance clamped to min")
	_near(attenuator.volume_db_for_distance(20.0), -6.020599913279624, "inside clamp range")
	attenuator.use_clamp = false
	_near(attenuator.volume_db_for_distance(0.0), 26.020599913279625, "min_distance 0.5 without clamp")
	_near(attenuator.volume_db_for_distance(1000.0), -40.0, "no clamp far away")
	(rig.root as Node).free()
	return true


func _test_attenuator_absorption() -> bool:
	var rig: Dictionary = _make_rig(Vector3(0.0, 0.0, 0.0))
	var attenuator: AudioDistanceAttenuator = rig.attenuator
	attenuator.use_clamp = false
	attenuator.reference_volume_db = 150.0
	attenuator.reference_distance = 10.0
	attenuator.world_unit_in_meters = SoundFalloff.METERS_PER_FOOT
	attenuator.absorption_db_per_km = 1.9
	_near(attenuator.volume_db_for_distance(1000.0), 109.4266712, "same as the core vector in feet")
	(rig.root as Node).free()
	return true


func _test_attenuator_signal() -> bool:
	var rig: Dictionary = _make_rig(Vector3(3.0, 4.0, 0.0))
	var attenuator: AudioDistanceAttenuator = rig.attenuator
	var received: Array = []
	attenuator.volume_updated.connect(func(d: float, v: float) -> void: received.append([d, v]))
	attenuator.use_clamp = false
	attenuator.update_volume()
	_check(received.size() == 1, "signal emitted once")
	if received.size() == 1:
		var pair: Array = received[0]
		var got_distance: float = pair[0]
		var got_volume: float = pair[1]
		_near(got_distance, 5.0, "signal distance")
		_near(got_volume, -13.979400086720377, "signal volume")
	attenuator.listener_path = NodePath("../../Missing")
	_check(is_nan(attenuator.update_volume()), "missing listener returns NAN")
	(rig.root as Node).free()
	return true


func _test_demo_scene() -> bool:
	var packed: PackedScene = load(DEMO_SCENE)
	_check(packed != null, "scene loads")
	if packed == null:
		return true
	var demo: Node3D = packed.instantiate()
	get_root().add_child(demo)
	var attenuator: AudioDistanceAttenuator = demo.get_node("Horn/AudioDistanceAttenuator")
	var horn: AudioStreamPlayer3D = demo.get_node("Horn")
	attenuator.update_volume()
	demo.call("_set_listener_ground_position", Vector2(horn.position.x + 60.96, 0.0))
	attenuator.update_volume()
	# Listener at y=1.7 vs horn at y=4: slant distance, not 60.96 exactly.
	var expected_distance: float = Vector3(60.96, 1.7 - 4.0, 0.0).length()
	_near(attenuator.get_last_distance(), expected_distance, "demo distance", 1e-4)
	_near(horn.volume_db, -12.0 - 20.0 * log(expected_distance / 30.48) / log(10.0), "demo volume", 1e-4)
	demo.call("_update_hud")
	var hud: Label = demo.get_node("HUD/Panel/Label")
	_check(hud.text.contains("Free-field estimate: 104.0 dB"), "HUD shows the estimate, got: %s" % hud.text)
	demo.free()
	return true
