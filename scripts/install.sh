#!/bin/bash
# Install Insomnia: put Insomnia.app (with backstop.sh sealed inside it) in
# ~/Applications, install the LaunchAgent that verifies the bundle and runs
# that script, and write the sudoers rule. Idempotent; asks for sudo once (for
# /etc/sudoers.d/insomnia), before anything of a previous install is touched.
# The bundle and the LaunchAgent are replaced together, in one locked step
# (the agent pins one build, so the two must match at every moment), and a
# run that stops after that step began puts the previous bundle back. Not
# atomic beyond that: a failure after the sudoers step says exactly what was
# replaced so far.
#
# Where the bundle comes from:
#   ./scripts/install.sh                      builds it from this checkout
#                                             (scripts/build-app.sh, ad-hoc
#                                             signed); only from a checkout's
#                                             scripts/ folder (in_checkout)
#   ./install.sh --app /path/to/Insomnia.app  installs a prebuilt bundle, such
#                                             as the one in a release zip
#                                             (arm64 only, so this stops on a
#                                             Mac without Apple Silicon), after
#                                             checking its signature, bundle
#                                             identifier and version. Those
#                                             show the bundle is intact, not
#                                             who made it, so it is refused
#                                             unless --allow-unverified-origin
#                                             is given as well: releases are
#                                             ad-hoc signed and not notarized,
#                                             and the checksum and attestation
#                                             the user checks are what tie a
#                                             zip to this repository. Nothing
#                                             of this checkout is needed then;
#                                             the zip carries this script.
# Either way the bundle is checked before the password prompt, so a bad build
# or download changes nothing.
set -euo pipefail

# Installation always uses the standard per-user layout. A relocated
# INSOMNIA_HOME would make the backstop run here act on one tree while the
# app is installed against another, so refuse rather than guess.
if [[ -n "${INSOMNIA_HOME:-}" ]]; then
  echo "INSOMNIA_HOME ayarlanmış ($INSOMNIA_HOME). install.sh yalnızca ~/Library altındaki standart düzeni destekler;" >&2
  echo "INSOMNIA_HOME değişkenini kaldırıp (unset) yeniden çalıştırın. Hiçbir şey değiştirilmedi." >&2
  exit 1
fi

# How long to wait for the app to exit after asking it to quit.
QUIT_WAIT_SECONDS=15

# Fixed tool paths: never taken from PATH. Tests patch these lines in a
# private copy of the script so no real tool ever runs.
PGREP=/usr/bin/pgrep
KILL=/bin/kill
OSASCRIPT=/usr/bin/osascript
LAUNCHCTL=/bin/launchctl
SUDO=/usr/bin/sudo
PLUTIL=/usr/bin/plutil
CODESIGN=/usr/bin/codesign
DITTO=/usr/bin/ditto
CHMOD=/bin/chmod
SYSCTL=/usr/sbin/sysctl
LOCKF=/usr/bin/lockf
MV=/bin/mv
RM=/bin/rm
RMDIR=/bin/rmdir
MKTEMP=/usr/bin/mktemp
MKDIR=/bin/mkdir
LOCK_TIMEOUT_SECONDS=10
# The limit for one call to sudo, pgrep, launchctl or codesign made while this
# run holds the recovery lock (and for the sudoers check before it); see
# bounded() below.
CALL_TIMEOUT_SECONDS=30

# What a prebuilt bundle (--app) must be.
BUNDLE_ID=com.kgarg.insomnia

# The folder this script is in. build-app.sh and backstop.sh are taken from
# there, and only when it is the scripts/ folder of a source checkout, with
# Package.swift one level up (in_checkout). A release zip's folder is not: it
# holds Insomnia.app, install.sh and uninstall.sh, so a build-app.sh found
# beside this script there was added after the zip was unpacked, for example
# by another account that created the folder in /tmp beforehand. Never the
# folder above either: a zip unpacked at /tmp/Insomnia-<version> would make
# that /tmp, where any account can create scripts/build-app.sh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
in_checkout() { [[ "${SCRIPT_DIR##*/}" == scripts && -f "${SCRIPT_DIR%/*}/Package.swift" ]]; }
APP_DIR="$HOME/Applications"
APP="$APP_DIR/Insomnia.app"
APP_SUPPORT="$HOME/Library/Application Support/Insomnia"
LOG_DIR="$HOME/Library/Logs/Insomnia"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
LABEL="com.insomnia.backstop"
PLIST="$LAUNCH_AGENTS/$LABEL.plist"
SUDOERS=/etc/sudoers.d/insomnia
UID_NUM="$(id -u)"
# Where the new bundle is assembled and signed (step 3) and where the previous
# one waits during the swap (step 6). Both inside $APP_DIR, so the swap is two
# renames on one filesystem. The staging directory's name carries the PID of
# the run that made it, so a later run can tell a dead run's leftover from
# the directory of an install that is still running (step 5).
PREVIOUS_APP="$APP_DIR/.Insomnia.app.previous"
STAGE=""
NEW_APP=""
# Where build-app.sh writes a source build before it is staged.
BUILD_DIR=""
TMP_SUDOERS=""
CANDIDATE=""
CANDIDATE_DIR=""
WORK=""

step() { printf '\n==> %s\n' "$*"; }
usage() { echo "kullanım: $0 [--app /yol/Insomnia.app [--allow-unverified-origin]]" >&2; }
# A command for the user to paste, each word quoted for the shell, so a space,
# quote or $ in a path stays part of that path.
command_line() { local line; line="$(printf '%q ' "$@")"; printf '%s' "${line% }"; }

# Run one external call with a time limit, so a call that stalls (a sudo
# policy or directory-service lookup, a launchd that does not answer) cannot
# keep this run waiting forever. Its combined output is left in
# BOUNDED_OUTPUT (trailing newline removed) and its exit status returned, or
# 124 when it did not finish within CALL_TIMEOUT_SECONDS and was stopped, or
# 125 when it is sudo and still running (pid in BOUNDED_PID).
#
# supervise() starts the call in the background and enforces the limit
# itself, so the limit holds even if this run is killed while it waits. Once
# the limit has passed, the call gets SIGTERM, and SIGKILL one to two seconds
# later if it is still there. sudo only ever gets SIGTERM: killing sudo would
# orphan what it runs as root. Both waits are read from bash's SECONDS clock,
# which counts whole seconds, so a call gets at least CALL_TIMEOUT_SECONDS
# and at most a second more; a slow machine, where each poll takes longer,
# does not stretch them. The supervisor and the call keep fd 9 (the recovery lock, once
# this run holds it) until the call has exited, so no call made under the
# lock outlives it: if this run is killed during a launchctl bootout, the
# bootout is stopped and reaped before the lock goes, and cannot unload an
# agent the app confirms after taking the lock. Every call but sudo is gone
# within three seconds of the limit. A sudo that ignores SIGTERM keeps the
# lock until it ends, as backstop.sh does with sudo pmset.
# Each call's files get a name from mktemp, so a call made inside $(...)
# cannot reuse another's.
BOUNDED_OUTPUT=""
BOUNDED_PID=""
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
# How a bounded call's exit status reads in a message.
call_result() { # status
  if (( $1 == 124 )); then
    printf '%s saniye içinde yanıt vermedi' "$CALL_TIMEOUT_SECONDS"
  else
    printf '%s çıkış koduyla sonlandı' "$1"
  fi
}

# `launchctl print` exits 0 when a job with the label is loaded and 113 when
# none is. Anything else is unknown, not absent, and so is a print that did
# not answer in time (unknown:124). Being loaded says nothing about which
# plist or schedule that job runs (it may be an older one).
loaded_state() { # -> yes | no | unknown:<rc>
  local rc=0
  bounded "$LAUNCHCTL" print "gui/$UID_NUM/$LABEL" || rc=$?
  if (( rc == 124 )); then
    echo "'launchctl print gui/$UID_NUM/$LABEL' ${CALL_TIMEOUT_SECONDS} saniye içinde yanıt vermedi; görevin yüklü olup olmadığı bilinmiyor (unknown:124)." >&2
  fi
  case "$rc" in
    0) echo yes ;;
    113) echo no ;;
    *) echo "unknown:$rc" ;;
  esac
}

PREBUILT=""
ALLOW_UNVERIFIED_ORIGIN=0
while (( $# )); do
  case "$1" in
    --app) [[ $# -ge 2 ]] || { usage; exit 2; }; PREBUILT="$2"; shift 2 ;;
    --allow-unverified-origin) ALLOW_UNVERIFIED_ORIGIN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "bilinmeyen argüman: $1" >&2; usage; exit 2 ;;
  esac
done
if (( ALLOW_UNVERIFIED_ORIGIN )) && [[ -z "$PREBUILT" ]]; then
  echo "--allow-unverified-origin yalnızca --app ile geçerlidir; kaynaktan derlemede kökenine kefil olunacak bir indirme yoktur." >&2
  usage
  exit 2
fi
if [[ "${INSOMNIA_LID_SIMULATION:-}" == 1 && -n "$PREBUILT" ]]; then
  echo "INSOMNIA_LID_SIMULATION=1 yalnızca kaynaktan derlemede geçerlidir; --app ile verilen paket zaten derlenmiş. Hiçbir şey değiştirilmedi." >&2
  exit 2
fi

# Moves a bundle with one rename. Every path passed here is inside $APP_DIR,
# one filesystem, so a rename that fails leaves both paths as they were.
# Refuses when something is at the destination: mv would move the bundle
# into it instead. Each caller handles a failure itself; under set -e an
# unhandled one would exit with the previous job unloaded and let cleanup
# delete the staged build.
move_bundle() { # from to
  if [[ -e "$2" || -L "$2" ]]; then
    echo "$1 taşınmıyor: $2 zaten var" >&2
    return 1
  fi
  "$MV" "$1" "$2"
}

# Whether sudo grants the four pmset commands of the rule without a
# password: 0 when it does, 124 when a check did not answer within
# CALL_TIMEOUT_SECONDS and stopped on SIGTERM, 125 when it did not stop and
# is still running (BOUNDED_PID), 1 otherwise. `sudo -n -l <command>` checks
# the rule without running pmset (nothing on the machine changes).
pmset_rule_check() { # pmset arguments
  local rc=0
  bounded "$SUDO" -n -l /usr/bin/pmset "$@" || rc=$?
  if (( rc == 0 || rc == 124 || rc == 125 )); then return "$rc"; fi
  return 1
}
# The part of a message about a sudo check that is still running.
sudo_alive_note() {
  printf "Bu sudo sürecine SIGTERM gönderildi ve süreç hâlâ çalışıyor (pid %s). Zorla sonlandırılmıyor, çünkü sudo'yu öldürmek root olarak çalıştırdığı işlemi geride bırakabilir" "${BOUNDED_PID:-?}"
}
pmset_rule_effective() {
  pmset_rule_check -a disablesleep 1 \
    && pmset_rule_check -a disablesleep 0 \
    && pmset_rule_check -b lowpowermode 1 \
    && pmset_rule_check -b lowpowermode 0
}

cleanup() {
  if [[ -n "$TMP_SUDOERS" ]]; then "$RM" -f "$TMP_SUDOERS"; fi
  if [[ -n "$CANDIDATE" ]]; then "$RM" -f "$CANDIDATE"; fi
  if [[ -n "$CANDIDATE_DIR" ]]; then "$RMDIR" "$CANDIDATE_DIR" 2>/dev/null || true; fi
  if [[ -n "$STAGE" ]]; then "$RM" -rf "$STAGE"; fi
  if [[ -n "$BUILD_DIR" ]]; then "$RM" -rf "$BUILD_DIR"; fi
  if [[ -n "$WORK" ]]; then
    "$RM" -f "$WORK"/call.* 2>/dev/null || true
    "$RMDIR" "$WORK" 2>/dev/null || true
  fi
}
trap cleanup EXIT
# Scratch space for bounded(): this run's own directory, emptied on exit.
WORK="$("$MKTEMP" -d "${TMPDIR:-/tmp}/insomnia-install.XXXXXX")"

# 1. The bundle to install ---------------------------------------------------
#    Built or verified before the password prompt: nothing on the machine has
#    changed when this step fails.
if [[ -n "$PREBUILT" ]]; then
  step "Hazır derlenmiş paket denetleniyor: $PREBUILT"
  # Release bundles are built for arm64 only (the Release workflow runs on
  # Apple Silicon). hw.optional.arm64 describes the hardware, so a shell
  # running under Rosetta on an Apple Silicon Mac still reads 1; an Intel
  # Mac reads 0 or has no such key.
  arm64="$("$SYSCTL" -n hw.optional.arm64 2>/dev/null || true)"
  if [[ "$arm64" != 1 ]]; then
    echo "Insomnia sürüm paketleri yalnızca Apple Silicon Mac'lerde çalışır ve bu Mac öyle değil ('sysctl -n hw.optional.arm64' sonucu: ${arm64:-değer yok}). Bunun yerine kaynak kod kopyasından derleyip kurun (README, Kurulum). Hiçbir şey değiştirilmedi." >&2
    exit 1
  fi
  if [[ ! -d "$PREBUILT" || ! -f "$PREBUILT/Contents/Info.plist" ]]; then
    echo "$PREBUILT bir uygulama paketi değil (Contents/Info.plist yok). Hiçbir şey değiştirilmedi." >&2
    exit 1
  fi
  # Every check below runs on a private copy, and that copy is what step 3
  # stages and pins. $PREBUILT may sit where someone else can write (a
  # shared folder, /tmp); a bundle swapped there while the password prompt
  # waits is never copied in. BUILD_DIR is removed at exit, as for a build.
  BUILD_DIR="$("$MKTEMP" -d)"
  CHECKED_APP="$BUILD_DIR/Insomnia.app"
  if ! "$DITTO" "$PREBUILT" "$CHECKED_APP"; then
    echo "denetlemek için kopyalanamadı: $PREBUILT. Hiçbir şey değiştirilmedi." >&2
    exit 1
  fi
  INFO_PLIST="$CHECKED_APP/Contents/Info.plist"
  # Signature first: nothing below is read from the bundle until it is known
  # to be intact. --strict rejects what newer codesign would, --deep covers
  # nested code should a later build add any.
  if ! "$CODESIGN" --verify --strict --deep "$CHECKED_APP"; then
    echo "$PREBUILT 'codesign --verify --strict --deep' denetiminden geçemiyor: indirilen dosya bozuk ya da değiştirilmiş. Hiçbir şey değiştirilmedi." >&2
    echo "Zip dosyasını SHA256SUMS ve 'gh attestation verify' ile denetleyin (docs/install.md) ve yeniden indirin." >&2
    exit 1
  fi
  PREBUILT_ID="$("$PLUTIL" -extract CFBundleIdentifier raw -o - "$INFO_PLIST" 2>/dev/null || true)"
  if [[ "$PREBUILT_ID" != "$BUNDLE_ID" ]]; then
    echo "$PREBUILT için paket tanımlayıcısı '${PREBUILT_ID:-<yok>}'; beklenen: $BUNDLE_ID. Hiçbir şey değiştirilmedi." >&2
    exit 1
  fi
  PREBUILT_VERSION="$("$PLUTIL" -extract CFBundleShortVersionString raw -o - "$INFO_PLIST" 2>/dev/null || true)"
  if [[ ! "$PREBUILT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$PREBUILT içinde kullanılabilir bir CFBundleShortVersionString yok ('${PREBUILT_VERSION:-<yok>}'). Hiçbir şey değiştirilmedi." >&2
    exit 1
  fi
  if [[ ! -f "$CHECKED_APP/Contents/Resources/backstop.sh" ]]; then
    echo "$PREBUILT içinde Contents/Resources/backstop.sh yok; kurtarma ajanı mühürlü kopyaya ihtiyaç duyar. Hiçbir şey değiştirilmedi." >&2
    exit 1
  fi
  # Origin. The checks above show the bundle is intact, not where it came
  # from. A signature shows the bundle has not changed since it was signed,
  # and anyone can sign a bundle with this identifier, so this script does
  # not read who signed it. Releases are ad-hoc signed and not notarized
  # (docs/releasing.md). What ties a zip to this repository's Release
  # workflow is the checksum and the attestation, which only the user can
  # check, so every prebuilt bundle needs --allow-unverified-origin, the flag
  # that says they did.
  if (( ALLOW_UNVERIFIED_ORIGIN )); then
    echo "UYARI: Insomnia $PREBUILT_VERSION sürümünün kökeni doğrulanmadı. İmzası paketin bozulmadığını gösterir, onu kimin yaptığını değil."
    echo "--allow-unverified-origin: yine de kuruluyor. İçindeki backstop.sh girişte ve her 60 saniyede bir sizin hesabınızla çalışacak."
    echo "Yalnızca zip dosyasını SHA256SUMS ve 'gh attestation verify' ile kendiniz denetlediyseniz devam edin (docs/install.md)."
    echo "Sürümler Apple onaylı (notarized) değildir; bu yüzden macOS, indirilen bir sürümün ilk açılışını siz Sistem Ayarları > Gizlilik ve Güvenlik bölümünde izin verene dek engeller."
  else
    cat >&2 <<REFUSE
$PREBUILT konumundaki Insomnia $PREBUILT_VERSION sürümünün kökeni doğrulanmadı. İmzası paketin
bozulmadığını gösterir, onu kimin yaptığını değil: herkes bu tanımlayıcıyla bir paket imzalayabilir ve
bu install.sh paketin nereden geldiğini bilemez. Kurulursa içindeki backstop.sh girişte ve her 60 saniyede
bir sizin hesabınızla çalışır. Hiçbir şey değiştirilmedi.
Önce zip dosyasını kendiniz doğrulayın ('shasum -a 256 -c SHA256SUMS' ve --signer-workflow ile
'gh attestation verify'; bkz. docs/install.md), ardından bunu yaptığınızı belirten bayrakla yeniden çalıştırın:
  $(command_line "$0" --allow-unverified-origin --app "$PREBUILT")
REFUSE
    exit 1
  fi
  SOURCE_APP="$CHECKED_APP"
else
  if ! in_checkout || [[ ! -f "$SCRIPT_DIR/build-app.sh" ]]; then
    echo "$SCRIPT_DIR bir kaynak kod kopyasının scripts klasörü değil (bu betiğin yanında build-app.sh, bir üst klasörde Package.swift olmalı); bu yüzden derlenecek bir kaynak yok. Bir sürüm zip dosyasındaki paketi kurmak için onu --app ile verin (docs/install.md). Hiçbir şey değiştirilmedi." >&2
    if [[ -e "$SCRIPT_DIR/build-app.sh" ]] && ! in_checkout; then
      echo "$SCRIPT_DIR/build-app.sh çalıştırılmadı: sürüm zip dosyalarında build-app.sh bulunmaz, yani bu dosya zip açıldıktan sonra eklenmiş." >&2
    fi
    exit 1
  fi
  BUILD_DIR="$("$MKTEMP" -d)"
  "$SCRIPT_DIR/build-app.sh" --output "$BUILD_DIR"
  SOURCE_APP="$BUILD_DIR/Insomnia.app"
fi

# 2. sudoers -----------------------------------------------------------------
#    The password prompt comes first: until the rule is installed and proven
#    effective, the running app is not asked to quit and neither the bundle
#    (backstop.sh included) nor the LaunchAgent are touched.
step "$SUDOERS yazılıyor (parolanız bir kez istenecek)"
TMP_SUDOERS="$("$MKTEMP")"
cat > "$TMP_SUDOERS" <<SUDO
# Installed by Insomnia install.sh. Exactly four commands, nothing else.
$USER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1
$USER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0
$USER ALL=(root) NOPASSWD: /usr/bin/pmset -b lowpowermode 1
$USER ALL=(root) NOPASSWD: /usr/bin/pmset -b lowpowermode 0
SUDO
if "$SUDO" visudo -cf "$TMP_SUDOERS" >/dev/null; then
  "$SUDO" install -m 0440 -o root -g wheel "$TMP_SUDOERS" "$SUDOERS"
else
  echo "sudoers dosyası doğrulamadan geçemedi (ya da sudo kimlik doğrulaması başarısız oldu); kurulmadı. Hiçbir şey değiştirilmedi." >&2
  exit 1
fi
# The backstop cannot undo anything without the rule, so stop here. Checked
# again once this run holds the recovery lock (step 5).
rule_rc=0
pmset_rule_effective || rule_rc=$?
if (( rule_rc == 0 )); then
  echo "sudoers kuralı doğrulandı"
elif (( rule_rc == 124 )); then
  echo "Kuralı denetleyen 'sudo -n -l' ${CALL_TIMEOUT_SECONDS} saniye içinde yanıt vermedi; bu yüzden $SUDOERS içindeki kural doğrulanmadı. Uygulama (backstop.sh dahil) ve LaunchAgent olduğu gibi bırakıldı; sudo yanıt verdiğinde yeniden çalıştırın." >&2
  exit 1
elif (( rule_rc == 125 )); then
  echo "Kuralı denetleyen 'sudo -n -l' ${CALL_TIMEOUT_SECONDS} saniye içinde yanıt vermedi; bu yüzden $SUDOERS içindeki kural doğrulanmadı. $(sudo_alive_note). Uygulama (backstop.sh dahil) ve LaunchAgent olduğu gibi bırakıldı; süreç bittiğinde yeniden çalıştırın (ya da 'sudo kill ${BOUNDED_PID:-<pid>}' ile durdurun)." >&2
  exit 1
else
  echo "'sudo -n pmset' hâlâ izinli değil; $SUDOERS dosyasını denetleyin. Uygulama (backstop.sh dahil) ve LaunchAgent olduğu gibi bırakıldı." >&2
  exit 1
fi

# 3. Bundle ------------------------------------------------------------------
#    Copied into a staging directory inside $APP_DIR. $APP itself is
#    replaced in step 6, in the same locked step as the LaunchAgent: the
#    agent pins one build's requirement, so the bundle at $APP and the loaded
#    agent must be a matching pair before, during and after a failed run.
step "Insomnia.app hazırlanıyor"
# Ask the app to quit and wait until it has actually exited. It refuses to
# quit while it has unresolved recovery work; that refusal stands (no pkill),
# and nothing of the old install is overwritten while it is still running.
if "$PGREP" -x Insomnia >/dev/null 2>&1; then
  echo "Insomnia çalışıyor; önce kapatılıyor (bu, süren oturumu bitirir)."
  "$OSASCRIPT" -e 'tell application id "com.kgarg.insomnia" to quit' >/dev/null 2>&1 || true
  for (( i = 0; i < QUIT_WAIT_SECONDS; i++ )); do
    "$PGREP" -x Insomnia >/dev/null 2>&1 || break
    sleep 1
  done
  if "$PGREP" -x Insomnia >/dev/null 2>&1; then
    echo "Insomnia ${QUIT_WAIT_SECONDS} saniye sonra hâlâ çalışıyor (kendi kurtarması bitene dek kapanmayı reddediyor olabilir)." >&2
    echo "Bitmesini bekleyin ya da menüsünden Insomnia'dan çıkın, ardından yeniden çalıştırın. $SUDOERS kuruldu; uygulama (backstop.sh dahil) ve LaunchAgent olduğu gibi bırakıldı." >&2
    exit 1
  fi
fi
"$MKDIR" -p "$APP_DIR"
STAGE="$("$MKTEMP" -d "$APP_DIR/.Insomnia.app.staging.$$.XXXXXX")"
NEW_APP="$STAGE/Insomnia.app"
# The bundle is copied here whole and reaches $APP in one rename under the
# recovery lock (step 5), so backstop.sh never sees this binary beside an
# older Info.plist or the reverse (it runs the binary's --resume-frozen mode
# only once Info.plist declares InsomniaResumeFrozenVersion).
# ditto keeps the signature's resource seal and every attribute intact (a
# downloaded bundle keeps its quarantine flag; Gatekeeper decides at launch).
"$DITTO" "$SOURCE_APP" "$NEW_APP"
# It keeps the source's modes and ACLs as well. A zip unpacked by a tool
# that keeps group or other write bits, a build made under umask 002, or a
# bundle given an ACL would let other accounts edit the installed bundle.
# An edited backstop.sh breaks the seal, so the agent stops running any
# recovery. The signature covers neither mode bits nor ACLs: both go here
# and the bundle still verifies (the check below runs on this copy).
# Extended attributes, the quarantine flag among them, stay. chmod -R
# skips symbolic links.
if ! "$CHMOD" -R go-w "$NEW_APP" || ! "$CHMOD" -R -N "$NEW_APP"; then
  echo "hazırlanan paketten ($NEW_APP) grup ve diğer kullanıcıların yazma izni ile ACL'ler kaldırılamadı (yukarıdaki hataya bakın). $SUDOERS kuruldu; $APP konumundaki uygulama ve LaunchAgent olduğu gibi bırakıldı." >&2
  exit 1
fi
# backstop.sh was sealed into the bundle before signing (build-app.sh), so
# the signature's resource seal covers it. The LaunchAgent below verifies
# the whole bundle against the requirement read here and only then runs this
# copy; an edited script fails that check. No executable is left in a
# writable directory.
BACKSTOP="$NEW_APP/Contents/Resources/backstop.sh"
echo "imzalandı: $("$CODESIGN" -dv "$NEW_APP" 2>&1 | grep -i identifier || true)"
# What the agent pins: the bundle's designated requirement, in the form
# `codesign -d -r-` prints (an implicit one carries a leading "# "). For an
# ad-hoc signature, which source builds and releases have, that is the cdhash
# of this build, so no other build and no edited bundle satisfies it. A
# bundle signed with a certificate pins what its own signature declares
# instead. It does not depend on the path, so it still holds
# once the bundle is at $APP. The app reads the same text through the
# Security framework (CodeRequirement.swift) to recognise this plist.
REQUIREMENT="$("$CODESIGN" -d -r- "$NEW_APP" 2>&1 | sed -n 's/^#\{0,1\} *designated => //p' | head -n 1)"
if [[ -z "$REQUIREMENT" ]]; then
  echo "yeni paketin belirlenmiş gereksinimi (designated requirement) okunamadı ('codesign -d -r-'); LaunchAgent onu sabitleyemez. $SUDOERS kuruldu; $APP konumundaki uygulama ve LaunchAgent olduğu gibi bırakıldı." >&2
  exit 1
fi
# The check the agent will run every minute, run once here so a bundle the
# agent would refuse is caught now instead of at the first recovery.
if ! "$CODESIGN" --verify --strict "-R=$REQUIREMENT" "$NEW_APP"; then
  echo "yeni paket kendi gereksinimini karşılamıyor ($REQUIREMENT); LaunchAgent, backstop.sh betiğini hiçbir zaman çalıştırmazdı. $SUDOERS kuruldu; $APP konumundaki uygulama ve LaunchAgent olduğu gibi bırakıldı." >&2
  exit 1
fi
echo "LaunchAgent şu gereksinimi arayacak: $REQUIREMENT"

# 4. Directories -------------------------------------------------------------
step "Klasörler oluşturuluyor: $APP_SUPPORT, $LOG_DIR ve $LAUNCH_AGENTS"
"$MKDIR" -p "$APP_SUPPORT" "$LOG_DIR" "$LAUNCH_AGENTS"

# 5. Recovery and LaunchAgent replacement are one transaction under the
#    recovery lock (the same flock(2) file the app and backstop use), so a
#    freshly started app cannot dirty the journal between the clean check
#    and the bootout of the old job. The backstop inherits fd 9 and shares
#    the lock instead of waiting on it. The lock file is never unlinked or
#    replaced, so every party keeps locking the same inode.
step "Kurtarma kilidi alınıyor"
LOCK="$APP_SUPPORT/.recovery.lock"
exec 9<>"$LOCK"
lock_rc=0
"$LOCKF" -t "$LOCK_TIMEOUT_SECONDS" 9 2>/dev/null || lock_rc=$?
if (( lock_rc != 0 )); then
  echo "Kurtarma kilidi ($LOCK) başka bir sürecin elinde (uygulama ya da çalışan bir backstop.sh)." >&2
  echo "Bir dakika bekleyip yeniden çalıştırın. $SUDOERS kuruldu; $APP konumundaki uygulama ve LaunchAgent olduğu gibi bırakıldı." >&2
  exit 75
fi
# From here on every sudo, pgrep, launchctl and codesign call goes through
# bounded(): one that stalls is stopped and ends this run, which lets go of
# the lock, so the app and the agent's backstop can take it again and undo a
# session. A sudo that does not stop on SIGTERM keeps the lock until it ends.
# A pgrep that cannot answer does not say the app is gone, so the run stops.
pgrep_rc=0
bounded "$PGREP" -x Insomnia || pgrep_rc=$?
if (( pgrep_rc == 0 )); then
  echo "Insomnia yeniden açıldı; Insomnia'dan çıkıp yeniden çalıştırın. $APP konumundaki uygulama ve LaunchAgent olduğu gibi bırakıldı." >&2
  exit 1
elif (( pgrep_rc != 1 )); then
  echo "pgrep $(call_result "$pgrep_rc"); bu yüzden Insomnia'nın yeniden açılıp açılmadığı bilinmiyor. $APP konumundaki uygulama ve LaunchAgent olduğu gibi bırakıldı; yeniden çalıştırın." >&2
  exit 1
fi
# The rule was verified in step 2, before this run waited for the lock. An
# uninstall.sh that took the lock first removes $SUDOERS under it, and its
# recovery leaves no journal, so the recovery below would succeed without
# the rule. Without it no session can undo pmset. Checked here, under the
# lock that uninstall.sh also needs, and this run holds the lock until the
# new pair is published.
rule_rc=0
pmset_rule_effective || rule_rc=$?
if (( rule_rc == 124 )); then
  cat >&2 <<FAIL

Kurulum durduruldu: bu çalıştırma kurtarma kilidini aldıktan sonra $SUDOERS içindeki
kuralı yeniden denetleyen 'sudo -n -l', ${CALL_TIMEOUT_SECONDS} saniye içinde yanıt vermedi.
Denetim SIGTERM ile durdu ve bu çalıştırma sonlanıyor; böylece kilit bırakılır ve hem
uygulama hem de LaunchAgent üzerinden çalışan backstop.sh kilidi yeniden alıp geride
kalmış bir oturumu geri alabilir. $APP konumundaki uygulama ve LaunchAgent olduğu gibi
bırakıldı; yeni derleme atıldı. sudo yanıt verdiğinde bu betiği yeniden çalıştırın.
FAIL
  exit 1
elif (( rule_rc == 125 )); then
  cat >&2 <<FAIL

Kurulum durduruldu: bu çalıştırma kurtarma kilidini aldıktan sonra $SUDOERS içindeki
kuralı yeniden denetleyen 'sudo -n -l', ${CALL_TIMEOUT_SECONDS} saniye içinde yanıt vermedi. $(sudo_alive_note).
Süreç bitene dek kurtarma kilidini tutar; o zamana kadar uygulama oturum başlatamaz,
LaunchAgent üzerinden çalışan backstop.sh de bir oturumu geri alamaz. Kendiliğinden
bitmezse durdurun:
  sudo kill ${BOUNDED_PID:-<pid>}
$APP konumundaki uygulama ve LaunchAgent olduğu gibi bırakıldı; yeni derleme atıldı.
Süreç bittiğinde bu betiği yeniden çalıştırın.
FAIL
  exit 1
elif (( rule_rc != 0 )); then
  cat >&2 <<FAIL

Kurulum durduruldu: 'sudo -n pmset', $SUDOERS yukarıda kurulduğunda izinliydi; ama bu
çalıştırma kurtarma kilidini aldıktan sonra artık izinli değil. Bu çalıştırma beklerken
bir şey kuralı kaldırdı ya da değiştirdi (uninstall.sh onu aynı kilit altında kaldırır) ve
kural olmadan hiçbir oturum pmset değişikliğini geri alamaz. $APP konumundaki uygulama ve
LaunchAgent olduğu gibi bırakıldı; yeni derleme atıldı. Kuralı yeniden kurmak için bu
betiği yeniden çalıştırın.
FAIL
  exit 1
fi

# Leftovers of earlier runs are handled only here, under the lock. Step 6
# runs under it too, so no other install is between setting the previous
# bundle aside and resolving the swap now: a bundle at $PREVIOUS_APP belongs
# to a run that was stopped, and no live run needs it to roll back.
#
# Until this run's recovery has succeeded, nothing that could part a loaded
# job from the build it pins is touched: while recovery is unresolved that
# job may be the one retrying it. Two things cannot: putting a set-aside
# bundle back when nothing is at $APP, and removing the staging directories
# of runs that are gone. A job only ever pins $APP, never a path inside a
# staging directory.
if [[ -d "$PREVIOUS_APP" && ! -e "$APP" ]]; then
  # Stopped between the two renames: nothing at $APP.
  if ! move_bundle "$PREVIOUS_APP" "$APP"; then
    cat >&2 <<FAIL

Kurulum durduruldu: $APP konumunda hiçbir şey yok ve yarıda kalmış bir çalıştırmanın
$PREVIOUS_APP konumuna ayırdığı önceki uygulamayı geri koyma başarısız oldu. Uygulama
orada kalıyor; başka hiçbir şey taşınmadı ya da devreden çıkarılmadı ve yeni derleme atıldı.
Şu ana kadar kurulan: $SUDOERS.
Uygulama geri gelene kadar LaunchAgent $APP konumunda uygulama bulamaz. macOS oturumunuzu
kapatmadan önce onu geri taşıyın ve bu betiği yeniden çalıştırın:
  $(command_line mv "$PREVIOUS_APP" "$APP")
FAIL
    exit 1
  fi
  echo "yarıda kalmış bir çalıştırmanın kenara ayırdığı uygulama geri kondu: $APP"
fi
# Staging directories of runs that are gone, matched by the exact name step 3
# gives them (mktemp's suffix is six letters and digits). One whose PID is
# alive belongs to an install that is still assembling its bundle and has
# not reached this lock yet, so it stays. kill -0 only asks whether the
# process exists; it sends no signal.
staging_re='^\.Insomnia\.app\.staging\.([0-9]+)\.[A-Za-z0-9]{6}$'
for dir in "$APP_DIR"/.Insomnia.app.staging.*; do
  [[ -d "$dir" && ! -L "$dir" && "$dir" != "$STAGE" ]] || continue
  [[ "${dir##*/}" =~ $staging_re ]] || continue
  if "$KILL" -0 "${BASH_REMATCH[1]}" 2>/dev/null; then
    continue
  fi
  "$RM" -rf "$dir"
done

# Whether the plist on disk, the one launchd loads at the next login, pins
# the bundle at $PREVIOUS_APP and not the one at $APP: 0 when it does, 1
# when it does not, 124 when a codesign check did not answer in time, so
# it is not known which of the two it pins.
plist_pins_previous() {
  local pinned rc
  pinned="$("$PLUTIL" -extract ProgramArguments.4 raw -o - "$PLIST" 2>/dev/null || true)"
  [[ -n "$pinned" ]] || return 1
  rc=0
  bounded "$CODESIGN" --verify --strict "-R=$pinned" "$APP" || rc=$?
  if (( rc == 0 )); then return 1; fi
  if (( rc == 124 )); then return 124; fi
  rc=0
  bounded "$CODESIGN" --verify --strict "-R=$pinned" "$PREVIOUS_APP" || rc=$?
  if (( rc == 0 || rc == 124 )); then return "$rc"; fi
  return 1
}
pins_unknown_note="$PLIST dosyasının iki paketten hangisini sabitlediğini gösteren 'codesign --verify',
${CALL_TIMEOUT_SECONDS} saniye içinde yanıt vermedi."

step "Kalmış bir oturum varsa bitiriliyor ve kurtarma kayıt defteri denetleniyor"
recovery_rc=0
/bin/bash "$BACKSTOP" --force || recovery_rc=$?

if (( recovery_rc != 0 )); then
  held="$(loaded_state)"
  case "$held" in
    yes) agent_note="$LABEL etiketli bir LaunchAgent görevi yüklü ve olduğu gibi bırakıldı. Hangi plist ve
zamanlamayla çalıştığı burada doğrulanmadı; 'launchctl print gui/$UID_NUM/$LABEL' ile denetleyin." ;;
    no) agent_note="$LABEL adlı LaunchAgent yüklü değil; yani kendiliğinden yeniden deneyen bir şey yok." ;;
    *) agent_note="'launchctl print gui/$UID_NUM/$LABEL' $(call_result "${held#unknown:}"); bu yüzden yüklü bir LaunchAgent olup olmadığı bilinmiyor." ;;
  esac
  if [[ -d "$PREVIOUS_APP" ]]; then
    pair_note="Yarıda kalmış bir kurulum $APP konumuna bir derleme bıraktı ve önceki uygulamayı
$PREVIOUS_APP konumuna ayırdı. İki paket de taşınmadı ve hiçbir LaunchAgent görevi devreden
çıkarılmadı ya da değiştirilmedi; yani yüklü bir görev sabitlediği derlemeyi hâlâ bulur. Yeni derleme atıldı."
    pins_rc=0
    plist_pins_previous || pins_rc=$?
    if (( pins_rc == 0 )); then
      pair_note="$pair_note
$PLIST önceki uygulamayı sabitliyor; bu yüzden bir sonraki girişte yüklenen ajan
$APP konumundaki derlemeyi reddeder. macOS oturumunuzu kapatmadan önce kurtarma
sorununu çözün ve önceki uygulamayı geri koyan bu betiği yeniden çalıştırın."
    elif (( pins_rc == 124 )); then
      pair_note="$pair_note
$pins_unknown_note"
    fi
  else
    pair_note="$APP konumundaki uygulama ve LaunchAgent değiştirilmedi ya da devreden
çıkarılmadı; yani hâlâ birbiriyle eşleşiyorlar. Yeni derleme atıldı."
  fi
  # How to run the recovery again. A checkout has backstop.sh under scripts/.
  # A zip has it only inside the bundle at $PREBUILT, and the checked private
  # copy is deleted when this script exits; the original may have changed
  # since the check, so the step is this script again, which checks a new copy.
  if [[ -n "$PREBUILT" ]]; then
    manual_step="Ya da bu betiği yeniden çalıştırın. Betik paketin yeni bir özel
kopyasını denetler ve uygulama ya da LaunchAgent değiştirilmeden önce o kopyanın
kurtarmasını çalıştırır:
  $(command_line "$0" --allow-unverified-origin --app "$PREBUILT")"
  else
    manual_step="Ya da kurtarmayı elle çalıştırın:
  $(command_line /bin/bash "$SCRIPT_DIR/backstop.sh" --force)
Ardından uygulama ve LaunchAgent kurulsun diye bu betiği yeniden çalıştırın."
  fi
  cat >&2 <<FAIL

Kurulum durduruldu: backstop.sh önceki bir oturumu tümüyle geri alamadı
(çıkış kodu: $recovery_rc). $pair_note
Şu ana kadar kurulan: $SUDOERS.
$agent_note
$LOG_DIR/insomnia.log dosyasını denetleyin ve bildirdiği sorunu çözün. Kaydedilmiş ses,
ekran parlaklığı ya da klavye arka ışığı için uygulama gerekir; kuruluysa açın:
  $(command_line open "$APP")
$manual_step
FAIL
  exit 1
fi

# Recovery is resolved, so a loaded job has nothing left to retry, and the
# rest of the repair may unload it and move bundles.
if [[ -d "$PREVIOUS_APP" ]]; then
  pins_rc=0
  plist_pins_previous || pins_rc=$?
  if (( pins_rc == 124 )); then
    # Which bundle goes back is not known, so neither moves and no job is
    # unloaded: whatever job is loaded keeps the build it pins.
    cat >&2 <<FAIL

Kurulum durduruldu: yarıda kalmış bir çalıştırma $APP konumuna bir derleme bıraktı ve
önceki uygulamayı $PREVIOUS_APP konumuna ayırdı; ayrıca $pins_unknown_note
İki paket de taşınmadı ve hiçbir LaunchAgent görevi devreden çıkarılmadı; yeni derleme
atıldı. Şu ana kadar kurulan: $SUDOERS. Kurtarma kayıt defteri yukarıda denetlendiğinde
temizdi. codesign yanıt verdiğinde bu betiği yeniden çalıştırın.
FAIL
    exit 1
  fi
  if (( pins_rc == 0 )); then
    # Stopped after the second rename but before the new plist was
    # published: $PLIST still pins the previous bundle, so that one goes
    # back and the interrupted run's build is discarded with this run's
    # staging directory. That run may have left its own job loaded (it was
    # killed after its bootstrap, or its unload failed). Such a job pins the
    # build at $APP: a run loads its job only after the swap, and swaps only
    # once print confirms the previous job is gone. So any loaded job is
    # unloaded first, and if print does not confirm that, neither bundle
    # moves and the job keeps the build it pins.
    held="$(loaded_state)"
    if [[ "$held" != no ]]; then
      bounded "$LAUNCHCTL" bootout "gui/$UID_NUM/$LABEL" || true
      cleared="$(loaded_state)"
      if [[ "$cleared" != no ]]; then
        cat >&2 <<FAIL

Kurulum durduruldu: yarıda kalmış bir çalıştırma kendi derlemesini $APP konumunda,
önceki uygulamayı $PREVIOUS_APP konumunda bıraktı ve $PLIST önceki uygulamayı sabitliyor.
O çalıştırmadan kalan $LABEL etiketli bir görev hâlâ yüklü olabilir ve devreden
çıkarıldığı doğrulanamadı (launchctl print: $cleared). O görev $APP konumundaki derlemeyi
sabitlediği için iki paket de taşınmadı. Şu ana kadar kurulan: $SUDOERS. Kurtarma kayıt
defteri yukarıda denetlendiğinde temizdi.
Bir sonraki girişte $PLIST yüklenir ve bu dosya $APP konumundaki uygulamayla eşleşmez.
macOS oturumunuzu kapatmadan önce görevi devreden çıkarın ve bu betiği yeniden çalıştırın:
  launchctl bootout gui/$UID_NUM/$LABEL
FAIL
        exit 1
      fi
    fi
    unloaded_note=""
    if [[ "$held" != no ]]; then
      unloaded_note="O çalıştırmanın bıraktığı görev devreden çıkarıldı (launchctl print doğruluyor); şu anda yüklü görev yok.
"
    fi
    if ! move_bundle "$APP" "$STAGE/Interrupted.app"; then
      cat >&2 <<FAIL

Kurulum durduruldu: yarıda kalmış bir çalıştırma kendi derlemesini $APP konumunda,
$PLIST dosyasının sabitlediği önceki uygulamayı $PREVIOUS_APP konumunda bıraktı ve
o derlemeyi $APP konumundan çıkarma başarısız oldu.
İki paket de taşınmadı; yeni derleme atıldı. Şu ana kadar kurulan: $SUDOERS.
${unloaded_note}Bir sonraki girişte $PLIST yüklenir ve bu dosya $APP konumundaki uygulamayla eşleşmez.
macOS oturumunuzu kapatmadan önce paketin taşınmasını engelleyen sorunu giderin (yukarıdaki
hataya bakın) ve önceki uygulamayı geri koyan bu betiği yeniden çalıştırın.
FAIL
      exit 1
    fi
    if ! move_bundle "$PREVIOUS_APP" "$APP"; then
      # Nothing is at $APP now. The previous app stays set aside, and the
      # staging directory is kept, with the interrupted run's build and this
      # run's: no bundle is deleted while none is at $APP.
      kept="$STAGE"
      STAGE=""
      cat >&2 <<FAIL

Kurulum durduruldu: yarıda kalmış bir çalıştırma kendi derlemesini $APP konumunda,
$PLIST dosyasının sabitlediği önceki uygulamayı $PREVIOUS_APP konumunda bıraktı. O derleme
yoldan çekildi, ama önceki uygulamayı $APP konumuna geri taşıma başarısız oldu; yani $APP
konumunda hiçbir şey yok.
Önceki uygulama $PREVIOUS_APP konumunda kalıyor; yarıda kalan çalıştırmanın derlemesi ve
yeni derleme şurada tutuluyor: $kept. Şu ana kadar kurulan: $SUDOERS.
${unloaded_note}Önceki uygulama geri gelene kadar LaunchAgent $APP konumunda uygulama bulamaz.
macOS oturumunuzu kapatmadan önce onu geri taşıyın ve ajanını yükleyin:
  $(command_line mv "$PREVIOUS_APP" "$APP")
  $(command_line launchctl bootstrap "gui/$UID_NUM" "$PLIST")
ya da önce onu geri koyan bu betiği yeniden çalıştırın.
FAIL
      exit 1
    fi
    echo "yarıda kalmış bir çalıştırmanın kenara ayırdığı uygulama geri kondu: $APP; $PLIST onu sabitliyor"
    if [[ "$held" != no ]]; then
      # A job was loaded when this run started; the previous plist takes its
      # place, so a failure in step 6 reloads that one. Unless print confirms
      # the reload, nothing below may count on a loaded job, so the run stops.
      reload_rc=0
      bounded "$LAUNCHCTL" bootstrap "gui/$UID_NUM" "$PLIST" || reload_rc=$?
      now="$(loaded_state)"
      if (( reload_rc != 0 )) || [[ "$now" != yes ]]; then
        if (( reload_rc != 0 )); then
          reload_reason="'launchctl bootstrap' $(call_result "$reload_rc")"
        else
          reload_reason="'launchctl bootstrap' başarılı olduğunu bildirdi, ama launchctl print sonucu: $now"
        fi
        if [[ "$now" == yes ]]; then
          job_note="$LABEL etiketli bir görev listeleniyor (launchctl print), ama bootstrap başarısız oldu;
yani hangi plist ile çalıştığı bilinmiyor. 'launchctl print gui/$UID_NUM/$LABEL' ile denetleyin."
        else
          job_note="$LABEL etiketli hiçbir görevin yüklü olduğu doğrulanmadı (launchctl print: $now). Hiç
görev yüklü değilse öncekini yeniden yükleyin:
  $(command_line launchctl bootstrap "gui/$UID_NUM" "$PLIST")"
        fi
        cat >&2 <<FAIL

Kurulum durduruldu: yarıda kalmış bir çalıştırmanın bıraktığı görev devreden çıkarıldı
ve $PLIST dosyasının sabitlediği önceki uygulama $APP konumuna geri döndü, ama $PLIST
dosyasının yeniden yüklendiği doğrulanamadı ($reload_reason).
Yeni derleme atıldı. Şu ana kadar kurulan: $SUDOERS. Kurtarma kayıt defteri yukarıda
denetlendiğinde temizdi ve bir sonraki girişte $APP konumundaki uygulamayla eşleşen
$PLIST yüklenir.
$job_note
Ardından bu betiği yeniden çalıştırın.
FAIL
        exit 1
      fi
      echo "yarıda kalan çalıştırmanın bıraktığı görev devreden çıkarıldı ve $PLIST yeniden yüklendi (launchctl print doğruluyor)"
    fi
  else
    # $APP is what the plist pins (the interrupted run got as far as
    # publishing it), or nothing pins either: the set-aside copy is spare.
    "$RM" -rf "$PREVIOUS_APP"
    echo "yarıda kalmış bir çalıştırmanın kenara ayırdığı paket kaldırıldı; $APP yerinde kalıyor"
  fi
fi

# 6. LaunchAgent: verifies the bundle and runs its sealed backstop at load
#    and every 60 s. The backstop enforces the saved deadline itself and is
#    a no-op while the session on disk is valid. The plist's ProgramArguments
#    are `/bin/sh -c "$AGENT_PROGRAM" sh "$REQUIREMENT" "$APP"`: the program
#    runs `codesign --verify --strict -R=<requirement>` on the bundle and
#    execs Contents/Resources/backstop.sh only when that passes; otherwise it
#    logs one line to $LOG_DIR/insomnia.log and exits 1 without running
#    anything. AGENT_PROGRAM must stay byte for byte what LaunchdBackstop.swift
#    writes (LaunchdBackstopTests compares them), or the app reloads the agent
#    at every session start. Same pattern as the app for the file itself: the
#    trusted plist at $PLIST is only ever a plist launchd actually loaded.
#    The new one is written to a private candidate one directory below it:
#    launchctl refuses any path without a `.plist` suffix (EIO), and
#    launchd's login-time load of $LAUNCH_AGENTS does not descend into
#    subdirectories, so a leftover candidate is never picked up as a second
#    copy of the label. It is loaded from there and published with one
#    rename (same filesystem) after `launchctl print` confirms the job is
#    loaded. Any failure leaves $PLIST byte for byte as it was. A run whose
#    recovery is unresolved stopped above, so the previous job and the
#    bundle at $APP it pins are only replaced once nothing is left to retry.
step "LaunchAgent kuruluyor: $LABEL"
CANDIDATE_DIR="$LAUNCH_AGENTS/.$LABEL.staging"
CANDIDATE="$CANDIDATE_DIR/$LABEL.candidate-$$.plist"
"$MKDIR" -p "$CANDIDATE_DIR"
# Leftovers of earlier attempts, including an older build's candidates in
# $LAUNCH_AGENTS itself (those make launchd's login load report an error).
"$RM" -f "$CANDIDATE_DIR/$LABEL.candidate-"* "$LAUNCH_AGENTS/$LABEL.candidate-"*

before="$(loaded_state)"

# shellcheck disable=SC2016  # the $1/$2/$HOME/$r below are for the agent's shell, not this one
AGENT_PROGRAM='r="$(/usr/bin/codesign --verify --strict "-R=$1" "$2" 2>&1)" && exec /bin/bash "$2/Contents/Resources/backstop.sh"; mkdir -p "$HOME/Library/Logs/Insomnia"; printf "%s [error] backstop agent: %s does not satisfy the pinned code requirement; backstop.sh not run. Reinstall Insomnia (scripts/install.sh). codesign: %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$2" "$(printf %s "$r" | tr "\n" " ")" >> "$HOME/Library/Logs/Insomnia/insomnia.log"; exit 1'
xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
cat > "$CANDIDATE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>-c</string>
		<string>$(printf '%s' "$AGENT_PROGRAM" | xml_escape)</string>
		<string>sh</string>
		<string>$(printf '%s' "$REQUIREMENT" | xml_escape)</string>
		<string>$(printf '%s' "$APP" | xml_escape)</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>StartInterval</key>
	<integer>60</integer>
</dict>
</plist>
PLIST
"$PLUTIL" -lint "$CANDIDATE" >/dev/null

# bootout by service target (ignored if nothing is loaded; a path launchctl
# cannot read fails with EIO instead of unloading anything), swap the new
# bundle in, then bootstrap from the candidate. The swap waits until print
# confirms the previous job is gone, and the new job is loaded after it, so
# no agent is ever loaded against the other build's bundle, and any job
# loaded after the swap is this run's. On failure that job is unloaded
# (print confirms it) before the swap is undone and anything is reloaded.
bounded "$LAUNCHCTL" bootout "gui/$UID_NUM/$LABEL" || true
if [[ "$before" != no ]]; then
  cleared="$(loaded_state)"
  if [[ "$cleared" != no ]]; then
    reload_hint=""
    if [[ "$cleared" != yes && -f "$PLIST" ]]; then
      reload_hint="Yüklü görev yoksa öncekini yeniden yükleyin:
  $(command_line launchctl bootstrap "gui/$UID_NUM" "$PLIST")
"
    fi
    cat >&2 <<FAIL

Kurulum durduruldu: önceki LaunchAgent görevinin devreden çıkarıldığı doğrulanamadı
(launchctl print: $cleared); bu yüzden $APP konumundaki uygulama değiştirilmedi ve yeni
derleme atıldı. $PLIST değiştirilmedi.
$SUDOERS kuruldu ve kurtarma kayıt defteri yukarıda denetlendiğinde temizdi.
${reload_hint}'launchctl print gui/$UID_NUM/$LABEL' ile denetleyin ve bu betiği yeniden çalıştırın.
FAIL
    exit 1
  fi
fi
# A rename that fails is handled like a failed load: no job of this run was
# loaded, and the failure branch below puts back what moved and reloads the
# previous job.
had_app=0
set_aside=0
swapped=0
swap_reason=""
if [[ -e "$APP" ]]; then
  had_app=1
  if move_bundle "$APP" "$PREVIOUS_APP"; then
    set_aside=1
  else
    swap_reason="$APP konumundaki önceki uygulama $PREVIOUS_APP konumuna ayrılamadı"
  fi
fi
if [[ -z "$swap_reason" ]]; then
  if move_bundle "$NEW_APP" "$APP"; then
    swapped=1
  else
    swap_reason="yeni derleme $NEW_APP konumundan $APP konumuna taşınamadı"
  fi
fi
bootstrap_rc=0
# Without a swap nothing was loaded: the previous job is confirmed unloaded
# above (or none was loaded), and the new one is loaded only after the swap.
after=no
published=0
if (( swapped )); then
  bounded "$LAUNCHCTL" bootstrap "gui/$UID_NUM" "$CANDIDATE" || bootstrap_rc=$?
  if [[ -n "$BOUNDED_OUTPUT" ]]; then printf '%s\n' "$BOUNDED_OUTPUT" >&2; fi
  after="$(loaded_state)"
  if (( bootstrap_rc == 0 )) && [[ "$after" == yes ]] && "$MV" -f "$CANDIDATE" "$PLIST"; then
    published=1
  fi
fi

if (( published )); then
  echo "LaunchAgent yüklendi: $LABEL (launchctl print doğruluyor); $PLIST yerine kondu"
  if (( set_aside )); then
    if "$RM" -rf "$PREVIOUS_APP"; then
      echo "önceki $APP yenisiyle değiştirildi"
    else
      echo "önceki $APP yenisiyle değiştirildi, ama $PREVIOUS_APP konumundaki kopyası kaldırılamadı; bu betiğin bir sonraki çalıştırması onu kaldırır" >&2
    fi
  fi
  # Installs before this layout ran a writable copy from $APP_SUPPORT. The
  # agent just loaded runs the sealed one, so that copy goes now, not before.
  if [[ -e "$APP_SUPPORT/backstop.sh" ]]; then
    "$RM" -f "$APP_SUPPORT/backstop.sh"
    echo "önceki kurulumdan kalan $APP_SUPPORT/backstop.sh kaldırıldı (ajan artık pakette mühürlü kopyayı çalıştırıyor)"
  fi
else
  fix_note="launchctl hatasını giderip yeniden çalıştırın."
  if [[ -n "$swap_reason" ]]; then
    reason="$swap_reason (yukarıdaki hataya bakın)"
    fix_note="Paketin taşınmasını engelleyen sorunu giderip yeniden çalıştırın."
  elif (( bootstrap_rc != 0 )); then
    reason="yeni LaunchAgent için 'launchctl bootstrap' $(call_result "$bootstrap_rc")"
  elif [[ "$after" != yes ]]; then
    reason="'launchctl bootstrap' başarılı olduğunu bildirdi, ama görevin yüklü olduğu doğrulanmadı (launchctl print: $after)"
  else
    reason="yeni LaunchAgent yüklendi, ama plist dosyası bir sonraki girişte yükleneceği
yere ($PLIST) taşınamadı"
    fix_note="$LAUNCH_AGENTS klasörünün yazılabilir olduğunu denetleyip yeniden çalıştırın."
  fi
  # A job print lists, or cannot rule out, is this run's (see the swap
  # above): loaded from the candidate, or by a bootstrap that reported an
  # error anyway. It pins the new build, so it is unloaded before the
  # previous bundle goes back, and print has to confirm that.
  unloaded=no
  stopped="Kurulum durduruldu: $reason."
  if [[ "$after" != no ]]; then
    bounded "$LAUNCHCTL" bootout "gui/$UID_NUM/$LABEL" || true
    unloaded="$(loaded_state)"
    stopped="$stopped
Yeni görev yeniden devreden çıkarıldı (launchctl print doğruluyor)."
  fi
  # Undo the swap first, so whatever job runs next (the previous plist
  # reloaded below, or loaded at the next login) finds the build it pins.
  # Unless the new job is confirmed unloaded it stays with the build it
  # pins: putting the previous app back would leave it refusing every run.
  kept_why=""
  if [[ "$unloaded" != no ]]; then
    kept_why="Yeni görev hâlâ yüklü olabilir: devreden çıkarıldığı doğrulanmadı (launchctl print: $unloaded).
Yeni derleme $APP konumunda kalıyor, çünkü o görev onu sabitliyor ve önceki
uygulamayı reddederdi."
  elif (( swapped )) && ! move_bundle "$APP" "$NEW_APP"; then
    kept_why="Bu çalıştırmaya ait yüklü görev yok (launchctl print doğruluyor), ama yeni
derlemeyi $APP konumundan çıkarma başarısız oldu (yukarıdaki hataya bakın); bu yüzden orada kalıyor."
  fi
  if [[ -n "$kept_why" ]]; then
    # The swap stays and the previous bundle stays set aside, which is the
    # state an install killed mid-swap leaves; the rerun's repair above
    # handles it.
    if (( set_aside )); then
      kept_note="Önceki uygulama $PREVIOUS_APP konumunda tutuluyor; yeniden çalıştırma yüklü
görevi devreden çıkarır ve $PLIST hâlâ önceki uygulamayı sabitliyorsa onu geri koyar."
    else
      kept_note="Bu çalıştırmadan önce $APP konumunda kurulu bir uygulama yoktu."
    fi
    if [[ -f "$PLIST" ]]; then
      plist_note="$PLIST değiştirilmedi ve bu derlemeyi sabitlemiyor; bu yüzden bir sonraki
girişte yüklenen ajan çalışmayı reddederdi."
    else
      plist_note="$PLIST konumunda plist yok; bu yüzden bir sonraki girişte hiçbir ajan yüklenmez."
    fi
    cat >&2 <<FAIL

Kurulum durduruldu: $reason.
$kept_why $kept_note
$plist_note
$SUDOERS kuruldu ve kurtarma kayıt defteri yukarıda denetlendiğinde temizdi.
${fix_note%.}; bunu macOS oturumunuzu kapatmadan önce yapın.
FAIL
    exit 1
  fi
  if (( set_aside )); then
    if ! move_bundle "$PREVIOUS_APP" "$APP"; then
      # Nothing is at $APP now. The previous app stays set aside and the
      # new build stays staged: no bundle is deleted while none is at $APP.
      # Its job is not reloaded, since it would find no app to run.
      STAGE=""
      if [[ -f "$PLIST" ]]; then
        plist_note="$PLIST konumundaki plist değiştirilmedi."
        restore="onu geri taşıyın ve ajanını yükleyin:
  $(command_line mv "$PREVIOUS_APP" "$APP")
  $(command_line launchctl bootstrap "gui/$UID_NUM" "$PLIST")"
      else
        plist_note="$PLIST konumunda plist yok."
        restore="onu geri taşıyın:
  $(command_line mv "$PREVIOUS_APP" "$APP")"
      fi
      cat >&2 <<FAIL

$stopped
Ardından önceki uygulamayı $APP konumuna geri koyma başarısız oldu (yukarıdaki hataya
bakın); yani $APP konumunda hiçbir şey yok. Önceki uygulama $PREVIOUS_APP konumunda,
yeni derleme $NEW_APP konumunda kalıyor; ikisi de silinmedi.
$plist_note
$SUDOERS kuruldu ve kurtarma kayıt defteri yukarıda denetlendiğinde temizdi.
Önceki uygulama geri gelene kadar LaunchAgent $APP konumunda uygulama bulamaz.
macOS oturumunuzu kapatmadan önce $restore
ya da önce onu geri koyan bu betiği yeniden çalıştırın.
FAIL
      exit 1
    fi
    app_note="Önceki uygulama $APP konumuna geri kondu; yeni derleme atıldı."
  elif (( had_app )); then
    app_note="Önceki uygulama $APP konumundan hiç taşınmadı; yeni derleme atıldı."
  else
    app_note="$APP konumunda önceden kurulu bir uygulama yoktu, şimdi de yok; yeni derleme atıldı."
  fi
  # The trusted plist was never modified. Reload the previous job only when
  # it is known to have been loaded. A job being listed afterwards does not
  # say where it came from: only a reload that itself succeeded, confirmed
  # by print, is "the previous plist loaded again". Every print result is
  # reported as yes / no / unknown; unknown is never reported as absent.
  case "$before" in
    yes)
      reload_rc=0
      bounded "$LAUNCHCTL" bootstrap "gui/$UID_NUM" "$PLIST" || reload_rc=$?
      now="$(loaded_state)"
      if (( reload_rc == 0 )) && [[ "$now" == yes ]]; then
        outcome="$LABEL etiketli bir görev önceki plist dosyasından ($PLIST) yeniden yüklendi
(launchctl bootstrap başarılı oldu ve launchctl print doğruluyor; zamanlaması burada doğrulanmadı)."
      elif [[ "$now" == yes ]]; then
        outcome="Önceki plist dosyasının yeniden yüklendiği doğrulanamadı ('launchctl bootstrap'
$(call_result "$reload_rc")). $LABEL etiketli bir görev yüklü (launchctl print), ama hangi plist ile çalıştığı
bilinmiyor: bu denemeden önce yüklü olan görev olabilir.
'launchctl print gui/$UID_NUM/$LABEL' ile kendiniz denetleyin ya da bu betiği yeniden çalıştırın."
      else
        outcome="Önceki görev yeniden yüklenemedi ('launchctl bootstrap'
$(call_result "$reload_rc"); launchctl print: $now); $LABEL etiketli hiçbir görevin yüklü olduğu doğrulanmadı. Şunu
  $(command_line launchctl bootstrap "gui/$UID_NUM" "$PLIST")
kendiniz çalıştırın ya da bu betiği yeniden çalıştırın."
      fi ;;
    no)
      now="$(loaded_state)"
      case "$now" in
        yes) outcome="Önceden yüklü görev yoktu; şimdi başarısız denemeden kalan bir görev yüklü (launchctl print).
Bu görev kurulmamış olan yeni derlemeyi sabitlediği için çalışmayı reddeder; onu
'launchctl bootout gui/$UID_NUM/$LABEL' ile devreden çıkarın ya da bu betiği yeniden çalıştırın." ;;
        no) outcome="$LABEL etiketli bir görev önceden yüklü değildi, şimdi de yüklü değil." ;;
        *) outcome="Önceden yüklü görev yoktu; şimdi yüklü olup olmadığı bilinmiyor ('launchctl print'
$(call_result "${now#unknown:}")); yani iki yönde de doğrulanmadı.
'launchctl print gui/$UID_NUM/$LABEL' ile kendiniz denetleyin." ;;
      esac ;;
    *)
      outcome="Önceden bir görevin yüklü olup olmadığı bilinmiyor (launchctl print $(call_result "${before#unknown:}"));
bu yüzden hiçbir şey yeniden yüklenmedi. 'launchctl print gui/$UID_NUM/$LABEL' ile denetleyin ve
yüklü görev yoksa öncekini kendiniz yükleyin:
  $(command_line launchctl bootstrap "gui/$UID_NUM" "$PLIST")" ;;
  esac
  if [[ -f "$PLIST" ]]; then
    plist_note="$PLIST konumundaki plist değiştirilmedi."
  else
    plist_note="$PLIST konumunda plist yok."
  fi
  cat >&2 <<FAIL

$stopped
$plist_note
$app_note
$outcome
$SUDOERS kuruldu ve kurtarma kayıt defteri yukarıda denetlendiğinde temizdi.
$fix_note
FAIL
  exit 1
fi

# 7. Done --------------------------------------------------------------------
step "Kuruldu"
# The uninstaller shipped beside this script: scripts/ in a checkout, the
# zip's top level in a release (which may be unpacked inside a checkout).
UNINSTALL="$SCRIPT_DIR/uninstall.sh"
cat <<NEXT
Sonraki adımlar:
  1. Başlatın:          $(command_line open "$APP")
  2. İsteğe bağlı:      Sistem Ayarları > Wi-Fi > Erişim noktalarına katılmak için sor (Ask to join hotspots): Otomatik
  3. Ayar dosyası:      $APP_SUPPORT/config.json
  4. Günlükler:         $LOG_DIR/insomnia.log
  5. Kaldırma:          $(command_line "$UNINSTALL")
NEXT
