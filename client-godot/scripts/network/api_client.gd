extends Node
class_name ApiClientSingleton

## REST API Client communicating with the Node.js backend
## Supports async/await requests, Bearer token injection, and JSON parsing

signal unauthorized
signal connection_error(message: String)

var base_url: String = "http://localhost:3000"
var auth_token: String = ""

func set_auth_token(token: String) -> void:
	auth_token = token

func clear_auth_token() -> void:
	auth_token = ""

## Performs an HTTP request asynchronously and returns a Dictionary
## Format: { "ok": bool, "status": int, "data": Variant, "error": String }
func api_request(endpoint: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, body: Dictionary = {}, extra_headers: Dictionary = {}) -> Dictionary:
	var http = HTTPRequest.new()
	add_child(http)
	
	var url = base_url + endpoint
	var headers = PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])
	
	if auth_token != "":
		headers.append("Authorization: Bearer " + auth_token)
		
	for k in extra_headers.keys():
		headers.append(str(k) + ": " + str(extra_headers[k]))
		
	var payload: String = ""
	if method != HTTPClient.METHOD_GET and not body.is_empty():
		payload = JSON.stringify(body)
		
	var err = http.request(url, headers, method, payload)
	if err != OK:
		http.queue_free()
		var msg = "Không thể tạo kết nối tới " + url
		connection_error.emit(msg)
		return { "ok": false, "status": 0, "data": null, "error": msg }
		
	var result = await http.request_completed
	http.queue_free()
	
	var _res_result: int = result[0]
	var res_code: int = result[1]
	var _res_headers: PackedStringArray = result[2]
	var res_body: PackedByteArray = result[3]
	
	var text = res_body.get_string_from_utf8()
	var parsed_data: Variant = null
	if text.length() > 0:
		var json = JSON.new()
		var parse_err = json.parse(text)
		if parse_err == OK:
			parsed_data = json.data
		else:
			parsed_data = text
			
	if res_code == 401:
		unauthorized.emit()
		return { "ok": false, "status": res_code, "data": parsed_data, "error": "ERR_UNAUTHORIZED" }
		
	if res_code >= 200 and res_code < 300:
		return { "ok": true, "status": res_code, "data": parsed_data, "error": "" }
		
	var err_code = "ERR_HTTP_" + str(res_code)
	if parsed_data is Dictionary and parsed_data.has("error"):
		err_code = str(parsed_data["error"])
		
	return { "ok": false, "status": res_code, "data": parsed_data, "error": err_code }

# Helper methods for standard CRUD
func get_req(endpoint: String) -> Dictionary:
	return await api_request(endpoint, HTTPClient.METHOD_GET)

func post_req(endpoint: String, body: Dictionary, extra_headers: Dictionary = {}) -> Dictionary:
	return await api_request(endpoint, HTTPClient.METHOD_POST, body, extra_headers)

func put_req(endpoint: String, body: Dictionary) -> Dictionary:
	return await api_request(endpoint, HTTPClient.METHOD_PUT, body)

func patch_req(endpoint: String, body: Dictionary) -> Dictionary:
	return await api_request(endpoint, HTTPClient.METHOD_PATCH, body)

func delete_req(endpoint: String) -> Dictionary:
	return await api_request(endpoint, HTTPClient.METHOD_DELETE)
