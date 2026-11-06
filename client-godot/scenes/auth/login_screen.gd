extends Control

## Login and Register Scene for Godot 4 Client

@onready var username_input: LineEdit = %UsernameInput
@onready var password_input: LineEdit = %PasswordInput
@onready var master_name_input: LineEdit = %MasterNameInput
@onready var login_button: Button = %LoginButton
@onready var register_button: Button = %RegisterButton
@onready var status_label: Label = %StatusLabel

func _ready() -> void:
	login_button.pressed.connect(_on_login_pressed)
	register_button.pressed.connect(_on_register_pressed)
	username_input.text = GameState.DEFAULT_DEMO_USERNAME
	password_input.text = GameState.DEFAULT_DEMO_PASSWORD
	status_label.text = "Đang tự động đăng nhập tài khoản mặc định (demo)..."
	_set_loading(true)
	var ok := await GameState.ensure_demo_session()
	_set_loading(false)
	if ok:
		_go_to_hub()
		return
	status_label.text = "Chế độ mặc định (demo): Nhấn Đăng nhập hoặc kiểm tra kết nối máy chủ."

func _set_loading(is_loading: bool) -> void:
	login_button.disabled = is_loading
	register_button.disabled = is_loading
	username_input.editable = not is_loading
	password_input.editable = not is_loading

func _on_login_pressed() -> void:
	var username = username_input.text.strip_edges()
	var password = password_input.text.strip_edges()
	if username.is_empty() or password.is_empty():
		status_label.text = "Vui lòng nhập tên đăng nhập và mật khẩu."
		return
		
	_set_loading(true)
	status_label.text = "Đang đăng nhập..."
	
	var res = await ApiClient.post_req("/api/auth/login", {
		"username": username,
		"password": password
	})
	
	_set_loading(false)
	if not res["ok"]:
		status_label.text = "Đăng nhập thất bại: " + str(res["error"])
		return
		
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	var token: String = str(data.get("accessToken", data.get("token", "")))
	if token.is_empty():
		status_label.text = "Máy chủ không trả về token hợp lệ. Data: " + str(res["data"])
		return
		
	ApiClient.set_auth_token(token)
	status_label.text = "Đăng nhập thành công! Đang tải dữ liệu Master..."
	
	var profile_ok = await GameState.refresh_profile()
	if profile_ok:
		await GameState.refresh_heroes()
		status_label.text = "Xin chào Master " + GameState.master_name + "!"
		_go_to_hub()
	else:
		# Chưa khởi tạo Master? Thử init master
		var m_name = master_name_input.text.strip_edges()
		if m_name.is_empty():
			m_name = username
		var init_res = await ApiClient.post_req("/api/masters/init", {
			"masterName": m_name
		})
		if init_res["ok"]:
			await GameState.refresh_profile()
			await GameState.refresh_heroes()
			_go_to_hub()
		else:
			status_label.text = "Lỗi khởi tạo Master: " + str(init_res["error"])

func _on_register_pressed() -> void:
	var username = username_input.text.strip_edges()
	var password = password_input.text.strip_edges()
	if username.is_empty() or password.is_empty():
		status_label.text = "Vui lòng nhập tên đăng nhập và mật khẩu để đăng ký."
		return
		
	_set_loading(true)
	status_label.text = "Đang tạo tài khoản..."
	
	var res = await ApiClient.post_req("/api/auth/register", {
		"username": username,
		"password": password
	})
	
	_set_loading(false)
	if not res["ok"]:
		status_label.text = "Đăng ký thất bại: " + str(res["error"])
		return
		
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	var token: String = str(data.get("accessToken", data.get("token", "")))
	if not token.is_empty():
		ApiClient.set_auth_token(token)
		status_label.text = "Đăng ký thành công! Đang khởi tạo Master..."
		var m_name = master_name_input.text.strip_edges()
		if m_name.is_empty():
			m_name = username
		await ApiClient.post_req("/api/masters/init", {
			"masterName": m_name
		})
		await GameState.refresh_profile()
		await GameState.refresh_heroes()
		_go_to_hub()
	else:
		status_label.text = "Đăng ký thành công! Hãy bấm Đăng nhập."

func _go_to_hub() -> void:
	get_tree().change_scene_to_file("res://scenes/base/isometric_base_3d.tscn")
