extends Node3D
## Demo: a locomotive horn at a grade crossing and a listener you can drag.
##
## Scale: 1 world unit = 1 metre. The horn is modelled as 110 dB at 100 ft
## (30.48 m), the upper limit US rules (49 CFR 229.129) set for a locomotive
## horn measured 100 ft ahead. The AudioDistanceAttenuator child of the horn
## maps that to volume_db = -12 dB at 30.48 m and lets the inverse-square law
## do the rest. Drag with the left mouse button (or use the arrow keys) to
## move the listener. Space toggles the horn.
##
## The horn sound is synthesized in code (five sine partials of a B major
## sixth chord, in the style of a five-chime locomotive horn) and played in
## the US grade-crossing pattern: long, long, short, long.

const REAL_REFERENCE_DB: float = 110.0
const REAL_REFERENCE_DISTANCE_M: float = 30.48
const RING_DISTANCES_M: Array[float] = [30.48, 60.96, 121.92, 243.84]
const CHORD_HZ: Array[float] = [311.13, 369.99, 415.30, 493.88, 622.25]
## Grade-crossing pattern as [on_seconds, off_seconds] pairs; the last gap is
## the pause before the pattern repeats.
const PATTERN: Array[Vector2] = [
	Vector2(2.0, 0.5), Vector2(2.0, 0.5), Vector2(0.8, 0.5), Vector2(3.0, 3.0),
]
const MIX_RATE: float = 44100.0
const KEY_SPEED_M_PER_S: float = 40.0
const LISTENER_LIMIT := Vector2(300.0, 150.0)

var _phases: PackedFloat64Array = []
var _pattern_time: float = 0.0
var _envelope: float = 0.0
var _horn_enabled: bool = true
var _dragging: bool = false
var _playback: AudioStreamGeneratorPlayback
var _screenshot_path: String = ""
var _frames_rendered: int = 0

@onready var _horn: AudioStreamPlayer3D = $Horn
@onready var _attenuator: AudioDistanceAttenuator = $Horn/AudioDistanceAttenuator
@onready var _listener: Node3D = $Listener
@onready var _camera: Camera3D = $Camera3D
@onready var _hud: Label = $HUD/Panel/Label


func _ready() -> void:
	_build_world()
	_phases.resize(CHORD_HZ.size())
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.15
	_horn.stream = generator
	_horn.play()
	_playback = _horn.get_stream_playback() as AudioStreamGeneratorPlayback
	($Listener/AudioListener3D as AudioListener3D).make_current()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = args.find("--screenshot")
	if index != -1 and index + 1 < args.size():
		_screenshot_path = args[index + 1]


func _process(delta: float) -> void:
	_move_with_keys(delta)
	_fill_audio_buffer()
	_update_hud()
	if not _screenshot_path.is_empty():
		_frames_rendered += 1
		if _frames_rendered == 10:
			var image: Image = get_viewport().get_texture().get_image()
			image.save_png(_screenshot_path)
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button and mouse_button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mouse_button.pressed
		if _dragging:
			_move_listener_to_screen_point(mouse_button.position)
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		_move_listener_to_screen_point(motion.position)
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_SPACE:
		_horn_enabled = not _horn_enabled


func _move_listener_to_screen_point(screen_point: Vector2) -> void:
	var origin: Vector3 = _camera.project_ray_origin(screen_point)
	var direction: Vector3 = _camera.project_ray_normal(screen_point)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if hit is Vector3:
		var point: Vector3 = hit
		_set_listener_ground_position(Vector2(point.x, point.z))


func _move_with_keys(delta: float) -> void:
	var input := Vector2(
			Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if input != Vector2.ZERO:
		var current := Vector2(_listener.position.x, _listener.position.z)
		_set_listener_ground_position(current + input * KEY_SPEED_M_PER_S * delta)


func _set_listener_ground_position(point: Vector2) -> void:
	point = point.clamp(-LISTENER_LIMIT, LISTENER_LIMIT)
	_listener.position = Vector3(point.x, _listener.position.y, point.y)


func _fill_audio_buffer() -> void:
	if _playback == null:
		return
	var frames: int = _playback.get_frames_available()
	var step: float = 1.0 / MIX_RATE
	for _frame in frames:
		_pattern_time += step
		var target: float = 1.0 if _horn_enabled and _is_pattern_on(_pattern_time) else 0.0
		# Short attack and release so notes do not click.
		_envelope = move_toward(_envelope, target, step / 0.03)
		var sample: float = 0.0
		for i in CHORD_HZ.size():
			_phases[i] = fmod(_phases[i] + CHORD_HZ[i] * step, 1.0)
			var phase: float = _phases[i] * TAU
			sample += sin(phase) + 0.35 * sin(2.0 * phase) + 0.15 * sin(3.0 * phase)
		sample *= 0.12 * _envelope
		_playback.push_frame(Vector2(sample, sample))


func _is_pattern_on(time: float) -> bool:
	var total: float = 0.0
	for part in PATTERN:
		total += part.x + part.y
	var t: float = fmod(time, total)
	for part in PATTERN:
		if t < part.x:
			return true
		t -= part.x
		if t < part.y:
			return false
		t -= part.y
	return false


func _update_hud() -> void:
	var distance: float = _attenuator.get_last_distance()
	if is_nan(distance):
		return
	var real_db: float = SoundFalloff.level_at_distance(
			REAL_REFERENCE_DB, maxf(distance, _attenuator.min_distance), REAL_REFERENCE_DISTANCE_M)
	_hud.text = (
			"Locomotive horn modelled as 110 dB at 100 ft (30.48 m)\n"
			+ "Distance to listener: %.1f m (%.0f ft)\n" % [distance, SoundFalloff.meters_to_feet(distance)]
			+ "Free-field estimate: %.1f dB\n" % real_db
			+ "AudioStreamPlayer3D.volume_db: %.1f dB\n" % _horn.volume_db
			+ "Drag or arrow keys: move listener   Space: horn %s" % ("on" if _horn_enabled else "off"))


func _build_world() -> void:
	_add_box(Vector3(900.0, 0.2, 400.0), Vector3(0.0, -0.1, 0.0), Color(0.36, 0.45, 0.30))
	_add_box(Vector3(900.0, 0.3, 6.0), Vector3(0.0, 0.0, 0.0), Color(0.42, 0.37, 0.32))
	for z: float in [-0.75, 0.75]:
		_add_box(Vector3(900.0, 0.4, 0.4), Vector3(0.0, 0.2, z), Color(0.75, 0.75, 0.78))
	_add_box(Vector3(10.0, 0.25, 400.0), Vector3(0.0, 0.05, 0.0), Color(0.22, 0.22, 0.24))
	_add_box(Vector3(22.0, 4.5, 3.2), Vector3(-18.0, 2.4, 0.0), Color(0.95, 0.72, 0.10))
	for i in RING_DISTANCES_M.size():
		var radius: float = RING_DISTANCES_M[i]
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = radius - 0.8
		torus.outer_radius = radius + 0.8
		torus.rings = 128
		ring.mesh = torus
		ring.material_override = _unshaded(Color(0.72, 0.25, 0.11))
		ring.position = Vector3(_horn.position.x, 0.6, _horn.position.z)
		add_child(ring)
		var label := Label3D.new()
		var level: float = SoundFalloff.level_at_distance(
				REAL_REFERENCE_DB, radius, REAL_REFERENCE_DISTANCE_M)
		label.text = "%.0f ft: %.0f dB" % [SoundFalloff.meters_to_feet(radius), level]
		label.pixel_size = 0.25
		label.font_size = 34
		label.outline_size = 12
		label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		# Each label starts where its ring crosses the 30-degree line above the track.
		var direction := Vector3(cos(deg_to_rad(30.0)), 0.0, -sin(deg_to_rad(30.0)))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.position = Vector3(_horn.position.x + 3.0, 1.0, -4.0) + direction * radius
		add_child(label)
	var marker := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 5.0
	cylinder.bottom_radius = 5.0
	cylinder.height = 2.0
	marker.mesh = cylinder
	marker.material_override = _unshaded(Color(0.15, 0.45, 0.95))
	marker.position.y = 1.0
	_listener.add_child(marker)


func _add_box(size: Vector3, center: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = _unshaded(color)
	instance.position = center
	add_child(instance)


func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
