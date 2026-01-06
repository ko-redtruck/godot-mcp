extends Node
## MCP Screenshot Capture Utility
##
## This autoload script captures screenshots of scenes for the Godot MCP server.
## It only activates when the "--mcp-screenshot" command line argument is present.
## Otherwise, it removes itself and has zero impact on the running game.
##
## Config file at res://.mcp_screenshot_config.json specifies:
## { "scene": "res://path/to/scene.tscn", "width": 1920, "height": 1080, "delay": 0.5 }
##
## Screenshots are saved to: res://.mcp_screenshots/<timestamp>_<scene>_<width>x<height>_<delay>s.png

const CONFIG_PATH = "res://.mcp_screenshot_config.json"
const SCREENSHOT_DIR = "res://.mcp_screenshots"
const DEFAULT_WIDTH = 1920
const DEFAULT_HEIGHT = 1080
const DEFAULT_DELAY = 0.5

func _ready() -> void:
	# Only activate if --mcp-screenshot flag is present
	if not "--mcp-screenshot" in OS.get_cmdline_args():
		queue_free()
		return

	_capture_screenshot()

func _capture_screenshot() -> void:
	print("[MCP Screenshot] Starting capture...")

	# Read config file
	var config = _read_config()
	if config == null:
		printerr("[MCP Screenshot] Failed to read config file at: " + CONFIG_PATH)
		get_tree().quit(1)
		return

	var scene_path: String = config.get("scene", "")
	var width: int = int(config.get("width", DEFAULT_WIDTH))
	var height: int = int(config.get("height", DEFAULT_HEIGHT))
	var delay: float = float(config.get("delay", DEFAULT_DELAY))

	# If no scene specified, use current scene (main scene)
	var scene_instance: Node
	var scene_name: String

	if scene_path.is_empty():
		# Use the main scene - wait for it to be ready
		await get_tree().process_frame
		scene_instance = get_tree().current_scene
		scene_name = "main"
		if scene_instance == null:
			printerr("[MCP Screenshot] No main scene found")
			get_tree().quit(1)
			return
		print("[MCP Screenshot] Using main scene")
	else:
		scene_name = scene_path.get_file().get_basename()
		print("[MCP Screenshot] Loading scene: " + scene_path)

		var scene_resource = load(scene_path)
		if scene_resource == null:
			printerr("[MCP Screenshot] Failed to load scene: " + scene_path)
			get_tree().quit(1)
			return
		scene_instance = scene_resource.instantiate()

	print("[MCP Screenshot] Size: %dx%d, Delay: %.2fs" % [width, height, delay])

	# Create a SubViewport for rendering
	var viewport = SubViewport.new()
	viewport.size = Vector2i(width, height)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false

	# If we loaded a scene, add it to viewport
	# If using main scene, we need to reparent it temporarily
	var original_parent: Node = null
	if scene_path.is_empty():
		original_parent = scene_instance.get_parent()
		if original_parent:
			original_parent.remove_child(scene_instance)
		viewport.add_child(scene_instance)
	else:
		viewport.add_child(scene_instance)

	add_child(viewport)

	# Wait for initial render
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	# Wait the specified delay
	if delay > 0:
		print("[MCP Screenshot] Waiting %.2f seconds..." % delay)
		await get_tree().create_timer(delay).timeout

	# Final render wait
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	# Capture the image
	var image: Image = viewport.get_texture().get_image()
	if image == null:
		printerr("[MCP Screenshot] Failed to get viewport image")
		get_tree().quit(1)
		return

	# Generate output path
	var output_path = _generate_output_path(scene_name, width, height, delay)

	# Ensure screenshot directory exists
	_ensure_screenshot_dir()

	# Save the image
	var error = image.save_png(output_path)
	if error != OK:
		printerr("[MCP Screenshot] Failed to save image: " + str(error))
		get_tree().quit(1)
		return

	# Print the absolute path for MCP to read
	var absolute_path = ProjectSettings.globalize_path(output_path)
	print("[MCP Screenshot] SUCCESS:" + absolute_path)

	# Clean up config file
	_delete_config()

	get_tree().quit(0)

func _read_config() -> Variant:
	if not FileAccess.file_exists(CONFIG_PATH):
		return null

	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return null

	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		printerr("[MCP Screenshot] JSON parse error: " + json.get_error_message())
		return null

	return json.get_data()

func _delete_config() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_PATH))

func _ensure_screenshot_dir() -> void:
	var dir = DirAccess.open("res://")
	if dir and not dir.dir_exists(".mcp_screenshots"):
		dir.make_dir(".mcp_screenshots")

func _generate_output_path(scene_name: String, width: int, height: int, delay: float) -> String:
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var filename = "%s_%s_%dx%d_%.1fs.png" % [timestamp, scene_name, width, height, delay]
	return SCREENSHOT_DIR + "/" + filename
