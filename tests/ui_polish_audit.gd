extends SceneTree

var _selection := ""
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _on_map_selected(id: String) -> void:
	_selection = id


func _check(condition: bool, description: String) -> void:
	print("[ui-polish] %s %s" % ["PASS" if condition else "FAIL", description])
	if not condition:
		_failures += 1


func _run() -> void:
	var title: CanvasLayer = load("res://scripts/ui/title_screen.gd").new()
	root.add_child(title)
	title.open()
	title.map_selected.connect(_on_map_selected)
	await process_frame
	for key: String in title._selectors:
		var button: OptionButton = title._selectors[key]
		button._prepare_popup()
		var popup := button.get_popup()
		_check(button.has_meta("ink_dropdown"), "%s uses InkOptionButton" % key)
		_check(popup.theme == button.theme, "%s assigns the real popup theme" % key)
		_check(popup.get_theme_stylebox("panel") is StyleBoxTexture, "%s popup has painted paper panel" % key)
		_check(popup.get_theme_icon("radio_checked").resource_path.ends_with("choice_seal.svg"), "%s selected item uses cinnabar seal" % key)
		_check(popup.is_item_checked(button.selected), "%s current selection is checked" % key)
	var maps: OptionButton = title._selectors.selected_map
	maps.select(1)
	maps.item_selected.emit(1)
	_check(_selection == "bamboo_night", "map selection emits preview signal")
	_check(title._preview_title.text == "青岚夜院", "preview caption follows selected map")
	maps.select(0)
	maps.item_selected.emit(0)
	_check(_selection == "courtyard", "map selection can return to courtyard")
	var settings: CanvasLayer = load("res://scripts/ui/settings_screen.gd").new()
	root.add_child(settings)
	settings.open()
	await process_frame
	for key: String in settings._controls:
		var control: Control = settings._controls[key]
		if control is OptionButton:
			control._prepare_popup()
			_check(control.get_popup().theme == control.theme, "settings %s popup uses explicit ink theme" % key)
	_check(settings._controls.has("music_volume"), "music volume is separately adjustable")
	settings.close()
	title.queue_free()
	settings.queue_free()
	await process_frame
	# A delayed settings signal must not hold a released label/control capture.
	root.get_node("Settings").bindings_changed.emit()
	await process_frame
	print("[ui-polish] RESULT failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)
