#!/bin/bash
# Reverse install.sh. Quits the app, takes the recovery lock, runs the current
# backstop with --force under that same lock (from a source checkout: the
# checkout's copy when the installed app declares the interface version it
# speaks, else the app's own: the one sealed in the bundle, else the writable
# copy older installs left in Application Support; from anywhere else, such
# as a release zip: the sealed copy only), verifies for itself that the
# journal is clean, and only then removes the LaunchAgent, the sudoers rule,
# the app bundle (backstop.sh included), and the journal. Keeps config.json
# and the logs unless --purge. Everything after the quit happens while this
# process holds APP_SUPPORT/.recovery.lock, so neither a queued periodic
# backstop nor a relaunched app can republish the journal while it is being
# removed.
#
# If anything Insomnia changed is still journaled, nothing is removed: the
# LaunchAgent keeps retrying every minute, the sudoers rule keeps pmset
# undoable, and state.json keeps the evidence. The message says what to do.
# A brightness the app kept because its private-call guard refused the
# restore on this macOS does not stop the uninstall, since nothing here can
# restore it; state.json is kept, even with --purge, so a later Insomnia
# that can make the call restores it at launch. The app's records about that
# entry and about a restore under its Low Power Mode (displayRestoredUnderLowPower,
# keptDisplayUnderLowPower, keptDisplayUnderLowPowerBoot, keptDisplayReadLit)
# are never undone here and stay or go with state.json; backstop.sh of this
# version gives the record of the kept entry this boot, in a journal it
# publishes before it switches Low Power Mode off. One of the wrong type, a
# number the app cannot decode, one of the three keys about the kept entry
# found twice at the top level of the file, or text the check cannot follow
# makes the journal malformed: the same text check as backstop.sh
# (record_text_problems), which reads keys at the top level only, with
# their escapes decoded, as the app does.
#
# Deletion is by exact owned file, never by directory tree: --purge removes
# the files Insomnia writes (see Paths.swift), the session.json copies the
# app or backstop.sh moved aside (session.json.unreadable-<stamp>, only that
# exact shape), and then rmdir's its own directories only if they are empty.
# Only regular files are removed; anything else at one of those paths is
# left with a message. The lock file is never unlinked, so --purge leaves
# APP_SUPPORT/.recovery.lock (and therefore APP_SUPPORT). The bundle trees
# removed are the installed app and install.sh's own leftovers beside it,
# matched by the exact names install.sh gives them, and the agent plist goes
# with the candidate plists install.sh and the app stage it from.
#
# Honours INSOMNIA_HOME with the same layout as the app (see Paths.swift).
set -euo pipefail

PURGE=0
for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=1 ;;
    -h|--help) echo "kullanım: $0 [--purge]"; exit 0 ;;
    *) echo "bilinmeyen seçenek: $arg" >&2; exit 2 ;;
  esac
done

# The folder this script is in. backstop.sh is taken from there only when it
# is the scripts/ folder of a source checkout, with Package.swift one level
# up (in_checkout). A release zip's folder is not, and the zip has no
# backstop.sh, so one found beside its uninstall.sh was added after the zip
# was unpacked, for example by another account that created the folder in
# /tmp beforehand. Never the folder above either: a zip unpacked at
# /tmp/Insomnia-<version> would make that /tmp, where any account can create
# scripts/backstop.sh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
in_checkout() { [[ "${SCRIPT_DIR##*/}" == scripts && -f "${SCRIPT_DIR%/*}/Package.swift" ]]; }

# Fixed tool paths: never taken from PATH or the environment. Tests patch
# these lines in a private copy of the script.
PGREP=/usr/bin/pgrep
OSASCRIPT=/usr/bin/osascript
LAUNCHCTL=/bin/launchctl
SUDO=/usr/bin/sudo
PLUTIL=/usr/bin/plutil
CODESIGN=/usr/bin/codesign
LOCKF=/usr/bin/lockf
DEFAULTS=/usr/bin/defaults
KILL=/bin/kill
DATE=/bin/date
MKDIR=/bin/mkdir
RM=/bin/rm
RMDIR=/bin/rmdir
MKTEMP=/usr/bin/mktemp
LOCK_TIMEOUT_SECONDS=10
# How long to wait for the app to exit after asking it to quit.
QUIT_WAIT_SECONDS=10
# Longest one external call made by this script itself (pgrep, defaults,
# launchctl, codesign) may run before it is stopped with SIGTERM, then
# SIGKILL. A call made under the recovery lock keeps the lock until it has
# exited or been stopped, even if this run is killed first (see bounded()).
# backstop.sh bounds its own commands; the two sudo calls
# prompt for a password and are left to sudo's own prompt timeout.
CALL_TIMEOUT_SECONDS=30
APP="$HOME/Applications/Insomnia.app"
SUDOERS=/etc/sudoers.d/insomnia
# The --resume-frozen interface version this checkout's backstop.sh speaks
# (see step 3).
RESUME_FROZEN_VERSION=1

if [[ -n "${INSOMNIA_HOME:-}" ]]; then
  APP_SUPPORT="$INSOMNIA_HOME"
  LOG_DIR="$INSOMNIA_HOME/Logs"
  LAUNCH_AGENTS="$INSOMNIA_HOME/LaunchAgents"
  OWN_LAUNCH_AGENTS_DIR=1
else
  APP_SUPPORT="$HOME/Library/Application Support/Insomnia"
  LOG_DIR="$HOME/Library/Logs/Insomnia"
  LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
  OWN_LAUNCH_AGENTS_DIR=0
fi
LABEL="com.insomnia.backstop"
PLIST="$LAUNCH_AGENTS/$LABEL.plist"
SESSION="$APP_SUPPORT/session.json"
STATE="$APP_SUPPORT/state.json"
CONFIG="$APP_SUPPORT/config.json"
# The agent list the app ships with (Config.defaultAgentList in
# Sources/Insomnia/Model/Config.swift; a test keeps this copy in step). An
# older build may have set NSAppSleepDisabled for any of these, even one the
# user later took off the list in config.json, so the check below covers
# both lists.
DEFAULT_AGENTS=(
  com.t3tools.t3code              # T3 Code (Nightly)
  com.t3tools.t3code.reasoning    # T3 Code (Reasoning)
  com.conductor.app               # Conductor
  com.apple.Terminal              # Terminal
  com.googlecode.iterm2           # iTerm2
  com.mitchellh.ghostty           # Ghostty
  dev.warp.Warp-Stable            # Warp
  com.google.Chrome               # Google Chrome
  org.chromium.Chromium           # Chromium
  company.thebrowser.Browser      # Arc
  com.docker.docker               # Docker Desktop
  com.microsoft.VSCode            # Visual Studio Code
  com.todesktop.230313mzl4w4u92   # Cursor
  dev.zed.Zed                     # Zed
  com.google.antigravity          # Antigravity
  com.anthropic.claudefordesktop  # Claude
  com.openai.codex                # ChatGPT (hosts Codex and computer use)
  io.tailscale.ipn.macsys         # Tailscale
  ai.elementlabs.lmstudio         # LM Studio
  com.electron.ollama             # Ollama
)
LOCK="$APP_SUPPORT/.recovery.lock"
UID_NUM="$(id -u)"

step() { printf '\n==> %s\n' "$*"; }

# Scratch space for bounded(): this run's own directory, emptied on exit.
WORK="$("$MKTEMP" -d "${TMPDIR:-/tmp}/insomnia-uninstall.XXXXXX")"
trap '"$RM" -f "$WORK"/call.* 2>/dev/null; "$RMDIR" "$WORK" 2>/dev/null || true' EXIT

# Run one external call with a time limit. Its combined output is left in
# BOUNDED_OUTPUT (trailing newline removed) and its exit status returned, or
# 124 when it did not finish within CALL_TIMEOUT_SECONDS and was stopped, or
# 125 when it is sudo and still running (pid in BOUNDED_PID; this script
# bounds no sudo call). The same helper as install.sh's, which says more.
# supervise() enforces the limit itself, even if this run is killed while it
# waits: SIGTERM once the limit has passed on bash's SECONDS clock, SIGKILL
# one to two seconds later, never SIGKILL for sudo. The supervisor and the call keep fd 9 (the recovery lock) until the
# call has exited, so a launchctl bootout made under the lock cannot unload
# an agent the app confirms after this run is gone.
BOUNDED_OUTPUT=""
BOUNDED_PID=""
# shellcheck disable=SC2034  # BOUNDED_PID is for sudo, and this script bounds none
bounded() { # command args...
  local base supervisor rc deadline
  base="$("$MKTEMP" "$WORK/call.XXXXXX")"
  BOUNDED_OUTPUT=""
  BOUNDED_PID=""
  supervise "$base" "$@" </dev/null >/dev/null 2>&1 &
  supervisor=$!
  if [[ "$1" == "$SUDO" ]]; then
    # The supervisor's limit (at most a second over), then at least two
    # seconds for sudo to stop on SIGTERM.
    deadline=$(( SECONDS + CALL_TIMEOUT_SECONDS + 3 ))
    while [[ ! -s "$base.rc" ]] && (( SECONDS <= deadline )); do
      sleep 0.01
    done
    if [[ ! -s "$base.rc" ]]; then
      BOUNDED_PID="$(cat "$base.pid" 2>/dev/null || true)"
      return 125
    fi
  fi
  # Any other call gets SIGKILL at most two seconds after its SIGTERM, so
  # this wait ends.
  wait "$supervisor" 2>/dev/null || true
  rc=124
  if [[ -s "$base.rc" ]]; then read -r rc < "$base.rc"; fi
  IFS= read -r -d '' BOUNDED_OUTPUT < "$base.out" || true
  BOUNDED_OUTPUT="${BOUNDED_OUTPUT%$'\n'}"
  return "$rc"
}
# The supervising process of one bounded() call; it runs in the background.
# The call is its only job, so `kill %1` signals the call, and the shell
# skips a job it has already reaped: a reused pid is never signalled. The
# status file is written once the call has been reaped.
supervise() { # base command args...
  local base="$1" cpid rc=0 deadline
  shift
  "$@" </dev/null >"$base.out" 2>&1 &
  cpid=$!
  echo "$cpid" > "$base.pid"
  deadline=$(( SECONDS + CALL_TIMEOUT_SECONDS ))
  while kill -0 "$cpid" 2>/dev/null && (( SECONDS <= deadline )); do
    sleep 0.01
  done
  # Past the limit, and the shell has not reaped the call: it is still there.
  if (( SECONDS > deadline )) && [[ -n "$(jobs -rp)" ]]; then
    kill -TERM %1 2>/dev/null || true
    if [[ "$1" != "$SUDO" ]]; then
      deadline=$(( SECONDS + 1 ))
      while [[ -n "$(jobs -rp)" ]] && (( SECONDS <= deadline )); do
        sleep 0.01
      done
      if [[ -n "$(jobs -rp)" ]]; then kill -KILL %1 2>/dev/null || true; fi
    fi
    wait "$cpid" 2>/dev/null || true
    echo 124 > "$base.rc"
    return
  fi
  wait "$cpid" || rc=$?
  echo "$rc" > "$base.rc"
}

# Fail closed on paths that are not the exact things install.sh created.
case "$APP_SUPPORT" in /*) ;; *) echo "reddedildi: uygulama destek yolu mutlak değil: $APP_SUPPORT" >&2; exit 1 ;; esac
[[ "$(basename "$APP")" == "Insomnia.app" ]] || { echo "reddedildi: $APP bir Insomnia.app paket yolu değil" >&2; exit 1; }

extract() { # file keypath (raw scalar; non-zero if missing)
  "$PLUTIL" -extract "$2" raw -o - "$1" 2>/dev/null
}
extract_json() { # file keypath
  "$PLUTIL" -extract "$2" json -o - "$1" 2>/dev/null
}
type_of() { # file keypath -> bool|integer|float|string|array|dictionary|(any); empty if absent
  "$PLUTIL" -type "$2" -o - "$1" 2>/dev/null || true
}

# Prints one line per way the app's records about a kept display entry would
# not decode, or nothing. Read from the text of state.json $1 itself, not
# through plutil, which turns a number too small for a Double, such as
# 1e-400, into 0.0, reads 1., .5, +1 and other JSON5 forms the app refuses,
# and keeps the last of two copies of a key where the app's JSONDecoder keeps
# the first. The text is read the way the app reads it. Only keys of the
# top-level object count, with their \u escapes decoded, so
# "keptDisplayReadL\u0069t" is that key. Every value is stepped over whole: a
# string to its closing quote, an object or array to its closing bracket. So
# a saved audio name or UID, or a nested object, that holds such a key, a \u
# escape or a bad number holds no record. Each of the two numbers must be
# null or a JSON number a Swift Float holds: not above about 3.4028236e38, and
# either 0 in every digit or not so small that it rounds to 0 (below about
# 7.0065e-46). The range is read from the decimal exponent and the first 9
# significant digits, a little stricter than the app (from 3.40282356e38 and
# up to 7.01e-46), where no brightness lies. A string, object or array there
# is left to the type check. Also refused: one of the three keys found more
# than once at the top level, since plutil checks and republishes the last
# copy; a key with an escape JSON does not have, such as \x41, which plutil
# reads as A; and a top level this reader cannot follow, such as a key
# without quotes, a comment, a byte order mark other than UTF-8's, or a NUL
# byte. UTF-16 and UTF-32, which the app also reads, have NUL bytes, and the
# shell drops them from the text, which would turn such a file into other
# characters. Text outside ASCII cannot spell the keys, even under the
# decoder's Unicode equivalence, so a file with neither "keptDisplay" nor a
# backslash in it has none of them and is not read further. Any of these
# makes the journal malformed, as for a wrong type, and nothing is undone.
record_text_problems() { # file
  local LC_ALL=C
  local text rest raw key c token depth str plain scalar number esc hex lost
  local n_low=0 n_lit=0 n_boot=0 digits sig exp e10 lead
  str='^"([^"\\]|\\.)*"'
  plain='^[^]["{}]+'
  scalar='^[^],}[:space:]]+'
  number='^-?(0|[1-9][0-9]*)(\.([0-9]+))?([eE]([-+]?)([0-9]+))?$'
  esc='^u00(4[1-9A-Fa-f]|5[0-9Aa]|6[1-9A-Fa-f]|7[0-9Aa])'
  hex='^u[0-9A-Fa-f]{4}'
  lost="state.json dosyasının üst düzeyi burada izlenemiyor; bu yüzden saklanan ekran girdisiyle ilgili kayıtları denetlenemiyor"
  text="$(<"$1")"
  [[ "$text" == *keptDisplay* || "$text" == *\\* ]] || return 0
  if IFS= read -r -d '' c < "$1"; then
    echo "$lost"
    return 0
  fi
  rest="${text#$'\xef\xbb\xbf'}"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  [[ "${rest:0:1}" == "{" ]] || { echo "$lost"; return 0; }
  rest="${rest:1}"
  while :; do
    rest="${rest#"${rest%%[![:space:]]*}"}"
    # An empty object, or a comma before the end, which the app accepts.
    [[ "${rest:0:1}" == "}" ]] && break
    [[ "$rest" =~ $str ]] || { echo "$lost"; return 0; }
    raw="${BASH_REMATCH[0]}"
    rest="${rest:${#raw}}"
    raw="${raw:1:${#raw}-2}"
    # The key as the app reads it. Of the escapes JSON has, only a \u of a
    # letter can be part of one of the three keys; the others stand for no
    # letter.
    key=""
    while [[ "$raw" == *\\* ]]; do
      key+="${raw%%\\*}"
      raw="${raw#*\\}"
      if [[ "$raw" =~ $esc ]]; then
        printf -v c '%b' "\\x${BASH_REMATCH[1]}"
        key+="$c"
        raw="${raw:5}"
      elif [[ "$raw" =~ $hex ]]; then
        key+="?"
        raw="${raw:5}"
      else
        case "${raw:0:1}" in
          '"'|\\|/|b|f|n|r|t) key+="?"; raw="${raw:1}" ;;
          *) echo "state.json içindeki bir anahtarda JSON'da olmayan bir kaçış dizisi var; bu yüzden saklanan ekran girdisiyle ilgili kayıtları denetlenemiyor"; return 0 ;;
        esac
      fi
    done
    key+="$raw"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    [[ "${rest:0:1}" == : ]] || { echo "$lost"; return 0; }
    rest="${rest:1}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    token=""
    case "${rest:0:1}" in
      '"')
        [[ "$rest" =~ $str ]] || { echo "$lost"; return 0; }
        rest="${rest:${#BASH_REMATCH[0]}}"
        ;;
      '{'|'[')
        depth=0
        while :; do
          case "${rest:0:1}" in
            '{'|'[') depth=$((depth + 1)); rest="${rest:1}" ;;
            '}'|']') depth=$((depth - 1)); rest="${rest:1}"; (( depth > 0 )) || break ;;
            '"')
              [[ "$rest" =~ $str ]] || { echo "$lost"; return 0; }
              rest="${rest:${#BASH_REMATCH[0]}}"
              ;;
            '') echo "$lost"; return 0 ;;
            *)
              [[ "$rest" =~ $plain ]] || { echo "$lost"; return 0; }
              rest="${rest:${#BASH_REMATCH[0]}}"
              ;;
          esac
        done
        ;;
      *)
        [[ "$rest" =~ $scalar ]] || { echo "$lost"; return 0; }
        token="${BASH_REMATCH[0]}"
        rest="${rest:${#token}}"
        ;;
    esac
    case "$key" in
      keptDisplayUnderLowPower) n_low=$((n_low + 1)) ;;
      keptDisplayReadLit) n_lit=$((n_lit + 1)) ;;
      # The boot is a string, whose type plutil checks.
      keptDisplayUnderLowPowerBoot) n_boot=$((n_boot + 1)); token="" ;;
      *) token="" ;;
    esac
    if [[ -n "$token" && "$token" != null ]]; then
      if [[ "$token" =~ $number ]]; then
        digits="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"
        sig="${digits#"${digits%%[1-9]*}"}"
        if [[ -n "$sig" ]]; then
          exp="${BASH_REMATCH[6]#"${BASH_REMATCH[6]%%[1-9]*}"}"
          if (( ${#exp} > 18 )); then
            e10=1000000000000000000
          else
            e10=$((10#0$exp))
          fi
          [[ "${BASH_REMATCH[5]}" == - ]] && e10=$((-e10))
          e10=$((e10 + ${#BASH_REMATCH[1]} - 1 - (${#digits} - ${#sig})))
          lead="${sig}00000000"
          lead=$((10#${lead:0:9}))
          if (( e10 < -46 || (e10 == -46 && lead < 701000000) )); then
            echo "$key değeri ${token:0:40}: uygulamanın okuyamayacağı kadar küçük bir sayı"
          elif (( e10 > 38 || (e10 == 38 && lead > 340282355) )); then
            echo "$key değeri ${token:0:40}: uygulamanın okuyamayacağı kadar büyük bir sayı"
          fi
        fi
      else
        echo "$key değeri ${token:0:40} olarak yazılmış; uygulama bunu sayı olarak okumaz"
      fi
    fi
    rest="${rest#"${rest%%[![:space:]]*}"}"
    case "${rest:0:1}" in
      ,) rest="${rest:1}" ;;
      '}') break ;;
      *) echo "$lost"; return 0 ;;
    esac
  done
  (( n_low > 1 )) && echo "keptDisplayUnderLowPower, state.json dosyasının üst düzeyinde $n_low kez geçiyor; uygulama ilkini, plutil sonuncusunu okur"
  (( n_lit > 1 )) && echo "keptDisplayReadLit, state.json dosyasının üst düzeyinde $n_lit kez geçiyor; uygulama ilkini, plutil sonuncusunu okur"
  (( n_boot > 1 )) && echo "keptDisplayUnderLowPowerBoot, state.json dosyasının üst düzeyinde $n_boot kez geçiyor; uygulama ilkini, plutil sonuncusunu okur"
  return 0
}

# Shape check, same rules as backstop.sh: a JSON object whose known keys have
# the types RuntimeState.swift writes; null counts as absent.
journal_shape_problems() { # file
  local f="$1" key t i n
  if [[ "$("$PLUTIL" -convert json -o - "$f" 2>/dev/null | head -c 1)" != "{" ]]; then
    echo "state.json bir JSON nesnesi değil"
    return 0
  fi
  for key in sleepDisabledByUs lowPowerSetByUs dockerFrozen savedMuted displayRestoreRefused keyboardRestoreRefused; do
    t="$(type_of "$f" "$key")"
    [[ -z "$t" || "$t" == bool || "$t" == "(any)" ]] || echo "$key türü $t, bool değil"
  done
  for key in savedOutputVolume savedDisplayBrightness savedKeyboardBrightness displayRestoredUnderLowPower; do
    t="$(type_of "$f" "$key")"
    [[ -z "$t" || "$t" == float || "$t" == integer || "$t" == "(any)" ]] || echo "$key türü $t, sayı değil"
  done
  # The app's records about a kept display entry: never read for an undo
  # here, and they stay or go with state.json. Each must still decode, or
  # the app cannot read the journal at all.
  for key in keptDisplayUnderLowPower keptDisplayReadLit; do
    t="$(type_of "$f" "$key")"
    [[ -z "$t" || "$t" == float || "$t" == integer || "$t" == "(any)" ]] || echo "$key türü $t, sayı değil"
  done
  t="$(type_of "$f" keptDisplayUnderLowPowerBoot)"
  [[ -z "$t" || "$t" == string || "$t" == "(any)" ]] || echo "keptDisplayUnderLowPowerBoot türü $t, metin değil"
  record_text_problems "$f"
  t="$(type_of "$f" frozenProcesses)"
  if [[ -n "$t" && "$t" != "(any)" ]]; then
    if [[ "$t" != array ]]; then
      echo "frozenProcesses türü $t, dizi değil"
    else
      i=0
      while [[ -n "$(type_of "$f" "frozenProcesses.$i")" ]]; do
        if [[ "$(type_of "$f" "frozenProcesses.$i")" != dictionary ]]; then
          echo "frozenProcesses[$i] bir nesne değil"
        else
          [[ "$(type_of "$f" "frozenProcesses.$i.pid")" == integer ]] || echo "frozenProcesses[$i].pid bir tamsayı değil"
          for n in startedAt startedAtMicros; do
            t="$(type_of "$f" "frozenProcesses.$i.$n")"
            [[ -z "$t" || "$t" == integer || "$t" == "(any)" ]] || echo "frozenProcesses[$i].$n türü $t, tamsayı değil"
          done
          t="$(type_of "$f" "frozenProcesses.$i.bootSession")"
          [[ -z "$t" || "$t" == string || "$t" == "(any)" ]] || echo "frozenProcesses[$i].bootSession türü $t, metin değil"
        fi
        i=$((i + 1))
      done
    fi
  fi
  t="$(type_of "$f" frozenPids)"
  if [[ -n "$t" && "$t" != "(any)" ]]; then
    if [[ "$t" != array ]]; then
      echo "frozenPids türü $t, dizi değil"
    else
      i=0
      while [[ -n "$(type_of "$f" "frozenPids.$i")" ]]; do
        [[ "$(type_of "$f" "frozenPids.$i")" == integer ]] || echo "frozenPids[$i] bir tamsayı değil"
        i=$((i + 1))
      done
    fi
  fi
  t="$(type_of "$f" savedAudioOutputs)"
  if [[ -n "$t" && "$t" != "(any)" ]]; then
    if [[ "$t" != array ]]; then
      echo "savedAudioOutputs türü $t, dizi değil"
    else
      i=0
      while [[ -n "$(type_of "$f" "savedAudioOutputs.$i")" ]]; do
        if [[ "$(type_of "$f" "savedAudioOutputs.$i")" != dictionary ]]; then
          echo "savedAudioOutputs[$i] bir nesne değil"
        else
          [[ "$(type_of "$f" "savedAudioOutputs.$i.deviceUID")" == string ]] || echo "savedAudioOutputs[$i].deviceUID bir metin değil"
          t="$(type_of "$f" "savedAudioOutputs.$i.volume")"
          [[ "$t" == float || "$t" == integer ]] || echo "savedAudioOutputs[$i].volume bir sayı değil"
          [[ "$(type_of "$f" "savedAudioOutputs.$i.muted")" == bool ]] || echo "savedAudioOutputs[$i].muted bir bool değil"
          t="$(type_of "$f" "savedAudioOutputs.$i.name")"
          [[ -z "$t" || "$t" == string || "$t" == "(any)" ]] || echo "savedAudioOutputs[$i].name türü $t, metin değil"
          t="$(type_of "$f" "savedAudioOutputs.$i.saveID")"
          [[ -z "$t" || "$t" == string || "$t" == "(any)" ]] || echo "savedAudioOutputs[$i].saveID türü $t, metin değil"
        fi
        i=$((i + 1))
      done
    fi
  fi
  t="$(type_of "$f" appNapOverrides)"
  if [[ -n "$t" && "$t" != "(any)" ]]; then
    if [[ "$t" != array ]]; then
      echo "appNapOverrides türü $t, dizi değil"
    else
      i=0
      while [[ -n "$(type_of "$f" "appNapOverrides.$i")" ]]; do
        if [[ "$(type_of "$f" "appNapOverrides.$i")" != dictionary ]]; then
          echo "appNapOverrides[$i] bir nesne değil"
        else
          [[ "$(type_of "$f" "appNapOverrides.$i.bundleId")" == string ]] || echo "appNapOverrides[$i].bundleId bir metin değil"
          t="$(type_of "$f" "appNapOverrides.$i.previous")"
          [[ -z "$t" || "$t" == bool || "$t" == "(any)" ]] || echo "appNapOverrides[$i].previous türü $t, bool değil"
        fi
        i=$((i + 1))
      done
    fi
  fi
}

is_refused() { # key
  [[ "$(extract "$STATE" "$1" || true)" == "true" ]]
}

# Brightness the app kept after its private-call guard refused the restore
# on this macOS, one line per device with the saved level. Not a problem
# for uninstall: no step here can restore it.
refused_brightness() {
  local value
  [[ -f "$STATE" ]] || return 0
  if is_refused displayRestoreRefused && value="$(extract "$STATE" savedDisplayBrightness)"; then
    echo "ekran parlaklığı $value"
  fi
  if is_refused keyboardRestoreRefused && value="$(extract "$STATE" savedKeyboardBrightness)"; then
    echo "klavye arka ışığı $value"
  fi
}

# Same rules as backstop.sh: a date in the form Store.parseDate reads, and
# the keys and types the app's Session decoder needs.
epoch_of() { # string
  local form='^([0-9]{4})-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|([+-])([0-9]{2}):([0-9]{2}))$'
  local clock offset=0 e
  [[ "$1" =~ $form ]] || return 0
  (( 10#${BASH_REMATCH[1]} >= 1970 )) || return 0
  if [[ "${BASH_REMATCH[2]}" != Z ]]; then
    (( 10#${BASH_REMATCH[4]} <= 23 && 10#${BASH_REMATCH[5]} <= 59 )) || return 0
    offset=$(( 10#${BASH_REMATCH[4]} * 3600 + 10#${BASH_REMATCH[5]} * 60 ))
    if [[ "${BASH_REMATCH[3]}" == - ]]; then offset=$(( -offset )); fi
  fi
  clock="${1:0:19}"
  e="$("$DATE" -j -u -f '%Y-%m-%dT%H:%M:%S' "$clock" +%s 2>/dev/null)" || return 0
  if [[ "$("$DATE" -u -r "$e" +%Y-%m-%dT%H:%M:%S 2>/dev/null)" == "$clock" ]]; then
    echo $(( e - offset ))
  fi
  return 0
}

# Same as backstop.sh: epoch_of the string exactly as stored, with only
# plutil's own trailing newline cut.
epoch_at() { # file keypath
  local v
  v="$(extract "$1" "$2"; echo .)"
  v="${v%.}"
  epoch_of "${v%$'\n'}"
}
session_shape_problems() { # file
  local f="$1" key t i
  # plutil also reads XML and binary property lists, which the app's
  # JSONDecoder refuses, so the file itself must start with "{" too.
  if [[ "$(LC_ALL=C tr -d ' \t\r\n' < "$f" 2>/dev/null | head -c 1)" != "{" ]] \
     || [[ "$("$PLUTIL" -convert json -o - "$f" 2>/dev/null | head -c 1)" != "{" ]]; then
    echo "session.json bir JSON nesnesi değil"
    return 0
  fi
  for key in startedAt endsAt; do
    t="$(type_of "$f" "$key")"
    if [[ -z "$t" ]]; then
      echo "$key eksik"
    elif [[ "$t" != string ]]; then
      echo "$key türü JSON $t, tarih metni değil"
    elif [[ -z "$(epoch_at "$f" "$key")" ]]; then
      echo "$key, 2027-01-15T08:00:00Z ya da 2027-01-15T10:00:00+02:00 biçiminde bir tarih değil"
    fi
  done
  t="$(type_of "$f" extensions)"
  if [[ -z "$t" ]]; then
    echo "extensions eksik"
  elif [[ "$t" != array ]]; then
    echo "extensions türü JSON $t, dizi değil"
  else
    i=0
    while [[ -n "$(type_of "$f" "extensions.$i")" ]]; do
      t="$(type_of "$f" "extensions.$i")"
      [[ "$t" == integer || "$t" == float ]] || echo "extensions[$i] türü JSON $t, sayı değil"
      i=$((i + 1))
    done
  fi
}

# Independent check of the journal: prints one line per unresolved item.
# Trusts nothing about the backstop that just ran (it may be an older copy).
journal_problems() {
  local key value shape i
  if [[ -e "$SESSION" ]]; then
    shape=""
    # Only a regular file is opened: open(2) on a FIFO with no writer
    # blocks, and this check runs while the recovery lock is held.
    if [[ ! -f "$SESSION" ]]; then
      echo "session.json hâlâ duruyor ve okunamıyor: normal bir dosya değil, bu yüzden açılmadı"
    elif ! cat "$SESSION" >/dev/null 2>&1; then
      echo "session.json hâlâ duruyor ve okunamıyor (izinler ya da G/Ç)"
    elif shape="$(session_shape_problems "$SESSION")" && [[ -n "$shape" ]]; then
      echo "session.json hâlâ duruyor ve bir oturum değil: ${shape%%$'\n'*}"
    else
      echo "session.json hâlâ duruyor"
    fi
  fi
  [[ -e "$STATE" ]] || return 0
  if [[ ! -f "$STATE" ]]; then
    echo "state.json normal bir dosya değil, bu yüzden açılmadı"
    return 0
  fi
  if ! "$PLUTIL" -convert json -o /dev/null "$STATE" >/dev/null 2>&1; then
    echo "state.json okunamıyor ya da bozuk"
    return 0
  fi
  shape="$(journal_shape_problems "$STATE")"
  if [[ -n "$shape" ]]; then
    echo "state.json bozuk (beklenmeyen yapı):"
    echo "$shape"
    return 0
  fi
  for key in sleepDisabledByUs lowPowerSetByUs dockerFrozen; do
    if [[ "$(extract "$STATE" "$key" || true)" == "true" ]]; then
      echo "$key hâlâ true"
    fi
  done
  value="$(extract_json "$STATE" frozenProcesses || true)"
  if [[ -n "$value" && "$value" != "[]" ]]; then
    echo "dondurulmuş süreçler hâlâ kayıt defterinde: $value"
  fi
  value="$(extract_json "$STATE" frozenPids || true)"
  if [[ -n "$value" && "$value" != "[]" ]]; then
    echo "eski biçimde kaydedilmiş dondurulmuş pid'ler (kimlik bilgisi yok; backstop bunlara asla sinyal göndermez ve bunları temizlemez, bunu yalnızca uygulama yapar): $value"
  fi
  if extract "$STATE" savedOutputVolume >/dev/null || extract "$STATE" savedMuted >/dev/null; then
    echo "kaydedilmiş ses ayarları (ses düzeyi/sessiz) geri yüklenmedi; bunu yalnızca uygulama yapabilir"
  fi
  i=0
  while extract_json "$STATE" "savedAudioOutputs.$i" >/dev/null; do
    value="$(extract "$STATE" "savedAudioOutputs.$i.name" || extract "$STATE" "savedAudioOutputs.$i.deviceUID" || true)"
    echo "$value aygıtı kapak kapanınca sessize alındı ve hâlâ sessiz; ses düzeyini yalnızca uygulama, aygıt bağlandığında geri yükleyebilir"
    i=$((i + 1))
  done
  if extract "$STATE" savedDisplayBrightness >/dev/null && ! is_refused displayRestoreRefused; then
    echo "kaydedilmiş ekran parlaklığı geri yüklenmedi; bunu yalnızca uygulama yapabilir"
  fi
  if extract "$STATE" savedKeyboardBrightness >/dev/null && ! is_refused keyboardRestoreRefused; then
    echo "kaydedilmiş klavye arka ışığı geri yüklenmedi; bunu yalnızca uygulama yapabilir"
  fi
  value="$(extract_json "$STATE" appNapOverrides || true)"
  if [[ -n "$value" && "$value" != "[]" ]]; then
    echo "App Nap ayarları (NSAppSleepDisabled) eski hâline getirilmedi: $value"
  fi
}

# Agent apps whose NSAppSleepDisabled is YES with no journal entry: set by a
# build that did not record the previous value, or by the user. Nothing is
# known to put back, so nothing is changed; the exact command to undo each
# one is printed instead, shell-quoted, since the list editor takes any
# string. Checked: the shipped list plus config.json's agentList. Only a
# read that says the key is not there counts as clear ("does not exist" up
# to macOS 26, "Could not find key" or "Domain ... not found" on
# macOS 27); a read that fails any other way is reported, not counted.
# Each read is bounded; one that does not answer in time (cfprefsd stuck)
# ends the check, since the rest would wait the same way, and uninstall
# goes on.
list_unrecorded_app_nap() {
  local ids="" i=0 id value rc found=0 checked=0 unreadable=0 stuck="" skipped=0
  for id in "${DEFAULT_AGENTS[@]}"; do ids="$ids$id"$'\n'; done
  if [[ -f "$CONFIG" ]]; then
    while id="$(extract "$CONFIG" "agentList.$i")"; do
      i=$((i + 1))
      ids="$ids$id"$'\n'
    done
  fi
  while IFS= read -r id; do
    [[ -n "$id" && "$id" != -* ]] || continue
    if [[ -n "$stuck" ]]; then skipped=$((skipped + 1)); continue; fi
    rc=0
    bounded "$DEFAULTS" read "$id" NSAppSleepDisabled || rc=$?
    value="$BOUNDED_OUTPUT"
    if (( rc == 124 )); then
      stuck="$id"
      unreadable=$((unreadable + 1))
      printf 'defaults read %s saniye içinde yanıt vermedi (%s); kendiniz şununla denetleyin: defaults read %q NSAppSleepDisabled\n' "$CALL_TIMEOUT_SECONDS" "$id" "$id"
      continue
    fi
    if (( rc != 0 )); then
      if [[ "$value" == *"does not exist"* || "$value" == *"Could not find key 'NSAppSleepDisabled' in domain '"* || "$value" == *"Domain '"*"' not found."* ]]; then
        checked=$((checked + 1))
      else
        unreadable=$((unreadable + 1))
        printf 'NSAppSleepDisabled okunamadı (%s); kendiniz şununla denetleyin: defaults read %q NSAppSleepDisabled\n' "$id" "$id"
      fi
      continue
    fi
    checked=$((checked + 1))
    [[ "$value" == 1 ]] || continue
    if (( found == 0 )); then
      found=1
      cat <<MSG
Şu ajan uygulamalarında NSAppSleepDisabled YES ve Insomnia'da önceki değerine
dair bir kayıt yok (eski bir derleme bunu kaydetmeden ayarlamış). Olduğu gibi
bırakıldılar. Birinde App Nap'i yeniden açmak için şunu çalıştırın:
MSG
    fi
    printf '  defaults delete %q NSAppSleepDisabled\n' "$id"
  done < <(printf '%s' "$ids" | awk '!seen[$0]++')
  if (( found == 0 )); then
    echo "denetlenen $checked ajan uygulamasının hiçbirinde NSAppSleepDisabled ayarlı değil"
  fi
  if (( unreadable > 0 )); then
    echo "$unreadable uygulama için değer okunamadı; yukarıya bakın"
  fi
  if (( skipped > 0 )); then
    echo "$stuck yanıt vermeyince durduruldu; $skipped ajan uygulaması daha denetlenmedi"
  fi
}

# Copies of session.json that the app or backstop.sh moved aside, taken
# straight from the glob into MOVED_ASIDE, so a path holding a newline stays
# one path. A copy is a regular file whose name has exactly the shape the
# move writes (prefix, UTC stamp, optional -n). Anything else with such a
# name (a directory, a FIFO, a symlink) goes to NOT_MOVED_ASIDE and is never
# removed, even when the app or backstop.sh renamed it there: a session.json
# that cannot be read is moved without being opened, whatever it is, and
# Insomnia did not create its contents. Other names under the prefix are
# not Insomnia's and are skipped.
collect_moved_aside_sessions() {
  local f
  MOVED_ASIDE=()
  NOT_MOVED_ASIDE=()
  for f in "$APP_SUPPORT"/session.json.unreadable-*; do
    [[ -e "$f" || -L "$f" ]] || continue
    [[ "${f##*/}" =~ ^session\.json\.unreadable-[0-9]{8}T[0-9]{6}Z(-[0-9]+)?$ ]] || continue
    if [[ -f "$f" && ! -L "$f" ]]; then
      MOVED_ASIDE+=("$f")
    else
      NOT_MOVED_ASIDE+=("$f")
    fi
  done
  return 0
}

# Removes files Insomnia wrote, one path per argument. Only a regular file
# is removed. Anything else at one of these paths is not something Insomnia
# wrote; it is left and named, so a stray directory never stops the run
# halfway. A removal that fails is named and counted, and the rest go on.
remove_failures=0
remove_owned() { # path...
  local f
  for f in "$@"; do
    if [[ -f "$f" && ! -L "$f" ]]; then
      if ! "$RM" -f "$f"; then
        echo "Kaldırılamadı, yerinde bırakıldı: $f" >&2
        remove_failures=$((remove_failures + 1))
      fi
    elif [[ -e "$f" || -L "$f" ]]; then
      echo "$f bırakıldı: normal bir dosya değil, yani onu Insomnia yazmadı."
    fi
  done
  return 0
}

abort_incomplete() { # backstop exit status, problem lines...
  local rc="$1"; shift
  cat >&2 <<MSG

Kaldırma, HİÇBİR ŞEY kaldırılmadan durduruldu: Insomnia'nın değişiklikleri tümüyle
geri alınmadı (backstop çıkış kodu: $rc). $STATE içinde hâlâ kayıtlı olanlar:
MSG
  local p
  for p in "$@"; do printf '  - %s\n' "$p" >&2; done
  cat >&2 <<MSG

Bilerek hiçbir şey kaldırılmadı: LaunchAgent her dakika yeniden denemeyi sürdürür,
sudoers kuralı pmset değişikliklerini geri alınabilir tutar ve kayıt defteri kanıtı saklar.

Yapılacaklar (ardından bu betiği yeniden çalıştırın):
  - Kaydedilmiş ses (ses düzeyi/sessiz), ekran parlaklığı ya da klavye arka ışığı:
    Insomnia.app uygulamasını açın; açılışta bunları kayıt defterinden geri yükler.
    Ekran karanlıksa önce parlaklık artırma tuşuna basın.
  - Kapak kapanınca sessize alınmış ve hâlâ sessiz olan bir çıkış aygıtı: aygıtı
    bağlayıp Insomnia.app uygulamasını açın; ses düzeyini geri yükler. Aygıt kalıcı
    olarak yoksa Insomnia.app uygulamasını açın ve menüsünden "Beklemeyi bırak: <aygıt>"
    öğesini seçin; aygıt o zaman olduğu gibi kalır.
  - pmset hataları (uyku / Düşük Güç Modu): $SUDOERS dosyasını denetleyin
    (yeniden kurmak için scripts/install.sh betiğini yeniden çalıştırın) ya da
    'sudo pmset -a disablesleep 0' / 'sudo pmset -b lowpowermode 0' komutunu kendiniz çalıştırın.
  - Dondurulmuş ya da eski biçimde kaydedilmiş pid'ler: çözmek için Insomnia.app
    uygulamasını açın ya da her birini 'ps -o pid,stat,lstart,command -p <pid>' ile
    inceleyin ve tanıdığınız bir süreçse 'kill -CONT <pid>' ile kendiniz çözün.
  - App Nap (NSAppSleepDisabled): kurtarma ajanı 'defaults write' ya da 'defaults delete'
    komutunu her dakika yeniden dener ve Insomnia.app açılışta bunları eski hâline
    getirir. 'defaults' başarısız olmayı sürdürürse günlüğe bakın.
  - Okunamayan state.json: ne uygulama ne de kurtarma ajanı onu onarır ya da kaldırır.
    Günlüğe bakarak elle onarın ya da değişikliklerinin geri alındığından emin
    olduğunuzda kendiniz başka bir yere taşıyın.
  - Ayrıştırılamayan session.json: kurtarma ajanı, kayıt defteri temizlenir temizlenmez
    onu session.json.unreadable-<zaman> olarak yeniden adlandırır; uygulama da açılışta
    aynısını yapar. Ayrıca bir şey yapmanız gerekmez.
  - Hiç okunamayan session.json: bitiş zamanı bilinmediği için uygulama ve ajan onu
    süresi dolmuş sayar, kayıt defterindeki değişiklikleri geri alır ve ardından dosyayı
    açmadan session.json.unreadable-<zaman> olarak yeniden adlandırır. Hâlâ buradaysa bu
    yeniden adlandırma başarısız olmuştur (günlüğe bakın): onu kaldırın ya da bu klasörün
    dışına taşıyın, sonra yeniden çalıştırın. Bulunduğu yerde okunabilir hâle getirmeyin:
    uygulama o zaman o oturumu sürdürür.
  - Günlük: $LOG_DIR/insomnia.log
MSG
  exit 1
}

# A pgrep that does not answer in time counts as "running": fail closed.
app_running() {
  local rc=0
  bounded "$PGREP" -x Insomnia || rc=$?
  if (( rc == 124 )); then
    echo "pgrep ${CALL_TIMEOUT_SECONDS} saniye içinde yanıt vermedi; Insomnia çalışıyor kabul ediliyor." >&2
    return 0
  fi
  return "$rc"
}

# 1. Quit the app --------------------------------------------------------------
# Ask politely and wait. The app refuses to quit while it has unresolved
# recovery work, and that refusal must stand: no pkill, no force.
step "Insomnia kapatılıyor"
if app_running; then
  "$OSASCRIPT" -e 'tell application id "com.kgarg.insomnia" to quit' >/dev/null 2>&1 || true
  for (( i = 0; i < QUIT_WAIT_SECONDS; i++ )); do
    app_running || break
    sleep 1
  done
  if app_running; then
    echo "Insomnia hâlâ çalışıyor (kendi kurtarması bitene dek kapanmayı reddediyor olabilir)." >&2
    echo "Bitmesini bekleyin ya da menüsünden Insomnia'dan çıkın, ardından yeniden çalıştırın. Hiçbir şey kaldırılmadı." >&2
    exit 1
  fi
fi

# 2. Take the recovery lock and keep it to the end ---------------------------
step "Kurtarma kilidi alınıyor"
"$MKDIR" -p "$APP_SUPPORT"
exec 9<>"$LOCK"
lock_rc=0
"$LOCKF" -t "$LOCK_TIMEOUT_SECONDS" 9 2>/dev/null || lock_rc=$?
if (( lock_rc != 0 )); then
  echo "Kurtarma kilidi ($LOCK) başka bir sürecin elinde (çalışan bir backstop.sh ya da uygulama)." >&2
  echo "Bir dakika bekleyip yeniden çalıştırın. Hiçbir şey kaldırılmadı." >&2
  exit 75
fi
if app_running; then
  echo "Insomnia yeniden açıldı; Insomnia'dan çıkıp yeniden çalıştırın. Hiçbir şey kaldırılmadı." >&2
  exit 1
fi

# 3. Undo everything via a backstop that matches the installed app ----------
# The backstop inherits fd 9 and shares this lock instead of waiting on it.
# From a source checkout, the checkout's backstop.sh hands frozen entries
# that record microseconds to the installed app binary, and runs that binary
# only when the bundle's Info.plist declares InsomniaResumeFrozenVersion
# RESUME_FROZEN_VERSION (the same value as in backstop.sh; a test keeps the
# two in step). So the checkout's copy runs when the app declares that
# version. An app that does not was installed together with its own
# backstop.sh, which speaks its version: the copy install.sh sealed into the
# bundle, or for installs before that layout the writable copy in
# $APP_SUPPORT that the LaunchAgent runs. That copy is used instead when it
# exists. With neither copy the checkout's backstop runs anyway: it keeps the
# entries that need the binary, and step 4 stops before removing anything.
# From anywhere else, such as a release zip's folder, the sealed copy or
# nothing: a backstop.sh beside this script there is not from the zip (see
# SCRIPT_DIR), and the writable copy is older than release zips. The sealed
# copy runs only while the bundle's signature still verifies: its resource
# seal covers the script, so this is the check the LaunchAgent runs (without
# the pinned requirement, which this script does not have), and an edited
# copy is refused the same way.
step "Mac, backstop --force ile eski hâline getiriliyor"
if [[ -e "$SCRIPT_DIR/backstop.sh" ]] && ! in_checkout; then
  echo "$SCRIPT_DIR/backstop.sh çalıştırılmıyor: $SCRIPT_DIR bir kaynak kod kopyasının scripts klasörü değil ve sürüm zip dosyalarında backstop.sh bulunmaz; yani bu dosya zip açıldıktan sonra eklenmiş." >&2
fi
CHECKOUT_BACKSTOP=""
if in_checkout && [[ -f "$SCRIPT_DIR/backstop.sh" ]]; then
  CHECKOUT_BACKSTOP="$SCRIPT_DIR/backstop.sh"
fi
installed_version=""
if [[ -f "$APP/Contents/Info.plist" ]]; then
  installed_version="$(extract "$APP/Contents/Info.plist" InsomniaResumeFrozenVersion || true)"
fi
if [[ -n "$CHECKOUT_BACKSTOP" ]] && { [[ "$installed_version" == "$RESUME_FROZEN_VERSION" ]] || { [[ ! -f "$APP/Contents/Resources/backstop.sh" ]] && [[ ! -f "$APP_SUPPORT/backstop.sh" ]]; }; }; then
  BACKSTOP="$CHECKOUT_BACKSTOP"
elif [[ -f "$APP/Contents/Resources/backstop.sh" ]]; then
  verify_rc=0
  bounded "$CODESIGN" --verify --strict "$APP" || verify_rc=$?
  if (( verify_rc == 124 )); then
    echo "'codesign --verify --strict $APP' ${CALL_TIMEOUT_SECONDS} saniye içinde yanıt vermedi; bu yüzden içinde mühürlü backstop.sh çalıştırılmadı." >&2
    echo "Hiçbir şey kaldırılmadı. codesign yanıt verdiğinde yeniden çalıştırın ya da scripts/uninstall.sh betiğini kaynak kodun bir kopyasından çalıştırın: bu uygulama InsomniaResumeFrozenVersion $RESUME_FROZEN_VERSION bildiriyorsa betik kendi backstop.sh dosyasını çalıştırır." >&2
    exit 1
  elif (( verify_rc != 0 )); then
    echo "$APP 'codesign --verify --strict' denetiminden geçmiyor (çıkış kodu $verify_rc: ${BOUNDED_OUTPUT:-ayrıntı yok}); bu yüzden içinde mühürlü backstop.sh çalıştırılmadı." >&2
    echo "Hiçbir şey kaldırılmadı. Yeniden kurup yeniden çalıştırın ya da scripts/uninstall.sh betiğini kaynak kodun bir kopyasından çalıştırın: bu uygulama InsomniaResumeFrozenVersion $RESUME_FROZEN_VERSION bildiriyorsa betik kendi backstop.sh dosyasını çalıştırır." >&2
    exit 1
  fi
  echo "$APP doğrulandı"
  BACKSTOP="$APP/Contents/Resources/backstop.sh"
elif in_checkout && [[ -f "$APP_SUPPORT/backstop.sh" ]]; then
  BACKSTOP="$APP_SUPPORT/backstop.sh"
elif in_checkout; then
  echo "$SCRIPT_DIR, $APP/Contents/Resources ya da $APP_SUPPORT içinde backstop.sh bulunamadı; hiçbir şey kaldırılmadı" >&2
  exit 1
else
  echo "$APP/Contents/Resources içinde mühürlü backstop.sh yok ve bu betik, kaynak kod kopyası dışında başka bir kopya çalıştırmaz; hiçbir şey kaldırılmadı." >&2
  echo "scripts/uninstall.sh betiğini kaynak kodun bir kopyasından çalıştırın." >&2
  exit 1
fi
if [[ -n "$CHECKOUT_BACKSTOP" && "$BACKSTOP" != "$CHECKOUT_BACKSTOP" ]]; then
  echo "$APP, InsomniaResumeFrozenVersion $RESUME_FROZEN_VERSION bildirmiyor; onunla birlikte kurulan backstop kullanılıyor: $BACKSTOP"
fi
echo "kullanılıyor: $BACKSTOP"
recovery_rc=0
/bin/bash "$BACKSTOP" --force || recovery_rc=$?

# 4. Verify independently ------------------------------------------------------
step "Kurtarma kayıt defteri doğrulanıyor"
problems=()
while IFS= read -r line; do
  [[ -n "$line" ]] && problems+=("$line")
done < <(journal_problems)
if (( recovery_rc != 0 )) && (( ${#problems[@]} == 0 )); then
  problems+=("backstop $recovery_rc çıkış koduyla sonlandı; bkz. $LOG_DIR/insomnia.log")
fi
if (( ${#problems[@]} > 0 )); then
  abort_incomplete "$recovery_rc" "${problems[@]}"
fi
echo "kayıt defteri temiz"
kept_brightness=()
while IFS= read -r line; do
  [[ -n "$line" ]] && kept_brightness+=("$line")
done < <(refused_brightness)
if (( ${#kept_brightness[@]} > 0 )); then
  echo "Geri yüklenmedi ve $STATE içinde tutuluyor:"
  for line in "${kept_brightness[@]}"; do echo "  - $line"; done
  echo "Insomnia'nın özel çağrı koruması bu macOS sürümünde o geri yüklemeyi reddetti; bu yüzden"
  echo "burada hiçbir adım bunu yapamaz. Düzeyi parlaklık tuşlarıyla ya da Denetim Merkezi'nden ayarlayın."
  echo "Dosya yerinde kalır; böylece bu çağrıyı yapabilen sonraki bir Insomnia açılışta onu geri yükler."
fi
if app_running; then
  echo "Insomnia yeniden açıldı; Insomnia'dan çıkıp yeniden çalıştırın. Hiçbir şey kaldırılmadı." >&2
  exit 1
fi

step "Ajan uygulamalarının App Nap ayarları denetleniyor"
list_unrecorded_app_nap

# 5. Remove, still under the lock -------------------------------------------
# bootout first: it stops a running instance of the agent and drops queued
# runs, so nothing is left to reopen the journal once the files go. Then
# prove the job is really gone; if launchd still lists it, stop here with
# every recovery file intact.
step "LaunchAgent kaldırılıyor"
bootout_rc=0
bounded "$LAUNCHCTL" bootout "gui/$UID_NUM" "$PLIST" || bootout_rc=$?
# `launchctl print` exits 113 only when the service is not loaded; 0 means
# still loaded and anything else means launchd could not be asked. 124 from
# either call means it did not answer within CALL_TIMEOUT_SECONDS.
print_rc=0
bounded "$LAUNCHCTL" print "gui/$UID_NUM/$LABEL" || print_rc=$?
if (( print_rc != 113 )); then
  if (( print_rc == 0 )); then
    echo "launchctl bootout $bootout_rc çıkış koduyla sonlandı ve $LABEL hâlâ gui/$UID_NUM içinde yüklü." >&2
  elif (( print_rc == 124 )); then
    echo "launchctl bootout $bootout_rc çıkış koduyla sonlandı ve 'launchctl print' ${CALL_TIMEOUT_SECONDS} saniye içinde yanıt vermedi; $LABEL görevinin hâlâ yüklü olup olmadığı anlaşılamıyor." >&2
  else
    echo "launchctl bootout $bootout_rc çıkış koduyla, 'launchctl print' $print_rc çıkış koduyla sonlandı; $LABEL görevinin hâlâ yüklü olup olmadığı anlaşılamıyor." >&2
  fi
  echo "Hiçbir şey kaldırılmadı. 'launchctl bootout gui/$UID_NUM $PLIST' komutunu kendiniz çalıştırın, ardından bu betiği yeniden çalıştırın." >&2
  exit 1
fi
"$RM" -f "$PLIST"
# Candidate plists install.sh and the app write before a load and rename
# into place after it: in the staging directory beside the plist, and in
# $LAUNCH_AGENTS itself for older builds. Only files with the label's
# candidate prefix, the same ones both of them sweep; the staging directory
# goes only once empty.
CANDIDATE_DIR="$LAUNCH_AGENTS/.$LABEL.staging"
for candidate in "$CANDIDATE_DIR/$LABEL.candidate-"* "$LAUNCH_AGENTS/$LABEL.candidate-"*; do
  if [[ -f "$candidate" && ! -L "$candidate" ]]; then "$RM" -f "$candidate"; fi
done
if [[ -d "$CANDIDATE_DIR" && ! -L "$CANDIDATE_DIR" ]]; then "$RMDIR" "$CANDIDATE_DIR" 2>/dev/null || true; fi

step "$SUDOERS kaldırılıyor (parolanız istenecek)"
if [[ -e "$SUDOERS" ]] || "$SUDO" test -e "$SUDOERS"; then
  "$SUDO" rm -f "$SUDOERS"
fi

step "Uygulama paketi kaldırılıyor"
"$RM" -rf "$APP"
# install.sh's leftovers beside the bundle, by the exact names it gives them.
# An upgrade sets the previous bundle aside at .Insomnia.app.previous during
# its swap and assembles the new one in .Insomnia.app.staging.<pid>.<six
# letters and digits> (mktemp). The swap runs under the recovery lock, which
# this script holds, so a set-aside bundle belongs to a run that was stopped.
# A staging directory whose run is still alive belongs to an install that
# has not reached the lock yet, and stays. kill -0 only asks whether the
# process exists; it sends no signal. Symlinks and any other name are left.
APP_DIR="$(dirname "$APP")"
PREVIOUS_APP="$APP_DIR/.Insomnia.app.previous"
if [[ -d "$PREVIOUS_APP" && ! -L "$PREVIOUS_APP" ]]; then
  "$RM" -rf "$PREVIOUS_APP"
  echo "yarıda kalmış bir kurulumun kenara ayırdığı önceki paket kaldırıldı: $PREVIOUS_APP"
fi
staging_re='^\.Insomnia\.app\.staging\.([0-9]+)\.[A-Za-z0-9]{6}$'
for dir in "$APP_DIR"/.Insomnia.app.staging.*; do
  [[ -d "$dir" && ! -L "$dir" ]] || continue
  [[ "${dir##*/}" =~ $staging_re ]] || continue
  owner="${BASH_REMATCH[1]}"
  if "$KILL" -0 "$owner" 2>/dev/null; then
    echo "$dir tutuldu: onu oluşturan install.sh çalıştırması (pid $owner) hâlâ sürüyor"
    continue
  fi
  "$RM" -rf "$dir"
  echo "artık çalışmayan bir install.sh çalıştırmasından kalan klasör kaldırıldı: $dir"
done

# $APP_SUPPORT/backstop.sh below is the writable copy of older installs; the
# current one went with the bundle.
if (( PURGE == 1 )); then
  step "Insomnia'nın dosyaları temizleniyor: $APP_SUPPORT ve $LOG_DIR"
  remove_owned "$SESSION" "$APP_SUPPORT/config.json" "$APP_SUPPORT/backstop.sh" \
        "$APP_SUPPORT/unfinished-command.json" \
        "$LOG_DIR/insomnia.log" "$LOG_DIR/insomnia.log.1" \
        "$LOG_DIR/handoffs.log" "$LOG_DIR/handoffs.log.1"
  (( ${#kept_brightness[@]} > 0 )) || remove_owned "$STATE"
  collect_moved_aside_sessions
  if (( ${#MOVED_ASIDE[@]} > 0 )); then
    remove_owned "${MOVED_ASIDE[@]}"
  fi
  if (( ${#NOT_MOVED_ASIDE[@]} > 0 )); then
    for f in "${NOT_MOVED_ASIDE[@]}"; do
      echo "$f bırakıldı: kenara taşınmış bir session.json gibi adlandırılmış ama normal bir dosya değil; bu yüzden --purge onu kaldırmaz. Gerekmiyorsa kendiniz kaldırın."
    done
  fi
  # The lock file itself is kept, even on purge: this process still holds
  # it, and anything that opened it a moment ago (a queued agent run, an app
  # launched after the check above) waits on this inode. Unlinking it would
  # let the next opener create a second lock nobody else sees. A leftover
  # empty lock file and its directory are the accepted cost.
  "$RMDIR" "$LOG_DIR" 2>/dev/null || true
  (( OWN_LAUNCH_AGENTS_DIR == 1 )) && { "$RMDIR" "$LAUNCH_AGENTS" 2>/dev/null || true; }
  echo "$LOCK tutuldu (kurtarma kilidi hiçbir zaman silinmez; tamamen kaldırmak istiyorsanız $APP_SUPPORT klasörünü elle silin)."
  [[ -d "$LOG_DIR" ]] && echo "$LOG_DIR tutuldu: içinde hâlâ Insomnia'nın oluşturmadığı dosyalar var."
else
  # unfinished-command.json names a sudo pmset that held the recovery lock;
  # this run holds it now, so that command has exited.
  remove_owned "$APP_SUPPORT/backstop.sh" "$SESSION" "$APP_SUPPORT/unfinished-command.json"
  (( ${#kept_brightness[@]} > 0 )) || remove_owned "$STATE"
  echo "$APP_SUPPORT/config.json ve $LOG_DIR tutuldu (kaldırmak için --purge kullanın)."
  collect_moved_aside_sessions
  if (( ${#MOVED_ASIDE[@]} > 0 )); then
    echo "$APP_SUPPORT içinde kenara taşınmış ${#MOVED_ASIDE[@]} okunamayan session.json dosyası tutuldu (kaldırmak için --purge kullanın)."
  fi
  if (( ${#NOT_MOVED_ASIDE[@]} > 0 )); then
    for f in "${NOT_MOVED_ASIDE[@]}"; do
      echo "$f tutuldu: kenara taşınmış bir session.json gibi adlandırılmış ama normal bir dosya değil; bu yüzden --purge de onu kaldırmaz. Gerekmiyorsa kendiniz kaldırın."
    done
  fi
fi
(( ${#kept_brightness[@]} == 0 )) || echo "$STATE tutuldu: yukarıda listelenen parlaklık değerlerini içeriyor."

if (( remove_failures > 0 )); then
  echo "Bitti; yalnızca kaldırılamayan $remove_failures dosya kaldı (adları yukarıda)." >&2
  exit 1
fi
echo "Bitti."
