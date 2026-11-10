#!/bin/zsh
# usage: typeslow.sh <text>  -> type into the frontmost app one character at a time with human-like pauses
osascript - "$1" <<'AS'
on run argv
  set s to item 1 of argv
  tell application "System Events"
    repeat with c in characters of s
      keystroke (c as text)
      delay (random number from 0.07 to 0.18)
    end repeat
  end tell
end run
AS
