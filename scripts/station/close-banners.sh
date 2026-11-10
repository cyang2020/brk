#!/bin/bash
# Closes every macOS notification banner or alert on screen through accessibility (the Close action only: a
# permission alert from a test instance is neither allowed nor denied). Test instances' "allow notifications?"
# alerts pile up at the screen's right edge and land in window captures (P37, Arc references).
for round in 1 2 3 4 5 6; do
  n=$(osascript <<'AS' 2>/dev/null
tell application "System Events"
  if not (exists process "NotificationCenter") then return 0
  tell process "NotificationCenter"
    if (count of windows) = 0 then return 0
    set closed to 0
    try
      set g to UI element 1 of UI element 1 of UI element 1 of UI element 1 of window 1
      repeat with e in UI elements of g
        try
          if subrole of e starts with "AXNotificationCenter" then
            -- on macOS 26 the action name reads Name:Close followed by Target and Selector lines
            repeat with a in actions of e
              if name of a starts with "Name:Close" or name of a is "Close" then
                perform a
                set closed to closed + 1
                exit repeat
              end if
            end repeat
          end if
        end try
      end repeat
    end try
    return closed
  end tell
end tell
AS
)
  [ "${n:-0}" = "0" ] && break
  sleep 0.6
done
echo "banners closed: $(( ${round:-1} - 1 )) rounds"
