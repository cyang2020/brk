#!/bin/zsh
# usage: arcopen.sh <url> [pin]  -> Cmd+T, type the url, Return; optionally Cmd+D to pin
osascript - "$1" "${2:-}" <<'AS'
on run argv
  tell application "System Events" to tell process "Arc"
    set frontmost to true
    delay 0.3
    keystroke "t" using command down
    delay 0.9
    keystroke (item 1 of argv)
    delay 0.4
    key code 36
    delay 2.5
    if (item 2 of argv) is "pin" then
      keystroke "d" using command down
      delay 0.8
    end if
  end tell
end run
AS
