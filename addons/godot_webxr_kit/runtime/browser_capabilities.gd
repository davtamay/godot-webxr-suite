extends Control

## Attach this to a small diagnostics Control in the Godot demo.
## It reads the browser capability object created by company_webxr_shell.html.

@export var output_label_path: NodePath

var _output_label: Label

func _ready() -> void:
    if output_label_path != NodePath():
        _output_label = get_node_or_null(output_label_path) as Label
    _refresh()

func _refresh() -> void:
    var text := "Browser capability data unavailable."

    if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
        var js_bridge = Engine.get_singleton("JavaScriptBridge")
        var caps_json = js_bridge.eval("JSON.stringify(window.CompanyWebCaps || {})", true)
        text = str(caps_json)
    elif not OS.has_feature("web"):
        text = "Not running in web export. Browser capabilities are only available in exported web builds."

    if _output_label:
        _output_label.text = text
    else:
        print(text)
