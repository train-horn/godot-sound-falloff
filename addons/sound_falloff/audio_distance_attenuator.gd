@tool
@icon("res://addons/sound_falloff/icon.svg")
class_name AudioDistanceAttenuator
extends Node
## Drives an [AudioStreamPlayer3D]'s [member AudioStreamPlayer3D.volume_db]
## from the real-world inverse-square law.
##
## Add it as a child of an [AudioStreamPlayer3D] (or point [member player_path]
## at one). Every frame it measures the distance from the player to the
## listener and sets:
## [codeblock]
## volume_db = reference_volume_db - 20 * log10(d / reference_distance)
##             - absorption_db_per_km * (d - reference_distance) / 1000
## [/codeblock]
## so the level falls 6.02 dB per doubling of distance, like a point source
## in open air. By default it also sets the player's
## [member AudioStreamPlayer3D.attenuation_model] to
## [constant AudioStreamPlayer3D.ATTENUATION_DISABLED] so Godot's own distance
## curve is not applied on top. Panning, Doppler and
## [member AudioStreamPlayer3D.max_distance] still work as usual.

## Emitted when [member AudioStreamPlayer3D.volume_db] is updated.
signal volume_updated(distance: float, volume_db: float)

## The player to drive. Empty means the parent node.
@export var player_path: NodePath
## The listener position. Empty means the current [Camera3D] of the viewport.
## Point it at an [AudioListener3D] (or any [Node3D]) when the listener is not
## the camera.
@export var listener_path: NodePath

@export_group("Inverse-square law")
## Distance (in world units) at which [member reference_volume_db] applies.
@export_range(0.001, 10000.0, 0.001, "or_greater", "suffix:units") var reference_distance: float = 1.0
## [member AudioStreamPlayer3D.volume_db] at [member reference_distance].
@export_range(-80.0, 24.0, 0.1, "or_less", "or_greater", "suffix:dB") var reference_volume_db: float = 0.0
## Optional air absorption in dB per km (0 = pure inverse-square). See
## [constant SoundFalloff.AIR_ABSORPTION_DB_PER_KM] for typical values.
@export_range(0.0, 200.0, 0.1, "or_greater", "suffix:dB/km") var absorption_db_per_km: float = 0.0
## Metres in one world unit (1.0 for the usual Godot scale). Only used by the
## absorption term.
@export_range(0.001, 1000.0, 0.001, "or_greater", "suffix:m") var world_unit_in_meters: float = 1.0
## Distances below this value are treated as this value, to avoid an infinite
## level at distance 0. The inverse-square law is not valid very close to a
## source anyway.
@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:units") var min_distance: float = 0.1

@export_group("Clamp")
## When on, the result is clamped to [member min_volume_db]..[member max_volume_db].
@export var use_clamp: bool = true
## Lowest [member AudioStreamPlayer3D.volume_db] the node will set.
@export_range(-80.0, 24.0, 0.1, "or_less", "suffix:dB") var min_volume_db: float = -80.0
## Highest [member AudioStreamPlayer3D.volume_db] the node will set.
@export_range(-80.0, 24.0, 0.1, "or_greater", "suffix:dB") var max_volume_db: float = 6.0

@export_group("Behaviour")
## Set the player's attenuation model to "Disabled" when the node is ready.
@export var disable_builtin_attenuation: bool = true
## Update in [method Node._process]. Turn off and call [method update_volume]
## yourself if you want to drive it manually.
@export var auto_update: bool = true

var _last_distance: float = NAN


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var player: AudioStreamPlayer3D = get_player()
	if player == null:
		push_warning("AudioDistanceAttenuator: no AudioStreamPlayer3D found (set player_path or add the node as a child of one).")
		return
	if disable_builtin_attenuation:
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	update_volume()


func _process(_delta: float) -> void:
	if auto_update and not Engine.is_editor_hint():
		update_volume()


## Returns the player this node drives, or [code]null[/code].
func get_player() -> AudioStreamPlayer3D:
	var node: Node = get_node_or_null(player_path) if not player_path.is_empty() else get_parent()
	return node as AudioStreamPlayer3D


## Returns the listener node, or [code]null[/code] when there is none.
func get_listener() -> Node3D:
	if not listener_path.is_empty():
		return get_node_or_null(listener_path) as Node3D
	if not is_inside_tree():
		return null
	return get_viewport().get_camera_3d()


## Distance from the player to the listener at the last update
## ([constant @GDScript.NAN] before the first update).
func get_last_distance() -> float:
	return _last_distance


## The [member AudioStreamPlayer3D.volume_db] this node would set at
## [param distance] (world units), including the clamp.
func volume_db_for_distance(distance: float) -> float:
	var d: float = maxf(distance, min_distance)
	var volume: float = SoundFalloff.level_at_distance(
			reference_volume_db, d, reference_distance, absorption_db_per_km, world_unit_in_meters)
	if is_nan(volume):
		return min_volume_db
	if use_clamp:
		volume = clampf(volume, min_volume_db, max_volume_db)
	return volume


## Measures the distance now and updates the player's volume. Returns the new
## [member AudioStreamPlayer3D.volume_db], or [constant @GDScript.NAN] when the
## player or listener is missing.
func update_volume() -> float:
	var player: AudioStreamPlayer3D = get_player()
	var listener: Node3D = get_listener()
	if player == null or listener == null or not player.is_inside_tree() or not listener.is_inside_tree():
		return NAN
	_last_distance = player.global_position.distance_to(listener.global_position)
	var volume: float = volume_db_for_distance(_last_distance)
	player.volume_db = volume
	volume_updated.emit(_last_distance, volume)
	return volume


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if get_player() == null:
		warnings.append("Add this node as a child of an AudioStreamPlayer3D, or set player_path.")
	if use_clamp and min_volume_db > max_volume_db:
		warnings.append("min_volume_db is greater than max_volume_db.")
	return warnings
