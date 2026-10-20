---
name: maintain-uykusuz
description: Check on, troubleshoot, or uninstall an installed Uykusuz (the macOS menu bar app that keeps a Mac awake for a timed session). Use when the user asks why Uykusuz shows a warning, whether a session cleaned up after itself, why the hotspot password stopped working, or how to remove it.
---

# Maintain Uykusuz

Reference pages in https://github.com/Mustafa-Ghn/insomnia-tr (Turkish):
[docs/recovery.md](../../docs/recovery.md),
[docs/install.md](../../docs/install.md),
[docs/lid-close.md](../../docs/lid-close.md) and
[docs/extras.md](../../docs/extras.md).

## Rules

- Never run `sudo`, `pmset` changes, `kill` or `kill -CONT` yourself. Show the
  user the command, say why, and let them run it.
- Never edit or delete files in `~/Library/Application Support/Uykusuz/`.
  `state.json` there is the recovery journal: the list of changes Uykusuz
  still has to undo.
- Never signal a pid taken from an old log line. Pids get reused. Check it with
  `ps -o pid,stat,lstart,command -p <pid>` first.

## Check the state

1. `tail -n 100 ~/Library/Logs/Uykusuz/uykusuz.log` shows what the app and
   the recovery agent did last.
2. `pmset -g | grep -i sleepdisabled` shows `1` while sleep is turned off.
3. `cat ~/Library/Application\ Support/Uykusuz/state.json` shows what is
   still waiting to be undone. These entries are pending:
   - `sleepDisabledByUs`, `lowPowerSetByUs` or `dockerFrozen` set to `true`
   - a non-empty `frozenProcesses`, `appNapOverrides` or `savedAudioOutputs`
   - `savedOutputVolume` or `savedMuted`
   - `savedDisplayBrightness` or `savedKeyboardBrightness`, unless
     `displayRestoreRefused` or `keyboardRestoreRefused` is `true`

   Other keys, such as `keptDisplayReadLit`, `keptDisplayUnderLowPower` and
   `displayRestoredUnderLowPower`, are records the app keeps, not changes to
   undo. A brightness value kept after a refused restore blocks nothing.
   Saved audio for an output that isn't connected waits for it to reconnect
   and doesn't block ending a session.
4. `launchctl print gui/$(id -u)/com.mustafaghn.uykusuz.backstop` shows whether the
   recovery agent is loaded.

## Warnings in the menu

Match the warning to docs/recovery.md, "Kurtarmanın sınırları ve elle
ilgilenilmesi gerekenler". The menu shows the warnings in Turkish.

- **A stuck power command with a pid.** The user checks the pid, then runs the
  `sudo kill <pid>` the menu shows.
- **Stopped processes Uykusuz cannot prove it froze.** The user checks each
  pid with `ps` and decides whether to run `kill -CONT <pid>`.
- **An output device still muted.** Reconnect it and open Uykusuz, or choose
  "Beklemeyi bırak: <device>" in the menu.
- **Sleep disabled by something else.** Uykusuz did not set it and leaves it
  alone. Whoever set it turns sleep back on with
  `sudo pmset -a disablesleep 0`.
- **Hotspot password unreadable by this build.** A reinstall changes the app's
  signature. Enter the password again in Settings.

## Uninstall

Follow "Kaldırma" in docs/install.md and hand the user the command, since it
asks for the password. It stops when something is still waiting to be
undone. Fix that first, then run it again. A failed uninstall does not mean
the power settings are back to normal, so check `pmset -g` afterward.
