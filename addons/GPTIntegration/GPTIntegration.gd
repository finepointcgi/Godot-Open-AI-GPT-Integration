@tool
extends EditorPlugin

enum modes {
	Action, 
	Summarise,
	Chat,
	Help
}

var apiKey = ""
var max_tokens = 1024
var temperature = 0.5
var url = "https://api.openai.com/v1/completions"
var headers : Array
var engine = "text-davinachi-003"
var chatDock
var httpRequest
var currentMode
var cursorPos
var codeEditor
var settingsMenu

func update_headers():
	headers = ["Content-Type: application/json", "Authorization: Bearer " + apiKey]

func _enter_tree():
	chatDock = preload("res://addons/GPTIntegration/Chat.tscn").instantiate()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UR, chatDock)
	
	chatDock.get_node("Button").connect("pressed", onChatButtonDown)
	chatDock.get_node("HBoxContainer/Action").connect("pressed", onActionButtonDown)
	chatDock.get_node("HBoxContainer/Help").connect("pressed", onHelpButtonDown)
	chatDock.get_node("HBoxContainer/Summary").connect("pressed", onSummaryButtonDown)
	# Initialization of the plugin goes here.
	add_tool_menu_item("GPT Chat", onShowSettings)
	loadSettings()
	update_headers()
	pass

func onShowSettings():
	settingsMenu = preload("res://addons/GPTIntegration/SettingsWindow.tscn").instantiate()
	settingsMenu.get_node("Control/Button").connect("pressed", onSettingsButtonDown)
	setSettings(apiKey, int(max_tokens), float(temperature), engine)
	add_child(settingsMenu)
	settingsMenu.connect("close_requested", settingsMenuClose)
	settingsMenu.popup()
	
func onSettingsButtonDown():
	var index : int
	apiKey = settingsMenu.get_node("HBoxContainer/VBoxContainer2/APIKey").text
	update_headers()
	max_tokens = int(settingsMenu.get_node("HBoxContainer/VBoxContainer2/MaxTokens").text)
	temperature = float(settingsMenu.get_node("HBoxContainer/VBoxContainer2/Temperature").text)
	index = settingsMenu.get_node("HBoxContainer/VBoxContainer2/OptionButton").selected
	
	if index == 0:
		engine = "text-davinchi-003"
	settingsMenuClose()
	pass

func settingsMenuClose():
	settingsMenu.queue_free()
	pass

func setSettings(apikey, maxtokens, temp, engine):
	settingsMenu.get_node("HBoxContainer/VBoxContainer2/APIKey").text = apikey
	settingsMenu.get_node("HBoxContainer/VBoxContainer2/MaxTokens").text = var_to_str(maxtokens)
	settingsMenu.get_node("HBoxContainer/VBoxContainer2/Temperature").text = var_to_str(temp)
	var id = 0
	if engine == "text-davinchi-003":
		id = 0
	settingsMenu.get_node("HBoxContainer/VBoxContainer2/OptionButton").selected = id

func _exit_tree():
	# Clean-up of the plugin goes here.
	remove_control_from_docks(chatDock)
	chatDock.queue_free()
	remove_tool_menu_item("GPT Chat")
	saveSettings()
	pass

func _ready():
	httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	httpRequest.connect("request_completed", onRequestCompleted)

func onChatButtonDown():
	if(chatDock.get_node("TextEdit").text != ""):
		currentMode = modes.Chat
		var prompt = chatDock.get_node("TextEdit").text
		chatDock.get_node("TextEdit").text = ""
		AddToChat("Me: " + prompt)
		CallGPT(prompt)
		
func CallGPT(prompt):
	print(headers)
	var body = JSON.new().stringify({
		"prompt": prompt,
		"temperature": temperature,
		"max_tokens": max_tokens,
		"model": "text-davinci-003"
	})
	var error = httpRequest.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		push_error("Something Went Wrong!")
	
func onActionButtonDown():
	currentMode = modes.Action
	CallGPT("Code the following prompt in GDscript for the Godot game engine: " + GetSelectedCode())
	
func onHelpButtonDown():
	currentMode = modes.Help
	var code = GetSelectedCode()
	chatDock.get_node("TextEdit").text = ""
	AddToChat("Me: " + "What is wrong with this GDScript code? " + code)
	CallGPT("What is wrong with this GDScript code? " + code)
	
func onSummaryButtonDown():
	currentMode = modes.Summarise
	CallGPT("Summarize this GDScript Code: " + GetSelectedCode())
	print("onSummaryButtonDown Pressed")


# This GDScript code is used to handle the response from
# a request and either add it to a chat or summarise
# it. If the mode is set to Chat, it will add the response
# to the chat with the prefix "GPT". If the mode is set
# to Summarise, it will loop through the response and
# insert it into the code editor as a summarised version
# with each line having a maximum length of 50 characters
# and each line starting with a "#".
func onRequestCompleted(result, responseCode, headers, body):
	var json = JSON.new()
	json.parse(body.get_string_from_utf8())
	var response = json.get_data()
	print(response)
	
	var newStr = response.choices[0].text
	if currentMode == modes.Chat:
		AddToChat("GPT: " + newStr)
	elif currentMode == modes.Summarise:
		var str = response.choices[0].text.replace("\n" , "")
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
		codeEditor.insert_line_at(cursorPos, newStr)
	elif currentMode == modes.Action:
		codeEditor.insert_line_at(cursorPos, newStr)
	elif currentMode == modes.Help:
		AddToChat("GPT: " + response.choices[0].text)
	pass
	
func GetSelectedCode():
	var currentScriptEditor = get_editor_interface().get_script_editor().get_current_editor()
	
	codeEditor = currentScriptEditor.get_base_editor()
	
	if currentMode == modes.Summarise:
		cursorPos = codeEditor.get_selection_from_line()
	elif currentMode == modes.Action:
		cursorPos = codeEditor.get_selection_to_line()
	return codeEditor.get_selected_text()

func AddToChat(text):
	chatDock.get_node("RichTextLabel").text += "\n" + text + "\n"

func saveSettings():
	var data ={
		"api_key":apiKey,
		"max_tokens": max_tokens,
		"temperature": temperature,
		"engine": engine
	}
	var jsonStr = JSON.stringify(data)
	var file = FileAccess.open("res://addons/GPTIntegration/settings.json",FileAccess.WRITE)
	
	file.store_string(jsonStr)
	file.close()

func loadSettings():
	var file = FileAccess.open("res://addons/GPTIntegration/settings.json",FileAccess.READ)

	var jsonStr = file.get_as_text()
	file.close()
	var data = JSON.parse_string(jsonStr)
	
	apiKey = data["api_key"]
	max_tokens = int(data["max_tokens"])
	temperature = float(data["temperature"])
	engine = data["engine"]
