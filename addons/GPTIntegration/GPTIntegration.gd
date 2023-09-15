@tool
extends EditorPlugin

const MySettings:StringName = "res://addons/GPTIntegration/settings.json"

enum modes {
	Action, 
	Summarise,
	Chat,
	Help
}

var api_key = ""
var max_tokens = 1024
var temperature = 0.5
var url = "https://api.openai.com/v1/chat/completions"
var headers = ["Content-Type: application/json", "Authorization: Bearer " + api_key]
var engine = "gpt-3.5-turbo"
var chat_dock
var http_request :HTTPRequest
var current_mode
var cursor_pos
var code_editor
var settings_menu

func _enter_tree():
	printt('_enter_tree')
	chat_dock = preload("res://addons/GPTIntegration/Chat.tscn").instantiate()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UR, chat_dock)
	
	chat_dock.get_node("Button").connect("pressed", _on_chat_button_down)
	chat_dock.get_node("HBoxContainer/Action").connect("pressed", _on_action_button_down)
	chat_dock.get_node("HBoxContainer/Help").connect("pressed", _on_help_button_down)
	chat_dock.get_node("HBoxContainer/Summary").connect("pressed", _on_summary_button_down)
	# Initialization of the plugin goes here.
	add_tool_menu_item("GPT Chat", on_show_settings)
	load_settings()
	pass

func on_show_settings():
	settings_menu = preload("res://addons/GPTIntegration/SettingsWindow.tscn").instantiate()
	settings_menu.get_node("Control/Button").connect("pressed", on_settings_button_down)
	set_settings(api_key, int(max_tokens), float(temperature), engine)
	add_child(settings_menu)
	settings_menu.connect("close_requested", settings_menu_close)
	settings_menu.popup()
	
func on_settings_button_down():
	api_key = settings_menu.get_node("HBoxContainer/VBoxContainer2/APIKey").text
	
	max_tokens = int(settings_menu.get_node("HBoxContainer/VBoxContainer2/MaxTokens").text)
	temperature = float(settings_menu.get_node("HBoxContainer/VBoxContainer2/Temperature").text)
	var index = settings_menu.get_node("HBoxContainer/VBoxContainer2/OptionButton").selected
	
	
	if index == 0:
		engine = "gpt-4"
	elif index == 1:
		engine = "gpt-3.5-turbo"
	print(engine)
	settings_menu_close()
	save_settings()
	pass

func settings_menu_close():
	settings_menu.queue_free()
	pass

# This GDScript code sets the settings in a settings
# menu. It sets the API key, the maximum number of tokens,
# the temperature, and the engine. The engine is set
# by selecting the corresponding ID from a list of options.
func set_settings(api_key, maxtokens, temp, engine):
	settings_menu.get_node("HBoxContainer/VBoxContainer2/APIKey").text = api_key
	settings_menu.get_node("HBoxContainer/VBoxContainer2/MaxTokens").text = str(maxtokens)
	settings_menu.get_node("HBoxContainer/VBoxContainer2/Temperature").text = str(temp)
	var id = 0
	
	if engine == "gpt-4":
		id == 0
	elif engine == "gpt-3.5-turbo":
		id == 1
		
	settings_menu.get_node("HBoxContainer/VBoxContainer2/OptionButton").select(id)

func _exit_tree():
	# Clean-up of the plugin goes here.
	remove_control_from_docks(chat_dock)
	chat_dock.queue_free()
	remove_tool_menu_item("GPT Chat")
	save_settings()
	pass

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", _on_request_completed)

func _on_chat_button_down():
	if(chat_dock.get_node("TextEdit").text != ""):
		current_mode = modes.Chat
		var prompt = chat_dock.get_node("TextEdit").text
		chat_dock.get_node("TextEdit").text = ""
		add_to_chat("Me: " + prompt)
		call_GPT(prompt)
		
		
func call_GPT(prompt):
	var body = JSON.new().stringify({
		"messages" : [
		{
			"role": "user",
			"content": prompt
		}
			],
		"temperature": temperature,
		"max_tokens": max_tokens,
		"model": engine
	})
	var error = http_request.request(url, ["Content-Type: application/json", "Authorization: Bearer " + api_key], HTTPClient.METHOD_POST, body)
	
	if error != OK:
		push_error("Something Went Wrong!")

func _on_action_button_down():
	current_mode = modes.Action
	call_GPT("Code this for Godot " + get_selected_code())
	
func _on_help_button_down():
	current_mode = modes.Help
	var code = get_selected_code()
	chat_dock.get_node("TextEdit").text = ""
	add_to_chat("Me: " + "What is wrong with this GDScript code? " + code)
	call_GPT("What is wrong with this GDScript code? " + code)
	
func _on_summary_button_down():
	current_mode = modes.Summarise
	call_GPT("Summarize this GDScript Code " + get_selected_code())
	


# This GDScript code is used to handle the response from
# a request and either add it to a chat or summarise
# it. If the mode is set to Chat, it will add the response
# to the chat with the prefix "GPT". If the mode is set
# to Summarise, it will loop through the response and
# insert it into the code editor as a summarised version
# with each line having a maximum length of 50 characters
# and each line starting with a "#".
func _on_request_completed(result, responseCode, headers, body):
	printt(result, responseCode, headers, body)
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result:
		printerr(parse_result)
		return
	var response = json.get_data()
	if response is Dictionary:
		printt("Response", response)
		if response.has("error"):
			printt("Error", response['error'])
			return
	else:
		printt("Response is not a Dictionary", headers)
		return
	
	var newStr = response.choices[0].message.content
	if current_mode == modes.Chat:
		add_to_chat("GPT: " + newStr)
	elif current_mode == modes.Summarise:
		var str = response.choices[0].message.content.replace("\n" , "")
		newStr = "# "
		var lineLength = 50
		var currentLineLength = 0
		for i in range(str.length()):
			if currentLineLength >= lineLength and str[i] == " ":
				newStr += "\n# "
				currentLineLength = 0
			else:
				newStr += str[i]
				currentLineLength += 1
		code_editor.insert_line_at(cursor_pos, newStr)
	elif current_mode == modes.Action:
		code_editor.insert_line_at(cursor_pos, newStr)
	elif current_mode == modes.Help:
		add_to_chat("GPT: " + response.choices[0].text)
	pass
	
func get_selected_code():
	var currentScriptEditor = get_editor_interface().get_script_editor().get_current_editor()
	
	code_editor = currentScriptEditor.get_base_editor()
	
	if current_mode == modes.Summarise:
		cursor_pos = code_editor.get_selection_from_line()
	elif current_mode == modes.Action:
		cursor_pos = code_editor.get_selection_to_line()
	return code_editor.get_selected_text()

func add_to_chat(text):
	var chat_bubble = preload("res://addons/GPTIntegration/ChatBubble.tscn").instantiate()
	chat_bubble.get_node("RichTextLabel").text = "\n" + text + "\n"
	chat_dock.get_node("ScrollContainer/VBoxContainer").add_child(chat_bubble)
	#chat_dock.get_node("RichTextLabel").text += "\n" + text + "\n"

# This GDScript code creates a JSON file containing the
# values of the variables "api_key", "max_tokens", "temperature",
# and "engine", and stores the file in the "res://addons/GPTIntegration/"
# directory.
func save_settings():
	
	var data ={
		"api_key":api_key,
		"max_tokens": max_tokens,
		"temperature": temperature,
		"engine": engine
	}
	print(data)
	var jsonStr = JSON.stringify(data)
	var file = FileAccess.open(MySettings, FileAccess.WRITE)
	
	file.store_string(jsonStr)
	file.close()

# This GDScript code opens a JSON file, parses the data
# from it, and assigns the values to variables. The variables
# are api_key, max_tokens, temperature, and engine.
func load_settings():
	if not FileAccess.file_exists(MySettings):
		save_settings()

	var file = FileAccess.open(MySettings, FileAccess.READ)
	if not file:
		printerr("Unable to create", MySettings, error_string(ERR_CANT_CREATE))
		print_stack()
		return

	var jsonStr = file.get_as_text()
	file.close()
	var data = JSON.parse_string(jsonStr)
	print(data)
	api_key = data["api_key"]
	max_tokens = int(data["max_tokens"])
	temperature = float(data["temperature"])
	engine = data["engine"]


