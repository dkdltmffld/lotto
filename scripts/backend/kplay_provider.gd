class_name KplayBackendProvider
extends BackendProvider

# kplay.games 플랫폼 연동 (웹 빌드 전용).
#
# 설계 (공식 KPlayAPI 클래스 동작 기반 — https://docs.kplay.games/monetize/postmessage-api):
#  - storage는 localStorage가 source of truth. 클라우드는 로그인(user-info) 시 한 번
#    cloud→localStorage로 당겨와 동기화한다(_syncThenNotify). getItem은 localStorage만 읽음.
#  - 모든 JS/비동기/postMessage 처리는 아래 _js_helper() 안의 window.GodotKplay 가 담당하고,
#    Godot↔JS 는 "JSON 문자열"만 주고받는다 → GDScript에서 JS 객체 동적 key 접근 불필요.
#  - 로그인 시 헬퍼는 클라우드 동기화를 끝낸 "뒤"에 Godot으로 user-info를 알린다
#    → BackendService가 그때 재로드하면 localStorage엔 이미 최신 클라우드 데이터가 들어있다(레이스 해소).
#
# ⚠️ 라이브 플랫폼 미검증. kplay 테스트 프로젝트에 배포해 실동작(로그인/제출/저장/동기화) 확인 필요.
#    플랫폼이 제공하는 실제 KPlayAPI 버전이 문서와 다르면 _js_helper 메시지 포맷을 맞출 것.

const PREFIX := "kplay:"        # 공식 클래스와 동일한 localStorage 키 접두사
const STORAGE_KEY := "save_v1"  # 게임 전체 저장을 이 단일 key에 JSON 문자열로 (한도 10KB)

var _is_web: bool = false
var _message_cb  # JavaScriptBridge.create_callback 보관 — GC되면 콜백이 끊긴다
var _slot_key: String = STORAGE_KEY  # 현재 저장 슬롯 키. "save_v1"=인증(클라우드), "save_guest"=게스트(로컬)
var _cloud: bool = true              # 저장 시 클라우드(storage-set) 반영 여부. 게스트는 false(로컬만)


func set_slot(slot: String, cloud_sync: bool) -> void:
	# 게스트/인증 데이터가 섞이지 않게 localStorage 키를 분리. 게스트는 클라우드 동기 안 함.
	_slot_key = STORAGE_KEY if slot == BackendProvider.SLOT_AUTH else "save_%s" % slot
	_cloud = cloud_sync


func _init() -> void:
	_is_web = OS.has_feature("web")
	if not _is_web:
		return
	JavaScriptBridge.eval(_js_helper(), true)
	_message_cb = JavaScriptBridge.create_callback(_on_js_message)
	var window: Variant = JavaScriptBridge.get_interface("window")
	if window != null and window.GodotKplay != null:
		window.GodotKplay.setCallback(_message_cb)


# --- 저장 (localStorage 동기 읽기 / 헬퍼 통한 쓰기+클라우드) ---

func load_all() -> Dictionary:
	await _await_one_frame()
	if not _is_web:
		return {}
	# 현재 슬롯 키로 읽는다 (인증=save_v1 / 게스트=save_guest). JSON.stringify로 안전하게 따옴표 처리.
	var raw: Variant = JavaScriptBridge.eval("localStorage.getItem(%s)" % JSON.stringify(PREFIX + _slot_key), true)
	if typeof(raw) != TYPE_STRING or (raw as String).is_empty():
		return {}
	return _decode(raw as String)


func save_all(data: Dictionary) -> bool:
	if not _is_web:
		return false
	var value := _encode(data)
	if value.length() > 10000:
		# 압축 후에도 초과면 클라우드(키당 10KB) 동기는 누락될 수 있다(로컬은 localStorage라 ~5MB까지 OK).
		push_warning("[Backend/Kplay] 저장 데이터가 압축 후에도 10KB 초과: %d bytes — 클라우드 동기 누락 위험" % value.length())
	# ⚠️ localStorage(소스 오브 트루스) 성공 여부를 실제로 반환한다(quota/프라이빗 모드 실패를 성공으로 오인 금지).
	#    헬퍼/IIFE가 setItem 성공 시 1, 실패 시 0 을 돌려준다. _dirty 해제는 이 결과에 묶임(backend_service).
	var ok: bool = false
	if _cloud:
		# 인증: localStorage + 클라우드(storage-set). 반환=localStorage 성공 여부.
		var r: Variant = JavaScriptBridge.eval("(window.GodotKplay ? window.GodotKplay.save(%s, %s) : false) ? 1 : 0;" % [JSON.stringify(_slot_key), JSON.stringify(value)], true)
		ok = int(r) == 1
	else:
		# 게스트: localStorage만 (클라우드 미전송 → 인증 데이터와 분리).
		var r2: Variant = JavaScriptBridge.eval("(function(){try{localStorage.setItem(%s, %s);return 1;}catch(e){return 0;}})();" % [JSON.stringify(PREFIX + _slot_key), JSON.stringify(value)], true)
		ok = int(r2) == 1
	return ok


func _encode(data: Dictionary) -> String:
	# JSON → gzip → base64("z:" 접두사). 반복 키가 잘 압축돼 클라우드 10KB/키 한도 내 인벤토리 성장 여유 확보.
	var json := JSON.stringify(data)
	var comp := json.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	return "z:" + Marshalls.raw_to_base64(comp)


func _decode(raw: String) -> Dictionary:
	# 신포맷("z:" gzip+base64) / 구포맷(평문 JSON) 모두 지원 — 기존 세이브 하위호환.
	if raw.begins_with("z:"):
		var comp := Marshalls.base64_to_raw(raw.substr(2))
		var bytes := comp.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var parsed2: Variant = JSON.parse_string(raw)
	return parsed2 if typeof(parsed2) == TYPE_DICTIONARY else {}


# --- 플랫폼 기능 ---

func _call_helper(expr: String) -> void:
	# window.GodotKplay 가드 + eval 공용 경로(웹 전용, _is_web 가드 내장). expr = "메서드(인자);" 형태.
	# ⚠️ save_all 의 eval 2곳은 반환값 수신(_dirty 해제 연동)·IIFE 구조가 달라 이 헬퍼 대상 아님 — 건드리지 말 것.
	if _is_web:
		JavaScriptBridge.eval("window.GodotKplay && window.GodotKplay." + expr, true)


func login(provider_hint: String = "") -> void:
	# provider_hint("google"/"kplay")를 메시지에 힌트로 실어 보냄(플랫폼 지원 여부는 검증 필요 — 정리본 §8).
	_call_helper("login(%s);" % JSON.stringify(provider_hint))


func clear_local() -> void:
	# 현재 슬롯의 로컬(localStorage)만 제거. 서버 데이터는 유지.
	_call_helper("clearLocal(%s);" % JSON.stringify(_slot_key))


func clear_account() -> void:
	# 현재 슬롯 삭제. 인증이면 로컬+서버, 게스트면 로컬만(클라우드 없음).
	if not _is_web:
		return
	if _cloud:
		_call_helper("clear(%s);" % JSON.stringify(_slot_key))
	else:
		clear_local()  # 게스트 = 로컬 제거와 동일(이 시점 _is_web 이미 보장 — 내부 가드는 무해한 재확인)


func submit_score(score: int) -> void:
	_call_helper("submitScore(%d);" % score)


func show_leaderboard() -> void:
	_call_helper("showLeaderboard();")


# --- 플랫폼→게임 수신 (헬퍼가 JSON 문자열로 전달) ---

func _on_js_message(args: Array) -> void:
	if args.is_empty():
		return
	var json_str: Variant = args[0]
	if typeof(json_str) != TYPE_STRING:
		return
	var m: Variant = JSON.parse_string(json_str)
	if typeof(m) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = m
	match str(msg.get("type", "")):
		"user-info":
			# 헬퍼가 클라우드→localStorage 동기화를 끝낸 뒤 호출 → 곧 BackendService가 재로드
			var uid := str(msg.get("userId", ""))
			print("[kplay] user-info id=%s name=%s" % [uid, str(msg.get("name", ""))])
			# ⚠️ userId 가 비면 플랫폼 미인증(익명 자동 메시지) — 인증 로그인으로 올리지 않는다.
			#    (무조건 true면 "미인증인데 인증된 척" → login.gd 단축경로가 실로그인 없이 auth 슬롯 진입)
			login_changed.emit(uid != "", str(msg.get("name", "")))
		"storage-resynced":
			# 로그인 8초 타임아웃 뒤 늦게 도착한 클라우드 동기 → 재로드 유도(stale _data 가 클라우드 덮어쓰는 것 방지)
			resync_needed.emit()
		"score-submitted":
			score_submitted.emit(bool(msg.get("success", false)), int(msg.get("rank", -1)))


# 페이지에 1회 주입되는 JS 다리. 모든 postMessage/비동기/JS 객체 처리를 여기서 끝내고
# Godot에는 JSON 문자열만 콜백으로 넘긴다.
func _js_helper() -> String:
	var tmpl := """
(function(){
  if (window.GodotKplay) return;
  var PREFIX = '%s';
  var KEY = '%s';
  var H = {
    _cb: null,
    setCallback: function(cb){ this._cb = cb; },
    _emit: function(o){ if (this._cb) { this._cb(JSON.stringify(o)); } },
    login: function(provider){ window.parent.postMessage({type:'login-required', provider: provider||''}, '*'); },
    submitScore: function(s){ window.parent.postMessage({type:'submit-score', score:s}, '*'); },
    showLeaderboard: function(){ window.parent.postMessage({type:'show-leaderboard'}, '*'); },
    save: function(key, value){
      var ok = false;
      try { localStorage.setItem(PREFIX+key, value); ok = true; } catch(e){}
      window.parent.postMessage({type:'storage-set', requestId:'gsave', key:key, value:value}, '*');
      return ok;  // localStorage(소스 오브 트루스) 성공 여부 — 실패를 삼키지 않고 GDScript로 전달
    },
    clearLocal: function(key){
      try { localStorage.removeItem(PREFIX+key); } catch(e){}
    },
    clear: function(key){
      try { localStorage.removeItem(PREFIX+key); } catch(e){}
      window.parent.postMessage({type:'storage-remove', requestId:'gclear', key:key}, '*');
    },
    _syncThenNotify: function(d){
      var self = this, done = false;
      function finish(){ if (done) return; done = true; self._emit({type:'user-info', userId:d.userId||'', name:d.name||''}); }
      if (!d.userId) { finish(); return; }
      var handler = function(e){
        var m = e.data || {};
        if (m.type !== 'storage-load-result' || m.requestId !== 'gload') return;
        window.removeEventListener('message', handler);
        var wrote = false;
        if (m.success && m.data) { try { for (var k in m.data) { localStorage.setItem(PREFIX+k, m.data[k]); } wrote = true; } catch(e){} }
        if (done) {
          // 타임아웃(8s)이 먼저 finish 함 → localStorage는 지금 갱신됐지만 게임 _data 는 stale.
          // 재동기 알림으로 BackendService 가 다시 로드하게 한다(stale 데이터가 클라우드 덮어쓰는 것 방지).
          if (wrote) self._emit({type:'storage-resynced'});
        } else {
          finish();
        }
      };
      window.addEventListener('message', handler);
      window.parent.postMessage({type:'storage-load', requestId:'gload'}, '*');
      setTimeout(finish, 8000);
    }
  };
  window.GodotKplay = H;
  window.addEventListener('message', function(e){
    var d = e.data || {};
    if (!d.type) return;
    if (d.type === 'user-info') { H._syncThenNotify(d); }
    else if (d.type === 'score-submitted') { H._emit({type:'score-submitted', success:!!d.success, rank:(d.rank==null?-1:d.rank)}); }
  });
})();
"""
	return tmpl % [PREFIX, STORAGE_KEY]
