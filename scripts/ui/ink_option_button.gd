class_name InkOptionButton
extends OptionButton

## OptionButton owns a separate PopupMenu window. Assign its theme explicitly;
## styling the closed button or its Control parent does not style that window.
var _paper_theme: Theme


func _ready() -> void:
	_paper_theme = UITheme.dropdown_theme()
	theme = _paper_theme
	var popup := get_popup()
	popup.theme = _paper_theme
	# Native desktop menus bypass the game's font, paper panel and seal icons.
	for property: Dictionary in popup.get_property_list():
		if property.name == "prefer_native_menu":
			popup.set("prefer_native_menu", false)
	popup.about_to_popup.connect(_prepare_popup)
	item_selected.connect(_on_ink_selected)
	set_meta("ink_dropdown", true)


func _prepare_popup() -> void:
	var popup := get_popup()
	popup.theme = _paper_theme
	popup.min_size.x = ceili(size.x * get_global_transform_with_canvas().get_scale().x)
	popup.set_focused_item(selected)
	# Give the selected row its own seal even when navigation moves the focus.
	for index in item_count:
		popup.set_item_as_radio_checkable(index, true)
		popup.set_item_checked(index, index == selected)


func _on_ink_selected(_index: int) -> void:
	Sfx.play("click", -9.0)
