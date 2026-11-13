#!/bin/bash
# Live check of what Uykusuz needs from Claude Code to resume a session a
# network outage stopped (ClaudeOutageResume). Run it after a Claude Code
# update (AGENTS.md, "macOS, iOS ve Claude Code güncellemeleri").
#
# It runs one real Claude Code session against a fake API on this machine:
# the API is closed at first, so the turn fails as a network outage, and it
# opens 16 seconds later. Nothing is sent to Anthropic, no account is used,
# and the user's own settings, sessions and Uykusuz are not touched: the
# session has its own CLAUDE_CONFIG_DIR and the hook its own UYKUSUZ_HOME,
# both in a temporary folder that is removed on exit.
#
# What must hold:
#   1. A turn that cannot reach the API ends with the StopFailure hook,
#      error "server_error".
#   2. The hook runs in the background (asyncRewake) and its exit status 2
#      starts a new turn.
#   3. That turn is a UserPromptSubmit whose prompt carries the hook's
#      stderr (Uykusuz's fixed note), which is how Uykusuz tells its own
#      wake from something the user wrote.
#   4. The note is in the request that goes to the API.
#   5. The woken session answers.
#
# Usage: Tests/live/claude-outage-check.sh
#   CLAUDE_BIN=/path/to/claude  check that binary instead of the newest one
#   KEEP=1                      keep the temporary folder and print its path
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UYKUSUZ="$ROOT/.build/debug/Uykusuz"
OPEN_AFTER=16
SESSION_SECONDS=45

fail() { printf 'BAŞARISIZ: %s\n' "$1"; FAILED=1; }
pass() { printf 'tamam: %s\n' "$1"; }
FAILED=0

# The Claude Code to check: the newest one the desktop app carries, else the
# one on PATH.
find_claude() {
  if [[ -n "${CLAUDE_BIN:-}" ]]; then printf '%s\n' "$CLAUDE_BIN"; return; fi
  local bundled
  bundled="$(/bin/ls -d "$HOME/Library/Application Support/Claude/claude-code"/*/*/claude.app/Contents/MacOS/claude 2>/dev/null | /usr/bin/sort -V | /usr/bin/tail -n 1)"
  if [[ -n "$bundled" ]]; then printf '%s\n' "$bundled"; return; fi
  command -v claude
}

BIN="$(find_claude)"
if [[ -z "$BIN" || ! -x "$BIN" ]]; then
  echo "Claude Code bulunamadı. CLAUDE_BIN ile yolunu verin."
  exit 2
fi
if [[ ! -x "$UYKUSUZ" ]]; then
  echo "==> Uykusuz derleniyor (swift build)"
  (cd "$ROOT" && swift build >/dev/null 2>&1) || { echo "swift build başarısız oldu"; exit 2; }
fi

TMP="${TMPDIR:-/tmp}"
WORK="$(/usr/bin/mktemp -d "${TMP%/}/uykusuz-claude-check.XXXXXX")"
SERVER_PID=""
cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
  fi
  if [[ "${KEEP:-0}" == 1 ]]; then echo "Geçici klasör bırakıldı: $WORK"; else /bin/rm -rf "$WORK"; fi
}
trap cleanup EXIT
mkdir -p "$WORK/cfg" "$WORK/uk" "$WORK/project"
(cd "$WORK/project" && git init -q . 2>/dev/null)

# A free port. The address is written as an IPv4-mapped IPv6 literal so
# Uykusuz does not take it for a local proxy (APIHostProbe.isLocal) and
# probes it as it would probe the real API host.
PORT="$(/usr/bin/python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
BASE_URL="http://[::ffff:127.0.0.1]:$PORT"

# The hooks as ClaudeHooks installs them, pointed at the debug build.
/usr/bin/python3 - "$UYKUSUZ" "$WORK" <<'PY'
import json, shlex, sys
binary, work = sys.argv[1], sys.argv[2]
hook = "UYKUSUZ_HOME=%s %s --claude-hook" % (shlex.quote(work + "/uk"), shlex.quote(binary))
quiet = hook + " >/dev/null 2>&1 || true"
resuming = hook + " >/dev/null; [ $? -eq 2 ] && exit 2; exit 0"
hooks = {event: [{"hooks": [{"type": "command", "command": quiet, "timeout": 10}]}]
         for event in ["UserPromptSubmit", "Stop", "SessionEnd"]}
# Beside Uykusuz's own hook, one that writes down every prompt submitted.
record = "cat >> %s; echo >> %s" % (shlex.quote(work + "/prompts.jsonl"), shlex.quote(work + "/prompts.jsonl"))
hooks["UserPromptSubmit"][0]["hooks"].append({"type": "command", "command": record, "timeout": 10})
hooks["StopFailure"] = [{"hooks": [{"type": "command", "command": resuming, "timeout": 86400, "asyncRewake": True}]}]
json.dump({"hooks": hooks}, open(work + "/cfg/settings.json", "w"), indent=1)
PY

# The fake API: every Messages request gets one short answer, and the
# messages of each request are written down.
cat > "$WORK/server.py" <<'PY'
import http.server, json, sys
REPLY = "fake-api-answer"
EVENTS = [
    ("message_start", {"type": "message_start", "message": {"id": "msg_check", "type": "message", "role": "assistant", "model": "claude-check", "content": [], "stop_reason": None, "stop_sequence": None, "usage": {"input_tokens": 3, "output_tokens": 1}}}),
    ("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
    ("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": REPLY}}),
    ("content_block_stop", {"type": "content_block_stop", "index": 0}),
    ("message_delta", {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": None}, "usage": {"output_tokens": 3}}),
    ("message_stop", {"type": "message_stop"}),
]
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length", 0)))
        try:
            messages = json.loads(body)["messages"]
        except Exception:
            messages = None
        with open(sys.argv[2], "a") as log:
            log.write(self.path + " " + json.dumps(messages, ensure_ascii=False) + "\n")
        if "/messages" in self.path and "count_tokens" not in self.path:
            self.send_response(200)
            self.send_header("content-type", "text/event-stream")
            self.end_headers()
            for name, data in EVENTS:
                self.wfile.write(("event: %s\ndata: %s\n\n" % (name, json.dumps(data))).encode())
        else:
            self.send_response(404)
            self.send_header("content-type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"type":"error","error":{"type":"not_found_error","message":"not here"}}')
    do_GET = do_POST
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY

VERSION="$("$BIN" --version 2>/dev/null | /usr/bin/head -n 1)"
echo "==> Denetlenen Claude Code: ${VERSION:-bilinmiyor}"
echo "==> Oturum sahte API'ye karşı çalışıyor (yaklaşık $SESSION_SECONDS sn; API $OPEN_AFTER sn sonra açılır)"

( sleep "$OPEN_AFTER"; exec /usr/bin/python3 "$WORK/server.py" "$PORT" "$WORK/requests.log" ) &
SERVER_PID=$!

# One user message, then stdin stays open so the session is still there to
# be woken.
( printf '%s\n' '{"type":"user","message":{"role":"user","content":"Say hello."}}'; sleep "$SESSION_SECONDS" ) \
  | ( cd "$WORK/project" && CLAUDE_CONFIG_DIR="$WORK/cfg" ANTHROPIC_API_KEY=sk-ant-test-dummy \
      ANTHROPIC_BASE_URL="$BASE_URL" CLAUDE_CODE_MAX_RETRIES=1 DISABLE_TELEMETRY=1 DISABLE_AUTOUPDATER=1 \
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
      "$BIN" -p --input-format stream-json --output-format stream-json --verbose ) > "$WORK/session.jsonl" 2>&1

LOG="$WORK/uk/Logs/uykusuz.log"
if /usr/bin/grep -q "a network outage stopped session" "$LOG" 2>/dev/null; then
  pass "ulaşılamayan API, StopFailure hook'unu server_error ile çalıştırdı"
else
  fail "StopFailure hook'u bir ağ kesintisi görmedi (hook hiç çalışmadı ya da error alanı değişti)"
fi
if /usr/bin/grep -q "resuming session" "$LOG" 2>/dev/null; then
  pass "hook ağı bekledi ve 2 ile çıktı"
else
  fail "hook ağın geldiğini görmedi ya da 2 ile çıkmadı"
fi
if /usr/bin/grep -q "Uykusuz: " "$WORK/prompts.jsonl" 2>/dev/null; then
  pass "çıkış kodu 2 yeni bir tur başlattı: Uykusuz'un notu UserPromptSubmit olarak geldi"
else
  fail "çıkış kodu 2 yeni bir tur başlatmadı ya da hook'un stderr'i UserPromptSubmit'e ulaşmadı (asyncRewake değişmiş olabilir)"
fi
if /usr/bin/grep -q "Uykusuz: " "$WORK/requests.log" 2>/dev/null; then
  pass "not, API'ye giden istekte modele ulaştı"
else
  fail "not, API'ye giden istekte yok: model neden uyandığını görmüyor"
fi
if /usr/bin/grep -q "fake-api-answer" "$WORK/session.jsonl" 2>/dev/null; then
  pass "uyanan oturum yanıt verdi"
else
  fail "uyanan oturumdan yanıt gelmedi"
fi

if (( FAILED )); then
  echo
  echo "Uykusuz günlüğü:"
  /usr/bin/sed 's/^/  /' "$LOG" 2>/dev/null || echo "  (yok)"
  echo "Oturumun son satırları:"
  /usr/bin/tail -n 5 "$WORK/session.jsonl" 2>/dev/null | /usr/bin/cut -c1-300 | /usr/bin/sed 's/^/  /'
  exit 1
fi
echo "Ağ kesintisinden sonra sürdürme bu Claude Code sürümüyle çalışıyor."
